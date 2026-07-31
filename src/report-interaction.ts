import { formatValue, ordinal } from "./report";
import type { ReportDistribution, SectionReportIndex } from "./types";

export const DISTRIBUTION_CHART_WIDTH = 260;
const TOUCH_HOLD_MS = 200;
const TOUCH_CANCEL_DISTANCE = 8;
const SNAP_DURATION_MS = 160;

export function clampChartX(value: number): number {
  return Math.max(0, Math.min(DISTRIBUTION_CHART_WIDTH, value));
}

export function chartXFromClientX(clientX: number, left: number, width: number): number {
  if (!Number.isFinite(width) || width <= 0) return 0;
  return clampChartX(((clientX - left) / width) * DISTRIBUTION_CHART_WIDTH);
}

export function valueFromChartX(x: number, low: number, high: number): number {
  return low + (clampChartX(x) / DISTRIBUTION_CHART_WIDTH) * (high - low);
}

export function percentileAtValue(distribution: ReportDistribution, value: number): number {
  const values = distribution.percentileValues;
  const ranks = distribution.percentileRanks;
  if (!values.length || values.length !== ranks.length) return Number.NaN;

  const first = values[0]!;
  const last = values.at(-1)!;
  const tolerance = Math.max(1, Math.abs(value)) * 1e-10;
  if (value < first - tolerance) return 0;
  if (Math.abs(value - first) <= tolerance) return ranks[0]!;
  if (value > last + tolerance) return 100;
  if (Math.abs(value - last) <= tolerance) return ranks.at(-1)!;

  let lowerIndex = 0;
  let upperIndex = values.length - 1;
  while (lowerIndex + 1 < upperIndex) {
    const middle = Math.floor((lowerIndex + upperIndex) / 2);
    if (values[middle]! < value) lowerIndex = middle;
    else upperIndex = middle;
  }

  const lowerValue = values[lowerIndex]!;
  const upperValue = values[upperIndex]!;
  if (Math.abs(value - lowerValue) <= tolerance) return ranks[lowerIndex]!;
  if (Math.abs(value - upperValue) <= tolerance) return ranks[upperIndex]!;
  const progress = (value - lowerValue) / Math.max(Number.EPSILON, upperValue - lowerValue);
  return ranks[lowerIndex]! + progress * (ranks[upperIndex]! - ranks[lowerIndex]!);
}

export function distributionPreviewText(distribution: ReportDistribution, value: number): string {
  const percentile = percentileAtValue(distribution, value);
  const percentileText = Number.isFinite(percentile) ? ordinal(Math.round(percentile)) : "Unknown";
  return `${percentileText} percentile · ${formatValue(value, distribution.format)}`;
}

interface ChartController {
  chart: SVGSVGElement;
  line: SVGLineElement;
  dot: SVGCircleElement;
  hit: SVGRectElement;
  preview: HTMLOutputElement;
  distribution: ReportDistribution;
  low: number;
  high: number;
  originalX: number;
  originalValue: number;
  currentX: number;
  active: boolean;
  pointerId: number | null;
  pointerType: string;
  startClientX: number;
  startClientY: number;
  holdTimer: number | undefined;
  animationFrame: number | undefined;
}

export function bindDistributionCharts(container: HTMLElement, index: SectionReportIndex): () => void {
  const cleanups: Array<() => void> = [];
  const controllers = Array.from(container.querySelectorAll<SVGSVGElement>(".distribution-chart[data-metric]"))
    .map((chart) => createController(chart, index))
    .filter((controller): controller is ChartController => controller !== null);

  for (const controller of controllers) {
    const on = <K extends keyof SVGElementEventMap>(
      type: K,
      listener: (event: SVGElementEventMap[K]) => void,
    ) => {
      controller.hit.addEventListener(type, listener as EventListener);
      cleanups.push(() => controller.hit.removeEventListener(type, listener as EventListener));
    };

    on("pointerdown", (event) => beginPointerPreview(controller, event));
    on("pointermove", (event) => movePointerPreview(controller, event));
    on("pointerup", (event) => finishPointerPreview(controller, event));
    on("pointercancel", (event) => finishPointerPreview(controller, event));
    on("lostpointercapture", () => {
      if (controller.pointerId === null) return;
      restoreController(controller);
      controller.pointerId = null;
      controller.pointerType = "";
    });
    on("keydown", (event) => handlePreviewKeyDown(controller, event));
    on("keyup", (event) => handlePreviewKeyUp(controller, event));
    on("blur", () => restoreController(controller));
  }

  return () => {
    for (const cleanup of cleanups) cleanup();
    for (const controller of controllers) {
      clearHoldTimer(controller);
      if (controller.animationFrame !== undefined) cancelAnimationFrame(controller.animationFrame);
    }
  };
}

function createController(chart: SVGSVGElement, index: SectionReportIndex): ChartController | null {
  const metric = chart.dataset.metric;
  const line = chart.querySelector<SVGLineElement>(".distribution-marker");
  const dot = chart.querySelector<SVGCircleElement>(".distribution-dot");
  const hit = chart.querySelector<SVGRectElement>(".distribution-hit-target");
  const shell = chart.closest<HTMLElement>(".distribution-chart-shell");
  const preview = shell?.querySelector<HTMLOutputElement>(".distribution-preview");
  const distribution = metric ? index.distributions[metric] : undefined;
  const low = Number(chart.dataset.low);
  const high = Number(chart.dataset.high);
  const originalX = Number(chart.dataset.originalX);
  const originalValue = Number(chart.dataset.originalValue);
  if (!line || !dot || !hit || !preview || !distribution || !Number.isFinite(low) || !Number.isFinite(high) || !Number.isFinite(originalValue)) {
    return null;
  }
  return {
    chart,
    line,
    dot,
    hit,
    preview,
    distribution,
    low,
    high,
    originalX,
    originalValue,
    currentX: originalX,
    active: false,
    pointerId: null,
    pointerType: "",
    startClientX: 0,
    startClientY: 0,
    holdTimer: undefined,
    animationFrame: undefined,
  };
}

function beginPointerPreview(controller: ChartController, event: PointerEvent): void {
  if (event.button !== 0 && event.pointerType === "mouse") return;
  stopSnapAnimation(controller);
  controller.pointerId = event.pointerId;
  controller.pointerType = event.pointerType;
  controller.startClientX = event.clientX;
  controller.startClientY = event.clientY;
  try {
    controller.hit.setPointerCapture(event.pointerId);
  } catch {
    // Pointer capture is an enhancement; document-level pointer routing still works without it.
  }
  if (event.pointerType === "mouse") {
    activateController(controller);
    updateController(controller, controller.originalX, controller.originalValue);
    event.preventDefault();
    return;
  }
  controller.holdTimer = window.setTimeout(() => {
    controller.holdTimer = undefined;
    if (controller.pointerId === event.pointerId) {
      activateController(controller);
      updateController(controller, controller.originalX, controller.originalValue);
    }
  }, TOUCH_HOLD_MS);
}

function movePointerPreview(controller: ChartController, event: PointerEvent): void {
  if (event.pointerId !== controller.pointerId) return;
  if (!controller.active) {
    const distance = Math.hypot(event.clientX - controller.startClientX, event.clientY - controller.startClientY);
    if (distance > TOUCH_CANCEL_DISTANCE) {
      clearHoldTimer(controller);
      releasePointer(controller, event.pointerId);
    }
    return;
  }
  event.preventDefault();
  updateFromDrag(controller, event.clientX);
}

function finishPointerPreview(controller: ChartController, event: PointerEvent): void {
  if (event.pointerId !== controller.pointerId) return;
  clearHoldTimer(controller);
  restoreController(controller);
  releasePointer(controller, event.pointerId);
}

function releasePointer(controller: ChartController, pointerId: number): void {
  controller.pointerId = null;
  controller.pointerType = "";
  try {
    if (controller.hit.hasPointerCapture(pointerId)) controller.hit.releasePointerCapture(pointerId);
  } catch {
    // The browser may already have released capture after a pointer cancellation.
  }
}

function handlePreviewKeyDown(controller: ChartController, event: KeyboardEvent): void {
  if (event.key === "Escape") {
    event.preventDefault();
    restoreController(controller);
    return;
  }
  if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
  event.preventDefault();
  stopSnapAnimation(controller);
  activateController(controller);
  const step = DISTRIBUTION_CHART_WIDTH * (event.shiftKey ? 0.05 : 0.01);
  const nextX = event.key === "Home"
    ? 0
    : event.key === "End"
      ? DISTRIBUTION_CHART_WIDTH
      : controller.currentX + (event.key === "ArrowLeft" ? -step : step);
  updateController(controller, clampChartX(nextX));
}

function handlePreviewKeyUp(controller: ChartController, event: KeyboardEvent): void {
  if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
  restoreController(controller);
}

function activateController(controller: ChartController): void {
  controller.active = true;
  controller.chart.classList.add("is-exploring");
  controller.preview.hidden = false;
}

function updateFromDrag(controller: ChartController, clientX: number): void {
  const bounds = controller.chart.getBoundingClientRect();
  const delta = bounds.width > 0
    ? ((clientX - controller.startClientX) / bounds.width) * DISTRIBUTION_CHART_WIDTH
    : 0;
  updateController(controller, clampChartX(controller.originalX + delta));
}

function updateController(controller: ChartController, x: number, exactValue?: number): void {
  controller.currentX = x;
  setMarkerX(controller, x);
  const value = exactValue ?? valueFromChartX(x, controller.low, controller.high);
  const previewText = distributionPreviewText(controller.distribution, value);
  controller.preview.textContent = previewText;
  controller.preview.style.left = `${(Math.max(23, Math.min(237, x)) / DISTRIBUTION_CHART_WIDTH) * 100}%`;
  controller.hit.setAttribute("aria-valuenow", String(value));
  controller.hit.setAttribute("aria-valuetext", previewText);
}

function setMarkerX(controller: ChartController, x: number): void {
  const coordinate = x.toFixed(2);
  controller.line.setAttribute("x1", coordinate);
  controller.line.setAttribute("x2", coordinate);
  controller.dot.setAttribute("cx", coordinate);
  controller.hit.setAttribute("x", (x - 29).toFixed(2));
}

function restoreController(controller: ChartController): void {
  clearHoldTimer(controller);
  controller.active = false;
  controller.chart.classList.remove("is-exploring");
  controller.preview.hidden = true;
  const startX = controller.currentX;
  const reduceMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
  if (reduceMotion || Math.abs(startX - controller.originalX) < 0.1) {
    setOriginalMarker(controller);
    return;
  }
  stopSnapAnimation(controller);
  const startedAt = performance.now();
  controller.chart.classList.add("is-snapping");
  const frame = (time: number) => {
    const progress = Math.min(1, (time - startedAt) / SNAP_DURATION_MS);
    const eased = 1 - Math.pow(1 - progress, 3);
    const x = startX + (controller.originalX - startX) * eased;
    controller.currentX = x;
    setMarkerX(controller, x);
    if (progress < 1) controller.animationFrame = requestAnimationFrame(frame);
    else {
      controller.animationFrame = undefined;
      controller.chart.classList.remove("is-snapping");
      setOriginalMarker(controller);
    }
  };
  controller.animationFrame = requestAnimationFrame(frame);
}

function setOriginalMarker(controller: ChartController): void {
  controller.currentX = controller.originalX;
  setMarkerX(controller, controller.originalX);
  const value = controller.originalValue;
  controller.hit.setAttribute("aria-valuenow", String(value));
  controller.hit.setAttribute("aria-valuetext", distributionPreviewText(controller.distribution, value));
}

function stopSnapAnimation(controller: ChartController): void {
  if (controller.animationFrame !== undefined) {
    cancelAnimationFrame(controller.animationFrame);
    controller.animationFrame = undefined;
  }
  controller.chart.classList.remove("is-snapping");
}

function clearHoldTimer(controller: ChartController): void {
  if (controller.holdTimer !== undefined) {
    window.clearTimeout(controller.holdTimer);
    controller.holdTimer = undefined;
  }
}
