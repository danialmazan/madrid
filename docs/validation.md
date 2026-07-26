# Validation record

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
