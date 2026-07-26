source(file.path("scripts", "R", "common.R"))

building_dir <- file.path(processed_dir, "buildings")
dir.create(building_dir, recursive = TRUE, showWarnings = FALSE)

catastro_zip <- file.path(raw_dir, "catastro-buildings-28900.zip")
heights_zip <- file.path(raw_dir, "madrid-building-heights.zip")
download_cached(sources$catastro_buildings_zip, catastro_zip, insecure = TRUE)
download_cached(sources$madrid_building_heights_zip, heights_zip)

message_step("Reading Catastro building footprints and construction dates")
catastro_dsn <- paste0(
  "/vsizip/", normalizePath(catastro_zip, winslash = "/"),
  "/A.ES.SDGC.BU.28900.building.gml"
)
catastro <- sf::st_read(
  catastro_dsn,
  query = paste(
    "SELECT gml_id, beginning, end, reference, currentUse,",
    "numberOfBuildingUnits, numberOfDwellings, geometry FROM Building"
  ),
  quiet = TRUE,
  stringsAsFactors = FALSE
)
catastro <- normalise_sf_names(catastro)
geometry_col <- attr(catastro, "sf_column")
assert_true(!is.null(geometry_col), "Catastro buildings did not include geometry")

extract_year <- function(x) {
  year <- suppressWarnings(as.integer(substr(as.character(x), 1, 4)))
  year[year < 1000 | year > as.integer(format(Sys.Date(), "%Y")) + 1] <- NA_integer_
  year
}

catastro <- catastro |>
  transmute(
    building_id = trimws(as.character(gml_id)),
    construction_start_year = extract_year(beginning),
    construction_end_year = extract_year(end),
    construction_year_range = case_when(
      is.na(construction_start_year) ~ NA_character_,
      is.na(construction_end_year) | construction_start_year == construction_end_year ~
        as.character(construction_start_year),
      TRUE ~ paste0(construction_start_year, "–", construction_end_year)
    ),
    use = as.character(currentuse),
    building_units = suppressWarnings(as.integer(numberofbuildingunits)),
    dwellings = suppressWarnings(as.integer(numberofdwellings)),
    geometry
  ) |>
  sf::st_zm(drop = TRUE, what = "ZM") |>
  sf::st_make_valid()

message_step("Reading municipal estimated-height polygons")
height_dsn <- paste0("/vsizip/", normalizePath(heights_zip, winslash = "/"))
heights <- sf::st_read(
  height_dsn,
  query = paste(
    "SELECT ID_3D, ORIGEN, FECHA_ALTA, Z_HUELLA, Z_CAMB_ALT, ALTURA",
    "FROM ALTURAS_EDIFICIOS"
  ),
  quiet = TRUE,
  stringsAsFactors = FALSE
)
heights <- normalise_sf_names(heights)
heights <- heights |>
  transmute(
    height_id = as.character(id_3d),
    source_method = as.character(origen),
    source_date = as.character(fecha_alta),
    ground_elevation_m = as.numeric(z_huella),
    height_m = pmax(0, as.numeric(altura)),
    geometry = .data[[attr(heights, "sf_column")]]
  ) |>
  sf::st_zm(drop = TRUE, what = "ZM") |>
  sf::st_make_valid()
assert_true(all(heights$height_m >= 0, na.rm = TRUE), "Building heights contain negative values")

districts <- readRDS(file.path(processed_dir, "sections-2026.rds")) |>
  group_by(district_code, district) |>
  summarise(do_union = TRUE, .groups = "drop") |>
  sf::st_transform(25830)

assign_district <- function(features) {
  features <- sf::st_transform(features, 25830)
  points <- suppressWarnings(sf::st_point_on_surface(features))
  matches <- sf::st_intersects(points, districts)
  index <- vapply(matches, function(item) if (length(item)) item[[1]] else NA_integer_, integer(1))
  features$district_code <- ifelse(is.na(index), NA_character_, districts$district_code[index])
  features$district <- ifelse(is.na(index), NA_character_, districts$district[index])
  features
}

message_step("Assigning buildings to districts")
catastro <- assign_district(catastro) |>
  filter(!is.na(district_code), !sf::st_is_empty(geometry))
heights <- assign_district(heights) |>
  filter(!is.na(district_code), !sf::st_is_empty(geometry))

message_step("Writing district-level building inputs")
district_counts <- list()
for (code in names(district_names)) {
  age_part <- catastro |>
    filter(district_code == code) |>
    sf::st_transform(4326)
  height_part <- heights |>
    filter(district_code == code) |>
    sf::st_transform(4326)
  write_geojson(age_part, file.path(building_dir, paste0("building-age-", code, ".geojson")))
  write_geojson(height_part, file.path(building_dir, paste0("building-height-", code, ".geojson")))
  district_counts[[code]] <- list(age = nrow(age_part), height = nrow(height_part))
}

save_metadata("buildings", list(
  reference_date_catastro = "2026-02-20",
  reference_date_heights = "2026-06-18",
  catastro_source_url = sources$catastro_buildings_zip,
  heights_source_url = sources$madrid_building_heights_zip,
  counts = district_counts,
  construction_year_available = sum(!is.na(catastro$construction_start_year)),
  catastro_buildings = nrow(catastro),
  height_polygons = nrow(heights)
))

message_step(
  "Buildings ready: ", nrow(catastro), " Catastro buildings and ",
  nrow(heights), " height polygons"
)
