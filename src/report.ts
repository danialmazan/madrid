import type {
  CityElectionReport,
  ElectionKey,
  LayerDefinition,
  ReportDistribution,
  ReportElectionResult,
  ReportMetricValue,
  SectionReport,
  SectionReportIndex,
  ValueFormat,
} from "./types";

const populationMetrics = [
  "population_total",
  "population_density_km2",
  "under18_pct",
  "age65plus_pct",
  "foreign_citizenship_pct",
  "foreign_born_pct",
];

const incomeMetrics = [
  "income_per_person_eur",
  "below_60_median_pct",
  "above_200_median_pct",
  "gini",
  "income_p80_p20",
];

export function sectionProperties(
  report: SectionReport,
  definition: LayerDefinition,
): Record<string, unknown> {
  const properties: Record<string, unknown> = {
    section_id: report.id,
    section_name: report.name,
    district: report.district,
  };
  const percentileProperties: Record<string, string> = {
    population_total: "population_total_percentile",
    population_density_km2: "population_density_percentile",
    under18_pct: "under18_percentile",
    age65plus_pct: "age65plus_percentile",
    foreign_citizenship_pct: "foreign_citizenship_percentile",
    foreign_born_pct: "foreign_born_percentile",
    income_per_person_eur: "income_per_person_percentile",
    below_60_median_pct: "below_60_median_percentile",
    above_200_median_pct: "above_200_median_percentile",
    gini: "gini_percentile",
    income_p80_p20: "income_p80_p20_percentile",
  };
  for (const [metric, item] of Object.entries({ ...report.population, ...report.income })) {
    properties[metric] = item.value;
    properties[percentileProperties[metric] ?? `${metric}_percentile`] = item.percentile;
  }

  const election = definition.control?.election;
  if (election) {
    const result = report.elections[election];
    properties[`turnout_pct_${election}`] = result.turnoutPct;
    properties[`valid_votes_${election}`] = result.validVotes;
    properties[`blank_votes_${election}`] = result.blankVotes;
    properties[`leading_party_${election}`] = result.leadingParty;
    for (const party of result.results) {
      properties[`share_${party.key.toLowerCase()}_${election}`] = party.share;
    }
  }
  return properties;
}

export function renderMadridElectionCard(city: CityElectionReport): string {
  return `
    <div class="feature-header madrid-results-header">
      <span class="feature-kicker">Madrid city result</span>
      <h3>${escapeHtml(city.label)}</h3>
      <p>${escapeHtml(formatDate(city.referenceDate))} · ${formatValue(city.turnoutPct, "percent")} turnout</p>
    </div>
    ${renderElectionTable(city.results)}
    <p class="results-coverage">${formatValue(city.shownCoveragePct, "percent", 1)} of valid votes shown</p>`;
}

export function renderSectionReport(
  index: SectionReportIndex,
  section: SectionReport,
): string {
  const changed = Object.entries(section.matches).filter(([, match]) => match.boundaryChanged);
  const changedNote = changed.length
    ? `<aside class="report-boundary-note">
        <strong>Historical boundary match</strong>
        <p>${changed
          .map(
            ([year, match]) =>
              `${year} uses section ${escapeHtml(match.sectionId)} (${Math.round(match.overlapShare * 100)}% overlap with the current area).`,
          )
          .join(" ")}</p>
      </aside>`
    : "";

  return `
    <article class="section-report-document">
      <header class="report-hero">
        <div>
          <p class="report-overline">Madrid census-section report · current 2026 geography</p>
          <h2>${escapeHtml(section.name)}</h2>
          <p class="report-id">Official section ID ${escapeHtml(section.id)}</p>
        </div>
        <div class="report-stamp" aria-label="Report generated ${escapeHtml(index.generatedAt.slice(0, 10))}">
          <span>Madrid Atlas</span>
          <strong>${escapeHtml(index.generatedAt.slice(0, 10))}</strong>
        </div>
      </header>
      ${changedNote}
      <section class="report-chapter" aria-labelledby="report-population-heading">
        <div class="report-chapter-heading">
          <p>01</p><div><h3 id="report-population-heading">Population</h3><span>Padrón ${escapeHtml(formatDate(index.dataDates.population))} · foreign-born ${escapeHtml(formatDate(index.dataDates.foreignBorn))}</span></div>
        </div>
        <div class="report-metric-grid">
          ${populationMetrics.map((metric) => renderMetric(index, section.population[metric], metric)).join("")}
        </div>
      </section>
      <section class="report-chapter" aria-labelledby="report-income-heading">
        <div class="report-chapter-heading">
          <p>02</p><div><h3 id="report-income-heading">Income &amp; inequality</h3><span>INE Household Income Distribution Atlas · ${escapeHtml(formatDate(index.dataDates.income))}</span></div>
        </div>
        ${renderIncomeSuppression(section)}
        <div class="report-metric-grid">
          ${incomeMetrics.map((metric) => renderMetric(index, section.income[metric], metric)).join("")}
        </div>
      </section>
      <section class="report-chapter report-elections" aria-labelledby="report-elections-heading">
        <div class="report-chapter-heading">
          <p>03</p><div><h3 id="report-elections-heading">Elections</h3><span>Section result compared with the full city</span></div>
        </div>
        <div class="report-election-grid">
          ${(["general", "local", "assembly"] as ElectionKey[])
            .map((election) => renderElectionComparison(section, index, election))
            .join("")}
        </div>
      </section>
      <section class="report-chapter" aria-labelledby="report-buildings-heading">
        <div class="report-chapter-heading">
          <p>04</p><div><h3 id="report-buildings-heading">Buildings</h3><span>Catastro ${escapeHtml(formatDate(index.dataDates.buildings))} · current section assignment</span></div>
        </div>
        ${renderBuildings(index, section)}
      </section>
      <footer class="report-sources">
        <h3>Sources &amp; interpretation</h3>
        <p>Percentiles compare valid Madrid census-section observations. A higher percentile means a higher raw value, not necessarily a better outcome. Suppressed observations remain No data.</p>
        <p><strong>Geography.</strong> Current ${escapeHtml(index.geographyVintages.canonical)} sections are canonical. Foreign-born measures use ${escapeHtml(index.geographyVintages.foreignBorn)} sections; income and elections use ${escapeHtml(index.geographyVintages.incomeAndElections)} sections, matched by greatest polygon overlap without area-weighting or imputation. Catastro footprints are assigned by point-on-surface.</p>
        <p><a href="${escapeHtml(index.methodologyUrl)}">Read the full methodology</a></p>
        <ul>${index.references
          .slice(0, 6)
          .map(
            (reference) =>
              `<li><a href="${escapeHtml(reference.url)}">${escapeHtml(reference.title)}</a> · ${escapeHtml(reference.organisation)}<span>Retrieved ${escapeHtml(formatDate(reference.retrieved))} · ${escapeHtml(reference.licence)}</span></li>`,
          )
          .join("")}</ul>
      </footer>
    </article>`;
}

function renderMetric(
  index: SectionReportIndex,
  item: ReportMetricValue | undefined,
  metric: string,
): string {
  const distribution = index.distributions[metric];
  if (!distribution) return "";
  const value = item?.value ?? null;
  const percentile = item?.percentile ?? null;
  const percentileText = percentile === null ? "No percentile" : `${ordinal(Math.round(percentile))} percentile`;
  return `
    <article class="report-metric${value === null ? " is-missing" : ""}">
      <div class="report-metric-value">
        <h4>${escapeHtml(distribution.label)}</h4>
        <strong>${value === null ? "No data" : escapeHtml(formatValue(value, distribution.format))}</strong>
        <span>${escapeHtml(percentileText)} · n=${distribution.observationCount.toLocaleString("en-GB")}</span>
      </div>
      ${value === null ? renderNoDataChart(distribution) : renderDistributionChart(distribution, value, percentile)}
    </article>`;
}

function renderDistributionChart(
  distribution: ReportDistribution,
  value: number,
  percentile: number | null,
): string {
  const width = 260;
  const height = 68;
  const base = 52;
  const maximumCount = Math.max(...distribution.counts, 1);
  const barWidth = width / distribution.counts.length;
  const bars = distribution.counts
    .map((count, index) => {
      const barHeight = Math.max(2, (count / maximumCount) * 38);
      return `<rect x="${(index * barWidth + 2).toFixed(1)}" y="${(base - barHeight).toFixed(1)}" width="${Math.max(2, barWidth - 4).toFixed(1)}" height="${barHeight.toFixed(1)}" rx="2" />`;
    })
    .join("");
  const low = distribution.breaks[0] ?? distribution.minimum ?? 0;
  const high = distribution.breaks.at(-1) ?? distribution.maximum ?? low + 1;
  const markerX = Math.max(4, Math.min(width - 4, ((value - low) / Math.max(1e-9, high - low)) * width));
  const label = `${distribution.label}: ${formatValue(value, distribution.format)}, ${percentile === null ? "percentile unavailable" : `${ordinal(Math.round(percentile))} percentile`}. Distribution across ${distribution.observationCount} Madrid sections.`;
  return `<svg class="distribution-chart" viewBox="0 0 ${width} ${height}" role="img" aria-label="${escapeHtml(label)}">
      <g class="distribution-bars">${bars}</g>
      <line class="distribution-marker" x1="${markerX.toFixed(1)}" x2="${markerX.toFixed(1)}" y1="5" y2="57" />
      <circle class="distribution-dot" cx="${markerX.toFixed(1)}" cy="7" r="4" />
      <text x="0" y="66">${escapeHtml(formatValue(low, distribution.format))}</text>
      <text x="${width}" y="66" text-anchor="end">${escapeHtml(formatValue(high, distribution.format))}</text>
    </svg>`;
}

function renderNoDataChart(distribution: ReportDistribution): string {
  return `<div class="distribution-empty" role="img" aria-label="No published value for ${escapeHtml(distribution.label)}">
    <span></span><p>Not published for this section</p><span></span>
  </div>`;
}

function renderIncomeSuppression(section: SectionReport): string {
  const affected = ["Carabanchel", "Fuencarral-El Pardo"].includes(section.district);
  const missing = section.income.below_60_median_pct?.value === null;
  if (!affected || !missing) return "";
  return `<aside class="report-data-note"><strong>Official source suppression</strong><p>INE publishes no section values for the below-60% or above-200% median indicators in ${escapeHtml(section.district)}. Income per person, Gini and P80/P20 remain available.</p></aside>`;
}

function renderElectionComparison(
  section: SectionReport,
  index: SectionReportIndex,
  election: ElectionKey,
): string {
  const local = section.elections[election];
  const city = index.cityElections[election];
  const cityByKey = new Map(city.results.map((result) => [result.key, result]));
  const rows = local.results
    .filter((result) => result.share !== null)
    .sort((left, right) => (right.share ?? 0) - (left.share ?? 0))
    .map((result) => {
      const cityResult = cityByKey.get(result.key);
      return renderComparisonRow(result, cityResult?.share ?? null);
    })
    .join("");
  return `<article class="report-election">
    <header><h4>${escapeHtml(city.label)}</h4><span>${escapeHtml(formatDate(city.referenceDate))}</span></header>
    <div class="election-turnout"><span>Turnout</span><strong>${formatValue(local.turnoutPct ?? Number.NaN, "percent")}</strong><small>Madrid ${formatValue(city.turnoutPct, "percent")}</small></div>
    <div class="election-comparisons">${rows}</div>
  </article>`;
}

function renderComparisonRow(result: ReportElectionResult, cityShare: number | null): string {
  const sectionShare = result.share ?? 0;
  const sectionWidth = Math.min(100, (sectionShare / 60) * 100);
  const cityWidth = Math.min(100, ((cityShare ?? 0) / 60) * 100);
  return `<div class="election-comparison">
    <div><i style="background:${escapeHtml(result.color)}"></i><strong>${escapeHtml(result.label)}</strong><span>${formatValue(sectionShare, "percent", 1)}</span></div>
    <div class="comparison-track"><i style="width:${sectionWidth.toFixed(1)}%;background:${escapeHtml(result.color)}"></i></div>
    <div class="comparison-track is-city"><i style="width:${cityWidth.toFixed(1)}%;background:${escapeHtml(result.color)}"></i></div>
    <small>Madrid ${cityShare === null ? "No data" : formatValue(cityShare, "percent", 1)}</small>
  </div>`;
}

function renderBuildings(index: SectionReportIndex, section: SectionReport): string {
  const cityTotal = index.cityBuildings.constructionEras.reduce((sum, count) => sum + count, 0);
  const sectionTotal = section.buildings.constructionEras.reduce((sum, count) => sum + count, 0);
  const eras = index.constructionEras
    .map((label, eraIndex) => {
      const localCount = section.buildings.constructionEras[eraIndex] ?? 0;
      const cityCount = index.cityBuildings.constructionEras[eraIndex] ?? 0;
      const localShare = sectionTotal > 0 ? (100 * localCount) / sectionTotal : 0;
      const cityShare = cityTotal > 0 ? (100 * cityCount) / cityTotal : 0;
      return `<div class="building-era-row">
        <span>${escapeHtml(label)}</span>
        <div class="era-track"><i style="width:${localShare.toFixed(1)}%"></i></div>
        <strong>${formatValue(localShare, "percent", 1)}</strong>
        <small>Madrid ${formatValue(cityShare, "percent", 1)}</small>
      </div>`;
    })
    .join("");
  return `<div class="building-summary">
    <dl>
      <div><dt>Building footprints</dt><dd>${formatValue(section.buildings.buildingCount, "integer")}</dd></div>
      <div><dt>Recorded dwellings</dt><dd>${formatValue(section.buildings.dwellings, "integer")}</dd></div>
      <div><dt>Median earliest year</dt><dd>${section.buildings.medianConstructionYear === null ? "No data" : Math.round(section.buildings.medianConstructionYear)}</dd></div>
    </dl>
    <div class="building-era-chart" role="img" aria-label="Construction era distribution for this section compared with Madrid">${eras}</div>
  </div>`;
}

function renderElectionTable(results: ReportElectionResult[]): string {
  const sorted = [...results].filter((result) => result.share !== null).sort((a, b) => (b.share ?? 0) - (a.share ?? 0));
  return `<table class="election-results"><thead><tr><th>Party</th><th>Vote share</th></tr></thead><tbody>${sorted
    .map(
      (result) => `<tr><th><i style="background:${escapeHtml(result.color)}"></i>${escapeHtml(result.label)}</th><td>${formatValue(result.share ?? Number.NaN, "percent", 1)}</td></tr>`,
    )
    .join("")}</tbody></table>`;
}

function formatValue(value: number, format: ValueFormat, minimumFractionDigits = 0): string {
  if (!Number.isFinite(value)) return "No data";
  switch (format) {
    case "integer":
      return new Intl.NumberFormat("en-GB", { maximumFractionDigits: 0 }).format(value);
    case "decimal":
      return new Intl.NumberFormat("en-GB", { maximumFractionDigits: 1 }).format(value);
    case "percent":
      return `${new Intl.NumberFormat("en-GB", { minimumFractionDigits, maximumFractionDigits: 1 }).format(value)}%`;
    case "currency":
      return new Intl.NumberFormat("en-GB", { style: "currency", currency: "EUR", maximumFractionDigits: 0 }).format(value);
    case "year":
      return String(Math.round(value));
    case "text":
      return String(value);
  }
}

function formatDate(value: string): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return value;
  return new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "short", year: "numeric" }).format(
    new Date(`${value}T12:00:00Z`),
  );
}

function ordinal(value: number): string {
  const remainder100 = value % 100;
  if (remainder100 >= 11 && remainder100 <= 13) return `${value}th`;
  return `${value}${value % 10 === 1 ? "st" : value % 10 === 2 ? "nd" : value % 10 === 3 ? "rd" : "th"}`;
}

function escapeHtml(value: string): string {
  return value.replace(
    /[&<>'"]/g,
    (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[character]!,
  );
}
