import { describe, expect, it } from "vitest";
import {
  DEFAULT_ANALYSIS_STATE,
  parseAnalysisState,
  serialiseAnalysisState,
  toggleDistrict,
} from "../src/housing-migration-state";

const codes = new Set(Array.from({ length: 21 }, (_, index) => String(index + 1).padStart(2, "0")));

describe("housing analysis state", () => {
  it("defaults to Carabanchel and current-share outcomes", () => {
    expect(parseAnalysisState("", codes)).toEqual(DEFAULT_ANALYSIS_STATE);
  });

  it("round-trips district and outcome selections through the URL", () => {
    const state = { districtCodes: ["11", "10", "13"], sectionOutcome: "change" as const, districtOutcome: "change" as const };
    expect(parseAnalysisState(serialiseAnalysisState(state), codes)).toEqual(state);
  });

  it("rejects unknown, duplicate and fourth district values", () => {
    expect(parseAnalysisState("#districts=11,99,10,11,13,14", codes).districtCodes).toEqual(["11", "10", "13"]);
    expect(toggleDistrict(["11", "10", "13"], "14")).toEqual(["11", "10", "13"]);
  });

  it("does not allow the final selected district to be removed", () => {
    expect(toggleDistrict(["11"], "11")).toEqual(["11"]);
  });
});
