source(file.path("scripts", "R", "common.R"))
suppressPackageStartupMessages(library(readxl))

election_specs <- list(
  general = list(
    url = sources$election_general_xlsx,
    file = "election-general-2023.xlsx",
    parties = list(PP = "^pp$", PSOE = "^psoe$", VOX = "^vox$", SUMAR = "^sumar$"),
    left = c("PSOE", "SUMAR"),
    right = c("PP", "VOX")
  ),
  local = list(
    url = sources$election_local_xlsx,
    file = "election-local-2023.xlsx",
    parties = list(
      PP = "^pp$", PSOE = "^psoe$", VOX = "^vox$",
      MAS_MADRID = "mas_madrid|^mm$|^mm_vq$",
      PODEMOS_IU_AV = "podemos.*iu.*av|podemos"
    ),
    left = c("PSOE", "MAS_MADRID", "PODEMOS_IU_AV"),
    right = c("PP", "VOX")
  ),
  assembly = list(
    url = sources$election_assembly_xlsx,
    file = "election-assembly-2023.xlsx",
    parties = list(
      PP = "^pp$", PSOE = "^psoe$", VOX = "^vox$",
      MAS_MADRID = "mas_madrid|^mm$|^mm_vq$",
      PODEMOS_IU_AV = "podemos.*iu.*av|podemos"
    ),
    left = c("PSOE", "MAS_MADRID", "PODEMOS_IU_AV"),
    right = c("PP", "VOX")
  )
)

prepare_election <- function(election, spec) {
  path <- file.path(raw_dir, spec$file)
  download_cached(spec$url, path)
  raw <- suppressMessages(readxl::read_excel(path, sheet = 1, col_names = FALSE, .name_repair = "minimal"))
  assert_true(nrow(raw) > 1000 && ncol(raw) > 15, paste("Unexpected", election, "workbook dimensions"))

  header <- as.character(unlist(raw[7, ], use.names = FALSE))
  party_labels <- header[12:ncol(raw)]
  party_labels[is.na(party_labels) | party_labels == ""] <- paste0("party_", which(is.na(party_labels) | party_labels == ""))
  party_columns <- normalise_names(party_labels)
  columns <- c(
    "district_code", "neighbourhood_code", "section", "table", "census",
    "abstention", "votes_cast", "null_votes", "valid_votes", "blank_votes",
    "candidate_votes", party_columns
  )
  names(raw) <- columns

  tables <- raw |>
    mutate(
      district_code = suppressWarnings(as.integer(district_code)),
      section = suppressWarnings(as.integer(section))
    ) |>
    filter(!is.na(district_code), !is.na(section), !is.na(table)) |>
    mutate(
      section_id = sprintf("28079%02d%03d", district_code, section),
      across(c(census:candidate_votes, all_of(party_columns)), ~suppressWarnings(as.numeric(.x)))
    )

  section_results <- tables |>
    group_by(section_id) |>
    summarise(
      across(c(census:candidate_votes, all_of(party_columns)), ~sum(.x, na.rm = TRUE)),
      .groups = "drop"
    ) |>
    mutate(turnout_pct = if_else(census > 0, 100 * votes_cast / census, NA_real_))

  city_party_votes <- list()
  party_vote_columns <- list()
  for (target in names(spec$parties)) {
    pattern <- spec$parties[[target]]
    matched <- party_columns[grepl(pattern, party_columns, ignore.case = TRUE, perl = TRUE)]
    assert_true(length(matched) >= 1, paste("Could not find", target, "in", election, "ballot columns"))
    assert_true(length(matched) == 1, paste("Ambiguous", target, "ballot columns in", election))
    party_vote_columns[[target]] <- matched[[1]]
    property <- paste0("share_", tolower(target))
    section_results[[property]] <- ifelse(
      section_results$valid_votes > 0,
      100 * section_results[[matched[[1]]]] / section_results$valid_votes,
      NA_real_
    )
    city_party_votes[[target]] <- sum(tables[[matched[[1]]]], na.rm = TRUE)
  }

  left_columns <- unname(unlist(party_vote_columns[spec$left]))
  right_columns <- unname(unlist(party_vote_columns[spec$right]))
  assert_true(!any(left_columns %in% right_columns), paste(election, "bloc definitions overlap"))
  left_votes <- rowSums(section_results[left_columns], na.rm = TRUE)
  right_votes <- rowSums(section_results[right_columns], na.rm = TRUE)
  section_results$left_share <- ifelse(section_results$valid_votes > 0, 100 * left_votes / section_results$valid_votes, NA_real_)
  section_results$right_share <- ifelse(section_results$valid_votes > 0, 100 * right_votes / section_results$valid_votes, NA_real_)
  section_results$left_right_margin_pp <- section_results$right_share - section_results$left_share
  assert_true(
    all(abs(section_results$left_right_margin_pp - (section_results$right_share - section_results$left_share)) < 1e-10, na.rm = TRUE),
    paste(election, "Left–Right margin identity failed")
  )

  party_matrix <- as.matrix(section_results[party_columns])
  leading_index <- max.col(party_matrix, ties.method = "first")
  section_results$leading_party <- party_labels[leading_index]
  section_results$leading_party <- iconv(section_results$leading_party, from = "", to = "UTF-8")

  official <- suppressWarnings(as.numeric(unlist(raw[10, c("census", "votes_cast", "valid_votes", "blank_votes", "candidate_votes")])))
  names(official) <- c("census", "votes_cast", "valid_votes", "blank_votes", "candidate_votes")
  reconciled <- colSums(tables[names(official)], na.rm = TRUE)
  difference <- reconciled - official
  assert_true(
    all(abs(difference) <= pmax(2, official * 0.001), na.rm = TRUE),
    paste(election, "section totals do not reconcile with official Madrid total")
  )
  city_results <- lapply(names(city_party_votes), function(key) {
    votes <- unname(city_party_votes[[key]])
    list(
      key = key,
      votes = votes,
      share = if (official[["valid_votes"]] > 0) 100 * votes / official[["valid_votes"]] else NA_real_
    )
  })

  selected_columns <- c(
    "section_id", "census", "votes_cast", "valid_votes", "blank_votes",
    "turnout_pct", "leading_party", "left_share", "right_share", "left_right_margin_pp",
    grep("^share_", names(section_results), value = TRUE)
  )
  saveRDS(section_results[selected_columns], file.path(processed_dir, paste0("election-", election, ".rds")))
  save_metadata(paste0("election-", election), list(
    reference_date = if (election == "general") "2023-07-23" else "2023-05-28",
    source_url = spec$url,
    official_total = as.list(official),
    table_total = as.list(reconciled),
    difference = as.list(difference),
    sections = nrow(section_results),
    ballot_labels = as.list(party_labels),
    city_results = city_results
  ))
  section_results[selected_columns]
}

message_step("Preparing 2023 election results by census section")
elections <- Map(prepare_election, names(election_specs), election_specs)
names(elections) <- names(election_specs)

# Election attributes keep their own 2023 geography; income is prepared separately.
sections_2023 <- readRDS(file.path(processed_dir, "sections-2023.rds"))
for (election in names(elections)) {
  values <- elections[[election]]
  names(values)[names(values) != "section_id"] <- paste0(names(values)[names(values) != "section_id"], "_", election)
  sections_2023 <- left_join(sections_2023, values, by = "section_id")
}
saveRDS(sections_2023, file.path(processed_dir, "sections-2023-elections.rds"))
message_step("2023 election layers ready")
