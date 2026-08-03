import type { AtlasState, CameraState, LayerGroup } from "./types";

export const MADRID_CAMERA: CameraState = {
  lng: -3.7038,
  lat: 40.4168,
  zoom: 10.65,
  bearing: 0,
  pitch: 0,
};

export const DEFAULT_STATE: AtlasState = {
  group: "population",
  layer: "population-density",
  dataLayerVisible: true,
  election: "general",
  party: "leading",
  transport: [],
  route: "all",
  country: "total",
  camera: { ...MADRID_CAMERA },
  is3d: false,
  selectedSection: null,
  reportOpen: false,
};

const groups: LayerGroup[] = ["population", "education-work", "buildings", "elections", "income", "transport"];
const elections = ["general", "local", "assembly"] as const;
const countries = [
  "total", "venezuela", "colombia", "peru", "ecuador", "republica_dominicana",
  "argentina", "china", "marruecos",
] as const;

const finiteNumber = (value: string | null, fallback: number): number => {
  if (value === null || value.trim() === "") return fallback;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
};

const bounded = (value: number, min: number, max: number): number =>
  Math.min(max, Math.max(min, value));

export function parseHash(hash: string): AtlasState {
  const params = new URLSearchParams(hash.replace(/^#/, ""));
  const rawGroup = params.get("group");
  const rawElection = params.get("election");
  const group = groups.includes(rawGroup as LayerGroup)
    ? (rawGroup as LayerGroup)
    : DEFAULT_STATE.group;
  const election = elections.includes(rawElection as (typeof elections)[number])
    ? (rawElection as AtlasState["election"])
    : DEFAULT_STATE.election;
  const rawSection = params.get("section");
  const selectedSection = rawSection && /^28079[0-9]{5}$/.test(rawSection) ? rawSection : null;

  return {
    group,
    layer: params.get("layer") || DEFAULT_STATE.layer,
    dataLayerVisible: params.get("data") !== "0",
    election,
    party: params.get("party") || DEFAULT_STATE.party,
    transport: (params.get("transport") || "")
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean),
    route: params.get("route") || DEFAULT_STATE.route,
    country: countries.includes(params.get("country") as (typeof countries)[number])
      ? (params.get("country") as string)
      : DEFAULT_STATE.country,
    camera: {
      lng: bounded(finiteNumber(params.get("lng"), DEFAULT_STATE.camera.lng), -180, 180),
      lat: bounded(finiteNumber(params.get("lat"), DEFAULT_STATE.camera.lat), -85, 85),
      zoom: bounded(finiteNumber(params.get("z"), DEFAULT_STATE.camera.zoom), 0, 24),
      bearing: bounded(finiteNumber(params.get("bearing"), 0), -180, 180),
      pitch: bounded(finiteNumber(params.get("pitch"), 0), 0, 85),
    },
    is3d: params.get("3d") === "1",
    selectedSection,
    reportOpen: selectedSection !== null && params.get("report") === "1",
  };
}

const round = (value: number, digits: number): string => value.toFixed(digits);

export function serializeState(state: AtlasState): string {
  const params = new URLSearchParams();
  params.set("group", state.group);
  params.set("layer", state.layer);
  if (!state.dataLayerVisible) params.set("data", "0");
  if (state.group === "elections") {
    params.set("election", state.election);
    params.set("party", state.party);
  }
  if (state.transport.length > 0) params.set("transport", state.transport.join(","));
  if (state.route !== "all") params.set("route", state.route);
  if (state.country !== "total") params.set("country", state.country);
  params.set("lng", round(state.camera.lng, 5));
  params.set("lat", round(state.camera.lat, 5));
  params.set("z", round(state.camera.zoom, 2));
  if (Math.abs(state.camera.bearing) > 0.05) params.set("bearing", round(state.camera.bearing, 1));
  if (state.camera.pitch > 0.05) params.set("pitch", round(state.camera.pitch, 1));
  if (state.is3d) params.set("3d", "1");
  if (state.selectedSection) {
    params.set("section", state.selectedSection);
    if (state.reportOpen) params.set("report", "1");
  }
  return `#${params.toString()}`;
}
