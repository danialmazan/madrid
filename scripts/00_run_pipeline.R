options(warn = 1)

steps <- c(
  "scripts/01_prepare_boundaries.R",
  "scripts/02_prepare_population.R",
  "scripts/03_prepare_elections_income.R",
  "scripts/04_prepare_buildings.R",
  "scripts/05_prepare_transport.R",
  "scripts/06_build_tiles.R",
  "scripts/07_build_manifest.R",
  "scripts/08_build_section_reports.R",
  "scripts/09_validate_outputs.R"
)

started <- Sys.time()
for (step in steps) {
  message("\n=== ", step, " ===")
  source(step, local = new.env(parent = globalenv()))
}
message(
  "\nPipeline complete in ",
  round(as.numeric(difftime(Sys.time(), started, units = "mins")), 1),
  " minutes"
)
