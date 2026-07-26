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
    const state = parseHash("#group=unknown&election=old");
    expect(state.group).toBe(DEFAULT_STATE.group);
    expect(state.election).toBe(DEFAULT_STATE.election);
  });
});
