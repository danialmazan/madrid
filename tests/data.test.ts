import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { bytesToHeader } from "pmtiles";
import { describe, expect, it } from "vitest";
import { percentileAtValue } from "../src/report-interaction";
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

  it("publishes equal-width histograms that reconcile with every percentile", () => {
    const reports = readJson<SectionReportIndex>("public/data/section-reports.json");
    for (const [metric, distribution] of Object.entries(reports.distributions)) {
      expect(distribution.counts.length, metric).toBeGreaterThanOrEqual(10);
      expect(distribution.breaks, metric).toHaveLength(distribution.counts.length + 1);
      expect(distribution.counts.reduce((total, count) => total + count, 0), metric).toBe(
        distribution.observationCount,
      );
      const widths = distribution.breaks.slice(1).map((edge, index) => edge - distribution.breaks[index]!);
      const firstWidth = widths[0]!;
      expect(widths.every((width) => Math.abs(width - firstWidth) < 1e-7), metric).toBe(true);
      expect(distribution.breaks[0]!, metric).toBeLessThanOrEqual(distribution.minimum!);
      expect(distribution.breaks.at(-1)!, metric).toBeGreaterThanOrEqual(distribution.maximum!);
      expect(distribution.percentileValues, metric).toHaveLength(distribution.percentileRanks.length);
      expect(distribution.percentileValues.length, metric).toBeGreaterThan(1);
      expect(
        distribution.percentileValues.every((value, index, values) => index === 0 || value > values[index - 1]!),
        metric,
      ).toBe(true);
      expect(
        distribution.percentileRanks.every((rank, index, ranks) =>
          rank >= 0 && rank <= 100 && (index === 0 || rank >= ranks[index - 1]!),
        ),
        metric,
      ).toBe(true);
    }

    const metricGroups = ["population", "income"] as const;
    const mismatches: string[] = [];
    for (const report of Object.values(reports.sections)) {
      for (const group of metricGroups) {
        for (const [metric, item] of Object.entries(report[group])) {
          if (item.value === null || item.percentile === null) continue;
          const distribution = reports.distributions[metric]!;
          expect(percentileAtValue(distribution, item.value), `${report.id}:${metric}:curve`).toBeCloseTo(
            item.percentile,
            7,
          );
          const bin = distribution.counts.findIndex((_, index) => {
            const upper = distribution.breaks[index + 1]!;
            return index === distribution.counts.length - 1 ? item.value! <= upper : item.value! < upper;
          });
          const countBefore = distribution.counts
            .slice(0, bin)
            .reduce((total, count) => total + count, 0);
          const zeroBasedRank = (item.percentile / 100) * (distribution.observationCount - 1);
          const lastRankInBin = countBefore + distribution.counts[bin]! - 1;
          if (bin < 0 || zeroBasedRank < countBefore - 1e-7 || zeroBasedRank > lastRankInBin + 1e-7) {
            mismatches.push(`${report.id}:${metric}`);
          }
        }
      }
    }
    expect(mismatches).toEqual([]);
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
