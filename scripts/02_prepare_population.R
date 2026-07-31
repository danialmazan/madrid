source(file.path("scripts", "R", "common.R"))

message_step("Resolving latest monthly Madrid padrón")
population_resources <- package_resources(sources$madrid_population_package)
population_url <- pick_resource_url(
  population_resources,
  "padron.*csv|200076.*csv",
  "CSV"
)
population_path <- file.path(raw_dir, "madrid-padron-latest.csv")
download_cached(population_url, population_path, refresh = TRUE)
population_raw <- read_semicolon(population_path)

required <- c(
  "cod_dist_seccion", "cod_edad_int", "espanoleshombres", "espanolesmujeres",
  "extranjeroshombres", "extranjerosmujeres"
)
assert_true(all(required %in% names(population_raw)), "Unexpected Madrid padrón schema")

population <- population_raw |>
  mutate(
    section_id = paste0("28079", sprintf("%05d", as.integer(cod_dist_seccion))),
    age = as.integer(cod_edad_int),
    spanish = rowSums(across(c(espanoleshombres, espanolesmujeres), ~coalesce(as.numeric(.x), 0))),
    foreign = rowSums(across(c(extranjeroshombres, extranjerosmujeres), ~coalesce(as.numeric(.x), 0))),
    residents = spanish + foreign
  ) |>
  filter(grepl("^28079[0-9]{5}$", section_id), !is.na(age)) |>
  group_by(section_id) |>
  summarise(
    population_total = sum(residents, na.rm = TRUE),
    under18_pct = if_else(population_total > 0, 100 * sum(residents[age < 18], na.rm = TRUE) / population_total, NA_real_),
    age65plus_pct = if_else(population_total > 0, 100 * sum(residents[age >= 65], na.rm = TRUE) / population_total, NA_real_),
    foreign_citizenship_pct = if_else(population_total > 0, 100 * sum(foreign, na.rm = TRUE) / population_total, NA_real_),
    .groups = "drop"
  )

sections_2026 <- readRDS(file.path(processed_dir, "sections-2026.rds"))
sections_2026 <- sections_2026 |>
  left_join(population, by = "section_id")
area_km2 <- as.numeric(sf::st_area(sf::st_transform(sections_2026, 25830))) / 1e6
sections_2026$population_density_km2 <- sections_2026$population_total / area_km2
sections_2026 <- sections_2026 |>
  mutate(
    population_density_percentile = section_percentile(population_density_km2),
    under18_percentile = section_percentile(under18_pct),
    age65plus_percentile = section_percentile(age65plus_pct),
    foreign_citizenship_percentile = section_percentile(foreign_citizenship_pct)
  )

source_total <- sum(population$population_total, na.rm = TRUE)
joined_total <- sum(sections_2026$population_total, na.rm = TRUE)
coverage <- joined_total / source_total
assert_true(coverage >= 0.995, sprintf("Population join coverage %.3f%% is below 99.5%%", 100 * coverage))
assert_true(all(sections_2026$population_total >= 0, na.rm = TRUE), "Negative population totals")
assert_true(all(dplyr::between(sections_2026$under18_pct, 0, 100), na.rm = TRUE), "Under-18 percentage out of range")
assert_true(all(dplyr::between(sections_2026$age65plus_pct, 0, 100), na.rm = TRUE), "65+ percentage out of range")
assert_true(all(dplyr::between(sections_2026$foreign_citizenship_pct, 0, 100), na.rm = TRUE), "Foreign-citizenship percentage out of range")
saveRDS(sections_2026, file.path(processed_dir, "sections-2026-population.rds"))

date_columns <- intersect(c("fx_datos_fin", "fx_carga"), names(population_raw))
reference_date <- if (length(date_columns)) {
  values <- population_raw[[date_columns[[1]]]]
  parsed <- if (inherits(values, "Date")) {
    values
  } else if (inherits(values, "POSIXt")) {
    as.Date(values)
  } else {
    suppressWarnings(as.Date(
      as.character(values),
      tryFormats = c("%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y")
    ))
  }
  format(max(parsed, na.rm = TRUE), "%Y-%m-%d")
} else {
  format(Sys.Date(), "%Y-%m-%d")
}
if (identical(reference_date, "-Inf")) reference_date <- format(Sys.Date(), "%Y-%m-%d")
save_metadata("population", list(
  reference_date = reference_date,
  source_url = population_url,
  source_total = source_total,
  joined_total = joined_total,
  coverage = coverage
))

message_step("Preparing annual foreign-born share")
foreign_path <- file.path(raw_dir, "ine-foreign-born-69211.csv")
download_cached(sources$ine_foreign_born_csv, foreign_path)
foreign_raw <- read_semicolon(foreign_path)
required_foreign <- c("secciones", "sexo", "lugar_de_nacimiento", "periodo", "total")
assert_true(all(required_foreign %in% names(foreign_raw)), "Unexpected INE foreign-born schema")
latest_period <- max(as.integer(foreign_raw$periodo), na.rm = TRUE)
foreign_madrid <- foreign_raw |>
  mutate(
    section_id = sub(".*?([0-9]{10}).*", "\\1", secciones),
    value = parse_es_number(total),
    birthplace = tolower(iconv(lugar_de_nacimiento, to = "ASCII//TRANSLIT"))
  ) |>
  filter(
    grepl("^28079[0-9]{5}$", section_id),
    tolower(sexo) == "total",
    as.integer(periodo) == latest_period,
    grepl("total|extranjero", birthplace)
  ) |>
  mutate(category = if_else(grepl("extranjero", birthplace), "foreign", "total")) |>
  select(section_id, category, value) |>
  distinct() |>
  tidyr::pivot_wider(names_from = category, values_from = value) |>
  mutate(foreign_born_pct = 100 * foreign / total)

sections_2025 <- readRDS(file.path(processed_dir, "sections-2025.rds")) |>
  left_join(foreign_madrid |> select(section_id, foreign_born_pct), by = "section_id") |>
  mutate(foreign_born_percentile = section_percentile(foreign_born_pct))
assert_true(all(dplyr::between(sections_2025$foreign_born_pct, 0, 100), na.rm = TRUE), "Foreign-born percentage out of range")
saveRDS(sections_2025, file.path(processed_dir, "sections-2025-foreign-born.rds"))
save_metadata("foreign-born", list(
  reference_date = as.character(latest_period),
  source_url = sources$ine_foreign_born_csv,
  matched_sections = sum(!is.na(sections_2025$foreign_born_pct)),
  total_sections = nrow(sections_2025)
))

message_step(sprintf("Population ready: %.2f%% resident join coverage", 100 * coverage))
