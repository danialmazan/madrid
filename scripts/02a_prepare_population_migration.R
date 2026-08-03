source(file.path("scripts", "R", "common.R"))

country_options <- tibble::tribble(
  ~slug, ~label,
  "venezuela", "Venezuela",
  "colombia", "Colombia",
  "peru", "Perú",
  "ecuador", "Ecuador",
  "republica_dominicana", "República Dominicana",
  "argentina", "Argentina",
  "china", "China",
  "marruecos", "Marruecos"
)

padron_totals <- function(raw) {
  required <- c(
    "cod_dist_seccion", "cod_edad_int", "espanoleshombres", "espanolesmujeres",
    "extranjeroshombres", "extranjerosmujeres"
  )
  assert_true(all(required %in% names(raw)), "Unexpected historical Madrid padrón schema")
  raw |>
    mutate(
      section_id = paste0("28079", sprintf("%05d", as.integer(cod_dist_seccion))),
      residents = rowSums(
        across(c(espanoleshombres, espanolesmujeres, extranjeroshombres, extranjerosmujeres), ~coalesce(as.numeric(.x), 0))
      )
    ) |>
    filter(grepl("^28079[0-9]{5}$", section_id), !is.na(as.integer(cod_edad_int))) |>
    group_by(section_id) |>
    summarise(population_2021 = sum(residents, na.rm = TRUE), .groups = "drop")
}

message_step("Preparing reciprocal 2021–2026 population comparison")
population_meta <- readRDS(file.path(processed_dir, "population-metadata.rds"))
reference_date <- as.Date(population_meta$reference_date)
month_names_es <- c(
  "enero", "febrero", "marzo", "abril", "mayo", "junio",
  "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"
)
historic_resources <- package_resources(sources$madrid_historic_population_package)
searchable <- paste(historic_resources$name, historic_resources$description, historic_resources$url)
historic_keep <- grepl("2021", searchable) &
  grepl(month_names_es[as.integer(format(reference_date, "%m"))], searchable, ignore.case = TRUE) &
  grepl("CSV", historic_resources$format, ignore.case = TRUE)
assert_true(sum(historic_keep) >= 1, "No same-month 2021 historical padrón CSV found")
historic_url <- as.character(historic_resources$url[which(historic_keep)[[1]]])
historic_path <- file.path(raw_dir, sprintf("madrid-padron-2021-%02d.csv", as.integer(format(reference_date, "%m"))))
download_cached(historic_url, historic_path)
population_2021 <- padron_totals(read_semicolon(historic_path))

sections_2021 <- readRDS(file.path(processed_dir, "sections-2021.rds"))
sections_2026 <- readRDS(file.path(processed_dir, "sections-2026-population.rds")) |>
  select(-any_of(c(
    "population_match_2021", "population_match_comparable", "population_2021",
    "population_change_5y_pct", "population_change_5y_percentile"
  )))
population_crosswalk <- mutual_overlap_crosswalk(sections_2026, sections_2021, 2021)
population_comparison <- population_crosswalk |>
  left_join(population_2021, by = c("matched_section_id" = "section_id")) |>
  mutate(population_2021 = if_else(comparable, population_2021, NA_real_)) |>
  select(section_id, population_match_2021 = matched_section_id, population_match_comparable = comparable, population_2021)
sections_2026 <- sections_2026 |>
  left_join(population_comparison, by = "section_id") |>
  mutate(
    population_change_5y_pct = if_else(
      population_match_comparable & population_2021 > 0,
      round(100 * (population_total / population_2021 - 1), 10),
      NA_real_
    ),
    population_change_5y_percentile = section_percentile(population_change_5y_pct)
  )
saveRDS(sections_2026, file.path(processed_dir, "sections-2026-population.rds"))

read_country_table <- function(path, url, category_pattern) {
  download_cached(url, path)
  raw <- read_semicolon(path)
  category_col <- names(raw)[grepl(category_pattern, names(raw))][[1]]
  required <- c("secciones", "sexo", "periodo", "total", category_col)
  assert_true(all(required %in% names(raw)), paste("Unexpected INE country schema:", basename(path)))
  expected <- c("Total", "España", country_options$label)
  assert_true(all(expected %in% unique(raw[[category_col]])), paste("Missing country categories:", basename(path)))
  raw |>
    mutate(
      section_id = sub(".*?([0-9]{10}).*", "\\1", secciones),
      category = as.character(.data[[category_col]]),
      year = as.integer(periodo),
      value = parse_es_number(total)
    ) |>
    filter(
      grepl("^28079[0-9]{5}$", section_id), sexo == "Total",
      year %in% c(2021, 2025), category %in% expected
    ) |>
    select(section_id, year, category, value)
}

country_shares <- function(long, selected_year) {
  wide <- long |>
    filter(.data$year == selected_year) |>
    select(section_id, category, value) |>
    tidyr::pivot_wider(names_from = category, values_from = value)
  result <- wide |>
    transmute(section_id, denominator = Total, total = Total - España)
  for (index in seq_len(nrow(country_options))) {
    result[[country_options$slug[[index]]]] <- wide[[country_options$label[[index]]]]
  }
  result |>
    mutate(across(c(total, all_of(country_options$slug)), ~100 * .x / denominator)) |>
    mutate(across(c(total, all_of(country_options$slug)), ~round(.x, 10))) |>
    select(-denominator)
}

message_step("Preparing 2025 INE country-controlled migration measures")
birth_long <- read_country_table(
  file.path(raw_dir, "ine-birth-country-66428.csv"),
  sources$ine_birth_country_csv,
  "pa_is_de_nacimiento"
)
nationality_long <- read_country_table(
  file.path(raw_dir, "ine-nationality-country-66429.csv"),
  sources$ine_nationality_country_csv,
  "pa_is_de_nacionalidad"
)
birth_2025 <- country_shares(birth_long, 2025)
birth_2021 <- country_shares(birth_long, 2021)
nationality_2025 <- country_shares(nationality_long, 2025)

rename_country_columns <- function(data, prefix) {
  names(data)[names(data) != "section_id"] <- paste0(prefix, names(data)[names(data) != "section_id"])
  data
}

sections_2025 <- readRDS(file.path(processed_dir, "sections-2025.rds"))
migration_crosswalk <- mutual_overlap_crosswalk(sections_2025, sections_2021, 2021)
birth_change <- migration_crosswalk |>
  left_join(rename_country_columns(birth_2021, "birth_2021_"), by = c("matched_section_id" = "section_id")) |>
  left_join(rename_country_columns(birth_2025, "birth_2025_"), by = "section_id")
for (slug in c("total", country_options$slug)) {
  birth_change[[paste0("foreign_born_change_pp_", slug)]] <- ifelse(
    birth_change$comparable,
    round(birth_change[[paste0("birth_2025_", slug)]] - birth_change[[paste0("birth_2021_", slug)]], 10),
    NA_real_
  )
}
birth_change <- birth_change |>
  select(section_id, migration_match_2021 = matched_section_id, migration_match_comparable = comparable, starts_with("foreign_born_change_pp_"))

migration <- sections_2025 |>
  left_join(rename_country_columns(birth_2025, "foreign_born_pct_"), by = "section_id") |>
  left_join(rename_country_columns(nationality_2025, "foreign_citizenship_pct_"), by = "section_id") |>
  left_join(birth_change, by = "section_id")
metric_prefixes <- c("foreign_born_pct_", "foreign_citizenship_pct_", "foreign_born_change_pp_")
for (prefix in metric_prefixes) {
  for (slug in c("total", country_options$slug)) {
    column <- paste0(prefix, slug)
    percentile <- sub("_pct_|_pp_", "_percentile_", column)
    migration[[percentile]] <- section_percentile(migration[[column]])
  }
}
share_columns <- names(migration)[grepl("^foreign_(born|citizenship)_pct_", names(migration))]
assert_true(all(vapply(sf::st_drop_geometry(migration)[share_columns], function(x) all(dplyr::between(x, 0, 100), na.rm = TRUE), logical(1))), "Migration share out of range")
assert_unique(migration$section_id, "2025 migration sections")
saveRDS(migration, file.path(processed_dir, "sections-2025-migration.rds"))
save_metadata("migration", list(
  reference_date = "2025",
  change_period = "2021–2025",
  birth_source_url = sources$ine_birth_country_csv,
  nationality_source_url = sources$ine_nationality_country_csv,
  country_ranking_source_url = sources$madrid_birth_country_2026_xlsx,
  countries = as.list(country_options$label),
  unavailable_top_ten = c("Honduras", "Paraguay"),
  comparable_sections = sum(migration$migration_match_comparable, na.rm = TRUE),
  total_sections = nrow(migration)
))
message_step(
  "Population and migration comparisons ready: ",
  sum(sections_2026$population_match_comparable, na.rm = TRUE), " population; ",
  sum(migration$migration_match_comparable, na.rm = TRUE), " migration comparable sections"
)
