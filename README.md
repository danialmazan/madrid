# Madrid Interactive Atlas

A portfolio-scale explorer of Madrid municipality, with regional public-transport overlays. The
frontend uses TypeScript, Vite, MapLibre GL JS and PMTiles; the spatial-data build is reproducible
in R.

The production URL is intended to be
[danielalmazan.com/madrid/](https://danielalmazan.com/madrid/). Vite’s base path is `/madrid/`,
and GitHub Pages deployment is handled by `.github/workflows/deploy.yml`. Do not add a `CNAME`
file to this project repository: the account-level Pages site owns the custom domain.

## Local development

```sh
npm install
npm run dev
```

The interface expects generated archives in `public/data/`. To rebuild every dataset:

```sh
brew install tippecanoe
Rscript scripts/00_run_pipeline.R
```

Required R packages are `sf`, `dplyr`, `readr`, `tidyr`, `jsonlite`, `yaml`, `readxl` and
`xml2`. Raw downloads and intermediate files are excluded from Git; generated PMTiles archives
are committed so the Pages deployment does not need to download and process multi-gigabyte
spatial sources.

## Data model

`public/data/layer-manifest.json` is generated from pipeline metadata. Every visible layer declares
its source archive and vector-layer name, property, unit, reference date, matching geography,
palette, class breaks, tooltip fields, zoom range and source attribution.

- October 2026 monthly padrón measures use Madrid’s current 2026 census sections.
- 2025 foreign-born and foreign-citizenship measures use country-controlled INE section data.
- 2024 Education & Work measures use their matching INE section vintage.
- Longitudinal change uses reciprocal ≥95% one-to-one matches to 2021 sections.
- 2023 elections use 2023 INE census sections; 2024 income uses the January 2025 census frame.
- Catastro construction dates and municipal height polygons retain their own footprints.
- Transport uses source-specific static snapshots: EMT 13 October 2026, Metro Ligero 15 October 2026, and the retained Metro/Cercanías/BiciMAD inputs.

Missing values remain null and render as “No data”; they are never replaced with zero.

## Validation

`Rscript scripts/09_validate_outputs.R` checks identifier uniqueness, source references, resident
join coverage, election reconciliation, transport completeness, building counts, per-archive size
and total Pages artifact size. `npm test` covers URL state, published data, reports and interaction behaviour. The pipeline also runs
a regression check for the open-ended 100+ population category. See the validation record for
release-specific QA; historical Lighthouse results are labelled with their original release.

See [docs/methodology.md](docs/methodology.md) for calculation definitions and source notes, and
[docs/validation.md](docs/validation.md) for the validation record.

## Reproducing a release

`config/source-lock.json` selects the release's resolved source URLs, dates, encodings and SHA-256
checksums. `download_cached()` verifies selected bytes before using an input, including when a
caller requests a refresh. A changed upstream file stops the build instead of silently mixing
releases. Catalogue selections are frozen in the lock. Historical WFS boundaries use an additional
feature-collection checksum because the service changes its response timestamp on every request.
CSV columns are read as text before explicit Spanish-number and age conversion.

Keep an archive of the selected raw files: mutable upstream URLs cannot serve every past release.
For this refresh, the previous raw inputs and election baseline are preserved locally under
`data/releases/2026-08-16/`; the selected October inputs are in `data/raw/` and archived under
`data/releases/2026-10-26/`. These directories are
excluded from Git. To refresh again, audit the new sources, update the lock and same-month population
comparator together, stage the selected files, and run the full pipeline. `public/data/source-versions.json`
publishes the release's provenance. Client data requests carry a source-lock-derived cache version. `section-reports.json` is schema **2.0.0**, separating income and
election geographies; public map layer IDs and shared URL state remain compatible.
