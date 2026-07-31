import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { bytesToHeader } from "pmtiles";
import { describe, expect, it } from "vitest";
import type { LayerManifest, SectionReportIndex } from "../src/types";

const projectRoot = resolve(import.meta.dirname, "..");
const readJson = <T>(path: string): T =>
  JSON.parse(readFileSync(resolve(projectRoot, path), "utf8")) as T;

describe("published atlas data", () => {
  it("declares PMTiles zooms that match every archive header", () => {
    const manifest = readJson<LayerManifest>("public/data/layer-manifest.json");
    for (const source of manifest.sources) {
      const archive = readFileSync(resolve(projectRoot, "public", source.url));
      const headerBytes = archive.buffer.slice(
        archive.byteOffset,
        archive.byteOffset + 127,
      ) as ArrayBuffer;
      const header = bytesToHeader(headerBytes);
      expect(source.minzoom, source.id).toBe(header.minZoom);
      expect(source.maxzoom, source.id).toBe(header.maxZoom);
    }
  });

  it("publishes complete canonical section reports", () => {
    const reports = readJson<SectionReportIndex>("public/data/section-reports.json");
    const sectionEntries = Object.entries(reports.sections);
    expect(reports.canonicalVintage).toBe("2026");
    expect(sectionEntries).toHaveLength(2462);
    for (const [id, report] of sectionEntries) {
      expect(report.id).toBe(id);
      expect(report.matches["2023"].sectionId).toMatch(/^28079\d{5}$/);
      expect(report.matches["2025"].sectionId).toMatch(/^28079\d{5}$/);
    }
    const sectionBuildingTotal = sectionEntries.reduce(
      (total, [, report]) => total + report.buildings.buildingCount,
      0,
    );
    expect(sectionBuildingTotal).toBe(reports.cityBuildings.buildingCount);
  });

  it("preserves known income suppression without hiding other measures", () => {
    const reports = readJson<SectionReportIndex>("public/data/section-reports.json");
    const carabanchel = Object.values(reports.sections).filter(
      (report) => report.district === "Carabanchel",
    );
    expect(carabanchel).toHaveLength(182);
    for (const report of carabanchel) {
      expect(report.income.below_60_median_pct!.value).toBeNull();
      expect(report.income.above_200_median_pct!.value).toBeNull();
      expect(report.income.income_per_person_eur!.value).not.toBeNull();
      expect(report.income.gini!.value).not.toBeNull();
      expect(report.income.income_p80_p20!.value).not.toBeNull();
    }
  });

  it("puts Results/Leading party first for each election", () => {
    const manifest = readJson<LayerManifest>("public/data/layer-manifest.json");
    for (const election of ["general", "local", "assembly"] as const) {
      const first = manifest.layers.find(
        (layer) => layer.group === "elections" && layer.control?.election === election,
      );
      expect(first?.control?.party).toBe("leading");
    }
  });
});
