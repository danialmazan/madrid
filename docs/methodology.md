# Methodology

## Geography and missing data

The atlas covers Madrid municipality. Regional transport is retained beyond the municipal
boundary so journeys can be understood in context. Thematic values are joined only to the census
section vintage matching the observation year: 2026, 2025, 2024, 2023 or 2021. A failed or absent match remains
null and is displayed as **No data**.

Longitudinal measures require a reciprocal one-to-one polygon match covering at least 95% of both
section geometries. Split and merged sections are not area-weighted or imputed and remain **No data**.

## Population

The latest monthly municipal padrón is summed by section and single year of age. Total population
includes Spanish and foreign citizens of all genders. Under-18 and 65+ values divide the relevant
age total by all registered residents. Density divides residents by section area in square kilometres.
Five-year population change compares the latest monthly padrón with the same month of 2021.

Foreign-born and foreign-citizenship layers use 2025 INE annual census tables and divide the selected
country count by all residents. Total means all foreign countries. The comparable change is the
2025 share minus the 2021 share, explicitly a four-year percentage-point change. The selector offers
Venezuela, Colombia, Peru, Ecuador, Dominican Republic, Argentina, China and Morocco. Honduras and
Paraguay are omitted because INE groups them under Other countries of America at section level.

For each share measure, all eight country-specific maps use one common 0–10% scale. Values at or
above 10% receive the darkest colour. Total retains its own citywide scale. Country maps use
luminance-ordered, flag-derived palettes (gold for Colombia); the signed change map retains the
common red-white-blue direction scale with a fixed ±5 percentage-point limit.

The feature panel also reports each section’s rank across Madrid sections for density, under-18,
65+, foreign-citizenship and foreign-born measures. Tied values receive their average percentile
rank. Each country variant has its own citywide percentile distribution.

## Education & Work

The five 2024 measures use INE tables 66753 and 66755. Activity is active population divided by
population aged 16+; employment is employed divided by population aged 16+; unemployment is
unemployed divided by active population. Higher education and primary-or-lower attainment divide
the relevant category by population aged 15+. Official suppressions remain **No data**.

## Buildings

The construction layer reads `beginning` and `end` from Catastro INSPIRE’s `dateOfConstruction`.
Colour represents the earliest recorded year; the feature panel retains the full interval. The
height layer uses Madrid’s estimated building-height polygons and the non-negative `ALTURA` field.
At publication, the two vector layers are packaged together in one archive per district.

## Elections

The General election of 23 July 2023 and the Madrid Local and Assembly elections of 28 May 2023
are read from official polling-table workbooks. Tables are summed to district-and-section codes,
then joined to 2023 boundaries. Party share is:

`party votes / valid votes (candidate votes + blank ballots) × 100`

Turnout is ballots cast divided by the resident electoral census. Leading party is calculated
across every candidacy in the official workbook, not only the parties exposed as selectable layers.
For the results view, the feature panel ranks the selectable parties by vote share and shows rows
until their cumulative share reaches at least 90%.
The pipeline reconciles table totals against the published Madrid city totals; non-geographic votes
are excluded when they are not represented by a polling table.

Left–Right margins use right share minus left share of valid votes. General-election Left is PSOE +
SUMAR and Right is PP + VOX. Local and Assembly Left is PSOE + Más Madrid/MM-VQ + Podemos-IU-AV;
Right is PP + VOX. Every smaller candidacy is excluded from both blocs.

## Income and inequality

Net income per person and per household; the percentage of total income from pensions; the population below 60% and above 200% of median equivalised income; the
Gini coefficient; and the P80/P20 income ratio come from the 2023 INE Household Income Distribution
Atlas. They are retained as separate measures and joined to 2023 sections.

## Transport

Metro, Metro Ligero, Cercanías and EMT routes and stops are generated from CRTM GTFS snapshots.
BiciMAD contains station locations only. Every stop layer appears in full at zoom 12, while an EMT
route selector prevents the complete network from obscuring other information. This release does
not imply live vehicle positions, service status or bicycle availability.
