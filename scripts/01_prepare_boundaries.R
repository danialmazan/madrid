source(file.path("scripts", "R", "common.R"))

ine_sections_url <- function(year) {
  paste0(
    sources$ine_sections_wfs,
    "?service=WFS&version=2.0.0&request=GetFeature",
    "&typeName=WMS_INE_SECCIONES_G01%3ASecciones_", year,
    "&outputFormat=application%2Fjson",
    "&CQL_FILTER=CUMUN%3D%2728079%27%20AND%20CSEC%3C%3E%27000%27",
    "&count=10000&srsName=EPSG%3A4326"
  )
}

prepare_ine_boundary <- function(year) {
  if (year == 2026) {
    destination <- file.path(raw_dir, "madrid-current-sections.zip")
    download_cached(sources$madrid_current_sections_zip, destination)
    dsn <- paste0("/vsizip/", normalizePath(destination, winslash = "/"))
    sections <- sf::st_read(
      dsn,
      query = "SELECT * FROM SECCIONES_CENSALES",
      quiet = TRUE,
      stringsAsFactors = FALSE
    )
    sections <- normalise_sf_names(sections)
    sections <- sections |>
      transmute(
        section_id = paste0("28079", sprintf("%05d", as.integer(cod_seccio))),
        district_code = sprintf("%02d", as.integer(cod_dis)),
        district = as.character(nom_dis),
        section = sprintf("%03d", as.integer(substring(sprintf("%05d", as.integer(cod_seccio)), 3, 5))),
        geometry = .data[[attr(sections, "sf_column")]]
      ) |>
      make_valid_wgs84()
  } else {
  destination <- file.path(raw_dir, paste0("ine-sections-", year, ".geojson"))
  download_cached(ine_sections_url(year), destination)
  sections <- sf::st_read(destination, quiet = TRUE, stringsAsFactors = FALSE)
  sections <- normalise_sf_names(sections)
  assert_true(all(c("cusec", "cdis", "csec") %in% names(sections)), "Unexpected INE boundary schema")
  sections <- sections |>
    transmute(
      section_id = as.character(cusec),
      district_code = as.character(cdis),
      district = unname(district_names[as.character(cdis)]),
      section = as.character(csec),
      geometry
    ) |>
    make_valid_wgs84()
  }
  assert_true(all(sf::st_is_valid(sections)), paste("Invalid", year, "section geometries"))
  assert_unique(sections$section_id, paste(year, "section boundaries"))
  assert_true(nrow(sections) > 2300, paste("Too few INE sections for", year))
  saveRDS(sections, file.path(processed_dir, paste0("sections-", year, ".rds")))
  sections
}

message_step("Preparing matching INE census-section vintages")
boundaries <- lapply(c(2023, 2025, 2026), prepare_ine_boundary)
names(boundaries) <- c("2023", "2025", "2026")

message_step("Preparing place-search index")
districts <- boundaries[["2026"]] |>
  group_by(district_code, district) |>
  summarise(do_union = TRUE, .groups = "drop")

places <- lapply(seq_len(nrow(districts)), function(index) {
  bounds <- sf::st_bbox(districts[index, ])
  list(
    id = paste0("district-", districts$district_code[[index]]),
    name = districts$district[[index]],
    kind = "district",
    bbox = unname(c(bounds[["xmin"]], bounds[["ymin"]], bounds[["xmax"]], bounds[["ymax"]]))
  )
})

resources <- tryCatch(
  package_resources(sources$madrid_boundaries_package),
  error = function(error) {
    warning(conditionMessage(error))
    NULL
  }
)

neighbourhood_path <- file.path(raw_dir, "madrid-neighbourhoods.geojson")
neighbourhood_url <- NULL
if (!is.null(resources)) {
  neighbourhood_url <- tryCatch(
    pick_resource_url(resources, "barrios.*\\.(json|geojson)|barrios.*json", "JSON|GEOJSON"),
    error = function(error) NULL
  )
}
if (!is.null(neighbourhood_url)) {
  download_cached(neighbourhood_url, neighbourhood_path)
}
if (file.exists(neighbourhood_path)) {
  neighbourhoods <- sf::st_read(neighbourhood_path, quiet = TRUE, stringsAsFactors = FALSE)
  neighbourhoods <- normalise_sf_names(neighbourhoods)
  name_col <- intersect(c("nombre", "nom_bar", "nombre_barrio", "name"), names(neighbourhoods))[[1]]
  district_col <- intersect(c("nomdis", "nombre_distrito", "distrito", "nom_dist"), names(neighbourhoods))[[1]]
  if (!is.null(name_col)) {
    neighbourhoods <- make_valid_wgs84(neighbourhoods)
    neighbourhood_places <- lapply(seq_len(nrow(neighbourhoods)), function(index) {
      bounds <- sf::st_bbox(neighbourhoods[index, ])
      list(
        id = paste0("neighbourhood-", index),
        name = as.character(neighbourhoods[[name_col]][[index]]),
        kind = "neighbourhood",
        district = if (!is.null(district_col)) as.character(neighbourhoods[[district_col]][[index]]) else NULL,
        bbox = unname(c(bounds[["xmin"]], bounds[["ymin"]], bounds[["xmax"]], bounds[["ymax"]]))
      )
    })
    places <- c(places, neighbourhood_places)
  }
}

write_json_pretty(places, file.path(public_data_dir, "places.json"), auto_unbox = TRUE)

message_step("Preparing official street-address search index")
address_path <- file.path(raw_dir, "madrid-street-addresses.csv")
download_cached(sources$madrid_street_addresses_csv, address_path)
addresses <- suppressMessages(readr::read_delim(
  address_path,
  delim = ";",
  locale = readr::locale(encoding = "ISO-8859-1", decimal_mark = ","),
  col_types = readr::cols(.default = readr::col_character()),
  show_col_types = FALSE,
  progress = FALSE,
  trim_ws = TRUE
))
names(addresses) <- normalise_names(names(addresses))
assert_true(
  all(c(
    "cod_ndp", "via_clase", "via_par", "via_nombre_acentos", "numero",
    "calificador", "tipo_ndp", "distrito", "utmx_etrs", "utmy_etrs"
  ) %in% names(addresses)),
  "Unexpected official street-address schema"
)

title_es <- function(value) {
  result <- tools::toTitleCase(tolower(ifelse(is.na(value), "", value)))
  for (connector in c("De", "Del", "La", "Las", "Los", "Y")) {
    result <- gsub(
      paste0("\\b", connector, "\\b"),
      tolower(connector),
      result,
      perl = TRUE
    )
  }
  trimws(result)
}

addresses <- addresses |>
  mutate(
    utmx_etrs = parse_es_number(utmx_etrs),
    utmy_etrs = parse_es_number(utmy_etrs)
  ) |>
  filter(
    tipo_ndp == "PORTAL",
    is.finite(utmx_etrs),
    is.finite(utmy_etrs),
    !is.na(cod_ndp)
  ) |>
  distinct(cod_ndp, .keep_all = TRUE)

address_points <- sf::st_as_sf(
  addresses,
  coords = c("utmx_etrs", "utmy_etrs"),
  crs = 25830,
  remove = FALSE
) |>
  sf::st_transform(4326)
address_coordinates <- sf::st_coordinates(address_points)
address_labels <- trimws(gsub(
  "\\s+",
  " ",
  paste(
    title_es(addresses$via_clase),
    tolower(ifelse(is.na(addresses$via_par), "", addresses$via_par)),
    title_es(addresses$via_nombre_acentos),
    addresses$numero,
    ifelse(is.na(addresses$calificador), "", addresses$calificador)
  )
))
address_districts <- unname(district_names[sprintf("%02d", as.integer(addresses$distrito))])
address_records <- lapply(seq_len(nrow(addresses)), function(index) {
  unname(list(
    paste0("address-", addresses$cod_ndp[[index]]),
    address_labels[[index]],
    address_districts[[index]],
    round(address_coordinates[index, "X"], 6),
    round(address_coordinates[index, "Y"], 6)
  ))
})
jsonlite::write_json(
  list(
    referenceDate = format(Sys.Date(), "%Y-%m-%d"),
    records = address_records
  ),
  file.path(public_data_dir, "addresses.json"),
  auto_unbox = TRUE,
  pretty = FALSE,
  na = "null"
)
message_step("Address search ready: ", length(address_records), " valid portals")
message_step("Boundaries ready: ", paste(vapply(boundaries, nrow, integer(1)), collapse = ", "), " sections")
