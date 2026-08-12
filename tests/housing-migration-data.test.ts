import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import type { HousingMigrationAnalysis } from "../src/housing-migration-types";

const data = JSON.parse(
  readFileSync(resolve(import.meta.dirname, "../public/data/housing-migration-analysis.json"), "utf8"),
) as HousingMigrationAnalysis;

describe("housing and migration analysis payload", () => {
  it("covers all districts and canonical current sections", () => {
    expect(data.version).toBe("1.0.0");
    expect(data.districts).toHaveLength(21);
    expect(data.sections).toHaveLength(2462);
    expect(new Set(data.districts.map((district) => district.code)).size).toBe(21);
    expect(new Set(data.sections.map((section) => section.id)).size).toBe(2462);
    expect(data.defaultDistrictCode).toBe("11");
  });

  it("preserves weights, quantile order and missing boundary comparisons", () => {
    expect(data.coverage.recordedDwellings).toBe(1_523_106);
    expect(data.coverage.sectionsWithPositiveDwellingWeight).toBe(2461);
    expect(data.coverage.sectionsWithForeignBorn2025).toBe(2462);
    expect(data.sections.filter((section) => section.foreignBornChangePp === null)).toHaveLength(130);
    for (const section of data.sections) {
      expect(section.residentialBuildingCount).toBeGreaterThanOrEqual(0);
      expect(section.dwellingCount).toBeGreaterThanOrEqual(0);
      const values = Object.values(section.constructionYear).filter((value): value is number => value !== null);
      expect(values.length === 0 || values.length === 5).toBe(true);
      expect(values.every((value, index) => index === 0 || value >= values[index - 1]!)).toBe(true);
    }
  });

  it("publishes complete district distributions and reconciles the hypothesis measure", () => {
    for (const district of data.districts) {
      const buildingTotal = district.distribution.reduce((total, cohort) => total + cohort.buildingSharePct, 0);
      const dwellingTotal = district.distribution.reduce((total, cohort) => total + cohort.dwellingSharePct, 0);
      expect(buildingTotal, district.name).toBeCloseTo(100, 7);
      expect(dwellingTotal, district.name).toBeCloseTo(100, 7);
      const sixties = district.distribution
        .filter((cohort) => cohort.startYear === 1961 || cohort.startYear === 1966)
        .reduce((total, cohort) => total + cohort.dwellingSharePct, 0);
      expect(sixties, district.name).toBeCloseTo(district.shareDwellings1961To1970Pct, 7);
    }
  });

  it("aggregates robust district-level INE values directly", () => {
    const carabanchel = data.districts.find((district) => district.code === "11")!;
    expect(carabanchel.foreignBorn).toMatchObject({
      count2021: 81245,
      count2025: 107136,
      countChange: 25891,
    });
    expect(carabanchel.foreignBorn.shareChangePp).toBeCloseTo(6.9460064318, 8);
    expect(carabanchel.shareDwellings1961To1970Pct).toBeCloseTo(33.400837046, 8);
  });
});
