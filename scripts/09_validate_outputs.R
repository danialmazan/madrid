source(file.path("scripts", "R", "common.R"))

message_step("Validating publication outputs")
manifest_path <- file.path(public_data_dir, "layer-manifest.json")
assert_true(file.exists(manifest_path), "Missing layer-manifest.json")
manifest <- jsonlite::fromJSON(manifest_path, simplifyVector = FALSE)
places <- jsonlite::fromJSON(file.path(public_data_dir, "places.json"), simplifyVector = FALSE)
place_bounds <- unlist(lapply(places, `[[`, "bbox"))
assert_true(length(places) >= 150, "Place-search index is incomplete")
assert_true(all(is.finite(place_bounds)), "Place-search index contains invalid bounds")

source_ids <- vapply(manifest$sources, `[[`, character(1), "id")
layer_ids <- vapply(manifest$layers, `[[`, character(1), "id")
assert_unique(source_ids, "Manifest source IDs")
assert_unique(layer_ids, "Manifest layer IDs")
assert_true(manifest$defaultLayer %in% layer_ids, "Manifest default layer does not exist")

source_layer_ids <- unique(unlist(lapply(manifest$layers, `[[`, "sourceIds")))
assert_true(all(source_layer_ids %in% source_ids), "A layer references a missing PMTiles source")

archive_paths <- list.files(public_data_dir, pattern = "\\.pmtiles$", full.names = TRUE)
assert_true(length(archive_paths) >= 25, "Expected section, building and transport PMTiles archives")
archive_size <- file.info(archive_paths)$size
limit <- 95 * 1024^2
assert_true(all(archive_size < limit), "One or more PMTiles archives exceed 95 MB")

artifact_files <- list.files(file.path(project_root, "public"), recursive = TRUE, full.names = TRUE)
artifact_size <- sum(file.info(artifact_files)$size, na.rm = TRUE)
assert_true(artifact_size < 1024^3, "Pages public artifact exceeds 1 GB")

population <- readRDS(file.path(processed_dir, "population-metadata.rds"))
assert_true(population$coverage >= 0.995, "Population resident join coverage is below 99.5%")
assert_true(
  grepl("^20[0-9]{2}-[0-9]{2}-[0-9]{2}$", population$reference_date) &&
    as.integer(substr(population$reference_date, 1, 4)) <= as.integer(format(Sys.Date(), "%Y")),
  "Population reference date is invalid"
)

election_checks <- lapply(c("general", "local", "assembly"), function(election) {
  metadata <- readRDS(file.path(processed_dir, paste0("election-", election, "-metadata.rds")))
  difference <- unlist(metadata$difference)
  assert_true(all(abs(difference) <= 2), paste(election, "election reconciliation drifted"))
  list(election = election, difference = metadata$difference, sections = metadata$sections)
})

transport <- readRDS(file.path(processed_dir, "transport-metadata.rds"))
for (mode in names(transport$gtfs)) {
  values <- transport$gtfs[[mode]]
  assert_true(values$routes > 0, paste(mode, "has no routes"))
  assert_true(values$lines > 0, paste(mode, "has no route shapes"))
  assert_true(values$stops > 0, paste(mode, "has no stops"))
}
assert_true(transport$bicimad$stations > 0, "BiciMAD has no stations")

building <- readRDS(file.path(processed_dir, "buildings-metadata.rds"))
assert_true(building$catastro_buildings > 100000, "Too few Catastro buildings")
assert_true(building$height_polygons > 400000, "Too few height polygons")

report <- list(
  validated_at = paste0(format(Sys.time(), "%Y-%m-%dT%H:%M:%S"), "Z"),
  passed = TRUE,
  counts = list(
    manifest_sources = length(source_ids),
    manifest_layers = length(layer_ids),
    pmtiles_archives = length(archive_paths),
    building_footprints = building$catastro_buildings,
    building_height_polygons = building$height_polygons
  ),
  population = list(
    source_residents = population$source_total,
    joined_residents = population$joined_total,
    coverage = population$coverage
  ),
  elections = election_checks,
  archives = lapply(seq_along(archive_paths), function(index) {
    list(
      name = basename(archive_paths[[index]]),
      bytes = unname(archive_size[[index]]),
      under_95_mb = archive_size[[index]] < limit
    )
  }),
  public_artifact_bytes = artifact_size,
  licences = lapply(manifest$references, function(reference) {
    list(title = reference$title, licence = reference$licence, url = reference$url)
  })
)
write_json_pretty(report, file.path(public_data_dir, "validation-report.json"))
message_step(
  "Validation passed: ", length(layer_ids), " layers, ",
  round(artifact_size / 1024^2, 1), " MB public artifact"
)
