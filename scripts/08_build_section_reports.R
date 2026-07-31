source(file.path("scripts", "R", "common.R"))

message_step("Building canonical census-section reports")

current <- readRDS(file.path(processed_dir, "sections-2026-population.rds")) |>
  mutate(population_total_percentile = section_percentile(population_total))
foreign <- readRDS(file.path(processed_dir, "sections-2025-foreign-born.rds"))
historic <- readRDS(file.path(processed_dir, "sections-2023-thematics.rds"))

greatest_overlap_crosswalk <- function(current_sections, historic_sections, vintage) {
  current_projected <- sf::st_transform(current_sections |> select(section_id), 25830) |>
    rename(current_section_id = section_id)
  historic_projected <- sf::st_transform(historic_sections |> select(section_id), 25830) |>
    rename(source_section_id = section_id)
  current_area <- tibble::tibble(
    current_section_id = current_projected$current_section_id,
    current_area = as.numeric(sf::st_area(current_projected))
  )
  intersections <- suppressWarnings(sf::st_intersection(current_projected, historic_projected))
  intersections$overlap_area <- as.numeric(sf::st_area(intersections))
  intersections <- intersections |>
    sf::st_drop_geometry() |>
    filter(overlap_area > 0) |>
    group_by(current_section_id) |>
    slice_max(overlap_area, n = 1, with_ties = FALSE) |>
    ungroup() |>
    left_join(current_area, by = "current_section_id") |>
    transmute(
      section_id = current_section_id,
      source_section_id,
      overlap_share = pmin(1, overlap_area / current_area),
      boundary_changed = source_section_id != current_section_id | overlap_share < 0.95
    )
  assert_true(
    nrow(intersections) == nrow(current_projected),
    paste("Not every current section received a", vintage, "overlap match")
  )
  intersections
}

message_step("Matching 2025 and 2023 section vintages by greatest overlap")
crosswalk_2025 <- greatest_overlap_crosswalk(current, foreign, "2025")
crosswalk_2023 <- greatest_overlap_crosswalk(current, historic, "2023")

report_rows <- current |>
  sf::st_drop_geometry() |>
  select(
    section_id, district, section, population_total, population_total_percentile,
    population_density_km2, population_density_percentile,
    under18_pct, under18_percentile, age65plus_pct, age65plus_percentile,
    foreign_citizenship_pct, foreign_citizenship_percentile
  ) |>
  left_join(
    crosswalk_2025 |>
      rename(
        section_id_2025 = source_section_id,
        overlap_share_2025 = overlap_share,
        boundary_changed_2025 = boundary_changed
      ),
    by = "section_id"
  ) |>
  left_join(
    foreign |>
      sf::st_drop_geometry() |>
      select(
        section_id_2025 = section_id,
        foreign_born_pct, foreign_born_percentile
      ),
    by = "section_id_2025"
  ) |>
  left_join(
    crosswalk_2023 |>
      rename(
        section_id_2023 = source_section_id,
        overlap_share_2023 = overlap_share,
        boundary_changed_2023 = boundary_changed
      ),
    by = "section_id"
  ) |>
  left_join(
    historic |>
      sf::st_drop_geometry() |>
      select(-district, -district_code, -section),
    by = c("section_id_2023" = "section_id")
  )

message_step("Aggregating Catastro buildings to current sections")
building_files <- list.files(
  file.path(processed_dir, "buildings"),
  pattern = "^building-age-[0-9]{2}\\.geojson$",
  full.names = TRUE
)
assert_true(length(building_files) == 21, "Expected 21 district building-age inputs")
buildings <- do.call(rbind, lapply(building_files, function(path) sf::st_read(path, quiet = TRUE))) |>
  sf::st_transform(25830)
building_points <- suppressWarnings(sf::st_point_on_surface(buildings))
current_projected <- sf::st_transform(current |> select(section_id), 25830)
building_hits <- sf::st_intersects(building_points, current_projected)
building_section_index <- vapply(
  building_hits,
  function(hit) if (length(hit)) hit[[1]] else NA_integer_,
  integer(1)
)
assert_true(mean(!is.na(building_section_index)) >= 0.999, "Too many Catastro buildings fall outside current sections")
buildings$section_id <- ifelse(
  is.na(building_section_index),
  NA_character_,
  current_projected$section_id[building_section_index]
)
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
    median_construction_year = if (all(is.na(construction_start_year))) {
      NA_real_
    } else {
      stats::median(construction_start_year, na.rm = TRUE)
    },
    .groups = "drop"
  )
building_eras <- buildings |>
  sf::st_drop_geometry() |>
  filter(!is.na(section_id), !is.na(construction_era)) |>
  count(section_id, construction_era, .drop = FALSE) |>
  tidyr::pivot_wider(
    names_from = construction_era,
    values_from = n,
    values_fill = 0,
    names_prefix = "era_"
  )
report_rows <- report_rows |>
  left_join(building_summary, by = "section_id") |>
  left_join(building_eras, by = "section_id")

era_columns <- paste0("era_", era_labels)
for (column in era_columns) {
  if (!column %in% names(report_rows)) report_rows[[column]] <- 0L
}

metric_specs <- list(
  population_total = list(label = "Residents", format = "integer", unit = "residents", percentile = "population_total_percentile"),
  population_density_km2 = list(label = "Population density", format = "integer", unit = "residents / km²", percentile = "population_density_percentile"),
  under18_pct = list(label = "Under 18", format = "percent", unit = "%", percentile = "under18_percentile"),
  age65plus_pct = list(label = "65 and older", format = "percent", unit = "%", percentile = "age65plus_percentile"),
  foreign_citizenship_pct = list(label = "Foreign citizenship", format = "percent", unit = "%", percentile = "foreign_citizenship_percentile"),
  foreign_born_pct = list(label = "Foreign-born", format = "percent", unit = "%", percentile = "foreign_born_percentile"),
  income_per_person_eur = list(label = "Net income / person", format = "currency", unit = "€ / person", percentile = "income_per_person_percentile"),
  below_60_median_pct = list(label = "Below 60% median", format = "percent", unit = "%", percentile = "below_60_median_percentile"),
  above_200_median_pct = list(label = "Above 200% median", format = "percent", unit = "%", percentile = "above_200_median_percentile"),
  gini = list(label = "Gini coefficient", format = "decimal", unit = "index", percentile = "gini_percentile"),
  income_p80_p20 = list(label = "P80/P20 ratio", format = "decimal", unit = "ratio", percentile = "income_p80_p20_percentile")
)

distribution_for <- function(values, spec) {
  valid <- values[is.finite(values)]
  assert_true(length(valid) > 1, paste("Not enough values for", spec$label, "distribution"))
  chart_breaks <- pretty(range(valid), n = 20, min.n = 12)
  if (length(chart_breaks) - 1 < 12) {
    chart_breaks <- seq(min(valid), max(valid), length.out = 13)
  }
  # Stabilise decimal boundaries before both binning and JSON serialization.
  # `pretty()` can return e.g. 3.9000000000000008, which is written as 3.9;
  # using the serialized boundary for the counts keeps markers on bin edges
  # consistent in the browser.
  chart_breaks <- unique(signif(chart_breaks, 12))
  bins <- findInterval(valid, chart_breaks, all.inside = TRUE, rightmost.closed = TRUE)
  list(
    label = spec$label,
    format = spec$format,
    unit = spec$unit,
    breaks = unname(as.list(chart_breaks)),
    counts = unname(as.list(tabulate(bins, nbins = length(chart_breaks) - 1))),
    observationCount = length(valid),
    minimum = if (length(valid)) min(valid) else NA_real_,
    maximum = if (length(valid)) max(valid) else NA_real_
  )
}
distribution_values <- list(
  population_total = current$population_total,
  population_density_km2 = current$population_density_km2,
  under18_pct = current$under18_pct,
  age65plus_pct = current$age65plus_pct,
  foreign_citizenship_pct = current$foreign_citizenship_pct,
  foreign_born_pct = foreign$foreign_born_pct,
  income_per_person_eur = historic$income_per_person_eur,
  below_60_median_pct = historic$below_60_median_pct,
  above_200_median_pct = historic$above_200_median_pct,
  gini = historic$gini,
  income_p80_p20 = historic$income_p80_p20
)
distributions <- lapply(
  names(metric_specs),
  function(metric) distribution_for(distribution_values[[metric]], metric_specs[[metric]])
)
names(distributions) <- names(metric_specs)

party_labels <- list(
  general = c(PP = "PP", PSOE = "PSOE", VOX = "VOX", SUMAR = "SUMAR"),
  local = c(PP = "PP", PSOE = "PSOE", VOX = "VOX", MAS_MADRID = "Más Madrid", PODEMOS_IU_AV = "Podemos-IU-AV"),
  assembly = c(PP = "PP", PSOE = "PSOE", VOX = "VOX", MAS_MADRID = "Más Madrid", PODEMOS_IU_AV = "Podemos-IU-AV")
)
party_colours <- c(
  PP = "#1D84CE", PSOE = "#E32322", VOX = "#63A53A", SUMAR = "#E65A91",
  MAS_MADRID = "#16A085", PODEMOS_IU_AV = "#6B3FA0"
)

election_result_list <- function(row, election) {
  keys <- names(party_labels[[election]])
  lapply(keys, function(key) {
    property <- paste0("share_", tolower(key), "_", election)
    list(
      key = key,
      label = unname(party_labels[[election]][[key]]),
      color = unname(party_colours[[key]]),
      share = row[[property]]
    )
  })
}

city_elections <- lapply(c("general", "local", "assembly"), function(election) {
  metadata <- readRDS(file.path(processed_dir, paste0("election-", election, "-metadata.rds")))
  totals <- unlist(metadata$official_total)
  result_by_key <- setNames(metadata$city_results, vapply(metadata$city_results, `[[`, character(1), "key"))
  keys <- names(party_labels[[election]])
  results <- lapply(keys, function(key) {
    result <- result_by_key[[key]]
    list(
      key = key,
      label = unname(party_labels[[election]][[key]]),
      color = unname(party_colours[[key]]),
      votes = result$votes,
      share = result$share
    )
  })
  list(
    label = switch(election, general = "General election", local = "Madrid local election", assembly = "Madrid Assembly election"),
    referenceDate = metadata$reference_date,
    census = totals[["census"]],
    votesCast = totals[["votes_cast"]],
    validVotes = totals[["valid_votes"]],
    blankVotes = totals[["blank_votes"]],
    turnoutPct = 100 * totals[["votes_cast"]] / totals[["census"]],
    shownCoveragePct = sum(vapply(results, `[[`, numeric(1), "share")),
    results = results
  )
})
names(city_elections) <- c("general", "local", "assembly")

metric_value <- function(row, metric) {
  percentile_property <- metric_specs[[metric]]$percentile
  list(value = row[[metric]], percentile = row[[percentile_property]])
}

section_reports <- vector("list", nrow(report_rows))
names(section_reports) <- report_rows$section_id
for (index in seq_len(nrow(report_rows))) {
  row <- report_rows[index, , drop = FALSE]
  elections <- lapply(c("general", "local", "assembly"), function(election) {
    list(
      turnoutPct = row[[paste0("turnout_pct_", election)]],
      validVotes = row[[paste0("valid_votes_", election)]],
      blankVotes = row[[paste0("blank_votes_", election)]],
      leadingParty = row[[paste0("leading_party_", election)]],
      results = election_result_list(row, election)
    )
  })
  names(elections) <- c("general", "local", "assembly")

  section_reports[[index]] <- list(
    id = row$section_id,
    name = paste0(row$district, " · section ", as.integer(row$section)),
    district = row$district,
    matches = list(
      `2025` = list(
        sectionId = row$section_id_2025,
        overlapShare = row$overlap_share_2025,
        boundaryChanged = row$boundary_changed_2025
      ),
      `2023` = list(
        sectionId = row$section_id_2023,
        overlapShare = row$overlap_share_2023,
        boundaryChanged = row$boundary_changed_2023
      )
    ),
    population = lapply(
      c(
        "population_total", "population_density_km2", "under18_pct", "age65plus_pct",
        "foreign_citizenship_pct", "foreign_born_pct"
      ),
      function(metric) metric_value(row, metric)
    ),
    income = lapply(
      c(
        "income_per_person_eur", "below_60_median_pct", "above_200_median_pct",
        "gini", "income_p80_p20"
      ),
      function(metric) metric_value(row, metric)
    ),
    elections = elections,
    buildings = list(
      buildingCount = ifelse(is.na(row$building_count), 0, row$building_count),
      dwellings = ifelse(is.na(row$dwellings), 0, row$dwellings),
      medianConstructionYear = row$median_construction_year,
      constructionEras = unname(as.list(as.integer(unlist(row[era_columns], use.names = FALSE))))
    )
  )
  names(section_reports[[index]]$population) <- c(
    "population_total", "population_density_km2", "under18_pct", "age65plus_pct",
    "foreign_citizenship_pct", "foreign_born_pct"
  )
  names(section_reports[[index]]$income) <- c(
    "income_per_person_eur", "below_60_median_pct", "above_200_median_pct",
    "gini", "income_p80_p20"
  )
}

manifest <- jsonlite::fromJSON(
  file.path(public_data_dir, "layer-manifest.json"),
  simplifyVector = FALSE
)
matched_buildings <- buildings |> filter(!is.na(section_id))
city_era_counts <- table(factor(matched_buildings$construction_era, levels = era_labels))
layer_reference_date <- function(layer_id) {
  matches <- Filter(function(layer) identical(layer$id, layer_id), manifest$layers)
  assert_true(length(matches) == 1, paste("Missing report reference layer", layer_id))
  matches[[1]]$referenceDate
}
population_metadata <- readRDS(file.path(processed_dir, "population-metadata.rds"))
building_metadata <- readRDS(file.path(processed_dir, "buildings-metadata.rds"))
report_index <- list(
  generatedAt = paste0(format(Sys.time(), "%Y-%m-%dT%H:%M:%S"), "Z"),
  version = "1.0.0",
  canonicalVintage = "2026",
  geographyVintages = list(canonical = "2026", foreignBorn = "2025", incomeAndElections = "2023"),
  dataDates = list(
    population = population_metadata$reference_date,
    foreignBorn = layer_reference_date("population-foreign-born"),
    income = layer_reference_date("income-per-person"),
    buildings = building_metadata$reference_date_catastro
  ),
  methodologyUrl = "https://github.com/danialmazan/madrid/blob/main/docs/methodology.md",
  distributions = distributions,
  constructionEras = unname(as.list(era_labels)),
  cityBuildings = list(
    buildingCount = nrow(matched_buildings),
    dwellings = sum(matched_buildings$dwellings, na.rm = TRUE),
    medianConstructionYear = stats::median(matched_buildings$construction_start_year, na.rm = TRUE),
    constructionEras = unname(as.list(as.integer(city_era_counts)))
  ),
  cityElections = city_elections,
  references = manifest$references,
  sections = section_reports
)

write_json_pretty(report_index, file.path(public_data_dir, "section-reports.json"))
message_step("Section reports ready: ", length(section_reports), " current sections")
