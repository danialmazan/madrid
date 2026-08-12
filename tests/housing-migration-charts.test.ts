// @vitest-environment jsdom

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { beforeEach, describe, expect, it } from "vitest";
import {
  renderCityDiagnosticChart,
  renderCohortOutcomeChart,
  renderDistributionChart,
  renderSectionAgeChart,
} from "../src/housing-migration-charts";
import type { HousingMigrationAnalysis } from "../src/housing-migration-types";

const data = JSON.parse(
  readFileSync(resolve(import.meta.dirname, "../public/data/housing-migration-analysis.json"), "utf8"),
) as HousingMigrationAnalysis;

describe("housing analysis charts", () => {
  beforeEach(() => {
    document.body.innerHTML = '<div id="chart"></div><div id="analysis-tooltip" hidden></div>';
  });

  it("renders section whiskers with keyboard-accessible exact-value tooltips", () => {
    const container = document.querySelector<HTMLElement>("#chart")!;
    renderSectionAgeChart(container, { data, districtCodes: ["11"] });
    expect(container.querySelector("svg")?.getAttribute("aria-label")).toContain("Dwelling-weighted");
    const mark = container.querySelector<SVGGElement>(".section-whisker")!;
    expect(mark.getAttribute("tabindex")).toBe("0");
    mark.focus();
    expect(document.querySelector<HTMLElement>("#analysis-tooltip")!.hidden).toBe(false);
    expect(document.querySelector("#analysis-tooltip")!.textContent).toContain("Carabanchel");
  });

  it("renders both building and dwelling-weighted distribution modes", () => {
    const container = document.querySelector<HTMLElement>("#chart")!;
    renderDistributionChart(container, { data, districtCodes: ["11", "10"] });
    expect(container.querySelectorAll(".distribution-line")).toHaveLength(4);
    expect(container.querySelectorAll(".distribution-line.is-weighted")).toHaveLength(2);
  });

  it("uses boxes for stable cohorts and points for sparse cohorts in both outcomes", () => {
    const container = document.querySelector<HTMLElement>("#chart")!;
    renderCohortOutcomeChart(container, { data, districtCodes: ["11", "10"] }, "share");
    expect(container.querySelectorAll(".cohort-box").length).toBeGreaterThan(0);
    expect(container.querySelectorAll(".sparse-point").length).toBeGreaterThan(0);
    renderCohortOutcomeChart(container, { data, districtCodes: ["11", "10"] }, "change");
    expect(container.querySelector("svg")?.getAttribute("aria-label")).toContain("Boxes summarise");
  });

  it("shows all districts and highlights current selections in the city diagnostic", () => {
    const container = document.querySelector<HTMLElement>("#chart")!;
    renderCityDiagnosticChart(container, { data, districtCodes: ["11"] }, "count");
    expect(container.querySelectorAll(".district-bubble")).toHaveLength(21);
    expect(container.querySelectorAll(".district-bubble.is-selected")).toHaveLength(1);
    renderCityDiagnosticChart(container, { data, districtCodes: ["11"] }, "change");
    expect(container.querySelectorAll(".district-bubble")).toHaveLength(21);
  });
});
