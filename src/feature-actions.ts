import type { LayerGroup } from "./types";

export function renderFeatureActions(group: LayerGroup, isSection: boolean): string {
  const actions: string[] = [];
  if (isSection) {
    actions.push('<button class="open-section-report report-link-button" type="button">See full report</button>');
  }
  if ((group === "population" && isSection) || group === "buildings") {
    actions.push('<a class="housing-analysis-button report-link-button" href="/madrid/housing-migration/">Housing and migration analysis</a>');
  }
  if (group === "elections" && isSection) {
    actions.push('<button class="back-to-madrid quiet-link-button" type="button">Back to Madrid results</button>');
  }
  if (!actions.length) return "";
  const analysisClass = actions.length > 1 && group === "population"
    ? " feature-actions--analysis"
    : "";
  return `<div class="feature-actions${analysisClass}">${actions.join("")}</div>`;
}
