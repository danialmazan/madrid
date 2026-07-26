source(file.path("scripts", "R", "common.R"))

transport_dir <- file.path(processed_dir, "transport")
dir.create(transport_dir, recursive = TRUE, showWarnings = FALSE)

read_gtfs_table <- function(directory, filename, required = TRUE) {
  path <- file.path(directory, filename)
  if (!file.exists(path)) {
    if (required) stop("Missing GTFS table: ", filename)
    return(NULL)
  }
  suppressMessages(readr::read_csv(
    path,
    show_col_types = FALSE,
    progress = FALSE,
    col_types = cols(.default = col_character())
  ))
}

route_colour <- function(x, fallback = "#145C9E") {
  value <- trimws(as.character(x))
  value[value == "" | is.na(value)] <- sub("^#", "", fallback)
  paste0("#", sub("^#", "", value))
}

prepare_cercanias_features <- function(item) {
  station_url <- paste0(
    sources$cercanias_feature_service,
    "/0/query?where=1%3D1&outFields=*&f=geojson&outSR=4326"
  )
  line_url <- paste0(
    sources$cercanias_feature_service,
    "/4/query?where=1%3D1&outFields=*&f=geojson&outSR=4326"
  )
  station_path <- file.path(raw_dir, "cercanias-stations.geojson")
  line_path <- file.path(raw_dir, "cercanias-lines.geojson")
  download_cached(station_url, station_path, refresh = TRUE)
  download_cached(line_url, line_path, refresh = TRUE)
  stations <- normalise_sf_names(sf::st_read(station_path, quiet = TRUE, stringsAsFactors = FALSE))
  lines <- normalise_sf_names(sf::st_read(line_path, quiet = TRUE, stringsAsFactors = FALSE))

  stations <- make_valid_wgs84(stations) |>
    transmute(
      mode = "cercanias",
      stop_id = as.character(codigoestacion),
      stop_name = tools::toTitleCase(tolower(as.character(denominacion))),
      route_id = as.character(lineas),
      route_short_name = as.character(lineas),
      route_long_name = paste("Cercanías", as.character(lineas)),
      route_color = "#C21F39",
      geometry
    )
  lines <- make_valid_wgs84(lines) |>
    transmute(
      mode = "cercanias",
      route_id = as.character(codigogestionlinea),
      route_short_name = as.character(numerolineausuario),
      route_long_name = paste("Cercanías", as.character(numerolineausuario)),
      route_color = "#C21F39",
      route_text_color = "#FFFFFF",
      geometry
    )
  write_geojson(lines, file.path(transport_dir, "cercanias-lines.geojson"))
  write_geojson(stations, file.path(transport_dir, "cercanias-stops.geojson"))
  routes <- lines |>
    sf::st_drop_geometry() |>
    distinct(route_short_name, route_long_name) |>
    arrange(route_short_name)
  saveRDS(routes, file.path(processed_dir, "routes-cercanias.rds"))
  list(
    source_url = sources$cercanias_feature_service,
    item_id = item$item_id,
    routes = nrow(routes),
    lines = nrow(lines),
    stops = nrow(stations)
  )
}

prepare_gtfs <- function(mode, item) {
  if (mode == "cercanias") return(prepare_cercanias_features(item))
  zip_path <- file.path(raw_dir, paste0("gtfs-", mode, ".zip"))
  url <- paste0("https://www.arcgis.com/sharing/rest/content/items/", item$item_id, "/data")
  download_cached(url, zip_path)
  extract_dir <- file.path(raw_dir, paste0("gtfs-", mode))
  dir.create(extract_dir, recursive = TRUE, showWarnings = FALSE)
  utils::unzip(zip_path, exdir = extract_dir, overwrite = TRUE)

  routes <- read_gtfs_table(extract_dir, "routes.txt") |>
    mutate(
      route_short_name = coalesce(route_short_name, route_id),
      route_long_name = coalesce(route_long_name, route_short_name),
      route_color = route_colour(route_color),
      route_text_color = route_colour(route_text_color, "#FFFFFF")
    )
  trips <- read_gtfs_table(extract_dir, "trips.txt")
  stops <- read_gtfs_table(extract_dir, "stops.txt") |>
    mutate(
      stop_lon = as.numeric(stop_lon),
      stop_lat = as.numeric(stop_lat)
    ) |>
    filter(is.finite(stop_lon), is.finite(stop_lat))
  stop_times <- read_gtfs_table(extract_dir, "stop_times.txt")
  shapes <- read_gtfs_table(extract_dir, "shapes.txt", required = FALSE)

  route_fields <- routes |>
    select(route_id, route_short_name, route_long_name, route_color, route_text_color)
  trip_routes <- trips |>
    select(any_of(c("trip_id", "route_id", "shape_id", "direction_id", "trip_headsign"))) |>
    left_join(route_fields, by = "route_id")

  if (!is.null(shapes) && all(c("shape_pt_lon", "shape_pt_lat", "shape_id") %in% names(shapes))) {
    shape_routes <- trip_routes |>
      filter(!is.na(shape_id), shape_id != "") |>
      distinct(shape_id, .keep_all = TRUE)
    shape_points <- shapes |>
      mutate(
        shape_pt_lon = as.numeric(shape_pt_lon),
        shape_pt_lat = as.numeric(shape_pt_lat),
        shape_pt_sequence = as.numeric(shape_pt_sequence)
      ) |>
      filter(is.finite(shape_pt_lon), is.finite(shape_pt_lat)) |>
      arrange(shape_id, shape_pt_sequence)
    shape_groups <- split(shape_points, shape_points$shape_id)
    line_geometry <- lapply(shape_groups, function(group) {
      sf::st_linestring(as.matrix(group[, c("shape_pt_lon", "shape_pt_lat")]))
    })
    lines <- sf::st_sf(
      shape_id = names(shape_groups),
      geometry = sf::st_sfc(line_geometry, crs = 4326)
    ) |>
      left_join(shape_routes, by = "shape_id")
  } else {
    canonical_trips <- trip_routes |>
      group_by(route_id, direction_id) |>
      slice_head(n = 1) |>
      ungroup()
    route_points <- stop_times |>
      inner_join(canonical_trips, by = "trip_id") |>
      left_join(stops |> select(stop_id, stop_lon, stop_lat), by = "stop_id") |>
      mutate(stop_sequence = as.numeric(stop_sequence)) |>
      filter(is.finite(stop_lon), is.finite(stop_lat)) |>
      arrange(trip_id, stop_sequence)
    line_points <- split(route_points, route_points$trip_id)
    line_geometry <- lapply(line_points, function(group) {
      sf::st_linestring(as.matrix(group[, c("stop_lon", "stop_lat")]))
    })
    lines <- sf::st_sf(
      trip_id = names(line_points),
      geometry = sf::st_sfc(line_geometry, crs = 4326)
    ) |>
      left_join(canonical_trips, by = "trip_id")
  }

  stop_routes <- stop_times |>
    select(trip_id, stop_id) |>
    distinct() |>
    inner_join(trip_routes |> select(trip_id, route_id), by = "trip_id") |>
    distinct(stop_id, route_id) |>
    left_join(route_fields, by = "route_id") |>
    inner_join(stops |> select(any_of(c("stop_id", "stop_name", "stop_lon", "stop_lat", "wheelchair_boarding"))), by = "stop_id")
  stop_points <- sf::st_as_sf(stop_routes, coords = c("stop_lon", "stop_lat"), crs = 4326, remove = TRUE)

  lines <- lines |>
    transmute(
      mode = mode,
      route_id,
      route_short_name,
      route_long_name,
      route_color,
      route_text_color,
      geometry
    ) |>
    filter(!sf::st_is_empty(geometry))
  stop_points <- stop_points |>
    transmute(
      mode = mode,
      stop_id,
      stop_name,
      route_id,
      route_short_name,
      route_long_name,
      route_color,
      geometry
    )

  write_geojson(lines, file.path(transport_dir, paste0(mode, "-lines.geojson")))
  write_geojson(stop_points, file.path(transport_dir, paste0(mode, "-stops.geojson")))
  route_options <- route_fields |>
    distinct(route_short_name, route_long_name) |>
    arrange(suppressWarnings(as.numeric(route_short_name)), route_short_name)
  saveRDS(route_options, file.path(processed_dir, paste0("routes-", mode, ".rds")))

  list(
    source_url = url,
    item_id = item$item_id,
    routes = nrow(route_fields),
    lines = nrow(lines),
    stops = n_distinct(stop_points$stop_id)
  )
}

message_step("Preparing CRTM static-network snapshots")
gtfs_metadata <- Map(prepare_gtfs, names(sources$gtfs), sources$gtfs)
names(gtfs_metadata) <- names(sources$gtfs)

message_step("Preparing BiciMAD stations")
bicimad_path <- file.path(raw_dir, "bicimad-stations.geojson")
download_cached(sources$bicimad_geojson, bicimad_path, insecure = TRUE, refresh = TRUE)
bicimad <- sf::st_read(bicimad_path, quiet = TRUE, stringsAsFactors = FALSE)
bicimad <- normalise_sf_names(bicimad)
name_field <- intersect(c("name", "nombre", "station_name", "direccion"), names(bicimad))[[1]]
id_field <- intersect(c("id", "station_id", "numero", "number"), names(bicimad))[[1]]
bicimad <- make_valid_wgs84(bicimad) |>
  transmute(
    mode = "bicimad",
    stop_id = as.character(.data[[id_field]]),
    stop_name = as.character(.data[[name_field]]),
    geometry
  )
write_geojson(bicimad, file.path(transport_dir, "bicimad-stops.geojson"))

save_metadata("transport", list(
  reference_date = format(Sys.Date(), "%Y-%m-%d"),
  snapshot = TRUE,
  gtfs = gtfs_metadata,
  bicimad = list(
    source_url = sources$bicimad_geojson,
    stations = nrow(bicimad)
  )
))
message_step("Transport ready")
