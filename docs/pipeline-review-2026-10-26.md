# Madrid atlas pipeline review and implementation

## Scope and assumptions

The pipeline joins official population, migration, education, election and income tables to their
declared census geographies, prepares building and transport features, then publishes PMTiles,
search indices and section/housing reports. It uses the existing R spatial/data packages, Node,
Vite and Tippecanoe. This release retains the public map layer IDs and 2023 election definitions.
The source lock supplies the selected observation dates, geography vintages, encodings and hashes.
Original scripts and generated artifacts remain recoverable at deployment commit `72426b3`;
previous raw inputs and election intermediates are also preserved in the ignored release archive.

## Findings and implemented changes

| Priority / category | Finding | Change and affected stages |
| --- | --- | --- |
| High / clear error | Numeric-only age parsing discarded `100 o +` residents. | Shared explicit age parser, applied to current and historical population; reconciliation starts before age/section filtering and separately accounts for unassigned residents. Unknown age categories fail. Historical individual ages above 100 remain in source totals. |
| High / clear error | A year-filter-only income refresh would attach 2024 values to obsolete geometry. | Income has a separate preparation stage and archive on 2025 geometry. All seven measures, report joins, ranks and metadata use that frame; elections remain on 2023 geometry. |
| High / clear error | Old validators and notices asserted blanket income suppression in two districts. | Validate current source coverage and render notices from actual missing metrics. Preserve genuine nulls. |
| Medium / silent failure risk | The income-risk regex could also select the above-160% indicator; the old distinct-by-ID operation hid ambiguity. | Match below-60% and above-200% explicitly, assert unique indicator IDs, and reject finite values outside the selected geometry. |
| Medium / reproducibility risk | Cache reuse and build-date stamps obscured stale mutable inputs. | Verify locked bytes, freeze selected catalogue resources, publish source versions, retain source-specific building and transport dates. Historical WFS checks ignore only response metadata when comparing feature collections. |
| Medium / parsing risk | Type inference can lose late values; official CSV encoding headers are inconsistent. | Read source CSV fields as text before explicit conversion; declare Latin-1 for historical population and address files. |
| Low / performance | Address formatting repeated expensive title conversion for every portal. | Format distinct street classes/names once, then map them back without changing the label rules. |

## Cross-script consistency

The run order includes `03a_prepare_income.R`. Tile preparation, the manifest, canonical reports,
TypeScript types and report rendering all distinguish income year 2024 / geometry 2025 from election
year / geometry 2023. Report schema 2.0.0 records separate geographies. Housing analysis keeps its
2021–2025 migration interpretation and recomputes building-based summaries against current sections.
Client JSON and PMTiles requests include a source-lock-derived version token to avoid stale-cache schema mismatches.
Resident-dot validation derives the fallback target from section residents instead of fixing it at
the previous release's 29 dots. Source-backed release totals remain explicit regression expectations.

## Conceptual and mechanical assessment

No area-weighted imputation was introduced. Longitudinal section comparison still requires reciprocal
95% overlap, and current section reports disclose greatest-overlap matches for snapshot chapters.
Separating income processing prevents its annual geography changes from modifying historical election
attributes. Existing packages and deployment infrastructure are retained. Reading indicator rows after
filtering the target year/geography reduces unnecessary numeric conversion; CSV type inference is
disabled to prevent silent omissions. Raw/filtered building counts and full source-to-map population
accounting are checked separately from rendered counts.

## Validation and remaining limits

The release validation record documents the completed data, build and browser checks. Election
intermediates are compared with the preserved baseline after processing. Current source values are
also checked independently of the preparation functions. No new product or modelling decisions
require confirmation. Runtime OpenFreeMap data remains outside the frozen source release; mutable
upstream endpoints require retaining raw snapshots to reproduce an older release after upstream changes.

Overall rating: **GREEN.** The complete spatial pipeline, 42 tests, production build, independent source comparisons and desktop/mobile preview checks passed.
