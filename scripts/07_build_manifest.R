source(file.path("scripts", "R", "common.R"))

population_meta <- readRDS(file.path(processed_dir, "population-metadata.rds"))
foreign_meta <- readRDS(file.path(processed_dir, "foreign-born-metadata.rds"))
building_meta <- readRDS(file.path(processed_dir, "buildings-metadata.rds"))
transport_meta <- readRDS(file.path(processed_dir, "transport-metadata.rds"))

source_definition <- function(id, url, source_layer, attribution, minzoom = 0, maxzoom = 16) {
  list(
    id = id,
    url = url,
    sourceLayer = source_layer,
    attribution = attribution,
    minzoom = minzoom,
    maxzoom = maxzoom
  )
}

sources_out <- list(
  source_definition(
    "sections-2026", "data/sections-2026.pmtiles", "sections_2026",
    "Madrid City Council padrón · Madrid current census sections"
  ),
  source_definition(
    "sections-2025", "data/sections-2025.pmtiles", "sections_2025",
    "INE Population and Housing Census · INE census sections"
  ),
  source_definition(
    "sections-2023", "data/sections-2023.pmtiles", "sections_2023",
    "INE ADRH · Madrid/Interior election results · INE census sections"
  )
)

building_age_sources <- character()
building_height_sources <- character()
for (code in names(district_names)) {
  archive <- paste0("data/buildings-", code, ".pmtiles")
  age_id <- paste0("building-age-", code)
  height_id <- paste0("building-height-", code)
  building_age_sources <- c(building_age_sources, age_id)
  building_height_sources <- c(building_height_sources, height_id)
  sources_out <- append(sources_out, list(
    source_definition(age_id, archive, "building_age", "Catastro INSPIRE Buildings", 12, 16),
    source_definition(height_id, archive, "building_height", "Ayuntamiento de Madrid · estimated building heights", 12, 16)
  ))
}

transport_source <- function(id, layer) {
  source_definition(id, "data/transport.pmtiles", layer, "CRTM open data · EMT Madrid · BiciMAD", 8, 16)
}
for (mode in c("metro", "metro_ligero", "cercanias", "emt")) {
  sources_out <- append(sources_out, list(
    transport_source(paste0(mode, "-lines"), paste0(mode, "_lines")),
    transport_source(paste0(mode, "-stops"), paste0(mode, "_stops"))
  ))
}
sources_out <- append(sources_out, list(transport_source("bicimad-stops", "bicimad_stops")))

tooltip <- function(...) unname(list(...))
field <- function(property, label, format, suffix = NULL, percentile_property = NULL) {
  out <- list(property = property, label = label, format = format)
  if (!is.null(suffix)) out$suffix <- suffix
  if (!is.null(percentile_property)) out$percentileProperty <- percentile_property
  out
}

blue_palette <- c("#edf4f8", "#c9e0eb", "#8dbfd3", "#4a91b5", "#145c9e", "#0b396e")
viridis_palette <- c("#440154", "#414487", "#2a788e", "#22a884", "#7ad151", "#fde725")
green_palette <- c("#edf5ed", "#cce6d9", "#8dceb4", "#43aa8b", "#247a67", "#135348")
orange_palette <- c("#fff2e8", "#ffd2b6", "#f8a56d", "#fb7b2d", "#d94c08", "#963005")
brown_palette <- c("#f5eee9", "#dfcdbf", "#bf9f8a", "#956e55", "#694a38", "#3f2b21")
diverging_palette <- c("#184e77", "#52b69a", "#d9ed92", "#f9c74f", "#f9844a", "#c1121f")

layer <- function(
  id, group, kind, label, short_label, description, unit, reference_date,
  geography, source_ids, property, palette, breaks, format,
  tooltip_fields, minzoom = 8, maxzoom = 24, opacity = 0.72,
  control = NULL, methodology = NULL, line_color = NULL, line_width = NULL
) {
  out <- list(
    id = id, group = group, kind = kind, label = label, shortLabel = short_label,
    description = description, unit = unit, referenceDate = reference_date,
    geography = geography, sourceIds = unname(as.list(source_ids)), property = property,
    palette = unname(as.list(palette)), breaks = unname(as.list(breaks)), format = format,
    minzoom = minzoom, maxzoom = maxzoom, opacity = opacity,
    tooltip = tooltip_fields
  )
  if (!is.null(control)) out$control <- control
  if (!is.null(methodology)) out$methodology <- methodology
  if (!is.null(line_color)) out$lineColor <- line_color
  if (!is.null(line_width)) out$lineWidth <- line_width
  out
}

section_context_2026 <- tooltip(
  field("population_total", "Residents", "integer"),
  field(
    "population_density_km2", "Residents / km²", "integer",
    percentile_property = "population_density_percentile"
  ),
  field("under18_pct", "Under 18", "percent", percentile_property = "under18_percentile"),
  field("age65plus_pct", "65 and older", "percent", percentile_property = "age65plus_percentile"),
  field(
    "foreign_citizenship_pct", "Foreign citizenship", "percent",
    percentile_property = "foreign_citizenship_percentile"
  )
)

layers_out <- list(
  layer(
    "population-total", "population", "choropleth", "Resident population", "Total residents",
    "Residents registered in the municipal padrón.", "residents",
    population_meta$reference_date, "2026 census sections", "sections-2026",
    "population_total", blue_palette, c(0, 500, 1000, 1500, 2200, 3500, 6000), "integer",
    section_context_2026
  ),
  layer(
    "population-density", "population", "choropleth", "Population density", "Density",
    "Registered residents per square kilometre of section area.", "residents / km²",
    population_meta$reference_date, "2026 census sections", "sections-2026",
    "population_density_km2", viridis_palette, c(0, 5000, 10000, 20000, 35000, 55000, 90000), "integer",
    section_context_2026
  ),
  layer(
    "population-under18", "population", "choropleth", "Residents under 18", "Under 18",
    "Share of registered residents aged 0–17.", "%",
    population_meta$reference_date, "2026 census sections", "sections-2026",
    "under18_pct", green_palette, c(0, 10, 14, 18, 22, 27, 40), "percent",
    section_context_2026
  ),
  layer(
    "population-age65plus", "population", "choropleth", "Residents aged 65+", "65 and older",
    "Share of registered residents aged 65 and older.", "%",
    population_meta$reference_date, "2026 census sections", "sections-2026",
    "age65plus_pct", orange_palette, c(0, 10, 15, 20, 25, 32, 50), "percent",
    section_context_2026
  ),
  layer(
    "population-foreign-citizenship", "population", "choropleth", "Foreign citizenship", "Foreign citizenship",
    "Share of padrón residents without Spanish citizenship.", "%",
    population_meta$reference_date, "2026 census sections", "sections-2026",
    "foreign_citizenship_pct", brown_palette, c(0, 5, 10, 15, 22, 32, 55), "percent",
    section_context_2026
  ),
  layer(
    "population-foreign-born", "population", "choropleth", "Foreign-born residents", "Foreign-born",
    "Share of residents born outside Spain.", "%",
    as.character(foreign_meta$reference_date), "2025 census sections", "sections-2025",
    "foreign_born_pct", brown_palette, c(0, 8, 15, 22, 30, 40, 65), "percent",
    tooltip(
      field(
        "foreign_born_pct", "Foreign-born", "percent",
        percentile_property = "foreign_born_percentile"
      ),
      field("section_id", "Section ID", "text")
    )
  ),
  layer(
    "building-age", "buildings", "fill", "Earliest construction year", "Construction year",
    "Earliest recorded construction year; the full interval is shown in details.", "year",
    building_meta$reference_date_catastro, "Building footprints", building_age_sources,
    "construction_start_year", diverging_palette, c(1700, 1900, 1940, 1960, 1980, 2000, 2027), "year",
    tooltip(
      field("building_id", "Building ID", "text"),
      field("construction_start_year", "Earliest year", "year"),
      field("construction_end_year", "Latest year", "year"),
      field("construction_year_range", "Recorded range", "text"),
      field("use", "Use", "text"),
      field("building_units", "Building units", "integer"),
      field("dwellings", "Dwellings", "integer")
    ),
    minzoom = 12, opacity = 0.78
  ),
  layer(
    "building-height", "buildings", "fill-extrusion", "Estimated building height", "Height",
    "Estimated height above the footprint elevation; switch on 3D to extrude polygons.", "m",
    building_meta$reference_date_heights, "Municipal height polygons", building_height_sources,
    "height_m", orange_palette, c(0, 4, 8, 14, 24, 40, 120), "decimal",
    tooltip(
      field("height_id", "Height polygon ID", "text"),
      field("height_m", "Height", "decimal", " m"),
      field("ground_elevation_m", "Ground elevation", "decimal", " m"),
      field("source_method", "Method", "text"),
      field("source_date", "Survey date", "text")
    ),
    minzoom = 12, opacity = 0.84
  )
)

party_colours <- c(
  PP = "#1D84CE", PSOE = "#E32322", VOX = "#63A53A", SUMAR = "#E65A91",
  "MÁS MADRID" = "#16A085", "MAS MADRID" = "#16A085", MM = "#16A085",
  "MM-VQ" = "#16A085",
  "PODEMOS-IU-AV" = "#6B3FA0", "PODEMOS-IU-AV-MADRID" = "#6B3FA0"
)
party_base_colours <- c(
  PP = "#1D84CE", PSOE = "#E32322", VOX = "#63A53A", SUMAR = "#E65A91",
  MAS_MADRID = "#16A085", PODEMOS_IU_AV = "#6B3FA0"
)
party_palette <- function(colour) {
  grDevices::colorRampPalette(c("#f5f4ef", colour))(6)
}

election_definitions <- list(
  general = list(
    label = "General election", date = "2023-07-23",
    parties = c(PP = "PP", PSOE = "PSOE", VOX = "VOX", SUMAR = "SUMAR")
  ),
  local = list(
    label = "Madrid local election", date = "2023-05-28",
    parties = c(PP = "PP", PSOE = "PSOE", VOX = "VOX", MAS_MADRID = "Más Madrid", PODEMOS_IU_AV = "Podemos-IU-AV")
  ),
  assembly = list(
    label = "Madrid Assembly election", date = "2023-05-28",
    parties = c(PP = "PP", PSOE = "PSOE", VOX = "VOX", MAS_MADRID = "Más Madrid", PODEMOS_IU_AV = "Podemos-IU-AV")
  )
)

for (election in names(election_definitions)) {
  spec <- election_definitions[[election]]
  result_fields <- lapply(names(spec$parties), function(party_key) {
    list(
      property = paste0("share_", tolower(party_key), "_", election),
      label = unname(spec$parties[[party_key]]),
      color = unname(party_base_colours[[party_key]])
    )
  })
  election_tooltip <- tooltip(
    field(paste0("turnout_pct_", election), "Turnout", "percent"),
    field(paste0("valid_votes_", election), "Valid votes", "integer"),
    field(paste0("blank_votes_", election), "Blank ballots", "integer"),
    field(paste0("leading_party_", election), "Leading party", "text")
  )
  layers_out <- append(layers_out, list(
    layer(
      paste0("election-", election, "-turnout"), "elections", "choropleth",
      paste(spec$label, "turnout"), "Turnout",
      "Ballots cast as a share of the resident electoral census.", "%",
      spec$date, "2023 census sections", "sections-2023",
      paste0("turnout_pct_", election), green_palette, c(0, 45, 55, 65, 72, 80, 100), "percent",
      election_tooltip, control = list(election = election, party = "turnout")
    ),
    layer(
      paste0("election-", election, "-leading"), "elections", "choropleth",
      paste(spec$label, "results and leading party"), "Results/Leading party",
      "Candidacy receiving the most votes in each section.", "party",
      spec$date, "2023 census sections", "sections-2023",
      paste0("leading_party_", election), as.vector(rbind(names(party_colours), party_colours)),
      numeric(), "text", election_tooltip,
      control = list(election = election, party = "leading", results = result_fields)
    )
  ))
  for (party_key in names(spec$parties)) {
    party_label <- unname(spec$parties[[party_key]])
    layers_out <- append(layers_out, list(
      layer(
        paste0("election-", election, "-", tolower(gsub("_", "-", party_key))),
        "elections", "choropleth", paste(spec$label, "·", party_label), party_label,
        "Party votes divided by valid votes, including blank ballots.", "%",
        spec$date, "2023 census sections", "sections-2023",
        paste0("share_", tolower(party_key), "_", election),
        party_palette(unname(party_base_colours[[party_key]])),
        c(0, 5, 10, 20, 35, 50, 75), "percent",
        c(election_tooltip, tooltip(field(
          paste0("share_", tolower(party_key), "_", election),
          paste0(party_label, " share"), "percent"
        ))),
        control = list(election = election, party = party_label)
      )
    ))
  }
}

income_tooltip <- tooltip(
  field("income_per_person_eur", "Net income / person", "currency"),
  field("below_60_median_pct", "Below 60% median", "percent"),
  field("above_200_median_pct", "Above 200% median", "percent"),
  field("gini", "Gini coefficient", "decimal"),
  field("income_p80_p20", "P80/P20 ratio", "decimal")
)
layers_out <- append(layers_out, list(
  layer(
    "income-per-person", "income", "choropleth", "Net income per person", "Income per person",
    "Mean annual net income per resident.", "€ / person", "2023",
    "2023 census sections", "sections-2023", "income_per_person_eur",
    blue_palette, c(5000, 10000, 14000, 18000, 24000, 34000, 70000), "currency", income_tooltip
  ),
  layer(
    "income-below-median", "income", "choropleth", "Population below 60% of median", "Below 60% median",
    "Share of people below 60% of the national median equivalised income.", "%", "2023",
    "2023 census sections", "sections-2023", "below_60_median_pct",
    orange_palette, c(0, 8, 14, 20, 28, 38, 65), "percent", income_tooltip
  ),
  layer(
    "income-gini", "income", "choropleth", "Gini coefficient", "Gini coefficient",
    "Income inequality: higher values indicate a less equal distribution.", "index", "2023",
    "2023 census sections", "sections-2023", "gini",
    brown_palette, c(15, 22, 27, 32, 38, 45, 65), "decimal", income_tooltip
  ),
  layer(
    "income-above-200-median", "income", "choropleth",
    "Population above 200% of median", "Above 200% median",
    "Share of people above twice the national median equivalised income.", "%", "2023",
    "2023 census sections", "sections-2023", "above_200_median_pct",
    green_palette, c(0, 4, 10, 18, 28, 40, 60), "percent", income_tooltip
  ),
  layer(
    "income-p80-p20", "income", "choropleth", "P80/P20 income ratio", "P80/P20 ratio",
    "Income at the 80th percentile divided by income at the 20th percentile.", "ratio", "2023",
    "2023 census sections", "sections-2023", "income_p80_p20",
    orange_palette, c(1.8, 2.3, 2.5, 2.7, 2.9, 3.2, 4.1), "decimal", income_tooltip
  )
))

transport_style <- list(
  metro = list(label = "Metro", color = "#145C9E", minzoom = 9),
  metro_ligero = list(label = "Metro Ligero", color = "#43AA8B", minzoom = 10),
  cercanias = list(label = "Cercanías", color = "#C21F39", minzoom = 8),
  emt = list(label = "EMT", color = "#FB6107", minzoom = 11),
  bicimad = list(label = "BiciMAD", color = "#43AA8B", minzoom = 12)
)
mode_control <- c(
  metro = "metro", metro_ligero = "metro-ligero", cercanias = "cercanias",
  emt = "emt", bicimad = "bicimad"
)
emt_routes <- readRDS(file.path(processed_dir, "routes-emt.rds"))
route_options <- lapply(seq_len(nrow(emt_routes)), function(index) {
  list(
    value = as.character(emt_routes$route_short_name[[index]]),
    label = paste0(
      emt_routes$route_short_name[[index]], " · ",
      emt_routes$route_long_name[[index]]
    )
  )
})

for (mode in names(transport_style)) {
  style <- transport_style[[mode]]
  control <- list(transportMode = unname(mode_control[[mode]]))
  if (mode == "emt") {
    control$routeProperty <- "route_short_name"
    control$routes <- route_options
  }
  if (mode != "bicimad") {
    layers_out <- append(layers_out, list(layer(
      paste0("transport-", mode, "-lines"), "transport", "transport-line",
      paste(style$label, "lines"), paste(style$label, "lines"),
      "Static network snapshot.", "route", transport_meta$reference_date,
      "Regional transport network", paste0(mode, "-lines"), "route_short_name",
      character(), numeric(), "text",
      tooltip(
        field("route_short_name", "Line", "text"),
        field("route_long_name", "Route", "text")
      ),
      minzoom = style$minzoom, opacity = 0.9, control = control,
      line_color = style$color, line_width = if (mode == "emt") 1 else 1.8
    )))
  }
  layers_out <- append(layers_out, list(layer(
    paste0("transport-", mode, "-stops"), "transport", "transport-stop",
    paste(style$label, if (mode == "bicimad") "stations" else "stops"),
    paste(style$label, "stops"), "All stops appear together at zoom 12.", "stop",
    transport_meta$reference_date, "Regional transport network",
    paste0(mode, "-stops"), "stop_name", character(), numeric(), "text",
    tooltip(
      field("stop_name", if (mode == "bicimad") "Station" else "Stop", "text"),
      field("route_short_name", "Line", "text")
    ),
    minzoom = max(12, style$minzoom), opacity = 0.96, control = control,
    line_color = style$color
  )))
}

references <- list(
  list(
    title = "Padrón municipal de habitantes", organisation = "Ayuntamiento de Madrid",
    url = population_meta$source_url, licence = "Madrid open-data reuse terms",
    retrieved = format(Sys.Date(), "%Y-%m-%d")
  ),
  list(
    title = "Censo anual de población", organisation = "Instituto Nacional de Estadística",
    url = sources$ine_foreign_born_csv, licence = "INE standard reuse conditions",
    retrieved = format(Sys.Date(), "%Y-%m-%d")
  ),
  list(
    title = "Catastro INSPIRE Buildings", organisation = "Dirección General del Catastro",
    url = sources$catastro_buildings_zip, licence = "Catastro data-access conditions",
    retrieved = format(Sys.Date(), "%Y-%m-%d")
  ),
  list(
    title = "Alturas de edificios", organisation = "Ayuntamiento de Madrid",
    url = sources$madrid_building_heights_zip, licence = "Madrid open-data reuse terms",
    retrieved = format(Sys.Date(), "%Y-%m-%d")
  ),
  list(
    title = "2023 election results by polling table", organisation = "Madrid City Council / Interior Ministry",
    url = sources$election_general_xlsx, licence = "Public-sector information reuse terms",
    retrieved = format(Sys.Date(), "%Y-%m-%d")
  ),
  list(
    title = "Household Income Distribution Atlas", organisation = "Instituto Nacional de Estadística",
    url = sources$ine_income_person_csv, licence = "INE standard reuse conditions",
    retrieved = format(Sys.Date(), "%Y-%m-%d")
  ),
  list(
    title = "CRTM open transport data", organisation = "Consorcio Regional de Transportes de Madrid",
    url = "https://transparencia.crtm.es/presupuestos-contratos-y-gastos/datos-abiertos/",
    licence = "CRTM open-data licence", retrieved = format(Sys.Date(), "%Y-%m-%d")
  ),
  list(
    title = "BiciMAD stations", organisation = "EMT Madrid",
    url = sources$bicimad_geojson, licence = "Madrid open-data reuse terms",
    retrieved = format(Sys.Date(), "%Y-%m-%d")
  ),
  list(
    title = "Official Madrid street directory", organisation = "Ayuntamiento de Madrid",
    url = sources$madrid_street_addresses_csv, licence = "Madrid open-data reuse terms",
    retrieved = format(Sys.Date(), "%Y-%m-%d")
  )
)

manifest <- list(
  generatedAt = paste0(format(Sys.time(), "%Y-%m-%dT%H:%M:%S"), "Z"),
  version = "1.0.0",
  defaultLayer = "population-density",
  sources = sources_out,
  layers = layers_out,
  references = references,
  notes = list(
    "Population values are joined by official section identifiers; resident coverage must be at least 99.5%.",
    "Election shares use valid votes including blank ballots as the denominator.",
    "Election totals exclude non-geographic votes when they are absent from polling-table data.",
    "INE publishes no 2023 section values for the below-60% and above-200% median indicators in Carabanchel and Fuencarral-El Pardo; these remain No data.",
    "Transport is a static network snapshot; live vehicles and bicycle availability are intentionally excluded.",
    "Building archives are split by district and checked against a 95 MB per-file publication limit."
  )
)
write_json_pretty(manifest, file.path(public_data_dir, "layer-manifest.json"))
message_step("Layer manifest ready: ", length(layers_out), " layers")
