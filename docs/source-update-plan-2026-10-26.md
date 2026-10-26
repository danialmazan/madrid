# Madrid atlas: source audit and update plan

Audit date: **26 October 2026**. Scope: inspect the deployed atlas and its effective upstream data sources, then plan a refresh. No production data, application code, commits, or deployments were changed during this audit.

## Recommendation

Prepare one coordinated release covering **October population, 2024 income, August Catastro buildings, September municipal geography, the October EMT network, and current addresses**. Include the newer municipal building-height download, which was already available before the last deployment but was missed by the cache. Refresh Metro Ligero's source metadata; its mapped network is unchanged.

Keep migration at **2025**, Education & Work at **2024**, and elections at **2023**. Their source files match the cached inputs. Retain Metro, Cercanías and BiciMAD network inputs, which also match.

The release needs a small pipeline refactor before rebuilding: income and elections now require different geographies, income suppression rules changed, and the population parser currently drops the open-ended 100+ age group.

## Verified deployment baseline

- Last successful [GitHub Pages deployment](https://github.com/danialmazan/madrid/actions/runs/31939412022): **16 August 2026**, commit `72426b3380eff3a74aae76d8e249b52ee198e97d`.
- The live [layer manifest](https://danielalmazan.com/madrid/data/layer-manifest.json) matched the local manifest exactly when checked. It was generated on 15 August 2026, version `1.2.0`, and contains **52 visible layers**. Local validation records **27 PMTiles archives** and 2,462 current section reports.
- The manifest's common `retrieved: 2026-08-15` dates are build-time stamps, not reliable individual source download dates. Several raw inputs were downloaded in July. The source dates below come from file contents, source headers, API metadata and comparisons with those cached inputs.
- `docs/validation.md` still describes the July release (42 layers / 25 archives); update it with the next release's actual validation results.

## Source findings

“Unchanged” below means the downloaded file matched its cached input byte for byte, except for historical INE WFS responses, whose feature collections matched and whose response timestamp alone changed. Changed archives were checked beyond their ZIP timestamps where material to the map.

| Source / maps affected | Deployed input | Latest evidence | Action |
| --- | --- | --- | --- |
| [Monthly Madrid padrón](https://datos.madrid.es/dataset/200076-0-padron): residents, density, age shares, population change and resident dots | `FX_DATOS_FIN = 2026-07-01`; July download | New CSV published **6 October**, with internal `FX_DATOS_FIN = 2026-10-01`. The catalogue describes coverage through 30 September. | Update to **1 October 2026**, using the CSV's observation date and documenting the catalogue's month-end wording. |
| [Historical padrón](https://datos.madrid.es/dataset/209163-0-padron-municipal-historico) | July 2021 comparator | July 2021 file is unchanged. October 2021 CSV is available and was downloaded successfully. | Switch the comparator to **October 2021** when updating the current observation. |
| [INE income / inequality](https://www.ine.es/dyngs/INEbase/es/operacion.htm?c=Estadistica_C&cid=1254736177088&idp=1254735976608&menu=ultiDatos), tables **31097, 31098, 31102, 37727** | Income year 2023, joined to 2023 sections | All four CSVs changed; **2024** was released **19 October 2026**. All seven atlas income indicators have non-missing values for **2,462 Madrid sections** in 2024. | Update all seven measures, their distributions, ranks, metadata and source notes together. See the geography and suppression requirements below. |
| [Catastro INSPIRE buildings](https://www.catastro.hacienda.gob.es/INSPIRE/Buildings/28/28900-MADRID/A.ES.SDGC.BU.28900.zip): age, housing summaries and resident-dot allocation | February 2026 snapshot; ZIP 105,185,640 bytes | ZIP updated **21 August 2026**, now 116,809,103 bytes. Main building GML has **124,396 raw features** before the atlas's municipal/district filtering. | Refresh footprints, construction dates and dwelling counts; rebuild every dependent output. Validate the resulting filtered count rather than assuming the raw count is the final map count. |
| [Municipal census sections](https://geoportal.madrid.es/fsdescargas/IDEAM_WBGEOPORTAL/LIMITES_ADMINISTRATIVOS/Seccionado/Secciones_Censales.zip) | July-cached 2026 section file | Download updated **18 September**. Still **2,462 sections**, with identical section IDs, valid geometries, and **15 topologically changed polygons**. | Refresh current geometry, density areas, all spatial matches, building assignments and dots. |
| [Municipal neighbourhoods](https://geoportal.madrid.es/fsdescargas/IDEAM_WBGEOPORTAL/LIMITES_ADMINISTRATIVOS/Barrios/TopoJSON/Barrios.json) | July-cached TopoJSON | Updated **17 September**. Still 131 neighbourhoods and the same IDs; 109 decoded geometries differ. Differences can include coordinate precision changes. | Regenerate neighbourhood search extents; do not describe these automatically as legal boundary changes. |
| [Municipal estimated building heights](https://geoportal.madrid.es/fsdescargas/IDEAM_WBGEOPORTAL/CARTOGRAFIA/CARTOGRAFIA_ACTUALIZADA/ALTURAS_EDIFICIOS/ALTURAS_EDIFICIOS.ZIP) | June-dated / July-cached ZIP, 46,541,251 bytes; 490,740 raw records | New ZIP is 50,225,954 bytes with **492,776 raw records**, last modified **28 July 2026**. This predates deployment but supersedes the deployed input. | Include this missed refresh. Source product date and download modification date must be recorded separately. |
| [Official address directory](https://datos.madrid.es/dataset/213605-0-callejero-oficial-madrid/information) | July-cached CSV | Changed CSV, updated **20 October**; 34,705,052 bytes versus 34,696,474 cached. | Rebuild `addresses.json` and the address-based dot-placement fallback. |
| [EMT GTFS](https://www.arcgis.com/sharing/rest/content/items/868df0e58fca47e79b942902dffd7da0?f=pjson) | June 2026 feed | Item updated **16 October**; feed generated **13 October**. 236 routes remain; stops increase **4,924 → 4,928**. Route shapes, trips and stop associations change; route 6 and SE709 names change. | Rebuild the EMT routes, stops and route selector. |
| [Metro Ligero GTFS](https://www.arcgis.com/sharing/rest/content/items/aaed26cc0ff64b0c947ac0bc3e033196?f=pjson) | Feed version `20260622` | Item updated **16 October**, feed version `20261015`. Only `calendar.txt` and `feed_info.txt` differ. Routes, shapes, stops, trips and stop times match exactly. | Refresh the source snapshot and provenance; no mapped geometry change is expected. |
| [Metro GTFS](https://www.arcgis.com/sharing/rest/content/items/5c7f2951962540d69ffe8f640d94c246?f=pjson) | Feed version `20250527` | Exact ZIP match. This configured CRTM endpoint still serves the old feed. | Retain; do not label it as an October network revision merely because the release is rebuilt in October. |
| [Cercanías feature service](https://services5.arcgis.com/UxADft6QPcvFyDU1/arcgis/rest/services/M5_Red/FeatureServer) | August snapshot | Layers 0 (stations) and 4 (lines) match exactly. | Retain. The configured Cercanías GTFS item is bypassed by the pipeline and is not the effective map input. |
| [BiciMAD stations](https://datos.emtmadrid.es/dataset/5fcc0945-2cbd-46c3-801a-6a83f4167c11/resource/105ce5df-793f-4e0a-a88e-5d3b3f024a5d/download/bikestationbicimad_geojson.json) | August snapshot | Exact GeoJSON match. | Retain station geometry. |
| INE migration / birthplace / nationality, tables [69211](https://www.ine.es/jaxiT3/Tabla.htm?t=69211), [66428](https://www.ine.es/jaxiT3/Tabla.htm?t=66428), [66429](https://www.ine.es/jaxiT3/Tabla.htm?t=66429) | 2025; comparison with 2021 | All three full CSVs match exactly; latest year remains 2025. | Retain 2025 and the 2021–2025 four-year comparison. |
| INE Education & Work, tables [66753](https://www.ine.es/jaxiT3/Tabla.htm?t=66753), [66755](https://www.ine.es/jaxiT3/Tabla.htm?t=66755) | 2024 | Both full CSVs match exactly; latest year remains 2024. | Retain. |
| INE section geometry for 2021, 2023, 2024 and 2025 | Matching historical vintages | Feature collections are identical. Only the WFS response `timeStamp` changes. | Retain historical geometries. |
| 2023 general, local and Assembly election workbooks | Existing 2023 files | All three downloaded XLSX files match exactly. | Retain the existing elections, dates and section attributes. |
| Municipal 2026 birthplace ranking workbook (`C14141126.xlsx`) | Provenance for the country allow-list | Available; HTTP last-modified is **8 May 2026**, before deployment. No cached original exists for a byte comparison. The processing script cites it as provenance, rather than reading it to calculate the maps. | No evidenced post-deployment update. Retain the approved country selection. |

OpenFreeMap basemaps are loaded remotely at runtime. They are not frozen pipeline inputs and are not included in the atlas rebuild comparison.

## Requirements before rebuilding

### 1. Treat income year and geography year separately

The new 2024 income values match the **2025 INE section set exactly: 2,462 IDs**. Joining them to either the current pipeline's 2023 or 2024 INE geometry would leave **19 valid income sections without geometry**, while seven obsolete geometry IDs have no 2024 income value.

The [October 2026 INE methodology](https://www.ine.es/metodologia/metodologia_adrh.pdf), section 2.1, defines the population frame as the census at 1 January of the year after the income reference year. The observed section-ID match supports using the official **2025 geometry for 2024 income**. Keep the two dates explicit throughout the pipeline and UI.

Recommended implementation:

- Separate the income preparation from `03_prepare_elections_income.R`. Leave the election preparation and its 2023 attributes intact.
- Produce an income-only intermediate such as `sections-2025-income-2024.rds` and an archive such as `income-2024.pmtiles`, with a clearly declared 2025 geography. This avoids changing the existing migration archive or silently putting 2024 income on 2023 polygons.
- Update `06_build_tiles.R` and `07_build_manifest.R` to point the existing income layer IDs at that source. Keep public layer IDs, country controls and shared URL hashes stable.
- In `08_build_section_reports.R`, join election metrics through the 2023 report match and income through the existing 2025 report match. Split the combined `incomeAndElections` geography declaration into separate income/election declarations and update `src/types.ts`, `src/report.ts` and the schema version together.
- Audit class breaks against the new distributions; retain them where still useful, and document any changed breaks. Recalculate percentiles from the correct, non-missing 2024 source observations.

### 2. Replace the old income suppression assumptions

The source's 2024 below-60% and above-200% median indicators are available for all **2,462** active Madrid sections, including **369** across Fuencarral-El Pardo and Carabanchel. The current validator and tests explicitly expect those districts to be missing, so a download-only refresh would fail validation or preserve misleading notes.

INE changed the disclosure rules for ADRH 2024: the methodology's section 3.3 replaces the prior thresholds with protection based on the population in each classification combination and complementary suppression. Update source-aware missingness checks, `tests/data.test.ts`, manifest notes, `docs/methodology.md`, and the district-specific notices in `src/main.ts` / `src/report.ts`. Render suppression notices from actual missing indicators. Preserve any future genuine suppression as null.

Some historical cells in the refreshed income downloads also differ. Preserve the original cached release for provenance; do not silently claim historical invariance from a whole-file comparison or overwrite the election archive as a side effect.

### 3. Include residents aged 100 and over

`02_prepare_population.R` converts `COD_EDAD_INT` with `as.integer()` and filters missing ages. The source uses the text **`100 o +`**, which becomes missing and is dropped. The same general parsing pattern must be checked in the historical population helper in `02a_prepare_population_migration.R`.

Independent CSV aggregation found:

| Reconciliation | July source | October source |
| --- | ---: | ---: |
| All source residents | 3,512,850 | 3,535,824 |
| Residents with a valid section, including 100+ | 3,512,849 | 3,535,821 |
| Source residents without a section | 1 | 3 |
| Valid-section residents lost by numeric-only age parsing | 2,495 | 2,554 |
| Current parser's valid-section total | 3,510,354 | 3,533,267 |

Normalize the open-ended age category explicitly to 100 for age-band calculations, keep all valid-section residents in total-population denominators, and account separately for unassigned source residents. Reconcile totals before the age filter, rather than allowing the same filter to define both sides of the coverage test. Rebuild residents, density, age shares, percentiles, change and dot counts from the corrected totals. The mapped October target is **3,535,821** for these audited inputs; retain the three unassigned residents as a documented source-to-map difference.

The source's observation date is **1 October**, so the five-year comparison must use **October 2021**, with equivalent age treatment in both years.

### 4. Refresh mutable inputs explicitly and record their real versions

`download_cached()` normally reuses any existing file. Municipal geometry, addresses, buildings, INE CSVs and the GTFS ZIPs generally use that default; rerunning `00_run_pipeline.R` alone would leave much of this release stale.

- Preserve the old raw files and checksums, then stage the audited fresh versions in an isolated release input directory. Promote only the intended refreshed inputs into the build cache.
- Add a small source-version ledger recording resolved URL, observation year/date, geography vintage, actual retrieval time, source last-modified/feed version, byte size and SHA-256. Keep metadata-only changes distinguishable from changed mapped content.
- Derive building dates from source metadata. Remove the hard-coded February/June dates in `04_prepare_buildings.R`; do not replace actual source dates with the build date.
- Record transport dates per mode. The single `Sys.Date()` snapshot date currently hides the older Metro feed and unchanged Cercanías/BiciMAD inputs.
- Keep the full source ledger alongside release validation so the next audit does not depend on raw filesystem modification times.

## Execution sequence

1. **Freeze the baseline.** Create a release branch from the verified deployment commit; record hashes of current public assets, preserve the old raw inputs, and record the current section/election metrics. Keep the previous deployment available for rollback.
2. **Prepare input and parsing changes.** Stage the refreshed sources above, the October 2021 comparator, correct population age handling, separate income processing/geography, and make source versions explicit. Add meaningful regression checks for the 100+ category, source-to-map reconciliation and income's year/geography split.
3. **Rebuild spatial inputs.** Run the boundary and search-index stage with the September sections/neighbourhoods and October address data. Rebuild October population and its reciprocal 2021 comparison. Retain migration and education source values, but recompute their matches to the corrected current geography where used in reports.
4. **Rebuild buildings and derived analysis.** Process the new Catastro and height files; assign districts/sections against the updated current geography. Rebuild resident dots and their fallback, section building summaries, and `housing-migration-analysis.json`. Keep migration's 2021–2025 interpretation and the 25-residents-per-dot rule.
5. **Rebuild transport and income.** Process EMT's new shapes/stops and the refreshed Metro Ligero feed. Keep matching Metro/Cercanías/BiciMAD geometry. Produce the dedicated 2024 income archive on 2025 geometry, preserving all seven income measures used by maps and reports.
6. **Generate release outputs.** Rebuild affected PMTiles, `layer-manifest.json`, `section-reports.json`, `places.json`, `addresses.json`, housing analysis, source ledger and `validation-report.json`. Update README, methodology and the human-readable validation record from the actual results.
7. **Validate and review the complete candidate.** Apply the checks below, review the source and generated-output diff, and make the resulting commit ready for publication.
8. **Redeploy after the implementation is approved.** Push the intended release commit to `main`, allowing the existing `.github/workflows/deploy.yml` to run tests, build Vite and publish `dist/` to GitHub Pages. Keep the `/madrid/` base path and account-owned custom domain configuration.
9. **Verify production.** Wait for successful Pages deployment, fetch the live manifest and representative assets with cache-busting, compare release hashes, and smoke-test `https://danielalmazan.com/madrid/` plus `/madrid/housing-migration/`. Verify local/remote branch agreement. If a material release check fails, restore the previous known-good release through the same Pages workflow.

## Release checks

- Reconcile every padrón source resident into mapped or explicitly unassigned counts, including 100+. Check representative sections' total/under-18/65+ values and the same-month 2021 comparison independently of the preparation function.
- Require unique section IDs, valid geometry, complete current-section joins, and a report for every current section. For this snapshot the expected current count is still 2,462. Recalculate reciprocal ≥95% comparison matches; split/merged or insufficiently overlapping sections remain null.
- Explicitly inspect the 15 changed current polygons: `2807909002`, `2807909072`, `2807909073`, `2807909079`, `2807909083`, `2807909085`, `2807909088`, `2807909089`, `2807909092`, `2807909093`, `2807909096`, `2807910151`, `2807910152`, `2807910154`, `2807910158`.
- Confirm all seven 2024 income measures join to the 2,462 expected 2025 IDs and that reports use the same values as the source archive. Check source nulls and updated suppression wording; do not hard-code blanket district suppression.
- Require unchanged 2023 election attributes and exact original election totals. Retain the published historical boundaries; changes to current report crosswalks must not alter election source values.
- Reconcile Catastro/height raw, filtered and assigned counts. Verify residential dwelling totals, updated housing summaries, deterministic dot allocation, section rounding and complete retention at supported zooms using `scripts/validate_resident_dot_tiles.mjs`.
- Check EMT's 236 source routes / 4,928 source stops, mapped shapes, stop-to-route joins and route names, including SE709. Expect unchanged Metro Ligero mapped features and unchanged Metro/Cercanías/BiciMAD inputs.
- Run `Rscript scripts/09_validate_outputs.R`, `npm test`, `npm run build`, and the resident-dot tile validator through the pipeline's existing integration. Update the data validator for the new income source, corrected population reconciliation and release-specific counts first.
- Review desktop and narrow mobile layouts, all six thematic groups, source dates, income legends/cards/reports, country controls, address search, an existing shared URL, the housing analysis and browser console output. Check tile requests, PMTiles range delivery and archive/artifact size limits.
- Recheck source versions immediately before freezing the implementation release. A newly published monthly population file should either trigger a coherent new same-month comparison or be explicitly deferred; never mix months accidentally.

## Audit evidence and limits

`docs/source-update-audit-2026-10-26.json` records the effective source URLs, baseline/current hashes, source modification metadata and classification. Full downloaded source bodies were kept in a temporary audit directory, separate from `data/raw/` and `public/data/`; implementing the plan should preserve or re-fetch the selected versions and verify their hashes.

Several servers ignored HTTP Range and returned their complete CSVs; all nine INE table comparisons above therefore used full bodies. Catastro's server required the same certificate-verification workaround already used by the repository; the ZIP contents were checked as a valid archive and its main GML was read. A guessed provincial Atom URL returned HTML and was discarded as version evidence; the successful Madrid ZIP and its embedded file dates supply the Catastro evidence.

Fresh download counts are source counts, not promises about final filtered map counts. This audit did not execute the atlas production pipeline or publish a candidate release. Its only repository additions are this plan and the audit ledger.
