source(file.path("scripts", "R", "common.R"))

dot_value <- 25L
fallback_section_id <- "2807910157"
dot_seed <- 2807925L

message_step("Building deterministic dasymetric resident dots")

sections <- readRDS(file.path(processed_dir, "sections-2026-population.rds")) |>
  sf::st_transform(25830) |>
  arrange(section_id) |>
  mutate(dot_count = as.integer(round(population_total / dot_value)))

building_files <- list.files(
  file.path(processed_dir, "buildings"),
  pattern = "^building-age-[0-9]{2}\\.geojson$",
  full.names = TRUE
)
assert_true(length(building_files) == 21, "Expected 21 district Catastro building inputs")

buildings <- do.call(rbind, lapply(building_files, function(path) sf::st_read(path, quiet = TRUE))) |>
  sf::st_transform(25830) |>
  filter(use == "1_residential", is.finite(dwellings), dwellings > 0) |>
  arrange(building_id)

message_step("Assigning residential buildings to current census sections")
building_points <- suppressWarnings(sf::st_point_on_surface(buildings))
building_hits <- sf::st_intersects(building_points, sections)
building_section_index <- vapply(
  building_hits,
  function(hit) if (length(hit)) hit[[1]] else NA_integer_,
  integer(1)
)
buildings$section_id <- ifelse(
  is.na(building_section_index),
  NA_character_,
  sections$section_id[building_section_index]
)
assert_true(mean(!is.na(buildings$section_id)) >= 0.999, "Residential-building section assignment is incomplete")

largest_remainder <- function(weights, target, identifiers) {
  assert_true(length(weights) == length(identifiers), "Allocation weights and identifiers differ")
  assert_true(target >= 0 && sum(weights) > 0, "Dot allocation received invalid weights")
  expected <- target * weights / sum(weights)
  allocation <- floor(expected)
  remainder <- as.integer(target - sum(allocation))
  if (remainder > 0) {
    priority <- order(-(expected - allocation), identifiers)
    allocation[priority[seq_len(remainder)]] <- allocation[priority[seq_len(remainder)]] + 1L
  }
  as.integer(allocation)
}

sample_all_containers <- function(containers) {
  assert_true(requireNamespace("s2", quietly = TRUE), "The s2 R package is required for resident-dot validation")
  expected_container <- rep(seq_len(nrow(containers)), containers$allocated_dots)
  dot_count <- length(expected_container)
  message_step(
    "Sampling ", dot_count, " dots inside ", nrow(containers),
    " allocated building footprints"
  )

  container_bounds <- vapply(
    sf::st_geometry(containers),
    function(geometry) unname(sf::st_bbox(geometry)),
    numeric(4)
  )
  containers_wgs84 <- sf::st_transform(sf::st_geometry(containers), 4326)
  assigned_geography <- s2::s2_geog_from_wkb(
    sf::st_as_binary(containers_wgs84[expected_container]),
    check = FALSE
  )
  assigned_bounds <- container_bounds[, expected_container, drop = FALSE]
  sampled_x <- rep(NA_real_, dot_count)
  sampled_y <- rep(NA_real_, dot_count)
  pending <- seq_len(dot_count)
  set.seed(dot_seed)
  attempt <- 0L

  while (length(pending) > 0) {
    attempt <- attempt + 1L
    candidate_x <- stats::runif(
      length(pending),
      assigned_bounds[1, pending],
      assigned_bounds[3, pending]
    )
    candidate_y <- stats::runif(
      length(pending),
      assigned_bounds[2, pending],
      assigned_bounds[4, pending]
    )
    candidate_points <- sf::st_as_sf(
      data.frame(x = candidate_x, y = candidate_y),
      coords = c("x", "y"),
      crs = sf::st_crs(containers)
    ) |>
      sf::st_transform(4326)
    accepted <- s2::s2_covers(
      assigned_geography[pending],
      s2::s2_geog_from_wkb(sf::st_as_binary(sf::st_geometry(candidate_points)), check = FALSE)
    )
    accepted_indexes <- pending[accepted]
    sampled_x[accepted_indexes] <- candidate_x[accepted]
    sampled_y[accepted_indexes] <- candidate_y[accepted]
    pending <- pending[!accepted]
    assert_true(attempt < 500L, "Resident-dot rejection sampling did not converge")
  }

  sampled <- sf::st_as_sf(
    data.frame(
      section_id = containers$section_id[expected_container],
      container_id = containers$container_id[expected_container],
      allocation_method = containers$allocation_method[expected_container],
      x = sampled_x,
      y = sampled_y
    ),
    coords = c("x", "y"),
    crs = sf::st_crs(containers)
  )
  message_step("Verifying every dot against its assigned footprint")
  final_covered <- s2::s2_covers(
    assigned_geography,
    s2::s2_geog_from_wkb(
      sf::st_as_binary(sf::st_geometry(sf::st_transform(sampled, 4326))),
      check = FALSE
    )
  )
  assert_true(
    all(final_covered),
    "A sampled resident dot falls outside its assigned building"
  )
  message_step(
    "All ", nrow(sampled), " resident dots passed footprint containment after ",
    attempt, " rejection rounds"
  )
  sampled
}

regular_sections <- sections |>
  filter(section_id != fallback_section_id)
building_rows_by_section <- split(seq_len(nrow(buildings)), buildings$section_id)
buildings$allocated_dots <- 0L

for (section_index in seq_len(nrow(regular_sections))) {
  section <- regular_sections[section_index, ]
  candidate_rows <- building_rows_by_section[[section$section_id[[1]]]]
  candidates <- buildings[candidate_rows, ]
  assert_true(nrow(candidates) > 0, paste("No residential dwelling weights for", section$section_id[[1]]))
  allocations <- largest_remainder(
    candidates$dwellings,
    section$dot_count[[1]],
    candidates$building_id
  )
  buildings$allocated_dots[candidate_rows] <- allocations
}

message_step("Preparing address-linked municipal-building fallback for ", fallback_section_id)
fallback_section <- sections |>
  filter(section_id == fallback_section_id)
assert_true(nrow(fallback_section) == 1, "Fallback census section is missing")

fallback_heights <- sf::st_read(
  file.path(processed_dir, "buildings", "building-height-10.geojson"),
  quiet = TRUE
) |>
  sf::st_transform(25830)
fallback_height_points <- suppressWarnings(sf::st_point_on_surface(fallback_heights))
fallback_heights <- fallback_heights[lengths(sf::st_intersects(fallback_height_points, fallback_section)) > 0, ] |>
  arrange(height_id)
assert_true(nrow(fallback_heights) > 0, "Fallback section has no municipal building polygons")

addresses <- suppressMessages(readr::read_delim(
  file.path(raw_dir, "madrid-street-addresses.csv"),
  delim = ";",
  col_types = readr::cols(.default = readr::col_character()),
  locale = readr::locale(encoding = "UTF-8"),
  trim_ws = TRUE,
  progress = FALSE
))
names(addresses) <- normalise_names(names(addresses))
addresses$utmx_etrs <- parse_es_number(addresses$utmx_etrs)
addresses$utmy_etrs <- parse_es_number(addresses$utmy_etrs)
addresses <- addresses |>
  filter(is.finite(utmx_etrs), is.finite(utmy_etrs)) |>
  sf::st_as_sf(coords = c("utmx_etrs", "utmy_etrs"), crs = 25830, remove = FALSE)
addresses <- addresses[lengths(sf::st_intersects(addresses, fallback_section)) > 0, ]
assert_true(nrow(addresses) > 0, "Fallback section has no official address points")

nearest_height <- sf::st_nearest_feature(addresses, fallback_heights)
fallback_weights <- tibble::tibble(height_index = nearest_height) |>
  count(height_index, name = "address_count") |>
  arrange(height_index)
fallback_candidates <- fallback_heights[fallback_weights$height_index, ]
fallback_allocations <- largest_remainder(
  fallback_weights$address_count,
  fallback_section$dot_count[[1]],
  fallback_candidates$height_id
)
fallback_used <- fallback_allocations > 0
fallback_containers <- fallback_candidates[fallback_used, ] |>
  mutate(
    section_id = fallback_section_id,
    container_id = paste0("municipal-height:", height_id),
    allocation_method = "municipal-address-fallback",
    allocated_dots = fallback_allocations[fallback_used]
  ) |>
  select(section_id, container_id, allocation_method, allocated_dots, geometry)

regular_containers <- buildings |>
  filter(allocated_dots > 0) |>
  transmute(
    section_id,
    container_id = paste0("catastro:", building_id),
    allocation_method = "catastro-dwellings",
    allocated_dots,
    geometry
  )
containers <- rbind(regular_containers, fallback_containers) |>
  arrange(section_id, container_id)
saveRDS(containers, file.path(processed_dir, "resident-dot-containers.rds"))
dots <- sample_all_containers(containers) |>
  arrange(section_id, container_id) |>
  mutate(dot_id = sprintf("resident-dot-%06d", row_number())) |>
  select(dot_id, section_id, container_id, allocation_method, geometry)

expected_dot_count <- sum(sections$dot_count)
assert_true(nrow(dots) == expected_dot_count, "Generated dot total does not match section targets")
dot_counts <- sf::st_drop_geometry(dots) |>
  count(section_id, name = "generated_dots")
section_reconciliation <- sections |>
  sf::st_drop_geometry() |>
  select(section_id, population_total, dot_count) |>
  left_join(dot_counts, by = "section_id")
assert_true(
  all(section_reconciliation$dot_count == section_reconciliation$generated_dots),
  "One or more census-section dot totals failed to reconcile"
)

fallback_dot_count <- sum(dots$allocation_method == "municipal-address-fallback")
assert_true(
  fallback_dot_count == fallback_section$dot_count[[1]],
  "Fallback section dot total failed to reconcile"
)

public_dots <- dots |>
  select(section_id, geometry) |>
  sf::st_transform(4326)
dot_geojson_path <- file.path(processed_dir, "tile-inputs", "resident-dots.geojson")
write_geojson(public_dots, dot_geojson_path)
saveRDS(dots, file.path(processed_dir, "resident-dots.rds"))
save_metadata("resident-dots", list(
  dot_value = dot_value,
  random_seed = dot_seed,
  source_population = sum(sections$population_total),
  dot_count = nrow(dots),
  represented_population = nrow(dots) * dot_value,
  rounding_difference = nrow(dots) * dot_value - sum(sections$population_total),
  section_count = nrow(sections),
  sections_reconciled = sum(section_reconciliation$dot_count == section_reconciliation$generated_dots),
  catastro_dot_count = sum(dots$allocation_method == "catastro-dwellings"),
  fallback_section_id = fallback_section_id,
  fallback_dot_count = fallback_dot_count,
  fallback_address_count = nrow(addresses),
  fallback_building_count = nrow(fallback_candidates),
  points_inside_assigned_geometry = TRUE,
  coordinate_file_md5 = unname(tools::md5sum(dot_geojson_path))
))

message_step(
  "Resident dots ready: ", nrow(dots), " dots · 1 dot = ", dot_value,
  " residents · rounding difference ", nrow(dots) * dot_value - sum(sections$population_total)
)
