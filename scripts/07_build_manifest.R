source(file.path("scripts", "R", "common.R"))

population_meta <- readRDS(file.path(processed_dir, "population-metadata.rds"))
migration_meta <- readRDS(file.path(processed_dir, "migration-metadata.rds"))
education_meta <- readRDS(file.path(processed_dir, "education-work-metadata.rds"))
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
    "Madrid City Council padrón · Madrid current census sections",
    tile_zooms$sections[["min"]], tile_zooms$sections[["max"]]
  ),
  source_definition(
    "sections-2024", "data/sections-2024.pmtiles", "sections_2024",
    "INE Annual Population Census · 2024 census sections",
    tile_zooms$sections[["min"]], tile_zooms$sections[["max"]]
  ),
  source_definition(
    "sections-2025", "data/sections-2025.pmtiles", "sections_2025",
    "INE Population and Housing Census · INE census sections",
    tile_zooms$sections[["min"]], tile_zooms$sections[["max"]]
  ),
  source_definition(
    "sections-2023", "data/sections-2023.pmtiles", "sections_2023",
    "INE ADRH · Madrid/Interior election results · INE census sections",
    tile_zooms$sections[["min"]], tile_zooms$sections[["max"]]
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
    source_definition(
      age_id, archive, "building_age", "Catastro INSPIRE Buildings",
      tile_zooms$buildings[["min"]], tile_zooms$buildings[["max"]]
    ),
    source_definition(
      height_id, archive, "building_height", "Ayuntamiento de Madrid · estimated building heights",
      tile_zooms$buildings[["min"]], tile_zooms$buildings[["max"]]
    )
  ))
}

transport_source <- function(id, layer) {
  source_definition(
    id, "data/transport.pmtiles", layer, "CRTM open data · EMT Madrid · BiciMAD",
    tile_zooms$transport[["min"]], tile_zooms$transport[["max"]]
  )
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
building_age_palette <- c("#184e77", "#52b69a", "#d9ed92", "#f9c74f", "#f9844a", "#c1121f")
diverging_palette <- c("#b2182b", "#ffffff", "#2166ac")

six_quantile_breaks <- function(values) {
  valid <- values[is.finite(values)]
  unname(as.numeric(stats::quantile(valid, probs = seq(0, 1, length.out = 7), names = FALSE, type = 7)))
}

symmetric_limit <- function(values) {
  valid <- abs(values[is.finite(values)])
  max(0.01, unname(as.numeric(stats::quantile(valid, 0.95, names = FALSE, type = 7))))
}

layer <- function(
  id, group, kind, label, short_label, description, unit, reference_date,
  geography, source_ids, property, palette, breaks, format,
  tooltip_fields, minzoom = 8, maxzoom = 24, opacity = 0.72,
  control = NULL, methodology = NULL, line_color = NULL, line_width = NULL,
  scale = NULL
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
  if (!is.null(scale)) out$scale <- scale
  out
}

population_values <- readRDS(file.path(processed_dir, "sections-2026-population.rds"))
migration_values <- readRDS(file.path(processed_dir, "sections-2025-migration.rds"))
education_values <- readRDS(file.path(processed_dir, "sections-2024-education-work.rds"))
election_income_values <- readRDS(file.path(processed_dir, "sections-2023-thematics.rds"))

country_labels <- c(
  total = "Total", venezuela = "Venezuela", colombia = "Colombia", peru = "Perú",
  ecuador = "Ecuador", republica_dominicana = "República Dominicana",
  argentina = "Argentina", china = "China", marruecos = "Marruecos"
)
country_control <- function(property_prefix, percentile_prefix) {
  options <- lapply(names(country_labels), function(slug) list(
    value = slug,
    label = unname(country_labels[[slug]]),
    property = paste0(property_prefix, slug),
    percentileProperty = paste0(percentile_prefix, slug)
  ))
  list(country = list(defaultValue = "total", options = options))
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
    "population_change_5y_pct", "Five-year population change", "percent",
    percentile_property = "population_change_5y_percentile"
  )
)

population_change_limit <- symmetric_limit(population_values$population_change_5y_pct)
migration_change_limit <- symmetric_limit(migration_values$foreign_born_change_pp_total)

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
    "population-change-5y", "population", "choropleth", "Five-year population change", "5-year change",
    "Change in registered residents from the same month of 2021 to the current month. Only reciprocal one-to-one boundary matches covering at least 95% of both sections are shown.", "%",
    population_meta$reference_date, "2026 census sections matched to 2021", "sections-2026",
    "population_change_5y_pct", diverging_palette, c(-population_change_limit, 0, population_change_limit), "percent",
    section_context_2026,
    scale = list(type = "continuous-diverging", center = 0, clamp = TRUE)
  ),
  layer(
    "population-foreign-born", "population", "choropleth", "Foreign-born residents", "Foreign-born",
    "Selected-country residents born abroad divided by all residents. Total means all residents born outside Spain.", "%",
    "2025", "2025 census sections", "sections-2025",
    "foreign_born_pct_total", brown_palette, six_quantile_breaks(migration_values$foreign_born_pct_total), "percent",
    tooltip(
      field(
        "foreign_born_pct_total", "Foreign-born · Total", "percent",
        percentile_property = "foreign_born_percentile_total"
      ),
      field("section_id", "Section ID", "text")
    ),
    control = country_control("foreign_born_pct_", "foreign_born_percentile_")
  ),
  layer(
    "population-foreign-citizenship", "population", "choropleth", "Foreign citizenship", "Foreign citizenship",
    "Selected-country residents with foreign citizenship divided by all residents. Total means all non-Spanish citizenships.", "%",
    "2025", "2025 census sections", "sections-2025",
    "foreign_citizenship_pct_total", brown_palette, six_quantile_breaks(migration_values$foreign_citizenship_pct_total), "percent",
    tooltip(
      field(
        "foreign_citizenship_pct_total", "Foreign citizenship · Total", "percent",
        percentile_property = "foreign_citizenship_percentile_total"
      ),
      field("section_id", "Section ID", "text")
    ),
    control = country_control("foreign_citizenship_pct_", "foreign_citizenship_percentile_")
  ),
  layer(
    "population-foreign-born-change", "population", "choropleth", "2021–2025 foreign-born-share change (4 years)", "Foreign-born change",
    "Percentage-point change in the selected country's share of all residents. Only reciprocal one-to-one boundary matches covering at least 95% of both sections are shown.", "pp",
    "2021–2025", "2025 census sections matched to 2021", "sections-2025",
    "foreign_born_change_pp_total", diverging_palette, c(-migration_change_limit, 0, migration_change_limit), "decimal",
    tooltip(
      field(
        "foreign_born_change_pp_total", "2021–2025 change · Total", "decimal", " pp",
        percentile_property = "foreign_born_change_percentile_total"
      ),
      field("section_id", "Section ID", "text")
    ),
    control = country_control("foreign_born_change_pp_", "foreign_born_change_percentile_"),
    scale = list(type = "continuous-diverging", center = 0, clamp = TRUE)
  ),
  layer(
    "education-work-activity", "education-work", "choropleth", "Activity rate", "Activity rate",
    "Active population divided by the population aged 16 and over.", "%", "2024",
    "2024 census sections", "sections-2024", "activity_rate_pct", blue_palette,
    six_quantile_breaks(education_values$activity_rate_pct), "percent",
    tooltip(field("activity_rate_pct", "Activity rate", "percent", percentile_property = "activity_rate_percentile"), field("section_id", "Section ID", "text"))
  ),
  layer(
    "education-work-employment", "education-work", "choropleth", "Employment rate", "Employment rate",
    "Employed population divided by the population aged 16 and over.", "%", "2024",
    "2024 census sections", "sections-2024", "employment_rate_pct", green_palette,
    six_quantile_breaks(education_values$employment_rate_pct), "percent",
    tooltip(field("employment_rate_pct", "Employment rate", "percent", percentile_property = "employment_rate_percentile"), field("section_id", "Section ID", "text"))
  ),
  layer(
    "education-work-unemployment", "education-work", "choropleth", "Unemployment rate", "Unemployment rate",
    "Unemployed population divided by the active population.", "%", "2024",
    "2024 census sections", "sections-2024", "unemployment_rate_pct", orange_palette,
    six_quantile_breaks(education_values$unemployment_rate_pct), "percent",
    tooltip(field("unemployment_rate_pct", "Unemployment rate", "percent", percentile_property = "unemployment_rate_percentile"), field("section_id", "Section ID", "text"))
  ),
  layer(
    "education-work-higher-education", "education-work", "choropleth", "Higher education attainment", "Higher education",
    "Residents with Educación superior divided by the population aged 15 and over.", "%", "2024",
    "2024 census sections", "sections-2024", "higher_education_pct", viridis_palette,
    six_quantile_breaks(education_values$higher_education_pct), "percent",
    tooltip(field("higher_education_pct", "Higher education", "percent", percentile_property = "higher_education_percentile"), field("section_id", "Section ID", "text"))
  ),
  layer(
    "education-work-low-education", "education-work", "choropleth", "Low educational attainment", "Primary or lower",
    "Residents with Educación primaria e inferior divided by the population aged 15 and over.", "%", "2024",
    "2024 census sections", "sections-2024", "low_education_pct", orange_palette,
    six_quantile_breaks(education_values$low_education_pct), "percent",
    tooltip(field("low_education_pct", "Primary or lower", "percent", percentile_property = "low_education_percentile"), field("section_id", "Section ID", "text"))
  ),
  layer(
    "building-age", "buildings", "fill", "Earliest construction year", "Construction year",
    "Earliest recorded construction year; the full interval is shown in details.", "year",
    building_meta$reference_date_catastro, "Building footprints", building_age_sources,
    "construction_start_year", building_age_palette, c(1700, 1900, 1940, 1960, 1980, 2000, 2027), "year",
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
  margin_property <- paste0("left_right_margin_pp_", election)
  margin_limit <- symmetric_limit(election_income_values[[margin_property]])
  layers_out <- append(layers_out, list(
    layer(
      paste0("election-", election, "-leading"), "elections", "choropleth",
      paste(spec$label, "results and leading party"), "Results/Leading party",
      "Candidacy receiving the most votes in each section.", "party",
      spec$date, "2023 census sections", "sections-2023",
      paste0("leading_party_", election), as.vector(rbind(names(party_colours), party_colours)),
      numeric(), "text", election_tooltip,
      control = list(election = election, party = "leading", results = result_fields)
    ),
    layer(
      paste0("election-", election, "-turnout"), "elections", "choropleth",
      paste(spec$label, "turnout"), "Turnout",
      "Ballots cast as a share of the resident electoral census.", "%",
      spec$date, "2023 census sections", "sections-2023",
      paste0("turnout_pct_", election), green_palette, c(0, 45, 55, 65, 72, 80, 100), "percent",
      election_tooltip, control = list(election = election, party = "turnout")
    ),
    layer(
      paste0("election-", election, "-left-right"), "elections", "choropleth",
      paste(spec$label, "· Left vs Right"), "Left vs Right",
      "Right-bloc share minus left-bloc share of valid votes. Smaller candidacies are excluded from both blocs.", "pp",
      spec$date, "2023 census sections", "sections-2023",
      margin_property, diverging_palette, c(-margin_limit, 0, margin_limit), "decimal",
      c(election_tooltip, tooltip(
        field(paste0("left_share_", election), "Left share", "percent"),
        field(paste0("right_share_", election), "Right share", "percent"),
        field(margin_property, "Right − Left margin", "decimal", " pp")
      )),
      control = list(election = election, party = "Left vs Right"),
      scale = list(type = "continuous-diverging", center = 0, clamp = TRUE)
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
  field(
    "income_per_person_eur", "Net income / person", "currency",
    percentile_property = "income_per_person_percentile"
  ),
  field(
    "income_per_household_eur", "Net income / household", "currency",
    percentile_property = "income_per_household_percentile"
  ),
  field(
    "pension_income_pct", "Income from pensions", "percent",
    percentile_property = "pension_income_percentile"
  ),
  field(
    "below_60_median_pct", "Below 60% median", "percent",
    percentile_property = "below_60_median_percentile"
  ),
  field(
    "above_200_median_pct", "Above 200% median", "percent",
    percentile_property = "above_200_median_percentile"
  ),
  field("gini", "Gini coefficient", "decimal", percentile_property = "gini_percentile"),
  field(
    "income_p80_p20", "P80/P20 ratio", "decimal",
    percentile_property = "income_p80_p20_percentile"
  )
)
layers_out <- append(layers_out, list(
  layer(
    "income-per-person", "income", "choropleth", "Net income per person", "Income per person",
    "Mean annual net income per resident.", "€ / person", "2023",
    "2023 census sections", "sections-2023", "income_per_person_eur",
    blue_palette, c(5000, 10000, 14000, 18000, 24000, 34000, 70000), "currency", income_tooltip
  ),
  layer(
    "income-per-household", "income", "choropleth", "Net income per household", "Income per household",
    "Mean annual net income per household.", "€ / household", "2023",
    "2023 census sections", "sections-2023", "income_per_household_eur",
    blue_palette, six_quantile_breaks(election_income_values$income_per_household_eur), "currency", income_tooltip
  ),
  layer(
    "income-pensions", "income", "choropleth", "Income from pensions", "Pension income share",
    "Percentage of total section income coming from pensions; this is not a euro amount.", "% of total income", "2023",
    "2023 census sections", "sections-2023", "pension_income_pct",
    orange_palette, six_quantile_breaks(election_income_values$pension_income_pct), "percent", income_tooltip
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
    title = "Population by country of birth and nationality", organisation = "Instituto Nacional de Estadística",
    url = sources$ine_birth_country_csv, licence = "INE standard reuse conditions",
    retrieved = format(Sys.Date(), "%Y-%m-%d")
  ),
  list(
    title = "Education and economic activity by census section", organisation = "Instituto Nacional de Estadística",
    url = sources$ine_education_csv, licence = "INE standard reuse conditions",
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
    title = "Income distribution by source", organisation = "Instituto Nacional de Estadística",
    url = sources$ine_income_sources_csv, licence = "INE standard reuse conditions",
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
  version = "1.1.0",
  defaultLayer = "population-density",
  sources = sources_out,
  layers = layers_out,
  references = references,
  notes = list(
    "Population values are joined by official section identifiers; resident coverage must be at least 99.5%.",
    "Longitudinal change is shown only for reciprocal one-to-one section matches covering at least 95% of both vintages; split and merged sections remain No data.",
    "Country controls use 2025 INE sections for both birthplace and citizenship. Honduras and Paraguay are in Madrid's 2026 top ten but cannot be shown because INE groups them under Other countries of America.",
    "The foreign-born comparison is explicitly four years (2021–2025) and is expressed in percentage points.",
    "Election shares use valid votes including blank ballots as the denominator.",
    "Election totals exclude non-geographic votes when they are absent from polling-table data.",
    "INE publishes no 2023 section values for the below-60% and above-200% median indicators in Carabanchel and Fuencarral-El Pardo; these remain No data.",
    "Percentiles compare valid Madrid census-section observations; a higher percentile means a higher raw value, not necessarily a better outcome.",
    "Transport is a static network snapshot; live vehicles and bicycle availability are intentionally excluded.",
    "Building archives are split by district and checked against a 95 MB per-file publication limit."
  )
)
write_json_pretty(manifest, file.path(public_data_dir, "layer-manifest.json"))
message_step("Layer manifest ready: ", length(layers_out), " layers")
