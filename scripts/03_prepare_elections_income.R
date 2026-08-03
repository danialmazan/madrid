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

message_step("Downloading INE income and inequality tables")
income_downloads <- list(
  income_person = c(sources$ine_income_person_csv, "ine-income-person-31097.csv"),
  income_risk = c(sources$ine_income_risk_csv, "ine-income-risk-31102.csv"),
  gini = c(sources$ine_gini_csv, "ine-gini-37727.csv"),
  income_sources = c(sources$ine_income_sources_csv, "ine-income-sources-31098.csv")
)
income_paths <- lapply(income_downloads, function(item) {
  download_cached(item[[1]], file.path(raw_dir, item[[2]]))
})

extract_ine_indicator <- function(path, metric_pattern, value_name) {
  data <- read_semicolon(path)
  section_col <- intersect(c("secciones", "seccion"), names(data))[[1]]
  period_col <- intersect(c("periodo", "ano"), names(data))[[1]]
  value_col <- intersect(c("total", "valor"), names(data))[[1]]
  indicator_candidates <- grep("indicador|renta|porcentaje|indice|fuente|distribuci", names(data), value = TRUE)
  indicator_candidates <- setdiff(indicator_candidates, c(value_name, value_col))
  assert_true(length(indicator_candidates) > 0, paste("Could not find indicator column in", basename(path)))
  indicator_col <- indicator_candidates[[1]]

  if ("sexo" %in% names(data)) {
    data <- data |> filter(tolower(sexo) == "total")
  }
  data |>
    mutate(
      section_id = sub(".*?([0-9]{10}).*", "\\1", .data[[section_col]]),
      period = suppressWarnings(as.integer(.data[[period_col]])),
      indicator_ascii = tolower(gsub(
        "[^A-Za-z0-9]+", "_",
        iconv(.data[[indicator_col]], to = "ASCII//TRANSLIT")
      )),
      value = parse_es_number(.data[[value_col]])
    ) |>
    filter(
      grepl("^28079[0-9]{5}$", section_id),
      period == 2023,
      grepl(metric_pattern, indicator_ascii, perl = TRUE)
    ) |>
    transmute(section_id, !!value_name := value) |>
    distinct(section_id, .keep_all = TRUE)
}

income_person <- extract_ine_indicator(
  income_paths$income_person,
  "renta_neta_media_por_persona",
  "income_per_person_eur"
)
income_household <- extract_ine_indicator(
  income_paths$income_person,
  "renta_neta_media_por_hogar",
  "income_per_household_eur"
)
pension_income <- extract_ine_indicator(
  income_paths$income_sources,
  "fuente_de_ingreso_pensiones|pensiones",
  "pension_income_pct"
)
income_risk <- extract_ine_indicator(
  income_paths$income_risk,
  "debajo.*60.*mediana|60.*mediana",
  "below_60_median_pct"
)
gini <- extract_ine_indicator(
  income_paths$gini,
  "indice_de_gini|gini",
  "gini"
)
income_p80_p20 <- extract_ine_indicator(
  income_paths$gini,
  "p80.*p20",
  "income_p80_p20"
)
above_200_median <- extract_ine_indicator(
  income_paths$income_risk,
  "encima.*200.*mediana|200.*mediana",
  "above_200_median_pct"
)

assert_true(nrow(income_person) > 2000, "Too few income-per-person sections")
assert_true(nrow(income_household) > 2000, "Too few income-per-household sections")
assert_true(nrow(pension_income) > 2000, "Too few pension-income sections")
assert_true(nrow(income_risk) > 2000, "Too few income-risk sections")
assert_true(nrow(gini) > 2000, "Too few Gini sections")
assert_true(nrow(income_p80_p20) > 2000, "Too few P80/P20 sections")
assert_true(nrow(above_200_median) > 2000, "Too few above-200%-median sections")

sections_2023 <- readRDS(file.path(processed_dir, "sections-2023.rds"))
for (election in names(elections)) {
  suffix <- paste0("_", election)
  values <- elections[[election]]
  names(values)[names(values) != "section_id"] <- paste0(names(values)[names(values) != "section_id"], suffix)
  sections_2023 <- left_join(sections_2023, values, by = "section_id")
}
sections_2023 <- sections_2023 |>
  left_join(income_person, by = "section_id") |>
  left_join(income_household, by = "section_id") |>
  left_join(pension_income, by = "section_id") |>
  left_join(income_risk, by = "section_id") |>
  left_join(gini, by = "section_id") |>
  left_join(income_p80_p20, by = "section_id") |>
  left_join(above_200_median, by = "section_id") |>
  mutate(
    income_per_person_percentile = section_percentile(income_per_person_eur),
    income_per_household_percentile = section_percentile(income_per_household_eur),
    pension_income_percentile = section_percentile(pension_income_pct),
    below_60_median_percentile = section_percentile(below_60_median_pct),
    above_200_median_percentile = section_percentile(above_200_median_pct),
    gini_percentile = section_percentile(gini),
    income_p80_p20_percentile = section_percentile(income_p80_p20)
  )

assert_true(all(sections_2023$income_per_person_eur >= 0, na.rm = TRUE), "Negative income values")
assert_true(all(sections_2023$income_per_household_eur >= 0, na.rm = TRUE), "Negative household income values")
assert_true(all(dplyr::between(sections_2023$pension_income_pct, 0, 100), na.rm = TRUE), "Pension-income percentage out of range")
assert_true(all(dplyr::between(sections_2023$below_60_median_pct, 0, 100), na.rm = TRUE), "Income-risk percentage out of range")
assert_true(all(dplyr::between(sections_2023$gini, 0, 100), na.rm = TRUE), "Gini values out of range")
assert_true(all(sections_2023$income_p80_p20 >= 1, na.rm = TRUE), "P80/P20 values out of range")
assert_true(all(dplyr::between(sections_2023$above_200_median_pct, 0, 100), na.rm = TRUE), "Above-200%-median percentage out of range")
saveRDS(sections_2023, file.path(processed_dir, "sections-2023-thematics.rds"))
save_metadata("income", list(
  reference_date = "2023",
  source_urls = lapply(income_downloads, `[[`, 1),
  matched = list(
    income_per_person = nrow(income_person),
    income_per_household = nrow(income_household),
    pension_income = nrow(pension_income),
    below_60_median = nrow(income_risk),
    gini = nrow(gini),
    p80_p20 = nrow(income_p80_p20),
    above_200_median = nrow(above_200_median)
  )
))

message_step("Election and income layers ready")
