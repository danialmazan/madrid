source(file.path("scripts", "R", "common.R"))

message_step("Validating publication outputs")
manifest_path <- file.path(public_data_dir, "layer-manifest.json")
assert_true(file.exists(manifest_path), "Missing layer-manifest.json")
section_report_path <- file.path(public_data_dir, "section-reports.json")
assert_true(file.exists(section_report_path), "Missing section-reports.json")
housing_analysis_path <- file.path(public_data_dir, "housing-migration-analysis.json")
assert_true(file.exists(housing_analysis_path), "Missing housing-migration-analysis.json")
manifest <- jsonlite::fromJSON(manifest_path, simplifyVector = FALSE)
section_reports <- jsonlite::fromJSON(section_report_path, simplifyVector = FALSE)
housing_analysis <- jsonlite::fromJSON(housing_analysis_path, simplifyVector = FALSE)
places <- jsonlite::fromJSON(file.path(public_data_dir, "places.json"), simplifyVector = FALSE)
place_bounds <- unlist(lapply(places, `[[`, "bbox"))
assert_true(length(places) >= 150, "Place-search index is incomplete")
assert_true(all(is.finite(place_bounds)), "Place-search index contains invalid bounds")
addresses <- jsonlite::fromJSON(
  file.path(public_data_dir, "addresses.json"),
  simplifyVector = FALSE
)
assert_true(length(addresses$records) >= 150000, "Street-address search index is incomplete")
address_coordinates <- unlist(lapply(addresses$records, function(record) record[c(4, 5)]))
assert_true(
  all(is.finite(address_coordinates)) &&
    all(address_coordinates[c(TRUE, FALSE)] > -3.9) &&
    all(address_coordinates[c(TRUE, FALSE)] < -3.4) &&
    all(address_coordinates[c(FALSE, TRUE)] > 40.25) &&
    all(address_coordinates[c(FALSE, TRUE)] < 40.65),
  "Street-address index contains invalid Madrid coordinates"
)

source_ids <- vapply(manifest$sources, `[[`, character(1), "id")
layer_ids <- vapply(manifest$layers, `[[`, character(1), "id")
assert_unique(source_ids, "Manifest source IDs")
assert_unique(layer_ids, "Manifest layer IDs")
assert_true(manifest$defaultLayer %in% layer_ids, "Manifest default layer does not exist")
assert_true(identical(manifest$version, "1.2.0"), "Manifest schema must be 1.2.0")
assert_true(identical(section_reports$version, "1.1.0"), "Report schema must be 1.1.0")
assert_true(identical(housing_analysis$version, "1.0.0"), "Housing analysis schema must be 1.0.0")

source_layer_ids <- unique(unlist(lapply(manifest$layers, `[[`, "sourceIds")))
assert_true(all(source_layer_ids %in% source_ids), "A layer references a missing PMTiles source")

unique_source_urls <- unique(vapply(manifest$sources, `[[`, character(1), "url"))
for (source_url in unique_source_urls) {
  archive_path <- file.path(public_data_dir, sub("^data/", "", source_url))
  assert_true(file.exists(archive_path), paste("Missing PMTiles archive", source_url))
  connection <- file(archive_path, "rb")
  header <- readBin(connection, what = "raw", n = 127)
  close(connection)
  assert_true(length(header) == 127, paste("Incomplete PMTiles header", source_url))
  header_minzoom <- as.integer(header[[101]])
  header_maxzoom <- as.integer(header[[102]])
  matching_sources <- Filter(function(source) identical(source$url, source_url), manifest$sources)
  for (source in matching_sources) {
    assert_true(
      identical(as.integer(source$minzoom), header_minzoom) &&
        identical(as.integer(source$maxzoom), header_maxzoom),
      paste(
        "Manifest zoom does not match PMTiles header for", source$id,
        sprintf("(manifest %s-%s, archive %s-%s)", source$minzoom, source$maxzoom, header_minzoom, header_maxzoom)
      )
    )
  }
}

archive_paths <- list.files(public_data_dir, pattern = "\\.pmtiles$", full.names = TRUE)
assert_true(length(archive_paths) >= 26, "Expected section, resident-dot, building and transport PMTiles archives")
archive_size <- file.info(archive_paths)$size
limit <- 95 * 1024^2
assert_true(all(archive_size < limit), "One or more PMTiles archives exceed 95 MB")

artifact_files <- list.files(file.path(project_root, "public"), recursive = TRUE, full.names = TRUE)
artifact_size <- sum(file.info(artifact_files)$size, na.rm = TRUE)
assert_true(artifact_size < 1024^3, "Pages public artifact exceeds 1 GB")

population <- readRDS(file.path(processed_dir, "population-metadata.rds"))
assert_true(population$coverage >= 0.995, "Population resident join coverage is below 99.5%")
assert_true(
  grepl("^20[0-9]{2}-[0-9]{2}-[0-9]{2}$", population$reference_date) &&
    as.integer(substr(population$reference_date, 1, 4)) <= as.integer(format(Sys.Date(), "%Y")),
  "Population reference date is invalid"
)
population_sections <- readRDS(file.path(processed_dir, "sections-2026-population.rds"))
resident_dots <- readRDS(file.path(processed_dir, "resident-dots.rds"))
resident_dot_meta <- readRDS(file.path(processed_dir, "resident-dots-metadata.rds"))
resident_dot_target <- sum(round(population_sections$population_total / resident_dot_meta$dot_value))
resident_dot_section_counts <- sf::st_drop_geometry(resident_dots) |>
  count(section_id, name = "dot_count")
resident_dot_reconciliation <- population_sections |>
  sf::st_drop_geometry() |>
  transmute(section_id, expected_dots = round(population_total / resident_dot_meta$dot_value)) |>
  left_join(resident_dot_section_counts, by = "section_id")
assert_true(
  identical(as.integer(resident_dot_meta$dot_value), 25L) &&
    nrow(resident_dots) == resident_dot_target &&
    as.numeric(resident_dot_meta$dot_count) == resident_dot_target &&
    as.numeric(resident_dot_meta$sections_reconciled) == nrow(population_sections) &&
    all(resident_dot_reconciliation$expected_dots == resident_dot_reconciliation$dot_count),
  "Resident dots do not reconcile with 25-resident section targets"
)
assert_true(
  isTRUE(resident_dot_meta$points_inside_assigned_geometry) &&
    identical(as.character(resident_dot_meta$fallback_section_id), "2807910157") &&
    as.numeric(resident_dot_meta$fallback_dot_count) == 29 &&
    sum(resident_dots$allocation_method == "municipal-address-fallback") == 29,
  "Resident-dot containment or fallback validation failed"
)
resident_dot_geojson <- file.path(processed_dir, "tile-inputs", "resident-dots.geojson")
assert_true(
  file.exists(resident_dot_geojson) &&
    identical(unname(tools::md5sum(resident_dot_geojson)), resident_dot_meta$coordinate_file_md5),
  "Resident-dot coordinate checksum does not match its generated metadata"
)
node <- Sys.which("node")
assert_true(nzchar(node), "Node.js is required to validate resident-dot PMTiles")
resident_dot_archive <- file.path(public_data_dir, "resident-dots.pmtiles")
resident_dot_tile_output <- system2(
  node,
  c(
    file.path("scripts", "validate_resident_dot_tiles.mjs"),
    resident_dot_archive,
    as.character(resident_dot_target)
  ),
  stdout = TRUE,
  stderr = TRUE
)
resident_dot_tile_status <- attr(resident_dot_tile_output, "status")
assert_true(
  is.null(resident_dot_tile_status) || identical(resident_dot_tile_status, 0L),
  paste("Resident-dot PMTiles validation failed:", paste(resident_dot_tile_output, collapse = "\n"))
)
resident_dot_tiles <- jsonlite::fromJSON(paste(resident_dot_tile_output, collapse = "\n"))
resident_dot_layer <- Filter(function(layer) identical(layer$id, "population-total"), manifest$layers)
assert_true(
  length(resident_dot_layer) == 1 &&
    identical(resident_dot_layer[[1]]$kind, "dot-density") &&
    as.numeric(resident_dot_layer[[1]]$dotValue) == 25 &&
    identical(unlist(resident_dot_layer[[1]]$dotColors), c(light = "#145C9E", dark = "#77C4E4")) &&
    identical(
      as.numeric(unlist(resident_dot_layer[[1]]$dotRadiusStops)),
      c(8, 0.4, 9, 0.45, 11, 0.65, 13, 0.9, 15, 1.3, 17, 1.75, 19, 2.1)
    ) &&
    identical(
      as.numeric(unlist(resident_dot_layer[[1]]$dotOpacityStops)),
      c(8, 0.2, 9, 0.24, 11, 0.34, 13, 0.46, 15, 0.6, 17, 0.72, 19, 0.8)
    ) &&
    identical(resident_dot_layer[[1]]$sourceIds[[1]], "resident-dots"),
  "Resident-dot manifest definition is incomplete"
)
population_percentiles <- sf::st_drop_geometry(population_sections)[
  c(
    "population_density_percentile", "under18_percentile",
    "age65plus_percentile", "population_change_5y_percentile"
  )
]
assert_true(
  all(vapply(population_percentiles, function(x) all(dplyr::between(x, 0, 100), na.rm = TRUE), logical(1))),
  "Population percentile values are out of range"
)
assert_true(
  all(is.na(population_sections$population_change_5y_pct[!population_sections$population_match_comparable])) &&
    all(is.finite(population_sections$population_change_5y_pct[population_sections$population_match_comparable])),
  "Five-year population change violates reciprocal 95% matching"
)

education_sections <- readRDS(file.path(processed_dir, "sections-2024-education-work.rds"))
education_columns <- c("activity_rate_pct", "employment_rate_pct", "unemployment_rate_pct", "higher_education_pct", "low_education_pct")
assert_true(
  all(vapply(sf::st_drop_geometry(education_sections)[education_columns], function(x) all(dplyr::between(x, 0, 100), na.rm = TRUE), logical(1))),
  "Education & Work values are out of range"
)
assert_true(
  all(abs(education_sections$activity_rate_pct - education_sections$employment_rate_pct / (1 - education_sections$unemployment_rate_pct / 100)) < 1e-8, na.rm = TRUE),
  "Education & Work rate identity failed"
)

migration_sections <- readRDS(file.path(processed_dir, "sections-2025-migration.rds"))
country_slugs <- c("total", "venezuela", "colombia", "peru", "ecuador", "republica_dominicana", "argentina", "china", "marruecos")
assert_true(
  all(paste0("foreign_born_pct_", country_slugs) %in% names(migration_sections)) &&
    all(paste0("foreign_citizenship_pct_", country_slugs) %in% names(migration_sections)),
  "Country allow-list fields are incomplete"
)
for (slug in country_slugs) {
  change <- migration_sections[[paste0("foreign_born_change_pp_", slug)]]
  assert_true(all(is.na(change[!migration_sections$migration_match_comparable])), paste("Non-comparable migration change published for", slug))
}

income_sections <- readRDS(file.path(processed_dir, "sections-2023-thematics.rds"))
assert_true(
  all(income_sections$income_p80_p20 >= 1, na.rm = TRUE),
  "P80/P20 income values are out of range"
)
assert_true(
  all(dplyr::between(income_sections$above_200_median_pct, 0, 100), na.rm = TRUE),
  "Above-200%-median income values are out of range"
)
income_percentile_columns <- c(
  "income_per_person_percentile", "income_per_household_percentile", "pension_income_percentile", "below_60_median_percentile",
  "above_200_median_percentile", "gini_percentile", "income_p80_p20_percentile"
)
assert_true(all(income_sections$income_per_household_eur >= 0, na.rm = TRUE), "Negative household income values")
assert_true(all(dplyr::between(income_sections$pension_income_pct, 0, 100), na.rm = TRUE), "Pension-income percentage out of range")
assert_true(
  all(vapply(
    sf::st_drop_geometry(income_sections)[income_percentile_columns],
    function(x) all(dplyr::between(x, 0, 100), na.rm = TRUE),
    logical(1)
  )),
  "Income percentile values are out of range"
)
suppressed_districts <- c("Carabanchel", "Fuencarral-El Pardo")
suppressed_income <- income_sections |> filter(district %in% suppressed_districts)
assert_true(
  all(is.na(suppressed_income$below_60_median_pct)) &&
    all(is.na(suppressed_income$above_200_median_pct)),
  "Known INE-suppressed income indicators unexpectedly contain section values"
)
assert_true(
  all(is.finite(suppressed_income$income_per_person_eur)) &&
    all(is.finite(suppressed_income$gini)) &&
    all(is.finite(suppressed_income$income_p80_p20)),
  "Non-suppressed Carabanchel/Fuencarral income measures are incomplete"
)

report_ids <- names(section_reports$sections)
assert_true(length(report_ids) == 2462, "Section report index must cover all 2,462 current sections")
assert_unique(report_ids, "Section report IDs")
assert_true(
  identical(sort(report_ids), sort(as.character(population_sections$section_id))),
  "Section report IDs do not match current section boundaries"
)
for (report in section_reports$sections) {
  assert_true(
    all(vapply(c("2021", "2023", "2024", "2025"), function(year) !is.null(report$matches[[year]]$sectionId), logical(1))),
    paste("Section report is missing a historical match:", report$id)
  )
}
report_building_count <- sum(vapply(
  section_reports$sections,
  function(report) as.numeric(report$buildings$buildingCount),
  numeric(1)
))
assert_true(
  identical(report_building_count, as.numeric(section_reports$cityBuildings$buildingCount)),
  "Section building counts do not reconcile with the city report total"
)

assert_true(length(housing_analysis$districts) == 21, "Housing analysis must contain all 21 districts")
assert_true(length(housing_analysis$sections) == 2462, "Housing analysis must contain all current sections")
housing_district_codes <- vapply(housing_analysis$districts, `[[`, character(1), "code")
housing_section_ids <- vapply(housing_analysis$sections, `[[`, character(1), "id")
assert_unique(housing_district_codes, "Housing analysis district codes")
assert_unique(housing_section_ids, "Housing analysis section IDs")
assert_true(
  identical(sort(housing_section_ids), sort(report_ids)),
  "Housing analysis sections do not match canonical section reports"
)
nullable_number <- function(value) if (is.null(value)) NA_real_ else as.numeric(value)
missing_changes <- sum(vapply(
  housing_analysis$sections,
  function(section) is.null(section$foreignBornChangePp),
  logical(1)
))
assert_true(missing_changes == 130, "Housing analysis must preserve 130 non-comparable section changes")
for (section in housing_analysis$sections) {
  assert_true(
    as.numeric(section$residentialBuildingCount) >= 0 && as.numeric(section$dwellingCount) >= 0,
    paste("Negative housing weight in section", section$id)
  )
  quantiles <- vapply(
    section$constructionYear[c("p10", "q1", "median", "q3", "p90")],
    nullable_number,
    numeric(1)
  )
  valid_quantiles <- quantiles[is.finite(quantiles)]
  assert_true(
    length(valid_quantiles) %in% c(0, 5) && all(diff(valid_quantiles) >= 0),
    paste("Invalid weighted construction-year quantiles in section", section$id)
  )
}
for (district in housing_analysis$districts) {
  building_total <- sum(vapply(district$distribution, function(item) as.numeric(item$buildingSharePct), numeric(1)))
  dwelling_total <- sum(vapply(district$distribution, function(item) as.numeric(item$dwellingSharePct), numeric(1)))
  assert_true(abs(building_total - 100) < 1e-6, paste("Building cohort shares do not total 100% for", district$name))
  assert_true(abs(dwelling_total - 100) < 1e-6, paste("Dwelling cohort shares do not total 100% for", district$name))
  hypothesis_share <- sum(vapply(
    Filter(function(item) !is.null(item$startYear) && as.integer(item$startYear) %in% c(1961L, 1966L), district$distribution),
    function(item) as.numeric(item$dwellingSharePct),
    numeric(1)
  ))
  assert_true(
    abs(hypothesis_share - as.numeric(district$shareDwellings1961To1970Pct)) < 1e-6,
    paste("1961–1970 hypothesis measure does not reconcile for", district$name)
  )
}
assert_true(
  as.numeric(housing_analysis$coverage$currentSections) == 2462 &&
    as.numeric(housing_analysis$coverage$sectionsWithPositiveDwellingWeight) >= 2460 &&
    as.numeric(housing_analysis$coverage$sectionsWithForeignBorn2025) == 2462 &&
    as.numeric(housing_analysis$coverage$missingSectionChanges) == 130 &&
    as.numeric(housing_analysis$coverage$recordedDwellings) > 1500000,
  "Housing analysis coverage counts are incomplete"
)

for (election in c("general", "local", "assembly")) {
  election_layers <- Filter(
    function(layer) identical(layer$group, "elections") && identical(layer$control$election, election),
    manifest$layers
  )
  assert_true(
    identical(election_layers[[1]]$control$party, "leading"),
    paste("Results/Leading party is not first for", election)
  )
  margin_layer <- Filter(function(layer) identical(layer$id, paste0("election-", election, "-left-right")), election_layers)
  assert_true(length(margin_layer) == 1 && isTRUE(as.numeric(margin_layer[[1]]$scale$center) == 0), paste("Missing zero-centred Left–Right layer for", election))
}

election_checks <- lapply(c("general", "local", "assembly"), function(election) {
  metadata <- readRDS(file.path(processed_dir, paste0("election-", election, "-metadata.rds")))
  difference <- unlist(metadata$difference)
  assert_true(all(abs(difference) <= 2), paste(election, "election reconciliation drifted"))
  values <- readRDS(file.path(processed_dir, paste0("election-", election, ".rds")))
  assert_true(
    all(abs(values$left_right_margin_pp - (values$right_share - values$left_share)) < 1e-10, na.rm = TRUE),
    paste(election, "Left–Right margin formula failed")
  )
  list(election = election, difference = metadata$difference, sections = metadata$sections)
})

transport <- readRDS(file.path(processed_dir, "transport-metadata.rds"))
for (mode in names(transport$gtfs)) {
  values <- transport$gtfs[[mode]]
  assert_true(values$routes > 0, paste(mode, "has no routes"))
  assert_true(values$lines > 0, paste(mode, "has no route shapes"))
  assert_true(values$stops > 0, paste(mode, "has no stops"))
}
assert_true(transport$bicimad$stations > 0, "BiciMAD has no stations")

building <- readRDS(file.path(processed_dir, "buildings-metadata.rds"))
assert_true(building$catastro_buildings > 100000, "Too few Catastro buildings")
assert_true(building$height_polygons > 400000, "Too few height polygons")

report <- list(
  validated_at = paste0(format(Sys.time(), "%Y-%m-%dT%H:%M:%S"), "Z"),
  passed = TRUE,
  counts = list(
    manifest_sources = length(source_ids),
    manifest_layers = length(layer_ids),
    pmtiles_archives = length(archive_paths),
    building_footprints = building$catastro_buildings,
    building_height_polygons = building$height_polygons,
    housing_analysis_sections = length(housing_analysis$sections),
    housing_analysis_districts = length(housing_analysis$districts),
    housing_analysis_recorded_dwellings = housing_analysis$coverage$recordedDwellings,
    resident_dots = resident_dot_meta$dot_count,
    resident_dot_fallback = resident_dot_meta$fallback_dot_count
  ),
  population = list(
    source_residents = population$source_total,
    joined_residents = population$joined_total,
    coverage = population$coverage,
    resident_dot_value = resident_dot_meta$dot_value,
    resident_dots = resident_dot_meta$dot_count,
    represented_residents = resident_dot_meta$represented_population,
    rounding_difference = resident_dot_meta$rounding_difference,
    coordinate_file_md5 = resident_dot_meta$coordinate_file_md5,
    tile_retention = resident_dot_tiles
  ),
  elections = election_checks,
  archives = lapply(seq_along(archive_paths), function(index) {
    list(
      name = basename(archive_paths[[index]]),
      bytes = unname(archive_size[[index]]),
      under_95_mb = archive_size[[index]] < limit
    )
  }),
  public_artifact_bytes = artifact_size,
  licences = lapply(manifest$references, function(reference) {
    list(title = reference$title, licence = reference$licence, url = reference$url)
  })
)
write_json_pretty(report, file.path(public_data_dir, "validation-report.json"))
message_step(
  "Validation passed: ", length(layer_ids), " layers, ",
  round(artifact_size / 1024^2, 1), " MB public artifact"
)
