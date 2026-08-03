source(file.path("scripts", "R", "common.R"))

read_ine_section_measure <- function(path, source_url, category_pattern, expected_categories) {
  download_cached(source_url, path)
  raw <- read_semicolon(path)
  category_col <- names(raw)[grepl(category_pattern, names(raw))][[1]]
  assert_true(
    all(c("secciones", "sexo", "periodo", "total", category_col) %in% names(raw)),
    paste("Unexpected INE schema for", basename(path))
  )
  observed <- unique(as.character(raw[[category_col]]))
  assert_true(all(expected_categories %in% observed), paste("Missing categories in", basename(path)))
  raw |>
    mutate(
      section_id = sub(".*?([0-9]{10}).*", "\\1", secciones),
      category = .data[[category_col]],
      value = parse_es_number(total)
    ) |>
    filter(
      grepl("^28079[0-9]{5}$", section_id),
      sexo == "Total",
      as.integer(periodo) == 2024,
      category %in% expected_categories
    ) |>
    select(section_id, category, value)
}

message_step("Preparing INE 2024 Education & Work measures")
education_categories <- c("Total", "Educación primaria e inferior", "Educación superior")
activity_categories <- c("Total", "Ocupado/a", "Parado/a")

education <- read_ine_section_measure(
  file.path(raw_dir, "ine-education-66753.csv"),
  sources$ine_education_csv,
  "nivel_de_formaci",
  education_categories
) |>
  tidyr::pivot_wider(names_from = category, values_from = value) |>
  transmute(
    section_id,
    higher_education_pct = 100 * `Educación superior` / Total,
    low_education_pct = 100 * `Educación primaria e inferior` / Total
  )

activity <- read_ine_section_measure(
  file.path(raw_dir, "ine-activity-66755.csv"),
  sources$ine_activity_csv,
  "relaci_on_con_la_actividad",
  activity_categories
) |>
  tidyr::pivot_wider(names_from = category, values_from = value) |>
  transmute(
    section_id,
    activity_rate_pct = 100 * (`Ocupado/a` + `Parado/a`) / Total,
    employment_rate_pct = 100 * `Ocupado/a` / Total,
    unemployment_rate_pct = 100 * `Parado/a` / (`Ocupado/a` + `Parado/a`)
  )

education_work <- full_join(activity, education, by = "section_id")
metric_columns <- c(
  "activity_rate_pct", "employment_rate_pct", "unemployment_rate_pct",
  "higher_education_pct", "low_education_pct"
)
assert_unique(education_work$section_id, "INE 2024 Education & Work")
for (column in metric_columns) {
  assert_true(all(dplyr::between(education_work[[column]], 0, 100), na.rm = TRUE), paste(column, "out of range"))
  education_work[[sub("_pct$", "_percentile", column)]] <- section_percentile(education_work[[column]])
}
identity_gap <- abs(
  education_work$activity_rate_pct -
    education_work$employment_rate_pct / (1 - education_work$unemployment_rate_pct / 100)
)
assert_true(all(identity_gap < 1e-8, na.rm = TRUE), "Activity/employment/unemployment identity failed")

sections_2024 <- readRDS(file.path(processed_dir, "sections-2024.rds")) |>
  left_join(education_work, by = "section_id")
assert_true(sum(!is.na(sections_2024$activity_rate_pct)) > 2300, "Too few Education & Work section matches")
saveRDS(sections_2024, file.path(processed_dir, "sections-2024-education-work.rds"))
save_metadata("education-work", list(
  reference_date = "2024",
  education_source_url = sources$ine_education_csv,
  activity_source_url = sources$ine_activity_csv,
  matched_sections = sum(!is.na(sections_2024$activity_rate_pct)),
  total_sections = nrow(sections_2024)
))
message_step("Education & Work ready: ", sum(!is.na(sections_2024$activity_rate_pct)), " sections")
