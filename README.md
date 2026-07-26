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

- July 2026 monthly padrón measures use Madrid’s current 2026 census sections.
- The latest annual foreign-born measure uses its matching 2025 INE section vintage.
- 2023 elections and income measures use 2023 INE census sections.
- Catastro construction dates and municipal height polygons retain their own footprints.
- Transport is a static GTFS/BiciMAD network snapshot.

Missing values remain null and render as “No data”; they are never replaced with zero.

## Validation

`Rscript scripts/09_validate_outputs.R` checks identifier uniqueness, source references, resident
join coverage, election reconciliation, transport completeness, building counts, per-archive size
and total Pages artifact size. `npm test` covers URL-state restoration and input bounds. A mobile
Lighthouse audit of the production build scores 100 for accessibility, with first contentful paint
at 1.23 seconds under simulated mobile throttling.

See [docs/methodology.md](docs/methodology.md) for calculation definitions and source notes, and
[docs/validation.md](docs/validation.md) for the validation record.
