source(file.path("scripts", "R", "common.R"))

message_step("Building canonical census-section reports")

current <- readRDS(file.path(processed_dir, "sections-2026-population.rds")) |>
  mutate(population_total_percentile = section_percentile(population_total))
migration <- readRDS(file.path(processed_dir, "sections-2025-migration.rds"))
education_work <- readRDS(file.path(processed_dir, "sections-2024-education-work.rds"))
historic <- readRDS(file.path(processed_dir, "sections-2023-thematics.rds"))
sections_2021 <- readRDS(file.path(processed_dir, "sections-2021.rds"))

greatest_overlap_crosswalk <- function(current_sections, source_sections, vintage) {
  target <- sf::st_transform(current_sections |> select(section_id), 25830) |>
    rename(target_id = section_id)
  source <- sf::st_transform(source_sections |> select(section_id), 25830) |>
    rename(source_id = section_id)
  target$target_area <- as.numeric(sf::st_area(target))
  overlaps <- suppressWarnings(sf::st_intersection(target, source))
  overlaps$overlap_area <- as.numeric(sf::st_area(overlaps))
  overlaps <- overlaps |>
    sf::st_drop_geometry() |>
    filter(overlap_area > 0) |>
    group_by(target_id) |>
    slice_max(overlap_area, n = 1, with_ties = FALSE) |>
    ungroup() |>
    transmute(
      section_id = target_id,
      source_section_id = source_id,
      overlap_share = pmin(1, overlap_area / target_area),
      boundary_changed = source_section_id != section_id | overlap_share < 0.95
    )
  assert_true(nrow(overlaps) == nrow(target), paste("Not every current section received a", vintage, "match"))
  overlaps
}

message_step("Matching 2021, 2023, 2024 and 2025 report geographies")
crosswalks <- list(
  `2021` = greatest_overlap_crosswalk(current, sections_2021, "2021"),
  `2023` = greatest_overlap_crosswalk(current, historic, "2023"),
  `2024` = greatest_overlap_crosswalk(current, education_work, "2024"),
  `2025` = greatest_overlap_crosswalk(current, migration, "2025")
)

report_rows <- current |>
  sf::st_drop_geometry() |>
  select(
    section_id, district, section, population_total, population_total_percentile,
    population_density_km2, population_density_percentile,
    under18_pct, under18_percentile, age65plus_pct, age65plus_percentile,
    population_change_5y_pct, population_change_5y_percentile
  )
for (vintage in names(crosswalks)) {
  renamed <- crosswalks[[vintage]]
  names(renamed)[names(renamed) != "section_id"] <- paste0(names(renamed)[names(renamed) != "section_id"], "_", vintage)
  report_rows <- left_join(report_rows, renamed, by = "section_id")
}
report_rows <- report_rows |>
  left_join(
    migration |> sf::st_drop_geometry() |> select(section_id, starts_with("foreign_")),
    by = c("source_section_id_2025" = "section_id")
  ) |>
  left_join(
    education_work |> sf::st_drop_geometry() |> select(section_id, ends_with("_pct"), ends_with("_percentile")),
    by = c("source_section_id_2024" = "section_id")
  ) |>
  left_join(
    historic |> sf::st_drop_geometry() |> select(-district, -district_code, -section),
    by = c("source_section_id_2023" = "section_id")
  )

message_step("Aggregating Catastro buildings to current sections")
building_files <- list.files(file.path(processed_dir, "buildings"), pattern = "^building-age-[0-9]{2}\\.geojson$", full.names = TRUE)
assert_true(length(building_files) == 21, "Expected 21 district building-age inputs")
buildings <- do.call(rbind, lapply(building_files, function(path) sf::st_read(path, quiet = TRUE))) |>
  sf::st_transform(25830)
building_points <- suppressWarnings(sf::st_point_on_surface(buildings))
current_projected <- sf::st_transform(current |> select(section_id), 25830)
building_hits <- sf::st_intersects(building_points, current_projected)
building_section_index <- vapply(building_hits, function(hit) if (length(hit)) hit[[1]] else NA_integer_, integer(1))
assert_true(mean(!is.na(building_section_index)) >= 0.999, "Too many Catastro buildings fall outside current sections")
buildings$section_id <- ifelse(is.na(building_section_index), NA_character_, current_projected$section_id[building_section_index])
era_labels <- c("Before 1900", "1900–1939", "1940–1959", "1960–1979", "1980–1999", "2000+")
buildings <- buildings |>
  mutate(construction_era = cut(
    construction_start_year,
    breaks = c(-Inf, 1899, 1939, 1959, 1979, 1999, Inf),
    labels = era_labels,
    right = TRUE
  ))
building_summary <- buildings |>
  sf::st_drop_geometry() |>
  filter(!is.na(section_id)) |>
  group_by(section_id) |>
  summarise(
    building_count = n(),
    dwellings = sum(dwellings, na.rm = TRUE),
    median_construction_year = if (all(is.na(construction_start_year))) NA_real_ else stats::median(construction_start_year, na.rm = TRUE),
    .groups = "drop"
  )
building_eras <- buildings |>
  sf::st_drop_geometry() |>
  filter(!is.na(section_id), !is.na(construction_era)) |>
  count(section_id, construction_era, .drop = FALSE) |>
  tidyr::pivot_wider(names_from = construction_era, values_from = n, values_fill = 0, names_prefix = "era_")
report_rows <- report_rows |>
  left_join(building_summary, by = "section_id") |>
  left_join(building_eras, by = "section_id")
era_columns <- paste0("era_", era_labels)
for (column in era_columns) if (!column %in% names(report_rows)) report_rows[[column]] <- 0L

metric_specs <- list(
  population_total = list(label = "Residents", format = "integer", unit = "residents", percentile = "population_total_percentile"),
  population_density_km2 = list(label = "Population density", format = "integer", unit = "residents / km²", percentile = "population_density_percentile"),
  under18_pct = list(label = "Under 18", format = "percent", unit = "%", percentile = "under18_percentile"),
  age65plus_pct = list(label = "65 and older", format = "percent", unit = "%", percentile = "age65plus_percentile"),
  population_change_5y_pct = list(label = "Five-year population change", format = "percent", unit = "%", percentile = "population_change_5y_percentile"),
  activity_rate_pct = list(label = "Activity rate", format = "percent", unit = "%", percentile = "activity_rate_percentile"),
  employment_rate_pct = list(label = "Employment rate", format = "percent", unit = "%", percentile = "employment_rate_percentile"),
  unemployment_rate_pct = list(label = "Unemployment rate", format = "percent", unit = "%", percentile = "unemployment_rate_percentile"),
  higher_education_pct = list(label = "Higher education", format = "percent", unit = "%", percentile = "higher_education_percentile"),
  low_education_pct = list(label = "Primary or lower", format = "percent", unit = "%", percentile = "low_education_percentile"),
  income_per_person_eur = list(label = "Net income / person", format = "currency", unit = "€ / person", percentile = "income_per_person_percentile"),
  income_per_household_eur = list(label = "Net income / household", format = "currency", unit = "€ / household", percentile = "income_per_household_percentile"),
  pension_income_pct = list(label = "Income from pensions", format = "percent", unit = "% of total income", percentile = "pension_income_percentile"),
  below_60_median_pct = list(label = "Below 60% median", format = "percent", unit = "%", percentile = "below_60_median_percentile"),
  above_200_median_pct = list(label = "Above 200% median", format = "percent", unit = "%", percentile = "above_200_median_percentile"),
  gini = list(label = "Gini coefficient", format = "decimal", unit = "index", percentile = "gini_percentile"),
  income_p80_p20 = list(label = "P80/P20 ratio", format = "decimal", unit = "ratio", percentile = "income_p80_p20_percentile")
)
country_labels <- c(
  total = "Total", venezuela = "Venezuela", colombia = "Colombia", peru = "Perú",
  ecuador = "Ecuador", republica_dominicana = "República Dominicana", argentina = "Argentina",
  china = "China", marruecos = "Marruecos"
)
for (slug in names(country_labels)) {
  metric_specs[[paste0("foreign_born_pct_", slug)]] <- list(
    label = paste("Foreign-born", country_labels[[slug]]), format = "percent", unit = "%",
    percentile = paste0("foreign_born_percentile_", slug)
  )
  metric_specs[[paste0("foreign_citizenship_pct_", slug)]] <- list(
    label = paste("Foreign citizenship", country_labels[[slug]]), format = "percent", unit = "%",
    percentile = paste0("foreign_citizenship_percentile_", slug)
  )
  metric_specs[[paste0("foreign_born_change_pp_", slug)]] <- list(
    label = paste("2021–2025 foreign-born change", country_labels[[slug]]), format = "pp", unit = "pp",
    percentile = paste0("foreign_born_change_percentile_", slug)
  )
}

distribution_for <- function(values, spec) {
  valid <- values[is.finite(values)]
  assert_true(length(valid) > 1, paste("Not enough values for", spec$label, "distribution"))
  percentile_curve <- tibble::tibble(value = valid, percentile = section_percentile(valid)) |>
    group_by(value) |>
    summarise(percentile = first(percentile), .groups = "drop") |>
    arrange(value)
  chart_breaks <- pretty(range(valid), n = 20, min.n = 12)
  if (length(chart_breaks) - 1 < 12) chart_breaks <- seq(min(valid), max(valid), length.out = 13)
  chart_breaks <- unique(signif(chart_breaks, 12))
  bins <- findInterval(valid, chart_breaks, all.inside = TRUE, rightmost.closed = TRUE)
  list(
    label = spec$label, format = spec$format, unit = spec$unit,
    breaks = unname(as.list(chart_breaks)), counts = unname(as.list(tabulate(bins, nbins = length(chart_breaks) - 1))),
    observationCount = length(valid), minimum = min(valid), maximum = max(valid),
    percentileValues = unname(as.list(percentile_curve$value)), percentileRanks = unname(as.list(percentile_curve$percentile))
  )
}
distribution_sources <- c(
  list(
    population_total = current$population_total, population_density_km2 = current$population_density_km2,
    under18_pct = current$under18_pct, age65plus_pct = current$age65plus_pct,
    population_change_5y_pct = current$population_change_5y_pct,
    activity_rate_pct = education_work$activity_rate_pct, employment_rate_pct = education_work$employment_rate_pct,
    unemployment_rate_pct = education_work$unemployment_rate_pct, higher_education_pct = education_work$higher_education_pct,
    low_education_pct = education_work$low_education_pct,
    income_per_person_eur = historic$income_per_person_eur, income_per_household_eur = historic$income_per_household_eur,
    pension_income_pct = historic$pension_income_pct, below_60_median_pct = historic$below_60_median_pct,
    above_200_median_pct = historic$above_200_median_pct, gini = historic$gini, income_p80_p20 = historic$income_p80_p20
  ),
  as.list(migration |> sf::st_drop_geometry() |> select(all_of(grep("^foreign_", names(migration), value = TRUE)[!grepl("percentile", grep("^foreign_", names(migration), value = TRUE))])))
)
distributions <- lapply(names(metric_specs), function(metric) distribution_for(distribution_sources[[metric]], metric_specs[[metric]]))
names(distributions) <- names(metric_specs)

party_labels <- list(
  general = c(PP = "PP", PSOE = "PSOE", VOX = "VOX", SUMAR = "SUMAR"),
  local = c(PP = "PP", PSOE = "PSOE", VOX = "VOX", MAS_MADRID = "Más Madrid", PODEMOS_IU_AV = "Podemos-IU-AV"),
  assembly = c(PP = "PP", PSOE = "PSOE", VOX = "VOX", MAS_MADRID = "Más Madrid", PODEMOS_IU_AV = "Podemos-IU-AV")
)
party_colours <- c(PP = "#1D84CE", PSOE = "#E32322", VOX = "#63A53A", SUMAR = "#E65A91", MAS_MADRID = "#16A085", PODEMOS_IU_AV = "#6B3FA0")
election_result_list <- function(row, election) {
  lapply(names(party_labels[[election]]), function(key) list(
    key = key, label = unname(party_labels[[election]][[key]]), color = unname(party_colours[[key]]),
    share = row[[paste0("share_", tolower(key), "_", election)]]
  ))
}
city_elections <- lapply(c("general", "local", "assembly"), function(election) {
  metadata <- readRDS(file.path(processed_dir, paste0("election-", election, "-metadata.rds")))
  totals <- unlist(metadata$official_total)
  result_by_key <- setNames(metadata$city_results, vapply(metadata$city_results, `[[`, character(1), "key"))
  results <- lapply(names(party_labels[[election]]), function(key) {
    result <- result_by_key[[key]]
    list(key = key, label = unname(party_labels[[election]][[key]]), color = unname(party_colours[[key]]), votes = result$votes, share = result$share)
  })
  left_keys <- if (election == "general") c("PSOE", "SUMAR") else c("PSOE", "MAS_MADRID", "PODEMOS_IU_AV")
  right_keys <- c("PP", "VOX")
  left_share <- sum(vapply(results[names(party_labels[[election]]) %in% left_keys], `[[`, numeric(1), "share"))
  right_share <- sum(vapply(results[names(party_labels[[election]]) %in% right_keys], `[[`, numeric(1), "share"))
  list(
    label = switch(election, general = "General election", local = "Madrid local election", assembly = "Madrid Assembly election"),
    referenceDate = metadata$reference_date, census = totals[["census"]], votesCast = totals[["votes_cast"]],
    validVotes = totals[["valid_votes"]], blankVotes = totals[["blank_votes"]],
    turnoutPct = 100 * totals[["votes_cast"]] / totals[["census"]], shownCoveragePct = sum(vapply(results, `[[`, numeric(1), "share")),
    leftShare = left_share, rightShare = right_share, margin = right_share - left_share, results = results
  )
})
names(city_elections) <- c("general", "local", "assembly")

metric_value <- function(row, metric) list(value = row[[metric]], percentile = row[[metric_specs[[metric]]$percentile]])
metric_record <- function(row, metrics) {
  values <- lapply(metrics, function(metric) metric_value(row, metric))
  names(values) <- metrics
  values
}
population_metrics <- c("population_total", "population_density_km2", "under18_pct", "age65plus_pct", "population_change_5y_pct")
education_metrics <- c("activity_rate_pct", "employment_rate_pct", "unemployment_rate_pct", "higher_education_pct", "low_education_pct")
income_metrics <- c("income_per_person_eur", "income_per_household_eur", "pension_income_pct", "below_60_median_pct", "above_200_median_pct", "gini", "income_p80_p20")

section_reports <- vector("list", nrow(report_rows))
names(section_reports) <- report_rows$section_id
for (index in seq_len(nrow(report_rows))) {
  row <- report_rows[index, , drop = FALSE]
  elections <- lapply(c("general", "local", "assembly"), function(election) list(
    turnoutPct = row[[paste0("turnout_pct_", election)]], validVotes = row[[paste0("valid_votes_", election)]],
    blankVotes = row[[paste0("blank_votes_", election)]], leadingParty = row[[paste0("leading_party_", election)]],
    leftShare = row[[paste0("left_share_", election)]], rightShare = row[[paste0("right_share_", election)]],
    margin = row[[paste0("left_right_margin_pp_", election)]], results = election_result_list(row, election)
  ))
  names(elections) <- c("general", "local", "assembly")
  migration_report <- lapply(names(country_labels), function(slug) list(
    foreignBorn = metric_value(row, paste0("foreign_born_pct_", slug)),
    foreignCitizenship = metric_value(row, paste0("foreign_citizenship_pct_", slug)),
    foreignBornChange = metric_value(row, paste0("foreign_born_change_pp_", slug))
  ))
  names(migration_report) <- names(country_labels)
  matches <- lapply(names(crosswalks), function(vintage) list(
    sectionId = row[[paste0("source_section_id_", vintage)]],
    overlapShare = row[[paste0("overlap_share_", vintage)]],
    boundaryChanged = row[[paste0("boundary_changed_", vintage)]]
  ))
  names(matches) <- names(crosswalks)
  section_reports[[index]] <- list(
    id = row$section_id, name = paste0(row$district, " · section ", as.integer(row$section)), district = row$district,
    matches = matches, population = metric_record(row, population_metrics), migration = migration_report,
    educationWork = metric_record(row, education_metrics), income = metric_record(row, income_metrics), elections = elections,
    buildings = list(
      buildingCount = ifelse(is.na(row$building_count), 0, row$building_count),
      dwellings = ifelse(is.na(row$dwellings), 0, row$dwellings), medianConstructionYear = row$median_construction_year,
      constructionEras = unname(as.list(as.integer(unlist(row[era_columns], use.names = FALSE))))
    )
  )
}

manifest <- jsonlite::fromJSON(file.path(public_data_dir, "layer-manifest.json"), simplifyVector = FALSE)
matched_buildings <- buildings |> filter(!is.na(section_id))
city_era_counts <- table(factor(matched_buildings$construction_era, levels = era_labels))
population_metadata <- readRDS(file.path(processed_dir, "population-metadata.rds"))
building_metadata <- readRDS(file.path(processed_dir, "buildings-metadata.rds"))
report_index <- list(
  generatedAt = paste0(format(Sys.time(), "%Y-%m-%dT%H:%M:%S"), "Z"), version = "1.1.0", canonicalVintage = "2026",
  geographyVintages = list(canonical = "2026", populationChange = "2021", incomeAndElections = "2023", educationWork = "2024", migration = "2025"),
  dataDates = list(population = population_metadata$reference_date, migration = "2025", educationWork = "2024", income = "2023", buildings = building_metadata$reference_date_catastro),
  countries = as.list(country_labels), methodologyUrl = "https://github.com/danialmazan/madrid/blob/main/docs/methodology.md",
  distributions = distributions, constructionEras = unname(as.list(era_labels)),
  cityBuildings = list(
    buildingCount = nrow(matched_buildings), dwellings = sum(matched_buildings$dwellings, na.rm = TRUE),
    medianConstructionYear = stats::median(matched_buildings$construction_start_year, na.rm = TRUE),
    constructionEras = unname(as.list(as.integer(city_era_counts)))
  ),
  cityElections = city_elections, references = manifest$references, sections = section_reports
)
write_json_pretty(report_index, file.path(public_data_dir, "section-reports.json"))
message_step("Section reports ready: ", length(section_reports), " current sections")
