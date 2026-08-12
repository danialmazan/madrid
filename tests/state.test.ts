import { describe, expect, it } from "vitest";
import { DEFAULT_STATE, parseHash, serializeState } from "../src/state";

describe("URL state", () => {
  it("round-trips an election view", () => {
    const state = {
      ...DEFAULT_STATE,
      group: "elections" as const,
      layer: "election-general-PSOE",
      election: "general" as const,
      party: "PSOE",
      transport: ["metro", "cercanias"],
      is3d: true,
      camera: { lng: -3.7, lat: 40.42, zoom: 12.34, bearing: 3, pitch: 46 },
    };
    expect(parseHash(serializeState(state))).toEqual(state);
  });

  it("bounds unsafe camera values", () => {
    const state = parseHash("#lng=999&lat=-999&z=99&pitch=100");
    expect(state.camera).toMatchObject({ lng: 180, lat: -85, zoom: 24, pitch: 85 });
  });

  it("falls back when enums are invalid", () => {
    const state = parseHash("#group=unknown&election=old&country=not-real");
    expect(state.group).toBe(DEFAULT_STATE.group);
    expect(state.election).toBe(DEFAULT_STATE.election);
    expect(state.country).toBe("total");
  });

  it("round-trips a migration country selection", () => {
    const state = {
      ...DEFAULT_STATE,
      layer: "population-foreign-born-change",
      country: "colombia",
    };
    const hash = serializeState(state);
    expect(hash).toContain("country=colombia");
    expect(parseHash(hash)).toEqual(state);
  });

  it("round-trips the dark background map", () => {
    const state = { ...DEFAULT_STATE, basemap: "dark" as const };
    expect(serializeState(state)).toContain("basemap=dark");
    expect(parseHash(serializeState(state))).toEqual(state);
  });

  it("drops migration country state outside the Population theme", () => {
    const state = {
      ...DEFAULT_STATE,
      group: "income" as const,
      layer: "income-per-person",
      country: "ecuador",
    };
    const hash = serializeState(state);
    expect(hash).not.toContain("country=");
    expect(parseHash("#group=income&layer=income-per-person&country=ecuador").country).toBe("total");
  });

  it("persists a transport-only view without a thematic layer", () => {
    const state = {
      ...DEFAULT_STATE,
      group: "transport" as const,
      dataLayerVisible: false,
      transport: ["metro"],
    };
    expect(parseHash(serializeState(state))).toEqual(state);
  });

  it("round-trips a canonical section and open report", () => {
    const state = {
      ...DEFAULT_STATE,
      group: "income" as const,
      layer: "income-per-person",
      selectedSection: "2807911001",
      reportOpen: true,
    };
    const hash = serializeState(state);
    expect(hash).toBe(
      "#group=income&layer=income-per-person&lng=-3.70380&lat=40.41680&z=10.65&section=2807911001&report=1",
    );
    expect(parseHash(hash)).toEqual(state);
  });

  it("rejects invalid section identifiers and orphan report state", () => {
    const state = parseHash("#section=not-a-section&report=1");
    expect(state.selectedSection).toBeNull();
    expect(state.reportOpen).toBe(false);
  });
});
