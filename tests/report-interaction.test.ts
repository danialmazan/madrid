// @vitest-environment jsdom

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  bindDistributionCharts,
  chartXFromClientX,
  distributionPreviewText,
  percentileAtValue,
  valueFromChartX,
} from "../src/report-interaction";
import type { ReportDistribution, SectionReportIndex } from "../src/types";

const distribution: ReportDistribution = {
  label: "Foreign citizenship",
  format: "percent",
  unit: "%",
  breaks: [0, 10, 20, 30, 40],
  counts: [2, 3, 3, 2],
  observationCount: 10,
  minimum: 10,
  maximum: 30,
  percentileValues: [10, 20, 30],
  percentileRanks: [0, 50, 100],
};

describe("distribution exploration calculations", () => {
  it("maps chart positions to values and clamps outside the chart", () => {
    expect(chartXFromClientX(150, 20, 260)).toBe(130);
    expect(chartXFromClientX(-100, 20, 260)).toBe(0);
    expect(chartXFromClientX(500, 20, 260)).toBe(260);
    expect(valueFromChartX(130, 0, 40)).toBe(20);
  });

  it("interpolates between exact tie-aware percentile points", () => {
    expect(percentileAtValue(distribution, 5)).toBe(0);
    expect(percentileAtValue(distribution, 10)).toBe(0);
    expect(percentileAtValue(distribution, 15)).toBe(25);
    expect(percentileAtValue(distribution, 20)).toBe(50);
    expect(percentileAtValue(distribution, 35)).toBe(100);
    expect(distributionPreviewText(distribution, 18.4)).toBe("42nd percentile · 18.4%");
  });
});

describe("distribution pointer interactions", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    Object.defineProperty(window, "matchMedia", {
      configurable: true,
      value: () => ({ matches: true }),
    });
  });

  afterEach(() => {
    vi.useRealTimers();
    document.body.innerHTML = "";
  });

  it("waits for touch hold, updates while dragging, and restores on release", () => {
    const { container, hit, line, preview, cleanup } = setupChart();
    hit.dispatchEvent(pointerEvent("pointerdown", { pointerId: 7, pointerType: "touch", clientX: 130 }));
    expect(preview.hidden).toBe(true);
    vi.advanceTimersByTime(199);
    expect(preview.hidden).toBe(true);
    vi.advanceTimersByTime(1);
    expect(preview.hidden).toBe(false);

    hit.dispatchEvent(pointerEvent("pointermove", { pointerId: 7, pointerType: "touch", clientX: 195 }));
    expect(line.getAttribute("x1")).toBe("195.00");
    expect(preview.textContent).toBe("100th percentile · 30%");

    hit.dispatchEvent(pointerEvent("pointerup", { pointerId: 7, pointerType: "touch", clientX: 195 }));
    expect(preview.hidden).toBe(true);
    expect(line.getAttribute("x1")).toBe("130.00");
    cleanup();
    container.remove();
  });

  it("cancels touch activation when movement indicates scrolling", () => {
    const { hit, preview, cleanup } = setupChart();
    hit.dispatchEvent(pointerEvent("pointerdown", { pointerId: 8, pointerType: "touch", clientX: 130, clientY: 20 }));
    hit.dispatchEvent(pointerEvent("pointermove", { pointerId: 8, pointerType: "touch", clientX: 131, clientY: 31 }));
    vi.advanceTimersByTime(250);
    expect(preview.hidden).toBe(true);
    cleanup();
  });

  it("previews with arrow keys and restores when the key is released", () => {
    const { hit, line, preview, cleanup } = setupChart();
    hit.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true, cancelable: true }));
    expect(preview.hidden).toBe(false);
    expect(line.getAttribute("x1")).toBe("132.60");
    expect(preview.textContent).toBe("52nd percentile · 20.4%");

    hit.dispatchEvent(new KeyboardEvent("keyup", { key: "ArrowRight", bubbles: true }));
    expect(preview.hidden).toBe(true);
    expect(line.getAttribute("x1")).toBe("130.00");
    cleanup();
  });
});

function setupChart() {
  document.body.innerHTML = `<div class="distribution-chart-shell">
    <svg class="distribution-chart" data-metric="test" data-low="0" data-high="40" data-original-x="130" data-original-value="20">
      <line class="distribution-marker" x1="130" x2="130"></line>
      <circle class="distribution-dot" cx="130"></circle>
      <rect class="distribution-hit-target" x="101" width="58" tabindex="0"></rect>
    </svg>
    <output class="distribution-preview" hidden></output>
  </div>`;
  const container = document.body.firstElementChild as HTMLElement;
  const chart = container.querySelector("svg")!;
  const hit = container.querySelector("rect")!;
  const line = container.querySelector("line")!;
  const preview = container.querySelector("output")!;
  vi.spyOn(chart, "getBoundingClientRect").mockReturnValue({
    left: 0,
    top: 0,
    width: 260,
    height: 68,
    right: 260,
    bottom: 68,
    x: 0,
    y: 0,
    toJSON: () => ({}),
  });
  Object.defineProperties(hit, {
    setPointerCapture: { configurable: true, value: vi.fn() },
    hasPointerCapture: { configurable: true, value: vi.fn(() => false) },
    releasePointerCapture: { configurable: true, value: vi.fn() },
  });
  const index = { distributions: { test: distribution } } as unknown as SectionReportIndex;
  const cleanup = bindDistributionCharts(container, index);
  return { container, hit, line, preview, cleanup };
}

function pointerEvent(
  type: string,
  properties: Partial<Pick<PointerEvent, "pointerId" | "pointerType" | "clientX" | "clientY" | "button">>,
): Event {
  const event = new Event(type, { bubbles: true, cancelable: true });
  for (const [key, value] of Object.entries({ button: 0, clientY: 0, ...properties })) {
    Object.defineProperty(event, key, { configurable: true, value });
  }
  return event;
}
