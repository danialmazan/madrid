source(file.path("scripts", "R", "common.R"))
income_year <- as.integer(source_lock$income_year)
income_geography <- as.integer(source_lock$income_geography_vintage)
assert_true(income_geography == income_year + 1L, "ADRH requires the following January census frame")

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
    # Filter before numeric conversion: geographic labels and other years are not indicator values.
    filter(as.character(.data[[period_col]]) == as.character(income_year), grepl("28079[0-9]{5}", .data[[section_col]])) |>
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
      period == income_year,
      grepl(metric_pattern, indicator_ascii, perl = TRUE)
    ) |>
    transmute(section_id, !!value_name := value) |>
    distinct()
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
  "por_debajo_60_.*mediana",
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
  "por_encima_200_.*mediana",
  "above_200_median_pct"
)

assert_true(nrow(income_person) > 2000, "Too few income-per-person sections")
assert_true(nrow(income_household) > 2000, "Too few income-per-household sections")
assert_true(nrow(pension_income) > 2000, "Too few pension-income sections")
assert_true(nrow(income_risk) > 2000, "Too few income-risk sections")
assert_true(nrow(gini) > 2000, "Too few Gini sections")
assert_true(nrow(income_p80_p20) > 2000, "Too few P80/P20 sections")
assert_true(nrow(above_200_median) > 2000, "Too few above-200%-median sections")

sections_income <- readRDS(file.path(processed_dir, paste0("sections-", income_geography, ".rds")))
income_metrics <- list(income_person, income_household, pension_income, income_risk, gini, income_p80_p20, above_200_median)
for (values in income_metrics) {
  assert_unique(values$section_id, "Income indicator section IDs")
  field <- setdiff(names(values), "section_id")
  unmatched <- values |> filter(!section_id %in% sections_income$section_id, !is.na(.data[[field]]))
  assert_true(nrow(unmatched) == 0, paste("Income values have no matching", income_geography, "geometry"))
  sections_income <- left_join(sections_income, values, by = "section_id")
}
sections_income <- sections_income |>
  mutate(
    income_per_person_percentile = section_percentile(income_per_person_eur),
    income_per_household_percentile = section_percentile(income_per_household_eur),
    pension_income_percentile = section_percentile(pension_income_pct),
    below_60_median_percentile = section_percentile(below_60_median_pct),
    above_200_median_percentile = section_percentile(above_200_median_pct),
    gini_percentile = section_percentile(gini),
    income_p80_p20_percentile = section_percentile(income_p80_p20)
  )

assert_true(all(sections_income$income_per_person_eur >= 0, na.rm = TRUE), "Negative income values")
assert_true(all(sections_income$income_per_household_eur >= 0, na.rm = TRUE), "Negative household income values")
assert_true(all(dplyr::between(sections_income$pension_income_pct, 0, 100), na.rm = TRUE), "Pension-income percentage out of range")
assert_true(all(dplyr::between(sections_income$below_60_median_pct, 0, 100), na.rm = TRUE), "Income-risk percentage out of range")
assert_true(all(dplyr::between(sections_income$gini, 0, 100), na.rm = TRUE), "Gini values out of range")
assert_true(all(sections_income$income_p80_p20 >= 1, na.rm = TRUE), "P80/P20 values out of range")
assert_true(all(dplyr::between(sections_income$above_200_median_pct, 0, 100), na.rm = TRUE), "Above-200%-median percentage out of range")
saveRDS(sections_income, file.path(processed_dir, "sections-2025-income-2024.rds"))
save_metadata("income", list(
  reference_date = as.character(income_year),
  geography_vintage = as.character(income_geography),
  source_urls = lapply(income_downloads, `[[`, 1),
  matched = list(
    income_per_person = sum(is.finite(sections_income$income_per_person_eur)),
    income_per_household = sum(is.finite(sections_income$income_per_household_eur)),
    pension_income = sum(is.finite(sections_income$pension_income_pct)),
    below_60_median = sum(is.finite(sections_income$below_60_median_pct)),
    gini = sum(is.finite(sections_income$gini)),
    p80_p20 = sum(is.finite(sections_income$income_p80_p20)),
    above_200_median = sum(is.finite(sections_income$above_200_median_pct))
  )
))

message_step("Income layers ready: ", income_year, " income on ", income_geography, " sections")
