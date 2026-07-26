suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(readr)
  library(sf)
  library(yaml)
})

project_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
raw_dir <- file.path(project_root, "data", "raw")
processed_dir <- file.path(project_root, "data", "processed")
public_data_dir <- file.path(project_root, "public", "data")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(public_data_dir, recursive = TRUE, showWarnings = FALSE)

sources <- yaml::read_yaml(file.path(project_root, "config", "sources.yml"))

message_step <- function(...) {
  message(sprintf("[%s] %s", format(Sys.time(), "%H:%M:%S"), paste0(..., collapse = "")))
}

download_cached <- function(url, destination, insecure = FALSE, refresh = FALSE) {
  if (file.exists(destination) && file.info(destination)$size > 0 && !refresh) {
    message_step("Using cached ", basename(destination))
    return(normalizePath(destination, winslash = "/"))
  }
  dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
  partial <- paste0(destination, ".part")
  args <- c(
    if (insecure) "-k",
    "-fL", "--retry", "3", "--retry-all-errors", "--retry-delay", "2", "--connect-timeout", "45",
    "-o", partial, url
  )
  message_step("Downloading ", basename(destination))
  status <- system2("curl", args = shQuote(args))
  if (!identical(status, 0L)) {
    if (file.exists(partial)) unlink(partial)
    stop("Download failed: ", url)
  }
  if (!file.rename(partial, destination)) stop("Could not move download to ", destination)
  normalizePath(destination, winslash = "/")
}

normalise_names <- function(x) {
  x <- iconv(x, to = "ASCII//TRANSLIT")
  x <- tolower(gsub("[^A-Za-z0-9]+", "_", x))
  x <- gsub("^_|_$", "", x)
  make.unique(x, sep = "_")
}

normalise_sf_names <- function(x) {
  geometry_name <- attr(x, "sf_column")
  geometry_index <- match(geometry_name, names(x))
  new_names <- normalise_names(names(x))
  names(x) <- new_names
  attr(x, "sf_column") <- new_names[[geometry_index]]
  x
}

parse_es_number <- function(x) {
  readr::parse_number(
    as.character(x),
    locale = readr::locale(decimal_mark = ",", grouping_mark = "."),
    na = c("", ".", "..", "...", "NA", "N/A")
  )
}

read_semicolon <- function(path) {
  first_line <- readr::read_lines(path, n_max = 1, progress = FALSE)
  delimiter <- if (grepl("\t", first_line, fixed = TRUE)) "\t" else ";"
  out <- suppressMessages(readr::read_delim(
    path,
    delim = delimiter,
    locale = readr::locale(encoding = "UTF-8"),
    show_col_types = FALSE,
    progress = FALSE,
    trim_ws = TRUE,
    name_repair = "minimal"
  ))
  names(out) <- normalise_names(names(out))
  out
}

make_valid_wgs84 <- function(x) {
  if (is.na(sf::st_crs(x))) {
    bounds <- sf::st_bbox(x)
    assumed_crs <- if (
      abs(bounds[["xmin"]]) <= 180 && abs(bounds[["xmax"]]) <= 180 &&
      abs(bounds[["ymin"]]) <= 90 && abs(bounds[["ymax"]]) <= 90
    ) 4326 else 25830
    sf::st_crs(x) <- assumed_crs
  }
  x |>
    sf::st_make_valid() |>
    sf::st_transform(4326)
}

write_geojson <- function(x, path) {
  if (file.exists(path)) unlink(path)
  sf::st_write(
    x,
    path,
    driver = "GeoJSON",
    delete_dsn = TRUE,
    quiet = TRUE,
    layer_options = "RFC7946=YES"
  )
  invisible(path)
}

write_json_pretty <- function(x, path, auto_unbox = TRUE) {
  jsonlite::write_json(
    x,
    path,
    pretty = TRUE,
    auto_unbox = auto_unbox,
    na = "null",
    null = "null",
    digits = 10
  )
  invisible(path)
}

assert_true <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

assert_unique <- function(x, label) {
  duplicate_count <- sum(duplicated(x[!is.na(x)]))
  assert_true(duplicate_count == 0, paste(label, "contains", duplicate_count, "duplicate identifiers"))
}

district_names <- c(
  "01" = "Centro", "02" = "Arganzuela", "03" = "Retiro", "04" = "Salamanca",
  "05" = "Chamartín", "06" = "Tetuán", "07" = "Chamberí", "08" = "Fuencarral-El Pardo",
  "09" = "Moncloa-Aravaca", "10" = "Latina", "11" = "Carabanchel", "12" = "Usera",
  "13" = "Puente de Vallecas", "14" = "Moratalaz", "15" = "Ciudad Lineal",
  "16" = "Hortaleza", "17" = "Villaverde", "18" = "Villa de Vallecas",
  "19" = "Vicálvaro", "20" = "San Blas-Canillejas", "21" = "Barajas"
)

package_resources <- function(package_id) {
  destination <- file.path(raw_dir, paste0("madrid-package-", package_id, ".json"))
  url <- paste0(sources$madrid_open_data_api, "?id=", package_id)
  download_cached(url, destination, refresh = TRUE)
  payload <- jsonlite::fromJSON(destination, simplifyDataFrame = TRUE)
  assert_true(isTRUE(payload$success), paste("Madrid package API failed for", package_id))
  payload$result$resources
}

pick_resource_url <- function(resources, pattern, format = NULL) {
  candidates <- resources
  searchable <- paste(candidates$name, candidates$description, candidates$url, candidates$format)
  keep <- grepl(pattern, searchable, ignore.case = TRUE, perl = TRUE)
  if (!is.null(format)) {
    keep <- keep & grepl(format, candidates$format, ignore.case = TRUE)
  }
  candidates <- candidates[keep, , drop = FALSE]
  assert_true(nrow(candidates) > 0, paste("No Madrid resource matched", pattern))
  as.character(candidates$url[[1]])
}

save_metadata <- function(name, metadata) {
  saveRDS(metadata, file.path(processed_dir, paste0(name, "-metadata.rds")))
}

safe_date <- function(x, fallback) {
  parsed <- suppressWarnings(as.Date(x))
  if (all(is.na(parsed))) as.Date(fallback) else max(parsed, na.rm = TRUE)
}
