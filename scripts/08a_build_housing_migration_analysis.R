source(file.path("scripts", "R", "common.R"))

message_step("Building housing-age and migration analysis payload")

section_reports_path <- file.path(public_data_dir, "section-reports.json")
assert_true(file.exists(section_reports_path), "Section reports must be built before the housing analysis")
section_reports <- jsonlite::fromJSON(section_reports_path, simplifyVector = FALSE)
current <- readRDS(file.path(processed_dir, "sections-2026.rds")) |>
  select(section_id, district_code, district)

building_files <- list.files(
  file.path(processed_dir, "buildings"),
  pattern = "^building-age-[0-9]{2}\\.geojson$",
  full.names = TRUE
)
assert_true(length(building_files) == 21, "Expected 21 district building-age inputs")
buildings <- do.call(rbind, lapply(building_files, function(path) sf::st_read(path, quiet = TRUE))) |>
  sf::st_transform(25830) |>
  filter(
    use == "1_residential",
    is.finite(construction_start_year),
    construction_start_year >= 1000,
    construction_start_year <= as.integer(format(Sys.Date(), "%Y")) + 1
  ) |>
  mutate(dwellings = pmax(0, coalesce(as.numeric(dwellings), 0)))

message_step("Assigning residential buildings to current 2026 census sections")
current_projected <- sf::st_transform(current, 25830)
building_points <- suppressWarnings(sf::st_point_on_surface(buildings))
building_hits <- sf::st_intersects(building_points, current_projected)
building_section_index <- vapply(
  building_hits,
  function(hit) if (length(hit)) hit[[1]] else NA_integer_,
  integer(1)
)
assignment_coverage <- mean(!is.na(building_section_index))
assert_true(assignment_coverage >= 0.999, "Too many residential buildings fall outside current sections")
buildings$section_id <- ifelse(
  is.na(building_section_index),
  NA_character_,
  current_projected$section_id[building_section_index]
)
building_rows <- buildings |>
  sf::st_drop_geometry() |>
  filter(!is.na(section_id)) |>
  transmute(
    section_id,
    district_code = as.character(district_code),
    construction_year = as.integer(construction_start_year),
    dwellings = as.numeric(dwellings)
  )

weighted_quantile <- function(values, weights, probability) {
  keep <- is.finite(values) & is.finite(weights) & weights > 0
  if (!any(keep)) return(NA_real_)
  ordered <- order(values[keep])
  sorted_values <- values[keep][ordered]
  sorted_weights <- weights[keep][ordered]
  threshold <- probability * sum(sorted_weights)
  sorted_values[[which(cumsum(sorted_weights) >= threshold)[[1]]]]
}

cohort_start <- function(year) {
  ifelse(year < 1901, NA_integer_, as.integer(floor((year - 1) / 5) * 5 + 1))
}

cohort_label <- function(start) {
  ifelse(
    is.na(start),
    "Before 1901",
    paste0(start, "–", substr(as.character(start + 4), 3, 4))
  )
}

section_buildings <- building_rows |>
  group_by(section_id) |>
  summarise(
    residential_building_count = n(),
    dwelling_count = sum(dwellings),
    p10 = weighted_quantile(construction_year, dwellings, 0.10),
    q1 = weighted_quantile(construction_year, dwellings, 0.25),
    median = weighted_quantile(construction_year, dwellings, 0.50),
    q3 = weighted_quantile(construction_year, dwellings, 0.75),
    p90 = weighted_quantile(construction_year, dwellings, 0.90),
    .groups = "drop"
  ) |>
  mutate(
    median_year_bucket_start = cohort_start(median),
    median_year_bucket_label = if_else(
      is.na(median), NA_character_, cohort_label(median_year_bucket_start)
    )
  )

message_step("Combining section housing measures with comparable migration observations")
report_rows <- lapply(section_reports$sections, function(report) {
  nullable_number <- function(value) if (is.null(value)) NA_real_ else as.numeric(value)
  tibble::tibble(
    section_id = report$id,
    foreign_born_pct_2025 = nullable_number(report$migration$total$foreignBorn$value),
    foreign_born_change_pp = nullable_number(report$migration$total$foreignBornChange$value)
  )
}) |>
  dplyr::bind_rows()

section_rows <- current |>
  sf::st_drop_geometry() |>
  mutate(
    district_code = sprintf("%02d", as.integer(district_code)),
    district = unname(district_names[district_code])
  ) |>
  left_join(report_rows, by = "section_id") |>
  left_join(section_buildings, by = "section_id") |>
  mutate(
    residential_building_count = coalesce(residential_building_count, 0L),
    dwelling_count = coalesce(dwelling_count, 0),
    across(c(p10, q1, median, q3, p90), as.numeric)
  ) |>
  arrange(district_code, section_id)

message_step("Aggregating district distributions and direct INE birthplace totals")
min_cohort_start <- 1901L
max_cohort_start <- max(cohort_start(building_rows$construction_year), na.rm = TRUE)
cohort_grid <- tibble::tibble(
  cohort_order = seq.int(0L, (max_cohort_start - min_cohort_start) %/% 5L + 1L),
  cohort_start = c(NA_integer_, seq.int(min_cohort_start, max_cohort_start, by = 5L)),
  cohort_label = cohort_label(cohort_start)
)
building_cohorts <- building_rows |>
  mutate(
    cohort_start = cohort_start(construction_year),
    cohort_label = cohort_label(cohort_start)
  ) |>
  group_by(district_code, cohort_start, cohort_label) |>
  summarise(
    building_count = n(),
    dwelling_count = sum(dwellings),
    .groups = "drop"
  )

ine_birth <- read_semicolon(file.path(raw_dir, "ine-birth-country-66428.csv")) |>
  mutate(
    section_id = substr(secciones, 1, 10),
    district_code = substr(section_id, 6, 7),
    year = as.integer(periodo),
    category = as.character(pa_is_de_nacimiento),
    value = parse_es_number(total)
  ) |>
  filter(
    grepl("^28079[0-9]{5}$", section_id),
    sexo == "Total", year %in% c(2021, 2025), category %in% c("Total", "España")
  ) |>
  group_by(district_code, year, category) |>
  summarise(value = sum(value, na.rm = TRUE), .groups = "drop") |>
  tidyr::pivot_wider(names_from = category, values_from = value) |>
  mutate(foreign_born = Total - España) |>
  select(district_code, year, population = Total, foreign_born) |>
  tidyr::pivot_wider(names_from = year, values_from = c(population, foreign_born), names_sep = "_") |>
  mutate(
    foreign_born_count_change = foreign_born_2025 - foreign_born_2021,
    foreign_born_growth_pct = 100 * foreign_born_count_change / foreign_born_2021,
    foreign_born_share_2021 = 100 * foreign_born_2021 / population_2021,
    foreign_born_share_2025 = 100 * foreign_born_2025 / population_2025,
    foreign_born_share_change_pp = foreign_born_share_2025 - foreign_born_share_2021
  )

district_totals <- building_rows |>
  group_by(district_code) |>
  summarise(
    residential_building_count = n(),
    dwelling_count = sum(dwellings),
    dwellings_1961_1970 = sum(dwellings[construction_year >= 1961 & construction_year <= 1970]),
    .groups = "drop"
  ) |>
  mutate(share_dwellings_1961_1970_pct = 100 * dwellings_1961_1970 / dwelling_count)

district_rows <- tibble::tibble(
  district_code = names(district_names),
  district = unname(district_names)
) |>
  left_join(district_totals, by = "district_code") |>
  left_join(ine_birth, by = "district_code") |>
  mutate(section_count = vapply(district_code, function(code) sum(section_rows$district_code == code), integer(1))) |>
  arrange(district)

district_payload <- lapply(seq_len(nrow(district_rows)), function(index) {
  row <- district_rows[index, , drop = FALSE]
  code <- row$district_code[[1]]
  totals <- building_cohorts |>
    filter(district_code == code) |>
    select(-district_code)
  distribution <- cohort_grid |>
    left_join(totals, by = c("cohort_start", "cohort_label")) |>
    mutate(
      building_count = coalesce(building_count, 0L),
      dwelling_count = coalesce(dwelling_count, 0),
      building_share_pct = 100 * building_count / row$residential_building_count[[1]],
      dwelling_share_pct = 100 * dwelling_count / row$dwelling_count[[1]]
    )
  list(
    code = code,
    name = row$district[[1]],
    sectionCount = row$section_count[[1]],
    residentialBuildingCount = row$residential_building_count[[1]],
    dwellingCount = row$dwelling_count[[1]],
    shareDwellings1961To1970Pct = row$share_dwellings_1961_1970_pct[[1]],
    foreignBorn = list(
      population2021 = row$population_2021[[1]],
      population2025 = row$population_2025[[1]],
      count2021 = row$foreign_born_2021[[1]],
      count2025 = row$foreign_born_2025[[1]],
      countChange = row$foreign_born_count_change[[1]],
      growthPct = row$foreign_born_growth_pct[[1]],
      share2021 = row$foreign_born_share_2021[[1]],
      share2025 = row$foreign_born_share_2025[[1]],
      shareChangePp = row$foreign_born_share_change_pp[[1]]
    ),
    distribution = lapply(seq_len(nrow(distribution)), function(distribution_index) {
      item <- distribution[distribution_index, , drop = FALSE]
      list(
        order = item$cohort_order[[1]],
        startYear = item$cohort_start[[1]],
        label = item$cohort_label[[1]],
        buildingCount = item$building_count[[1]],
        dwellingCount = item$dwelling_count[[1]],
        buildingSharePct = item$building_share_pct[[1]],
        dwellingSharePct = item$dwelling_share_pct[[1]]
      )
    })
  )
})

section_payload <- lapply(seq_len(nrow(section_rows)), function(index) {
  row <- section_rows[index, , drop = FALSE]
  list(
    id = row$section_id[[1]],
    districtCode = row$district_code[[1]],
    districtName = row$district[[1]],
    foreignBornPct2025 = row$foreign_born_pct_2025[[1]],
    foreignBornChangePp = row$foreign_born_change_pp[[1]],
    residentialBuildingCount = row$residential_building_count[[1]],
    dwellingCount = row$dwelling_count[[1]],
    constructionYear = list(
      p10 = row$p10[[1]], q1 = row$q1[[1]], median = row$median[[1]],
      q3 = row$q3[[1]], p90 = row$p90[[1]]
    ),
    medianYearBucket = list(
      startYear = row$median_year_bucket_start[[1]],
      label = row$median_year_bucket_label[[1]]
    )
  )
})

building_meta <- readRDS(file.path(processed_dir, "buildings-metadata.rds"))
migration_meta <- readRDS(file.path(processed_dir, "migration-metadata.rds"))
payload <- list(
  version = "1.0.0",
  generatedAt = paste0(format(Sys.time(), "%Y-%m-%dT%H:%M:%S"), "Z"),
  title = "Housing age and recent migration in Madrid",
  canonicalGeography = "Madrid census sections, 2026",
  defaultDistrictCode = "11",
  maximumDistrictSelections = 3,
  sources = list(
    list(
      publisher = "Dirección General del Catastro",
      title = "INSPIRE Buildings: Madrid municipality",
      url = building_meta$catastro_source_url,
      geography = "Building footprints assigned to Madrid 2026 census sections",
      vintage = building_meta$reference_date_catastro,
      status = "Direct building attributes; section assignment and weighted summaries are derived"
    ),
    list(
      publisher = "Instituto Nacional de Estadística (INE)",
      title = "Population by country of birth, sex and census section",
      url = migration_meta$birth_source_url,
      geography = "Census sections and direct district-code aggregation",
      vintage = "2021 and 2025",
      status = "Direct counts; shares, changes and boundary matching are derived"
    )
  ),
  calculationNotes = list(
    residentialFilter = "Catastro buildings whose currentUse is residential and whose construction year is valid.",
    weight = "numberOfDwellings. Zero-dwelling residential records remain in the building-count distribution and contribute zero to dwelling-weighted measures.",
    sectionAssignment = "Building point-on-surface assigned to the containing current 2026 census section.",
    quantiles = "Empirical dwelling-weighted construction-year p10, q1, median, q3 and p90.",
    cohorts = "Five-year cohorts start in years ending 1 or 6. Years before 1901 are pooled as Before 1901.",
    hypothesisMeasure = "Share of recorded residential dwellings constructed from 1961 through 1970 inclusive.",
    comparison = "2021–2025 section change is null where reciprocal boundary overlap is below 95%; district change aggregates original INE counts directly by district code."
  ),
  coverage = list(
    currentSections = nrow(section_rows),
    sectionsWithResidentialBuildings = sum(section_rows$residential_building_count > 0),
    sectionsWithPositiveDwellingWeight = sum(section_rows$dwelling_count > 0),
    sectionsWithForeignBorn2025 = sum(is.finite(section_rows$foreign_born_pct_2025)),
    comparableSectionChanges = sum(is.finite(section_rows$foreign_born_change_pp)),
    missingSectionChanges = sum(!is.finite(section_rows$foreign_born_change_pp)),
    residentialBuildings = nrow(building_rows),
    zeroDwellingResidentialBuildings = sum(building_rows$dwellings == 0),
    recordedDwellings = sum(building_rows$dwellings),
    buildingSectionAssignmentPct = 100 * assignment_coverage
  ),
  districts = district_payload,
  sections = section_payload
)

write_json_pretty(payload, file.path(public_data_dir, "housing-migration-analysis.json"))
message_step(
  "Housing analysis ready: ", nrow(section_rows), " sections, ",
  format(sum(building_rows$dwellings), big.mark = ",", scientific = FALSE), " recorded dwellings"
)
