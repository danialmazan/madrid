# Validation record

## Release: 26 October 2026

The complete `Rscript scripts/00_run_pipeline.R` passed in six minutes. It produced **52 visible
layers**, **28 PMTiles archives**, and **2,462 canonical section reports**. All **42 Vitest tests**
passed, as did TypeScript checking and the Vite production build.

- Current population is **1 October 2026**, compared with **October 2021**. Source accounting:
  **3,535,824** residents = **3,535,821 mapped** + **3 without a section identifier**. The mapped
  total includes **2,554** residents in the open-ended 100+ category.
- Independent raw-CSV aggregation matched every section's population and under-18/65+ shares,
  and every published same-month five-year change. **1,868** current sections pass the reciprocal
  95% population comparison rule.
- All **17,234** income observations (seven indicators × 2,462 sections) matched the raw 2024 INE
  files independently. The map archive uses **2025 geometry**. Previously suppressed poverty and
  high-income indicators are available in both affected districts.
- General, local and Assembly election intermediates are identical to the preserved deployment
  baseline. Each election's totals still reconcile exactly with its official workbook.
- Catastro: **124,396 raw / 124,393 published** footprints. Municipal heights: **492,776 raw /
  492,318 published** polygons. Filtering/assignment excludes out-of-area or empty geometries.
- **141,443** resident dots passed footprint containment and section allocation checks. The
  address-linked fallback has **30** dots. Dot rounding represents 254 more residents than the
  exact section totals; section cards and reports retain exact counts. Every dot is retained from
  zoom 8 through 16, with tile-boundary duplicates allowed at higher zooms.
- Housing analysis contains **1,524,538** recorded dwellings and 111,401 dated residential
  building records. It retains **130** non-comparable 2021–2025 migration changes.
- EMT contains **236 routes / 4,928 stops**, including the revised SE709 destination. Source inputs
  for Metro, Cercanías, BiciMAD, migration and education/work are unchanged. Education's PMTiles
  archive is also byte-identical. All migration tile observation values are unchanged; two tile
  percentile ranks for a tied Dominican Republic change now equal **29.92**, matching the existing
  canonical reports (previous tiles had 29.90 and 29.94). All 2,462 migration tile attribute sets
  were compared.
- All archives remain below 95 MB; the largest is `buildings-09.pmtiles` at
  **8.37 MB**. The public artifact is **166.3 MB**, below the 1 GB gate.
- Browser QA on the production preview covered all six groups, resident dots, income legends,
  the Carabanchel report, an existing shared URL, address search with accented names, EMT SE709,
  housing analysis, and **390 × 844** mobile layouts. The housing page has no horizontal overflow
  at 390 px. Browser warning/error logs were empty. Font URLs resolve from the public assets.
- The production build retains the existing large-bundle warning and Vite's absolute font-URL
  warnings; font files are included and load at runtime. No new dependency was introduced.
- Pre-release upstream version checks matched all changed source modification dates and confirmed
  that the October population CSV remains the current catalogue selection.

JSON and PMTiles requests carry a source-lock-derived version token to avoid mixing cached data
from the previous report schema with the new application. Full source provenance is published in
`public/data/source-versions.json`; machine-readable spatial checks are in
`public/data/validation-report.json`. GitHub Pages workflow history records the deployed release
commit; live asset hashes are checked against the completed release after publication.

## Historical validation: 26 July 2026

Validated on 26 July 2026 against the generated production files.

- 42 visible layers backed by 25 PMTiles archives.
- Population join: 3,510,354 of 3,510,354 residents (100% coverage).
- General, local and Assembly election aggregates reconcile exactly with the official Madrid
  totals for census, ballots cast, valid votes, blank ballots and candidate votes.
- 124,329 Catastro buildings and 490,298 municipal height polygons passed geometry and range checks.
- All PMTiles archives are below 8.0 MB; the complete public artifact is 107.1 MB.
- Vitest: 3 of 3 URL-state and bounds tests passed.
- Chrome production smoke test: no console errors or warnings.
- Lighthouse mobile audit: accessibility 100, performance 99, first contentful paint 1.23 s,
  largest contentful paint 1.23 s and cumulative layout shift 0.006.

The machine-readable spatial validation result is
[`public/data/validation-report.json`](../public/data/validation-report.json).
