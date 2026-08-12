import type {
  AnalysisDistrict,
  AnalysisSection,
  HousingMigrationAnalysis,
} from "./housing-migration-types";
import type { DistrictOutcome, SectionOutcome } from "./housing-migration-state";

const WIDTH = 980;
const HEIGHT = 540;
const MARGIN = { top: 34, right: 28, bottom: 76, left: 76 };
const plotWidth = WIDTH - MARGIN.left - MARGIN.right;
const plotHeight = HEIGHT - MARGIN.top - MARGIN.bottom;

export const DISTRICT_COLOURS: Record<string, string> = {
  "01": "#8a4d76", "02": "#007f72", "03": "#9a5d00", "04": "#3766a0",
  "05": "#b94b43", "06": "#497a2d", "07": "#7655a5", "08": "#a05c28",
  "09": "#147d9a", "10": "#d65f36", "11": "#176b87", "12": "#a13b65",
  "13": "#647b24", "14": "#816633", "15": "#6253a7", "16": "#00836f",
  "17": "#bb4e36", "18": "#3d7397", "19": "#8e5849", "20": "#47782f", "21": "#886087",
};

export interface ChartContext {
  data: HousingMigrationAnalysis;
  districtCodes: string[];
}

type TooltipDatum = { label: string; lines: string[] };

const svgElement = (name: string): SVGElement =>
  document.createElementNS("http://www.w3.org/2000/svg", name);

const setAttributes = (element: Element, attributes: Record<string, string | number>): void => {
  for (const [name, value] of Object.entries(attributes)) element.setAttribute(name, String(value));
};

const scale = (value: number, domainMin: number, domainMax: number, rangeMin: number, rangeMax: number): number =>
  domainMax === domainMin
    ? (rangeMin + rangeMax) / 2
    : rangeMin + ((value - domainMin) / (domainMax - domainMin)) * (rangeMax - rangeMin);

const extent = (values: number[], padding = 0): [number, number] => {
  const minimum = Math.min(...values);
  const maximum = Math.max(...values);
  const extra = (maximum - minimum || 1) * padding;
  return [minimum - extra, maximum + extra];
};

const quantile = (values: number[], probability: number): number => {
  const ordered = [...values].sort((a, b) => a - b);
  if (!ordered.length) return Number.NaN;
  const index = (ordered.length - 1) * probability;
  const lowerIndex = Math.floor(index);
  const upperIndex = Math.ceil(index);
  const lower = ordered[lowerIndex] ?? ordered[0]!;
  const upper = ordered[upperIndex] ?? ordered.at(-1)!;
  return lower + (upper - lower) * (index - lowerIndex);
};

const createSvg = (container: HTMLElement, title: string, description: string, height = HEIGHT): SVGSVGElement => {
  container.replaceChildren();
  const svg = svgElement("svg") as SVGSVGElement;
  setAttributes(svg, {
    viewBox: `0 0 ${WIDTH} ${height}`,
    role: "img",
    "aria-label": `${title}. ${description}`,
    class: "analysis-svg",
  });
  const titleNode = svgElement("title");
  titleNode.textContent = title;
  const descriptionNode = svgElement("desc");
  descriptionNode.textContent = description;
  svg.append(titleNode, descriptionNode);
  container.append(svg);
  return svg;
};

const addText = (
  svg: SVGSVGElement,
  text: string,
  x: number,
  y: number,
  className: string,
  anchor: "start" | "middle" | "end" = "start",
): SVGTextElement => {
  const node = svgElement("text") as SVGTextElement;
  node.textContent = text;
  setAttributes(node, { x, y, class: className, "text-anchor": anchor });
  svg.append(node);
  return node;
};

const addAxes = (
  svg: SVGSVGElement,
  xTicks: Array<{ position: number; label: string }>,
  yTicks: Array<{ position: number; label: string }>,
  xLabel: string,
  yLabel: string,
): void => {
  for (const tick of yTicks) {
    const line = svgElement("line");
    setAttributes(line, { x1: MARGIN.left, x2: WIDTH - MARGIN.right, y1: tick.position, y2: tick.position, class: "grid-line" });
    svg.append(line);
    addText(svg, tick.label, MARGIN.left - 12, tick.position + 4, "axis-tick", "end");
  }
  for (const tick of xTicks) addText(svg, tick.label, tick.position, HEIGHT - MARGIN.bottom + 24, "axis-tick", "middle");
  addText(svg, xLabel, MARGIN.left + plotWidth / 2, HEIGHT - 17, "axis-label", "middle");
  const y = addText(svg, yLabel, 19, MARGIN.top + plotHeight / 2, "axis-label", "middle");
  y.setAttribute("transform", `rotate(-90 19 ${MARGIN.top + plotHeight / 2})`);
}

const tooltip = (): HTMLElement => {
  let node = document.querySelector<HTMLElement>("#analysis-tooltip");
  if (!node) {
    node = document.createElement("div");
    node.id = "analysis-tooltip";
    node.className = "analysis-tooltip";
    node.setAttribute("role", "status");
    node.hidden = true;
    document.body.append(node);
  }
  return node;
};

const showTooltip = (datum: TooltipDatum, anchor: Element): void => {
  const node = tooltip();
  node.replaceChildren();
  const strong = document.createElement("strong");
  strong.textContent = datum.label;
  node.append(strong);
  for (const line of datum.lines) {
    const span = document.createElement("span");
    span.textContent = line;
    node.append(span);
  }
  const box = anchor.getBoundingClientRect();
  node.style.left = `${Math.min(window.innerWidth - 260, Math.max(12, box.left + box.width / 2))}px`;
  node.style.top = `${Math.max(12, box.top - 10)}px`;
  node.hidden = false;
};

const bindTooltip = (element: SVGElement, datum: TooltipDatum): void => {
  element.setAttribute("tabindex", "0");
  element.setAttribute("role", "button");
  element.setAttribute("aria-label", `${datum.label}. ${datum.lines.join(". ")}`);
  element.addEventListener("pointerenter", () => showTooltip(datum, element));
  element.addEventListener("focus", () => showTooltip(datum, element));
  const hide = (): void => { tooltip().hidden = true; };
  element.addEventListener("pointerleave", hide);
  element.addEventListener("blur", hide);
}

const selectedSections = (context: ChartContext): AnalysisSection[] =>
  context.data.sections.filter((section) => context.districtCodes.includes(section.districtCode));

const districtByCode = (context: ChartContext, code: string): AnalysisDistrict => {
  const district = context.data.districts.find((item) => item.code === code);
  if (!district) throw new Error(`Unknown district ${code}`);
  return district;
};

export function renderSectionAgeChart(container: HTMLElement, context: ChartContext): void {
  const rows = selectedSections(context).filter((section) => section.constructionYear.median !== null);
  const xDomain = extent(rows.map((section) => section.foreignBornPct2025), 0.04);
  const years = rows.flatMap((section) => [section.constructionYear.p10, section.constructionYear.p90]).filter((year): year is number => year !== null);
  const yDomain: [number, number] = [Math.floor(Math.min(...years) / 10) * 10, Math.ceil(Math.max(...years) / 10) * 10];
  const svg = createSvg(container, "Dwelling-weighted building age by section", "Each mark is one census section; whiskers show the dwelling-weighted p10 to p90 and boxes show q1 to q3.");
  addAxes(
    svg,
    Array.from({ length: 6 }, (_, index) => {
      const value = xDomain[0] + (index / 5) * (xDomain[1] - xDomain[0]);
      return { position: scale(value, ...xDomain, MARGIN.left, WIDTH - MARGIN.right), label: `${value.toFixed(0)}%` };
    }),
    Array.from({ length: 6 }, (_, index) => {
      const value = yDomain[0] + (index / 5) * (yDomain[1] - yDomain[0]);
      return { position: scale(value, ...yDomain, MARGIN.top + plotHeight, MARGIN.top), label: value.toFixed(0) };
    }),
    "Foreign-born population share, 2025",
    "Residential construction year",
  );

  for (const section of rows) {
    const colour = DISTRICT_COLOURS[section.districtCode] ?? "#176b87";
    const x = scale(section.foreignBornPct2025, ...xDomain, MARGIN.left, WIDTH - MARGIN.right);
    const year = section.constructionYear;
    if (year.p10 === null || year.q1 === null || year.median === null || year.q3 === null || year.p90 === null) continue;
    const group = svgElement("g");
    group.setAttribute("class", "section-whisker");
    const whisker = svgElement("line");
    setAttributes(whisker, { x1: x, x2: x, y1: scale(year.p10, ...yDomain, MARGIN.top + plotHeight, MARGIN.top), y2: scale(year.p90, ...yDomain, MARGIN.top + plotHeight, MARGIN.top), stroke: colour });
    const box = svgElement("rect");
    const q3Y = scale(year.q3, ...yDomain, MARGIN.top + plotHeight, MARGIN.top);
    const q1Y = scale(year.q1, ...yDomain, MARGIN.top + plotHeight, MARGIN.top);
    setAttributes(box, { x: x - 2.4, y: q3Y, width: 4.8, height: Math.max(1.5, q1Y - q3Y), fill: colour });
    const median = svgElement("line");
    const medianY = scale(year.median, ...yDomain, MARGIN.top + plotHeight, MARGIN.top);
    setAttributes(median, { x1: x - 3.5, x2: x + 3.5, y1: medianY, y2: medianY, stroke: colour, class: "median-mark" });
    group.append(whisker, box, median);
    bindTooltip(group, {
      label: `${section.districtName} · section ${Number(section.id.slice(-3))}`,
      lines: [
        `${section.foreignBornPct2025.toFixed(1)}% foreign-born`,
        `Weighted median ${year.median}; p10–p90 ${year.p10}–${year.p90}`,
        `${section.dwellingCount.toLocaleString("en-GB")} recorded dwellings`,
      ],
    });
    svg.append(group);
  }

  for (const code of context.districtCodes) {
    const districtRows = rows.filter((section) => section.districtCode === code);
    const bins = Array.from({ length: 10 }, (_, index) => {
      const low = xDomain[0] + (index / 10) * (xDomain[1] - xDomain[0]);
      const high = xDomain[0] + ((index + 1) / 10) * (xDomain[1] - xDomain[0]);
      const values = districtRows.filter((row) => row.foreignBornPct2025 >= low && (index === 9 ? row.foreignBornPct2025 <= high : row.foreignBornPct2025 < high));
      return values.length >= 3
        ? { x: values.reduce((sum, row) => sum + row.foreignBornPct2025, 0) / values.length, y: values.reduce((sum, row) => sum + (row.constructionYear.median ?? 0), 0) / values.length }
        : null;
    }).filter((item): item is { x: number; y: number } => item !== null);
    const path = svgElement("path");
    const commands = bins.map((item, index) => `${index ? "L" : "M"}${scale(item.x, ...xDomain, MARGIN.left, WIDTH - MARGIN.right).toFixed(1)},${scale(item.y, ...yDomain, MARGIN.top + plotHeight, MARGIN.top).toFixed(1)}`).join(" ");
    setAttributes(path, { d: commands, stroke: DISTRICT_COLOURS[code] ?? "#176b87", class: "trend-line" });
    svg.append(path);
  }
}

export function renderDistributionChart(container: HTMLElement, context: ChartContext): void {
  const districts = context.districtCodes.map((code) => districtByCode(context, code));
  const cohorts = districts[0]?.distribution ?? [];
  const maximum = Math.max(...districts.flatMap((district) => district.distribution.flatMap((item) => [item.buildingSharePct, item.dwellingSharePct]))) * 1.08;
  const svg = createSvg(container, "Residential construction-year distribution", "Solid lines count residential buildings equally; dashed lines weight the same records by recorded dwellings.");
  addAxes(
    svg,
    cohorts.filter((_, index) => index % 3 === 0).map((item) => ({ position: scale(item.order, 0, cohorts.length - 1, MARGIN.left, WIDTH - MARGIN.right), label: item.label.replace(/^\d{2}/, "") })),
    Array.from({ length: 6 }, (_, index) => ({ position: scale((index / 5) * maximum, 0, maximum, MARGIN.top + plotHeight, MARGIN.top), label: `${((index / 5) * maximum).toFixed(0)}%` })),
    "Construction cohort",
    "Share of district total",
  );
  for (const district of districts) {
    for (const mode of ["buildingSharePct", "dwellingSharePct"] as const) {
      const path = svgElement("path");
      const commands = district.distribution.map((item, index) => `${index ? "L" : "M"}${scale(item.order, 0, cohorts.length - 1, MARGIN.left, WIDTH - MARGIN.right).toFixed(1)},${scale(item[mode], 0, maximum, MARGIN.top + plotHeight, MARGIN.top).toFixed(1)}`).join(" ");
      setAttributes(path, { d: commands, stroke: DISTRICT_COLOURS[district.code] ?? "#176b87", class: mode === "dwellingSharePct" ? "distribution-line is-weighted" : "distribution-line" });
      svg.append(path);
    }
    district.distribution.forEach((item) => {
      const point = svgElement("circle");
      setAttributes(point, {
        cx: scale(item.order, 0, cohorts.length - 1, MARGIN.left, WIDTH - MARGIN.right),
        cy: scale(item.dwellingSharePct, 0, maximum, MARGIN.top + plotHeight, MARGIN.top),
        r: 5,
        fill: "transparent",
      });
      bindTooltip(point, {
        label: `${district.name} · ${item.label}`,
        lines: [`${item.buildingSharePct.toFixed(1)}% of residential buildings`, `${item.dwellingSharePct.toFixed(1)}% of recorded dwellings`],
      });
      svg.append(point);
    });
  }
}

export function renderCohortOutcomeChart(container: HTMLElement, context: ChartContext, outcome: SectionOutcome): void {
  const rows = selectedSections(context).filter((section) => section.medianYearBucket.startYear !== null && (outcome === "share" || section.foreignBornChangePp !== null));
  const bucketOrders = [...new Set(rows.map((row) => row.medianYearBucket.startYear as number))].sort((a, b) => a - b);
  const values = rows.map((row) => outcome === "share" ? row.foreignBornPct2025 : row.foreignBornChangePp as number);
  const yDomain = extent(values, 0.08);
  const svg = createSvg(container, "Foreign-born population by section housing cohort", "Boxes summarise groups with at least five sections; smaller groups show their individual sections.");
  addAxes(
    svg,
    bucketOrders.filter((_, index) => index % 2 === 0).map((bucket) => ({ position: scale(bucket, bucketOrders[0]!, bucketOrders.at(-1)!, MARGIN.left, WIDTH - MARGIN.right), label: `${bucket}–${String(bucket + 4).slice(-2)}` })),
    Array.from({ length: 6 }, (_, index) => { const value = yDomain[0] + (index / 5) * (yDomain[1] - yDomain[0]); return { position: scale(value, ...yDomain, MARGIN.top + plotHeight, MARGIN.top), label: `${value.toFixed(1)}${outcome === "share" ? "%" : " pp"}` }; }),
    "Section dwelling-weighted median construction cohort",
    outcome === "share" ? "Foreign-born population share, 2025" : "Foreign-born share change, 2021–2025",
  );
  const dodge = context.districtCodes.length === 1 ? 0 : 9;
  context.districtCodes.forEach((code, districtIndex) => {
    const offset = (districtIndex - (context.districtCodes.length - 1) / 2) * dodge;
    for (const bucket of bucketOrders) {
      const group = rows.filter((row) => row.districtCode === code && row.medianYearBucket.startYear === bucket);
      const groupValues = group.map((row) => outcome === "share" ? row.foreignBornPct2025 : row.foreignBornChangePp as number);
      const x = scale(bucket, bucketOrders[0]!, bucketOrders.at(-1)!, MARGIN.left, WIDTH - MARGIN.right) + offset;
      const colour = DISTRICT_COLOURS[code] ?? "#176b87";
      if (groupValues.length >= 5) {
        const stats = [0.1, 0.25, 0.5, 0.75, 0.9].map((p) => quantile(groupValues, p));
        const [p10, q1, median, q3, p90] = stats as [number, number, number, number, number];
        const mark = svgElement("g");
        mark.setAttribute("class", "cohort-box");
        const whisker = svgElement("line");
        setAttributes(whisker, { x1: x, x2: x, y1: scale(p10, ...yDomain, MARGIN.top + plotHeight, MARGIN.top), y2: scale(p90, ...yDomain, MARGIN.top + plotHeight, MARGIN.top), stroke: colour });
        const box = svgElement("rect");
        const q3Y = scale(q3, ...yDomain, MARGIN.top + plotHeight, MARGIN.top);
        const q1Y = scale(q1, ...yDomain, MARGIN.top + plotHeight, MARGIN.top);
        setAttributes(box, { x: x - 5, y: q3Y, width: 10, height: Math.max(2, q1Y - q3Y), fill: colour });
        const middle = svgElement("line");
        const middleY = scale(median, ...yDomain, MARGIN.top + plotHeight, MARGIN.top);
        setAttributes(middle, { x1: x - 6, x2: x + 6, y1: middleY, y2: middleY, stroke: colour, class: "median-mark" });
        mark.append(whisker, box, middle);
        bindTooltip(mark, { label: `${districtByCode(context, code).name} · ${bucket}–${String(bucket + 4).slice(-2)}`, lines: [`${groupValues.length} sections`, `Median ${median.toFixed(1)}${outcome === "share" ? "%" : " pp"}`, `p10–p90 ${p10.toFixed(1)}–${p90.toFixed(1)}`] });
        svg.append(mark);
      } else {
        group.forEach((section, pointIndex) => {
          const point = svgElement("circle");
          const value = groupValues[pointIndex]!;
          setAttributes(point, { cx: x + (pointIndex - (group.length - 1) / 2) * 3, cy: scale(value, ...yDomain, MARGIN.top + plotHeight, MARGIN.top), r: 3.5, fill: colour, class: "sparse-point" });
          bindTooltip(point, { label: `${section.districtName} · section ${Number(section.id.slice(-3))}`, lines: [`Sparse cohort: ${group.length} section${group.length === 1 ? "" : "s"}`, `${value.toFixed(1)}${outcome === "share" ? "% foreign-born" : " pp change"}`] });
          svg.append(point);
        });
      }
    }
  });
}

export function renderCityDiagnosticChart(container: HTMLElement, context: ChartContext, outcome: DistrictOutcome): void {
  const rows = context.data.districts;
  const xDomain = extent(rows.map((row) => row.shareDwellings1961To1970Pct), 0.08);
  const yValues = rows.map((row) => outcome === "count" ? row.foreignBorn.countChange : row.foreignBorn.shareChangePp);
  const yDomain = extent(yValues, 0.12);
  const dwellingExtent = extent(rows.map((row) => row.dwellingCount));
  const svg = createSvg(container, "Citywide diagnostic", "All 21 districts compare their 1961–1970 dwelling share with recent foreign-born population change.");
  addAxes(
    svg,
    Array.from({ length: 6 }, (_, index) => { const value = xDomain[0] + (index / 5) * (xDomain[1] - xDomain[0]); return { position: scale(value, ...xDomain, MARGIN.left, WIDTH - MARGIN.right), label: `${value.toFixed(0)}%` }; }),
    Array.from({ length: 6 }, (_, index) => { const value = yDomain[0] + (index / 5) * (yDomain[1] - yDomain[0]); return { position: scale(value, ...yDomain, MARGIN.top + plotHeight, MARGIN.top), label: outcome === "count" ? Math.round(value).toLocaleString("en-GB") : `${value.toFixed(1)} pp` }; }),
    "Recorded residential dwellings built in 1961–1970",
    outcome === "count" ? "Increase in foreign-born residents, 2021–2025" : "Foreign-born share change, 2021–2025",
  );
  for (const district of rows) {
    const selected = context.districtCodes.includes(district.code);
    const point = svgElement("circle");
    const radius = scale(Math.sqrt(district.dwellingCount), Math.sqrt(dwellingExtent[0]), Math.sqrt(dwellingExtent[1]), 6, 16);
    setAttributes(point, {
      cx: scale(district.shareDwellings1961To1970Pct, ...xDomain, MARGIN.left, WIDTH - MARGIN.right),
      cy: scale(outcome === "count" ? district.foreignBorn.countChange : district.foreignBorn.shareChangePp, ...yDomain, MARGIN.top + plotHeight, MARGIN.top),
      r: radius,
      fill: selected ? DISTRICT_COLOURS[district.code] ?? "#176b87" : "var(--chart-muted)",
      class: selected ? "district-bubble is-selected" : "district-bubble",
    });
    bindTooltip(point, {
      label: district.name,
      lines: [
        `${district.shareDwellings1961To1970Pct.toFixed(1)}% of recorded dwellings built 1961–1970`,
        `${district.foreignBorn.countChange.toLocaleString("en-GB", { signDisplay: "always" })} foreign-born residents`,
        `${district.foreignBorn.shareChangePp.toFixed(1)} pp share change`,
        `${district.dwellingCount.toLocaleString("en-GB")} recorded dwellings`,
      ],
    });
    svg.append(point);
    if (selected || ["10", "13", "14", "15"].includes(district.code)) {
      const x = Number(point.getAttribute("cx"));
      const y = Number(point.getAttribute("cy"));
      addText(svg, district.name, x + radius + 5, y + 4, selected ? "point-label is-selected" : "point-label");
    }
  }
}
