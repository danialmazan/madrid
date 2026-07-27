source(file.path("scripts", "R", "common.R"))

tippecanoe <- Sys.which("tippecanoe")
assert_true(nzchar(tippecanoe), "Tippecanoe is required to build PMTiles archives")

tile_input_dir <- file.path(processed_dir, "tile-inputs")
dir.create(tile_input_dir, recursive = TRUE, showWarnings = FALSE)

run_tippecanoe <- function(output, layer_inputs, minimum_zoom, maximum_zoom, extra = character()) {
  if (file.exists(output)) unlink(output)
  args <- c(
    "-o", output,
    "--force",
    "--minimum-zoom", as.character(minimum_zoom),
    "--maximum-zoom", as.character(maximum_zoom),
    "--no-feature-limit",
    "--no-tile-size-limit",
    "--simplification", "8",
    "--detect-shared-borders",
    "--coalesce-densest-as-needed",
    extra,
    unlist(Map(function(layer, path) c("-L", paste0(layer, ":", path)), names(layer_inputs), layer_inputs))
  )
  message_step("Building ", basename(output))
  status <- system2(tippecanoe, args = args)
  assert_true(identical(status, 0L), paste("Tippecanoe failed for", basename(output)))
  assert_true(file.exists(output) && file.info(output)$size > 0, paste("No archive produced:", output))
}

section_name <- function(x) {
  paste0(x$district, " · section ", as.integer(x$section))
}

message_step("Writing section tile inputs")
sections_2026 <- readRDS(file.path(processed_dir, "sections-2026-population.rds")) |>
  mutate(
    section_name = section_name(pick(everything())),
    across(
      c(
        population_density_km2, under18_pct, age65plus_pct, foreign_citizenship_pct,
        population_density_percentile, under18_percentile, age65plus_percentile,
        foreign_citizenship_percentile
      ),
      ~round(.x, 2)
    )
  ) |>
  select(
    section_id, section_name, district, population_total, population_density_km2,
    under18_pct, age65plus_pct, foreign_citizenship_pct,
    population_density_percentile, under18_percentile, age65plus_percentile,
    foreign_citizenship_percentile, geometry
  )
sections_2025 <- readRDS(file.path(processed_dir, "sections-2025-foreign-born.rds")) |>
  mutate(
    section_name = section_name(pick(everything())),
    foreign_born_pct = round(foreign_born_pct, 2),
    foreign_born_percentile = round(foreign_born_percentile, 2)
  ) |>
  select(section_id, section_name, district, foreign_born_pct, foreign_born_percentile, geometry)
sections_2023 <- readRDS(file.path(processed_dir, "sections-2023-thematics.rds")) |>
  mutate(
    section_name = section_name(pick(everything())),
    across(where(is.numeric), ~round(.x, 2))
  ) |>
  select(section_id, section_name, district, everything())

section_inputs <- c(
  "sections_2026" = file.path(tile_input_dir, "sections-2026.geojson"),
  "sections_2025" = file.path(tile_input_dir, "sections-2025.geojson"),
  "sections_2023" = file.path(tile_input_dir, "sections-2023.geojson")
)
write_geojson(sections_2026, section_inputs[["sections_2026"]])
write_geojson(sections_2025, section_inputs[["sections_2025"]])
write_geojson(sections_2023, section_inputs[["sections_2023"]])

for (year in c("2026", "2025", "2023")) {
  layer <- paste0("sections_", year)
  run_tippecanoe(
    file.path(public_data_dir, paste0("sections-", year, ".pmtiles")),
    setNames(section_inputs[[layer]], layer),
    minimum_zoom = 8,
    maximum_zoom = 15
  )
}

message_step("Building district-split building archives")
building_dir <- file.path(processed_dir, "buildings")
for (code in names(district_names)) {
  inputs <- c(
    building_age = file.path(building_dir, paste0("building-age-", code, ".geojson")),
    building_height = file.path(building_dir, paste0("building-height-", code, ".geojson"))
  )
  assert_true(all(file.exists(inputs)), paste("Missing building inputs for district", code))
  run_tippecanoe(
    file.path(public_data_dir, paste0("buildings-", code, ".pmtiles")),
    inputs,
    minimum_zoom = 12,
    maximum_zoom = 16
  )
}

message_step("Building combined transport archive")
transport_dir <- file.path(processed_dir, "transport")
transport_inputs <- c()
for (mode in c("metro", "metro_ligero", "cercanias", "emt")) {
  transport_inputs[paste0(mode, "_lines")] <- file.path(transport_dir, paste0(mode, "-lines.geojson"))
  transport_inputs[paste0(mode, "_stops")] <- file.path(transport_dir, paste0(mode, "-stops.geojson"))
}
transport_inputs[["bicimad_stops"]] <- file.path(transport_dir, "bicimad-stops.geojson")
assert_true(all(file.exists(transport_inputs)), "Missing one or more transport tile inputs")
run_tippecanoe(
  file.path(public_data_dir, "transport.pmtiles"),
  transport_inputs,
  minimum_zoom = 8,
  maximum_zoom = 16
)

message_step("PMTiles archives ready")
