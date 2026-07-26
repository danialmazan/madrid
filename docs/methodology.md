# Methodology

## Geography and missing data

The atlas covers Madrid municipality. Regional transport is retained beyond the municipal
boundary so journeys can be understood in context. Thematic values are joined only to the census
section vintage matching the observation year: 2026, 2025 or 2023. A failed or absent match remains
null and is displayed as **No data**.

## Population

The latest monthly municipal padrón is summed by section and single year of age. Total population
includes Spanish and foreign citizens of all genders. Under-18 and 65+ values divide the relevant
age total by all registered residents. Foreign citizenship divides residents recorded as foreign
citizens by all residents. Density divides residents by section area in square kilometres.

The foreign-born layer is deliberately separate. It comes from the latest INE annual census table
and divides residents born outside Spain by the total. Its date and boundary vintage are not
silently mixed with the monthly padrón.

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
The pipeline reconciles table totals against the published Madrid city totals; non-geographic votes
are excluded when they are not represented by a polling table.

## Income and inequality

Net income per person, the population below 60% of median equivalised income, and the Gini
coefficient come from the 2023 INE Household Income Distribution Atlas. They are retained as
separate measures and joined to 2023 sections.

## Transport

Metro, Metro Ligero, Cercanías and EMT routes and stops are generated from CRTM GTFS snapshots.
BiciMAD contains station locations only. Stops have higher minimum zoom levels than routes, and an
EMT route selector prevents the complete network from obscuring other information. This release
does not imply live vehicle positions, service status or bicycle availability.
