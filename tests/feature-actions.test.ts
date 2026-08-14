import { describe, expect, it } from "vitest";
import { renderFeatureActions } from "../src/feature-actions";

describe("atlas feature-card actions", () => {
  it("places the analysis action to the right of the report for Population sections", () => {
    const html = renderFeatureActions("population", true);
    expect(html).toContain("feature-actions--analysis");
    expect(html).toContain("See full report");
    expect(html).toContain("Housing and migration analysis");
    expect(html.indexOf("See full report")).toBeLessThan(html.indexOf("Housing and migration analysis"));
  });

  it("shows the analysis action under Buildings feature cards", () => {
    const html = renderFeatureActions("buildings", false);
    expect(html).toContain('href="/madrid/housing-migration/"');
    expect(html).toContain("Housing and migration analysis");
    expect(html).not.toContain("See full report");
  });

  it("does not add the analysis action to other themes", () => {
    expect(renderFeatureActions("income", true)).toContain("See full report");
    expect(renderFeatureActions("income", true)).not.toContain("Housing and migration analysis");
    expect(renderFeatureActions("transport", false)).toBe("");
  });

  it("preserves the election section actions", () => {
    const html = renderFeatureActions("elections", true);
    expect(html).toContain("See full report");
    expect(html).toContain("Back to Madrid results");
  });
});
