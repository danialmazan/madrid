import maplibregl, {
  type ExpressionSpecification,
  type MapGeoJSONFeature,
  type MapMouseEvent,
  type Map as MapLibreMap,
} from "maplibre-gl";
import { Protocol } from "pmtiles";
import "./styles.css";
import { MADRID_CAMERA, parseHash, serializeState } from "./state";
import { renderMadridElectionCard, renderSectionReport, sectionProperties } from "./report";
import { bindDistributionCharts } from "./report-interaction";
import { shareOrCopy } from "./share";
import type {
  AddressIndex,
  AddressRecord,
  AtlasState,
  LayerDefinition,
  LayerGroup,
  LayerManifest,
  Place,
  SectionReportIndex,
  ValueFormat,
} from "./types";

const BASE_URL = import.meta.env.BASE_URL;
const manifestUrl = `${BASE_URL}data/layer-manifest.json`;
const placesUrl = `${BASE_URL}data/places.json`;
const addressesUrl = `${BASE_URL}data/addresses.json`;
const sectionReportsUrl = `${BASE_URL}data/section-reports.json`;
const SECTION_HIT_LAYER = "atlas-current-section-hit";
const SECTION_OUTLINE_LAYER = "atlas-current-section-outline";

const panel = requireElement<HTMLElement>(".atlas-panel");
const controls = requireElement<HTMLElement>("#layer-controls");
const legend = requireElement<HTMLElement>("#legend");
const legendPanel = requireElement<HTMLElement>(".legend-panel");
const legendTitle = requireElement<HTMLElement>("#legend-title");
const legendDate = requireElement<HTMLElement>("#legend-date");
const featurePanel = requireElement<HTMLElement>("#feature-panel");
const status = requireElement<HTMLElement>("#map-status");
const searchInput = requireElement<HTMLInputElement>("#place-search");
const searchResults = requireElement<HTMLElement>("#search-results");
const basemapButton = requireElement<HTMLButtonElement>("#basemap-button");
const pitchButton = requireElement<HTMLButtonElement>("#pitch-button");
const resetButton = requireElement<HTMLButtonElement>("#reset-button");
const shareButton = requireElement<HTMLButtonElement>("#share-button");
const sheetToggle = requireElement<HTMLButtonElement>("#sheet-toggle");
const sheetToggleLabel = requireElement<HTMLElement>("#sheet-toggle-label");
const sheetClose = requireElement<HTMLButtonElement>("#sheet-close");
const mobileSheetTitle = requireElement<HTMLElement>("#mobile-sheet-title");
const mobileLayersButton = requireElement<HTMLButtonElement>("#mobile-layers-button");
const mobileLegendButton = requireElement<HTMLButtonElement>("#mobile-legend-button");
const mobileInfoButton = requireElement<HTMLButtonElement>("#mobile-info-button");
const infoStatusText = requireElement<HTMLElement>("#info-status-text");
const aboutDialog = requireElement<HTMLDialogElement>("#about-dialog");
const methodologyContent = requireElement<HTMLElement>("#methodology-content");
const shareDialog = requireElement<HTMLDialogElement>("#share-dialog");
const shareDialogTitle = requireElement<HTMLElement>("#share-dialog-title");
const shareViewAction = requireElement<HTMLButtonElement>("#share-view-action");
const shareReportAction = requireElement<HTMLButtonElement>("#share-report-action");
const reportDialog = requireElement<HTMLDialogElement>("#report-dialog");
const reportDialogTitle = requireElement<HTMLElement>("#report-dialog-title");
const reportContent = requireElement<HTMLElement>("#report-content");
const toast = requireElement<HTMLElement>("#toast");

let atlasState: AtlasState = parseHash(window.location.hash);
let manifest: LayerManifest;
let map: MapLibreMap;
let places: Place[] = [];
let addresses: AddressRecord[] = [];
let addressSearchText: string[] = [];
let addressLoadPromise: Promise<void> | undefined;
let sectionReportIndex: SectionReportIndex | undefined;
let sectionReportLoadPromise: Promise<SectionReportIndex> | undefined;
let searchMarker: maplibregl.Marker | undefined;
let activeMapLayerIds: string[] = [];
let hashTimer: number | undefined;
let toastTimer: number | undefined;
let currentFeatureTitle = "";
let reportChartCleanup: (() => void) | undefined;
let titleBeforePrint: string | undefined;

type MobilePanelView = "layers" | "legend" | "details" | "info";

void initialise();

async function initialise(): Promise<void> {
  bindStaticControls();
  setStatus("Loading layer catalogue…");

  try {
    [manifest, places] = await Promise.all([
      fetchJson<LayerManifest>(manifestUrl),
      fetchJson<Place[]>(placesUrl).catch(() => []),
    ]);
    normaliseInitialState();
    renderMethodology();
    renderGroupTabs();
    renderControls();
    renderLegend();
    void renderFeaturePanelForState().then(() => {
      if (atlasState.reportOpen) void openSelectedSectionReport(false);
    });
    createMap();
  } catch (error) {
    console.error(error);
    setStatus("The atlas catalogue could not be loaded.", true);
    controls.innerHTML = `
      <p class="feature-empty">
        Data files are unavailable. Run the reproducible data pipeline and reload this page.
      </p>`;
  }
}

function requireElement<T extends Element>(selector: string): T {
  const element = document.querySelector<T>(selector);
  if (!element) throw new Error(`Missing required element: ${selector}`);
  return element;
}

async function fetchJson<T>(url: string): Promise<T> {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
  return (await response.json()) as T;
}

function normaliseInitialState(): void {
  if (atlasState.group !== "population") atlasState.country = "total";
  const selected = manifest.layers.find((layer) => layer.id === atlasState.layer);
  if (!selected || selected.group === "transport") {
    atlasState.layer = manifest.defaultLayer;
  }
  const selectedLayer = getSelectedLayer();
  if (atlasState.group !== "transport" && selectedLayer.group !== atlasState.group) {
    const fallback = manifest.layers.find(
      (layer) => layer.group === atlasState.group && layer.group !== "transport",
    );
    if (fallback) atlasState.layer = fallback.id;
  }
  const normalisedLayer = getSelectedLayer();
  if (
    normalisedLayer.group !== "transport" &&
    normalisedLayer.minzoom !== undefined &&
    atlasState.camera.zoom < normalisedLayer.minzoom
  ) {
    atlasState.camera.zoom = normalisedLayer.minzoom;
  }
}

function bindStaticControls(): void {
  syncBasemapButton();
  document.querySelectorAll<HTMLButtonElement>(".group-tab").forEach((button) => {
    button.addEventListener("click", () => {
      const group = button.dataset.group as LayerGroup;
      selectGroup(group);
    });
  });

  pitchButton.addEventListener("click", () => toggle3d());
  basemapButton.addEventListener("click", switchBasemap);
  resetButton.addEventListener("click", () => resetView());
  shareButton.addEventListener("click", openShareDialog);
  sheetToggle.addEventListener("click", () => toggleMobilePanel("details"));
  sheetClose.addEventListener("click", () => setSheetOpen(false));
  mobileLayersButton.addEventListener("click", () => toggleMobilePanel("layers"));
  mobileLegendButton.addEventListener("click", () => toggleMobilePanel("legend"));
  mobileInfoButton.addEventListener("click", () => toggleMobilePanel("info"));
  document.querySelector("#about-button")?.addEventListener("click", openMethodology);
  document.querySelector("#info-methodology-button")?.addEventListener("click", openMethodology);
  document.querySelector("#close-about")?.addEventListener("click", () => aboutDialog.close());
  document.querySelector("#close-share")?.addEventListener("click", () => shareDialog.close());
  document.querySelector("#close-report")?.addEventListener("click", () => reportDialog.close());
  shareViewAction.addEventListener("click", () => void shareCurrentView());
  shareReportAction.addEventListener("click", () => {
    shareDialog.close();
    void openSelectedSectionReport();
  });
  document.querySelector("#copy-report-link")?.addEventListener("click", () => void copyReportLink());
  document.querySelector("#print-report")?.addEventListener("click", () => window.print());
  window.addEventListener("beforeprint", prepareReportPrintTitle);
  window.addEventListener("afterprint", restoreDocumentTitle);
  aboutDialog.addEventListener("click", (event) => {
    if (event.target === aboutDialog) aboutDialog.close();
  });
  shareDialog.addEventListener("click", (event) => {
    if (event.target === shareDialog) shareDialog.close();
  });
  reportDialog.addEventListener("click", (event) => {
    if (event.target === reportDialog) reportDialog.close();
  });
  reportDialog.addEventListener("close", () => {
    reportChartCleanup?.();
    reportChartCleanup = undefined;
    restoreDocumentTitle();
    if (!atlasState.reportOpen) return;
    atlasState.reportOpen = false;
    scheduleHashUpdate(true);
  });
  if (isMobileViewport()) setSheetOpen(false);
  window.addEventListener("resize", syncPanelAccessibility);

  searchInput.addEventListener("input", renderSearchResults);
  searchInput.addEventListener("focus", () => {
    void loadAddressIndex();
  });
  searchInput.addEventListener("keydown", handleSearchKeys);
  document.addEventListener("keydown", (event) => {
    if (
      event.key === "/" &&
      document.activeElement !== searchInput &&
      !(document.activeElement instanceof HTMLInputElement)
    ) {
      event.preventDefault();
      searchInput.focus();
    }
    if (event.key === "Escape") {
      hideSearchResults();
      if (reportDialog.open) reportDialog.close();
      else if (shareDialog.open) shareDialog.close();
      else if (aboutDialog.open) aboutDialog.close();
      setSheetOpen(false);
    }
  });

  window.addEventListener("hashchange", () => {
    const incoming = parseHash(window.location.hash);
    const basemapChanged = incoming.basemap !== atlasState.basemap;
    atlasState = incoming;
    syncBasemapButton();
    normaliseInitialState();
    renderGroupTabs();
    renderControls();
    renderLegend();
    if (map) {
      map.jumpTo({
        center: [atlasState.camera.lng, atlasState.camera.lat],
        zoom: atlasState.camera.zoom,
        bearing: atlasState.camera.bearing,
        pitch: atlasState.camera.pitch,
      });
      if (basemapChanged) reloadBasemap();
      else if (map.isStyleLoaded()) void applyMapLayers();
    }
    void renderFeaturePanelForState();
    if (atlasState.reportOpen) void openSelectedSectionReport(false);
    else if (reportDialog.open) reportDialog.close();
  });
}

function openMethodology(): void {
  setSheetOpen(false);
  aboutDialog.showModal();
}

function createMap(): void {
  const protocol = new Protocol();
  maplibregl.addProtocol("pmtiles", protocol.tile);

  try {
    map = new maplibregl.Map({
      container: "atlas-map",
      style: basemapStyleUrl(),
      center: [atlasState.camera.lng, atlasState.camera.lat],
      zoom: atlasState.camera.zoom,
      bearing: atlasState.camera.bearing,
      pitch: atlasState.is3d ? Math.max(48, atlasState.camera.pitch) : atlasState.camera.pitch,
      minZoom: 8,
      maxZoom: 19,
      hash: false,
      attributionControl: false,
      cooperativeGestures: false,
      fadeDuration: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 300,
    });
  } catch (error) {
    console.error(error);
    setStatus("WebGL is unavailable in this browser.", true);
    return;
  }

  map.addControl(
    new maplibregl.NavigationControl({ visualizePitch: true, showCompass: true }),
    "bottom-right",
  );
  map.addControl(
    new maplibregl.AttributionControl({
      compact: true,
      customAttribution: "Madrid Atlas · Daniel Almazán",
    }),
    "bottom-left",
  );
  map.addControl(new maplibregl.ScaleControl({ unit: "metric", maxWidth: 110 }), "bottom-left");

  map.on("load", () => {
    tuneBasemap();
    addManifestSources();
    addCanonicalSectionHitLayer();
    void applyMapLayers().then(() => void renderFeaturePanelForState());
    setStatus(`Ready · ${manifest.generatedAt.slice(0, 10)}`);
  });
  map.on("moveend", () => {
    const center = map.getCenter();
    atlasState.camera = {
      lng: center.lng,
      lat: center.lat,
      zoom: map.getZoom(),
      bearing: map.getBearing(),
      pitch: map.getPitch(),
    };
    scheduleHashUpdate();
  });
  map.on("click", handleMapClick);
  map.on("mousemove", handleMapHover);
  map.on("error", (event) => {
    console.warn("Map resource error", event.error);
  });
}

function tuneBasemap(): void {
  const dark = atlasState.basemap === "dark";
  const style = map.getStyle();
  for (const layer of style.layers ?? []) {
    const id = layer.id.toLowerCase();
    try {
      if (layer.type === "background") {
        map.setPaintProperty(layer.id, "background-color", dark ? "#0b0f0e" : "#f5f4ef");
      }
      if (layer.type === "fill" && /(park|wood|grass|landcover)/.test(id)) {
        map.setPaintProperty(layer.id, "fill-color", dark ? "#16251f" : "#dfe9df");
        map.setPaintProperty(layer.id, "fill-opacity", 0.7);
      }
      if (layer.type === "fill" && /water/.test(id)) {
        map.setPaintProperty(layer.id, "fill-color", dark ? "#101b21" : "#c8dfe9");
      }
      if (layer.type === "line" && /(road|street|highway)/.test(id)) {
        map.setPaintProperty(layer.id, "line-color", dark ? "#2a2f2d" : "#d8d5cd");
      }
      if (layer.type === "symbol" && /(poi|transit)/.test(id)) {
        map.setLayoutProperty(layer.id, "visibility", "none");
      }
      if (layer.type === "symbol" && /label/.test(id)) {
        map.setPaintProperty(layer.id, "text-color", dark ? "#a8b0ab" : "#52524d");
        map.setPaintProperty(layer.id, "text-halo-color", dark ? "#0b0f0e" : "#fafaf7");
      }
    } catch {
      // OpenFreeMap occasionally changes layer paint capabilities; safe to skip.
    }
  }
}

function basemapStyleUrl(): string {
  return `https://tiles.openfreemap.org/styles/${atlasState.basemap === "dark" ? "dark" : "positron"}`;
}

function syncBasemapButton(): void {
  const dark = atlasState.basemap === "dark";
  basemapButton.setAttribute("aria-pressed", String(dark));
  basemapButton.setAttribute("aria-label", `Switch to ${dark ? "light" : "dark"} background map`);
  const label = basemapButton.querySelector<HTMLElement>(".button-label");
  if (label) label.textContent = dark ? "Light map" : "Dark map";
}

function switchBasemap(): void {
  atlasState.basemap = atlasState.basemap === "dark" ? "light" : "dark";
  syncBasemapButton();
  reloadBasemap();
  scheduleHashUpdate(true);
}

function reloadBasemap(): void {
  setStatus(`Loading ${atlasState.basemap} background map…`);
  map.once("style.load", () => {
    tuneBasemap();
    addManifestSources();
    addCanonicalSectionHitLayer();
    void applyMapLayers().then(() => void renderFeaturePanelForState());
    setStatus(`Ready · ${manifest.generatedAt.slice(0, 10)}`);
  });
  map.setStyle(basemapStyleUrl());
}

function addManifestSources(): void {
  for (const source of manifest.sources) {
    if (map.getSource(source.id)) continue;
    map.addSource(source.id, {
      type: "vector",
      url: `pmtiles://${resolveAssetUrl(source.url)}`,
      attribution: source.attribution,
      minzoom: source.minzoom,
      maxzoom: source.maxzoom,
    });
  }
}

function addCanonicalSectionHitLayer(): void {
  const source = manifest.sources.find((candidate) => candidate.id === "sections-2026");
  if (!source || map.getLayer(SECTION_HIT_LAYER)) return;
  map.addLayer(
    {
      id: SECTION_HIT_LAYER,
      type: "fill",
      source: source.id,
      "source-layer": source.sourceLayer,
      minzoom: 8,
      maxzoom: 24,
      paint: { "fill-color": "#000000", "fill-opacity": 0 },
    },
    firstLabelLayerId(),
  );
}

function resolveAssetUrl(url: string): string {
  if (/^https?:\/\//.test(url)) return url;
  return new URL(url.replace(/^\//, ""), new URL(BASE_URL, window.location.origin)).toString();
}

async function applyMapLayers(): Promise<void> {
  if (!map) return;
  if (map.getLayer(SECTION_OUTLINE_LAYER)) map.removeLayer(SECTION_OUTLINE_LAYER);
  for (const layerId of activeMapLayerIds) {
    if (map.getLayer(layerId)) map.removeLayer(layerId);
  }
  activeMapLayerIds = [];

  if (atlasState.dataLayerVisible) {
    addDefinitionToMap(getSelectedLayer(), false);
  }

  const overlays = manifest.layers.filter(
    (layer) =>
      layer.group === "transport" &&
      layer.control?.transportMode &&
      atlasState.transport.includes(layer.control.transportMode),
  );
  for (const overlay of overlays) addDefinitionToMap(overlay, true);
  addSelectedSectionOutline();
  pitchButton.setAttribute("aria-pressed", String(atlasState.is3d));
}

function addSelectedSectionOutline(): void {
  if (!map || !atlasState.selectedSection) return;
  const source = manifest.sources.find((candidate) => candidate.id === "sections-2026");
  if (!source) return;
  map.addLayer(
    {
      id: SECTION_OUTLINE_LAYER,
      type: "line",
      source: source.id,
      "source-layer": source.sourceLayer,
      minzoom: 8,
      maxzoom: 24,
      filter: ["==", ["get", "section_id"], atlasState.selectedSection],
      paint: {
        "line-color": atlasState.basemap === "dark" ? "#f4f0df" : "#11110f",
        "line-width": ["interpolate", ["linear"], ["zoom"], 8, 2, 16, 4],
        "line-opacity": 0.96,
      },
    },
    firstLabelLayerId(),
  );
}

function addDefinitionToMap(definition: LayerDefinition, overlay: boolean): void {
  for (const [index, sourceId] of definition.sourceIds.entries()) {
    const source = manifest.sources.find((candidate) => candidate.id === sourceId);
    if (!source || !map.getSource(sourceId)) continue;
    const id = `atlas-${definition.id}-${index}`;
    const beforeId = firstLabelLayerId();
    const common = {
      id,
      source: sourceId,
      "source-layer": source.sourceLayer,
      minzoom: definition.minzoom,
      maxzoom: definition.maxzoom,
    };

    if (definition.kind === "transport-line") {
      const filter = routeFilter(definition);
      const lineColor: string | ExpressionSpecification =
        definition.control?.transportMode === "metro"
          ? ["coalesce", ["get", "route_color"], definition.lineColor || "#145c9e"]
          : definition.lineColor || "#145c9e";
      map.addLayer(
        {
          ...common,
          type: "line",
          paint: {
            "line-color": lineColor,
            "line-width": [
              "interpolate",
              ["linear"],
              ["zoom"],
              8,
              Math.max(0.7, definition.lineWidth ?? 1.5),
              14,
              Math.max(2.2, (definition.lineWidth ?? 1.5) * 2),
            ],
            "line-opacity": definition.opacity ?? 0.88,
          },
          layout: {
            "line-join": "round",
            "line-cap": "round",
          },
          ...(filter ? { filter } : {}),
        },
        beforeId,
      );
    } else if (definition.kind === "transport-stop") {
      const filter = routeFilter(definition);
      map.addLayer(
        {
          ...common,
          type: "circle",
          paint: {
            "circle-radius": ["interpolate", ["linear"], ["zoom"], 11, 2, 15, 5],
            "circle-color": definition.lineColor || "#ffffff",
            "circle-stroke-color": "#161613",
            "circle-stroke-width": 1,
            "circle-opacity": definition.opacity ?? 0.96,
          },
          ...(filter ? { filter } : {}),
        },
        beforeId,
      );
    } else if (
      definition.kind === "fill-extrusion" &&
      atlasState.is3d &&
      definition.property === "height_m"
    ) {
      map.addLayer(
        {
          ...common,
          type: "fill-extrusion",
          paint: {
            "fill-extrusion-color": colorExpression(definition),
            "fill-extrusion-height": [
              "case",
              ["has", definition.property],
              ["max", 0, ["to-number", ["get", definition.property]]],
              0,
            ],
            "fill-extrusion-base": 0,
            "fill-extrusion-opacity": 0.88,
          },
        },
        beforeId,
      );
    } else {
      map.addLayer(
        {
          ...common,
          type: "fill",
          paint: {
            "fill-color": colorExpression(definition),
            "fill-opacity": definition.opacity ?? (overlay ? 0.72 : 0.77),
            "fill-outline-color": "rgba(255,255,255,0.42)",
          },
        },
        beforeId,
      );
    }
    activeMapLayerIds.push(id);
  }
}

function routeFilter(definition: LayerDefinition): ExpressionSpecification | undefined {
  if (
    definition.control?.transportMode !== "emt" ||
    !atlasState.route ||
    atlasState.route === "all"
  ) {
    return undefined;
  }
  return ["==", ["to-string", ["get", definition.control.routeProperty || "route_short_name"]], atlasState.route];
}

function firstLabelLayerId(): string | undefined {
  return map.getStyle().layers?.find((layer) => layer.type === "symbol")?.id;
}

function colorExpression(definition: LayerDefinition): ExpressionSpecification {
  if (definition.format === "text") {
    const matches: unknown[] = ["match", ["get", definition.property]];
    for (let index = 0; index < definition.palette.length; index += 2) {
      const category = definition.palette[index];
      const color = definition.palette[index + 1];
      if (category && color) matches.push(category, color);
    }
    matches.push("#d3d3cc");
    return matches as ExpressionSpecification;
  }

  if (definition.scale?.type === "continuous-diverging") {
    return [
      "case",
      ["!", ["has", definition.property]],
      "#d3d3cc",
      [
        "interpolate",
        ["linear"],
        ["to-number", ["get", definition.property]],
        definition.breaks[0] ?? -1,
        definition.palette[0] ?? "#b2182b",
        definition.scale.center,
        definition.palette[1] ?? "#ffffff",
        definition.breaks.at(-1) ?? 1,
        definition.palette[2] ?? "#2166ac",
      ],
    ] as ExpressionSpecification;
  }

  const palette = definition.palette;
  const steps: unknown[] = [
    "case",
    ["!", ["has", definition.property]],
    "#d3d3cc",
    [
      "step",
      ["to-number", ["get", definition.property]],
      palette[0] ?? "#d3d3cc",
    ],
  ];
  const inner = steps[3] as unknown[];
  for (let index = 1; index < palette.length; index += 1) {
    const threshold = definition.breaks[index];
    if (threshold !== undefined) inner.push(threshold, palette[index]);
  }
  return steps as ExpressionSpecification;
}

function selectGroup(group: LayerGroup): void {
  atlasState.group = group;
  if (group !== "population") atlasState.country = "total";
  if (group !== "transport" && getSelectedLayer().group !== group) {
    const first = manifest.layers.find((layer) => layer.group === group);
    if (first) atlasState.layer = first.id;
  }
  if (group !== "transport") atlasState.dataLayerVisible = true;
  if (!isCensusSectionLayer(getSelectedLayer())) clearSelectedSection(false);
  renderGroupTabs();
  renderControls();
  renderLegend();
  if (map) {
    zoomToLayerMinimum(getSelectedLayer());
    void applyMapLayers().then(() => void renderFeaturePanelForState());
  } else {
    void renderFeaturePanelForState();
  }
  if (isMobileViewport()) setMobilePanel(true, "layers");
  scheduleHashUpdate();
}

function selectLayer(layerId: string): void {
  const layer = manifest.layers.find((candidate) => candidate.id === layerId);
  if (!layer || layer.group === "transport") return;
  atlasState.layer = layer.id;
  atlasState.dataLayerVisible = true;
  atlasState.group = layer.group;
  if (layer.group !== "population") atlasState.country = "total";
  if (layer.control?.election) atlasState.election = layer.control.election;
  if (layer.control?.party) atlasState.party = layer.control.party;
  if (!isCensusSectionLayer(layer)) clearSelectedSection(false);
  renderGroupTabs();
  renderControls();
  renderLegend();
  if (map) {
    zoomToLayerMinimum(layer);
    void applyMapLayers().then(() => void renderFeaturePanelForState());
  } else {
    void renderFeaturePanelForState();
  }
  if (isMobileViewport()) setSheetOpen(false);
  scheduleHashUpdate();
}

function renderGroupTabs(): void {
  document.querySelectorAll<HTMLButtonElement>(".group-tab").forEach((button) => {
    const active = button.dataset.group === atlasState.group;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-current", active ? "page" : "false");
  });
  updateDetailsToggleLabel();
}

function renderControls(): void {
  if (atlasState.group === "transport") {
    renderTransportControls();
    return;
  }
  if (atlasState.group === "elections") {
    renderElectionControls();
    return;
  }

  const layers = manifest.layers.filter((layer) => layer.group === atlasState.group);
  const selectedLayer = getSelectedLayer();
  const countryControl = selectedLayer.control?.country;
  controls.innerHTML = `
    <div class="radio-grid" role="radiogroup" aria-label="${escapeHtml(groupLabel(atlasState.group))} layers">
      ${layers
        .map(
          (layer) => `
            <label class="layer-choice">
              <input type="radio" name="thematic-layer" value="${escapeHtml(layer.id)}"
                ${layer.id === atlasState.layer ? "checked" : ""} />
              <span class="choice-label">${escapeHtml(layer.shortLabel || layer.label)}</span>
            </label>`,
        )
        .join("")}
    </div>
    ${countryControl ? `
      <label class="select-label">
        Country
        <select id="country-select" class="atlas-select">
          ${countryControl.options.map((option) => `
            <option value="${escapeHtml(option.value)}" ${option.value === atlasState.country ? "selected" : ""}>
              ${escapeHtml(option.label)}
            </option>`).join("")}
        </select>
      </label>
      <p class="control-note">Honduras and Paraguay are unavailable because INE publishes them only within “Other countries of America”.</p>` : ""}`;
  controls.querySelectorAll<HTMLInputElement>('input[name="thematic-layer"]').forEach((input) => {
    input.addEventListener("change", () => selectLayer(input.value));
  });
  controls.querySelector<HTMLSelectElement>("#country-select")?.addEventListener("change", (event) => {
    atlasState.country = (event.currentTarget as HTMLSelectElement).value;
    renderControls();
    renderLegend();
    if (map) void applyMapLayers().then(() => void renderFeaturePanelForState());
    else void renderFeaturePanelForState();
    scheduleHashUpdate();
  });
}

function renderElectionControls(): void {
  const elections: Array<[AtlasState["election"], string]> = [
    ["general", "General · 23 July 2023"],
    ["local", "Madrid Local · 28 May 2023"],
    ["assembly", "Madrid Assembly · 28 May 2023"],
  ];
  const available = manifest.layers.filter(
    (layer) => layer.group === "elections" && layer.control?.election === atlasState.election,
  );
  const current = available.find((layer) => layer.id === atlasState.layer) ?? available[0];
  if (current && current.id !== atlasState.layer) atlasState.layer = current.id;

  controls.innerHTML = `
    <label class="select-label">
      Election
      <select id="election-select" class="atlas-select">
        ${elections
          .map(
            ([value, label]) =>
              `<option value="${value}" ${value === atlasState.election ? "selected" : ""}>${label}</option>`,
          )
          .join("")}
      </select>
    </label>
    <label class="select-label">
      Result
      <select id="party-select" class="atlas-select">
        ${available
          .map(
            (layer) =>
              `<option value="${escapeHtml(layer.id)}" ${layer.id === atlasState.layer ? "selected" : ""}>${escapeHtml(layer.shortLabel || layer.label)}</option>`,
          )
          .join("")}
      </select>
    </label>`;

  controls.querySelector<HTMLSelectElement>("#election-select")?.addEventListener("change", (event) => {
    atlasState.election = (event.currentTarget as HTMLSelectElement).value as AtlasState["election"];
    const first = manifest.layers.find(
      (layer) => layer.group === "elections" && layer.control?.election === atlasState.election,
    );
    if (first) {
      atlasState.layer = first.id;
      atlasState.dataLayerVisible = true;
      atlasState.party = first.control?.party || "leading";
    }
    renderControls();
    renderLegend();
    if (map) void applyMapLayers().then(() => void renderFeaturePanelForState());
    else void renderFeaturePanelForState();
    scheduleHashUpdate();
  });
  controls.querySelector<HTMLSelectElement>("#party-select")?.addEventListener("change", (event) => {
    selectLayer((event.currentTarget as HTMLSelectElement).value);
  });
}

function renderEmptyFeaturePanel(): void {
  currentFeatureTitle = "";
  featurePanel.innerHTML =
    '<p class="feature-empty">Select a census section or map feature to see its details.</p>';
  updateDetailsToggleLabel();
}

function clearSelectedSection(updateHash = true): void {
  atlasState.selectedSection = null;
  atlasState.reportOpen = false;
  currentFeatureTitle = "";
  if (map?.getLayer(SECTION_OUTLINE_LAYER)) map.removeLayer(SECTION_OUTLINE_LAYER);
  if (updateHash) scheduleHashUpdate();
}

function isCensusSectionLayer(layer: LayerDefinition): boolean {
  return layer.group === "population" || layer.group === "education-work" || layer.group === "income" || layer.group === "elections";
}

function renderTransportControls(): void {
  const modes: Array<[string, string, string]> = [
    ["metro", "Metro", "Underground and surface"],
    ["metro-ligero", "Metro Ligero", "Light rail"],
    ["cercanias", "Cercanías", "Commuter rail"],
    ["emt", "EMT buses", "Madrid city routes"],
    ["bicimad", "BiciMAD", "Docking stations"],
  ];
  const routeOptions =
    manifest.layers.find((layer) => layer.control?.transportMode === "emt")?.control?.routes ?? [];

  controls.innerHTML = `
    <div class="transport-list-heading transport-data-heading">
      <span>Data layer</span>
      <button id="clear-data-layer" class="transport-clear" type="button"
        ${atlasState.dataLayerVisible ? "" : "disabled"}>
        ${atlasState.dataLayerVisible ? "Clear data layer" : "No data layer"}
      </button>
    </div>
    <div class="transport-list-heading">
      <span>Overlays</span>
      <button id="clear-transport" class="transport-clear" type="button"
        ${atlasState.transport.length === 0 ? "disabled" : ""}>Clear all</button>
    </div>
    <div class="transport-list" aria-label="Transport overlays">
      ${modes
        .map(
          ([value, label, note]) => `
          <label class="transport-choice">
            <input type="checkbox" name="transport-mode" value="${value}"
              ${atlasState.transport.includes(value) ? "checked" : ""} />
            <span class="choice-label">${label}</span>
            <span class="visually-hidden">${note}</span>
          </label>`,
        )
        .join("")}
    </div>
    <label class="select-label route-select">
      EMT route
      <select id="route-select" class="atlas-select" ${atlasState.transport.includes("emt") ? "" : "disabled"}>
        <option value="all">All routes</option>
        ${routeOptions
          .map(
            (route) =>
              `<option value="${escapeHtml(route.value)}" ${atlasState.route === route.value ? "selected" : ""}>${escapeHtml(route.label)}</option>`,
          )
          .join("")}
      </select>
    </label>
    <p class="feature-empty">All stops appear together at zoom 12. Select one EMT line to reduce clutter.</p>`;

  controls.querySelector<HTMLButtonElement>("#clear-data-layer")?.addEventListener("click", () => {
    atlasState.dataLayerVisible = false;
    clearSelectedSection(false);
    renderEmptyFeaturePanel();
    renderControls();
    renderLegend();
    if (map) void applyMapLayers();
    scheduleHashUpdate();
  });

  controls.querySelector<HTMLButtonElement>("#clear-transport")?.addEventListener("click", () => {
    atlasState.transport = [];
    atlasState.route = "all";
    renderControls();
    if (map) void applyMapLayers();
    scheduleHashUpdate();
  });

  controls.querySelectorAll<HTMLInputElement>('input[name="transport-mode"]').forEach((input) => {
    input.addEventListener("change", () => {
      atlasState.transport = Array.from(
        controls.querySelectorAll<HTMLInputElement>('input[name="transport-mode"]:checked'),
      ).map((item) => item.value);
      renderControls();
      if (map) void applyMapLayers();
      scheduleHashUpdate();
    });
  });
  controls.querySelector<HTMLSelectElement>("#route-select")?.addEventListener("change", (event) => {
    atlasState.route = (event.currentTarget as HTMLSelectElement).value;
    if (map) void applyMapLayers();
    scheduleHashUpdate();
  });
}

function renderLegend(): void {
  const selected = getSelectedLayer();
  const hideLegend = !atlasState.dataLayerVisible || selected.control?.party === "leading";
  legendPanel.classList.toggle("is-hidden", hideLegend);
  mobileLegendButton.disabled = hideLegend;
  if (hideLegend) {
    legend.innerHTML = "";
    if (panel.dataset.mobileView === "legend") setSheetOpen(false);
    return;
  }
  legendTitle.textContent = selected.label;
  legendDate.textContent = shortDate(selected.referenceDate);

  if (selected.format === "text") {
    const rows: string[] = [];
    for (let index = 0; index < selected.palette.length; index += 2) {
      const name = selected.palette[index];
      const color = selected.palette[index + 1];
      if (name && color) {
        rows.push(
          `<div class="legend-swatch"><i style="background:${escapeHtml(color)}"></i><span>${escapeHtml(name)}</span></div>`,
        );
      }
    }
    legend.innerHTML = `<div class="legend-swatch-list">${rows.join("")}</div>
      <p class="legend-note">${escapeHtml(selected.description)}</p>`;
    return;
  }

  const low = selected.breaks[0] ?? 0;
  const high = selected.breaks.at(-1) ?? low;
  const missingNote = /missing observations/i.test(selected.description)
    ? selected.description
    : `${selected.description} Missing observations are shown in grey.`;
  legend.innerHTML = `
    <div class="legend-ramp" style="grid-template-columns:repeat(${selected.palette.length},1fr)">
      ${selected.palette.map((color) => `<i style="background:${escapeHtml(color)}"></i>`).join("")}
    </div>
    <div class="legend-labels ${selected.scale?.type === "continuous-diverging" ? "has-centre" : ""}">
      <span>${formatValue(low, selected.format, selected.unit)}</span>
      ${selected.scale?.type === "continuous-diverging" ? `<span>${formatValue(selected.scale.center, selected.format, selected.unit)}</span>` : ""}
      <span>${formatValue(high, selected.format, selected.unit)}</span>
    </div>
    <p class="legend-note">${escapeHtml(missingNote)}</p>`;
}

function renderMethodology(): void {
  const sourceSections = manifest.references
    .map(
      (reference) => `
      <section class="method-section">
        <h3>${escapeHtml(reference.title)}</h3>
        <p>${escapeHtml(reference.organisation)} · retrieved ${escapeHtml(reference.retrieved)} ·
          ${escapeHtml(reference.licence)}</p>
        <p><a href="${escapeHtml(reference.url)}" target="_blank" rel="noreferrer">Open source dataset ↗</a></p>
      </section>`,
    )
    .join("");
  methodologyContent.innerHTML = `
    <section class="method-section">
      <h3>How to read the atlas</h3>
      <p>
        Thematic layers are mutually exclusive, while transport networks can be combined.
        Each dataset uses the census-section boundary vintage matching its reference year.
        Unmatched values remain “No data”; they are never converted to zero.
      </p>
      <ul>${manifest.notes.map((note) => `<li>${escapeHtml(note)}</li>`).join("")}</ul>
    </section>
    ${sourceSections}`;
}

function getSelectedLayer(): LayerDefinition {
  return effectiveDefinition(
    manifest.layers.find((layer) => layer.id === atlasState.layer) ??
      manifest.layers.find((layer) => layer.id === manifest.defaultLayer) ??
      manifest.layers[0]!,
  );
}

function effectiveDefinition(definition: LayerDefinition): LayerDefinition {
  const country = definition.control?.country;
  if (!country) return definition;
  const option = country.options.find((candidate) => candidate.value === atlasState.country) ??
    country.options.find((candidate) => candidate.value === country.defaultValue) ??
    country.options[0];
  if (!option) return definition;
  const baseProperty = definition.property;
  return {
    ...definition,
    property: option.property,
    palette: option.palette ?? definition.palette,
    breaks: option.breaks ?? definition.breaks,
    label: `${definition.label.replace(/ · .*$/, "")} · ${option.label}`,
    tooltip: definition.tooltip.map((field) =>
      field.property === baseProperty
        ? {
            ...field,
            property: option.property,
            percentileProperty: option.percentileProperty,
            label: `${field.label.replace(/ · .*$/, "")} · ${option.label}`,
          }
        : field,
    ),
  };
}

async function loadSectionReports(): Promise<SectionReportIndex> {
  if (sectionReportIndex) return sectionReportIndex;
  if (!sectionReportLoadPromise) {
    sectionReportLoadPromise = fetchJson<SectionReportIndex>(sectionReportsUrl).then((index) => {
      sectionReportIndex = index;
      return index;
    });
  }
  return sectionReportLoadPromise;
}

async function renderFeaturePanelForState(): Promise<void> {
  const selected = getSelectedLayer();
  if (atlasState.selectedSection && isCensusSectionLayer(selected)) {
    await renderSelectedSection(atlasState.selectedSection);
    return;
  }
  if (atlasState.group === "elections") {
    await renderMadridElectionPanel();
    return;
  }
  renderEmptyFeaturePanel();
}

async function renderSelectedSection(sectionId: string): Promise<void> {
  featurePanel.innerHTML = '<p class="feature-empty">Loading section details…</p>';
  try {
    const index = await loadSectionReports();
    const report = index.sections[sectionId];
    if (!report) {
      clearSelectedSection(false);
      renderEmptyFeaturePanel();
      scheduleHashUpdate(true);
      showToast("That census section is not available");
      return;
    }
    const definition = getSelectedLayer();
    renderFeatureDetails(
      definition,
      sectionProperties(report, definition),
      report.name,
      report.district,
      true,
    );
  } catch (error) {
    console.warn("Section report index could not be loaded", error);
    featurePanel.innerHTML = '<p class="feature-empty">Section details are temporarily unavailable.</p>';
  }
}

async function renderMadridElectionPanel(): Promise<void> {
  currentFeatureTitle = "Madrid results";
  updateDetailsToggleLabel();
  featurePanel.innerHTML = '<p class="feature-empty">Loading Madrid results…</p>';
  try {
    const index = await loadSectionReports();
    featurePanel.innerHTML = renderMadridElectionCard(index.cityElections[atlasState.election]);
  } catch (error) {
    console.warn("Madrid election results could not be loaded", error);
    featurePanel.innerHTML = '<p class="feature-empty">Madrid election results are temporarily unavailable.</p>';
  }
}

async function openSelectedSectionReport(updateState = true): Promise<void> {
  const sectionId = atlasState.selectedSection;
  if (!sectionId) return;
  reportChartCleanup?.();
  reportChartCleanup = undefined;
  reportContent.innerHTML = '<p class="report-loading">Preparing the census-section report…</p>';
  if (!reportDialog.open) reportDialog.showModal();
  try {
    const index = await loadSectionReports();
    const report = index.sections[sectionId];
    if (!report) throw new Error(`Unknown report section ${sectionId}`);
    reportDialogTitle.textContent = report.name;
    reportContent.innerHTML = renderSectionReport(index, report, atlasState.country);
    reportChartCleanup = bindDistributionCharts(reportContent, index);
    atlasState.reportOpen = true;
    if (updateState) scheduleHashUpdate(true);
  } catch (error) {
    console.warn("Census-section report could not be rendered", error);
    reportContent.innerHTML = '<p class="report-loading">This report is temporarily unavailable.</p>';
  }
}

function prepareReportPrintTitle(): void {
  if (!reportDialog.open) return;
  titleBeforePrint ??= document.title;
  const reportName = reportDialogTitle.textContent?.trim() || "Census-section report";
  document.title = `${reportName} · Madrid Atlas · danielalmazan.com`;
}

function restoreDocumentTitle(): void {
  if (titleBeforePrint === undefined) return;
  document.title = titleBeforePrint;
  titleBeforePrint = undefined;
}

async function copyReportLink(): Promise<void> {
  if (!atlasState.selectedSection) return;
  const reportState: AtlasState = { ...atlasState, reportOpen: true };
  await copyUrl(stateUrl(reportState), "Report link copied");
}

function bindSectionCardActions(): void {
  featurePanel.querySelector<HTMLButtonElement>(".open-section-report")?.addEventListener("click", () => {
    void openSelectedSectionReport();
  });
  featurePanel.querySelector<HTMLButtonElement>(".back-to-madrid")?.addEventListener("click", () => {
    clearSelectedSection();
    void renderMadridElectionPanel();
  });
}

function handleMapClick(event: MapMouseEvent): void {
  const features = map
    .queryRenderedFeatures(event.point)
    .filter((feature) => activeMapLayerIds.includes(feature.layer.id));
  const feature = features[0];
  if (!feature) {
    clearSelectedSection();
    void renderFeaturePanelForState();
    return;
  }
  const definition = manifest.layers.find((candidate) =>
    feature.layer.id.startsWith(`atlas-${candidate.id}-`),
  );
  if (definition && isCensusSectionLayer(definition)) {
    const canonical = map.queryRenderedFeatures(event.point, { layers: [SECTION_HIT_LAYER] })[0];
    const sectionId = canonical?.properties?.section_id;
    if (typeof sectionId === "string" && /^28079[0-9]{5}$/.test(sectionId)) {
      atlasState.selectedSection = sectionId;
      atlasState.reportOpen = false;
      if (map.getLayer(SECTION_OUTLINE_LAYER)) map.removeLayer(SECTION_OUTLINE_LAYER);
      addSelectedSectionOutline();
      scheduleHashUpdate();
      void renderSelectedSection(sectionId);
      return;
    }
  }
  clearSelectedSection(false);
  renderFeature(feature);
  scheduleHashUpdate();
}

function handleMapHover(event: MapMouseEvent): void {
  if (!map) return;
  const features = map
    .queryRenderedFeatures(event.point)
    .filter((feature) => activeMapLayerIds.includes(feature.layer.id));
  map.getCanvas().style.cursor = features.length > 0 ? "pointer" : "";
}

function renderFeature(feature: MapGeoJSONFeature): void {
  const layerId = feature.layer.id;
  const rawDefinition = manifest.layers.find((candidate) =>
    layerId.startsWith(`atlas-${candidate.id}-`),
  );
  if (!rawDefinition) return;
  const definition = effectiveDefinition(rawDefinition);
  const properties = feature.properties ?? {};
  const isBuilding = definition.group === "buildings";
  const buildingId = properties.building_id || properties.height_id;
  const title = isBuilding
    ? definition.id === "building-age"
      ? "Catastro building"
      : "Municipal height polygon"
    : properties.name ||
      properties.stop_name ||
      properties.route_long_name ||
      properties.section_name ||
      `Census section ${properties.section_id || "—"}`;
  const context = isBuilding
    ? [properties.district, buildingId ? `ID ${buildingId}` : definition.geography]
        .filter(Boolean)
        .join(" · ")
    : [properties.neighbourhood, properties.district].filter(Boolean).join(" · ");

  renderFeatureDetails(definition, properties, String(title), context || definition.geography, false);
}

function renderFeatureDetails(
  definition: LayerDefinition,
  properties: Record<string, unknown>,
  title: string,
  context: string,
  isSection: boolean,
): void {

  currentFeatureTitle = title;
  updateDetailsToggleLabel();

  if (definition.control?.party === "leading" && definition.control.results) {
    renderElectionResultFeature(title, context, properties, definition, isSection);
    if (isMobileViewport()) setMobilePanel(true, "details");
    return;
  }

  const fields = definition.tooltip
    .map((field) => {
      const value = properties[field.property];
      let shown =
        value === null || value === undefined || value === ""
          ? "No data"
          : formatValue(
              Number.isNaN(Number(value)) ? String(value) : Number(value),
              field.format,
              field.suffix ?? "",
              definition.group === "elections" &&
                field.format === "percent" &&
                /share/i.test(field.label)
                ? 1
                : 0,
            );
      const percentile = field.percentileProperty
        ? Number(properties[field.percentileProperty])
        : Number.NaN;
      if (shown !== "No data" && Number.isFinite(percentile)) {
        shown += ` (${ordinal(Math.round(percentile))} perc.)`;
      }
      return `
        <div class="feature-stat">
          <dt>${escapeHtml(field.label)}</dt>
          <dd>${escapeHtml(shown)}</dd>
        </div>`;
    })
    .join("");

  featurePanel.innerHTML = `
    <div class="feature-header">
      <h3>${escapeHtml(title)}</h3>
      <p>${escapeHtml(context)}</p>
    </div>
    <dl class="feature-grid">${fields}</dl>
    ${renderIncomeSuppressionNote(definition, properties)}
    ${renderSectionActions(definition, isSection)}`;
  if (isSection) bindSectionCardActions();
  if (isMobileViewport()) setMobilePanel(true, "details");
}

function renderIncomeSuppressionNote(
  definition: LayerDefinition,
  properties: Record<string, unknown>,
): string {
  if (definition.group !== "income") return "";
  const district = String(properties.district ?? "");
  const affected = district === "Carabanchel" || district === "Fuencarral-El Pardo";
  const missing = properties.below_60_median_pct == null && properties.above_200_median_pct == null;
  if (!affected || !missing) return "";
  return `<aside class="feature-data-note"><strong>Official source suppression</strong><p>INE publishes no section values for the below-60% or above-200% median indicators in ${escapeHtml(district)}. The other income measures remain available.</p></aside>`;
}

function renderSectionActions(definition: LayerDefinition, isSection: boolean): string {
  if (!isSection) return "";
  return `<div class="feature-actions">
    <button class="open-section-report report-link-button" type="button">See full report</button>
    ${definition.group === "elections" ? '<button class="back-to-madrid quiet-link-button" type="button">Back to Madrid results</button>' : ""}
  </div>`;
}

function renderElectionResultFeature(
  title: string,
  context: string,
  properties: Record<string, unknown>,
  definition: LayerDefinition,
  isSection = false,
): void {
  const candidates = (definition.control?.results ?? [])
    .map((result) => ({
      ...result,
      value: Number(properties[result.property]),
    }))
    .filter((result) => Number.isFinite(result.value) && result.value > 0)
    .sort((left, right) => right.value - left.value);

  const shown: typeof candidates = [];
  let cumulative = 0;
  for (const candidate of candidates) {
    if (cumulative >= 90) break;
    shown.push(candidate);
    cumulative += candidate.value;
  }

  featurePanel.innerHTML = `
    <div class="feature-header">
      <h3>${escapeHtml(title)}</h3>
      <p>${escapeHtml(context)}</p>
    </div>
    <table class="election-results">
      <thead><tr><th>Party</th><th>Vote share</th></tr></thead>
      <tbody>
        ${shown
          .map(
            (result) => `
              <tr>
                <th><i style="background:${escapeHtml(result.color)}"></i>${escapeHtml(result.label)}</th>
                <td>${escapeHtml(formatValue(result.value, "percent", "", 1))}</td>
              </tr>`,
          )
          .join("")}
      </tbody>
    </table>
    <p class="results-coverage">${escapeHtml(formatValue(cumulative, "percent", "", 1))} of valid votes shown</p>
    ${renderSectionActions(definition, isSection)}`;
  if (isSection) bindSectionCardActions();
}

function zoomToLayerMinimum(layer: LayerDefinition): void {
  if (!map || layer.group === "transport" || layer.minzoom === undefined) return;
  if (map.getZoom() >= layer.minzoom) return;
  map.easeTo({
    zoom: layer.minzoom,
    duration: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 650,
  });
}

function toggle3d(): void {
  if (!map) return;
  atlasState.is3d = !atlasState.is3d;
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  map.easeTo({
    pitch: atlasState.is3d ? 52 : 0,
    bearing: atlasState.is3d ? -8 : 0,
    duration: reduced ? 0 : 650,
  });
  pitchButton.setAttribute("aria-pressed", String(atlasState.is3d));
  void applyMapLayers();
  scheduleHashUpdate();
}

function resetView(): void {
  if (!map) return;
  atlasState.is3d = false;
  searchMarker?.remove();
  searchMarker = undefined;
  map.easeTo({
    center: [MADRID_CAMERA.lng, MADRID_CAMERA.lat],
    zoom: MADRID_CAMERA.zoom,
    bearing: 0,
    pitch: 0,
    duration: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 800,
  });
  void applyMapLayers();
}

function openShareDialog(): void {
  scheduleHashUpdate(true);
  const hasSection = atlasState.selectedSection !== null;
  shareDialogTitle.textContent = hasSection ? "Share this census section" : "Share this map view";
  shareViewAction.querySelector("strong")!.textContent = hasSection ? "Share section + layer" : "Share map view";
  shareViewAction.querySelector("small")!.textContent = hasSection
    ? "Reopens this section on the active layer"
    : "Includes the active layer and map position";
  shareReportAction.hidden = !hasSection;
  shareDialog.showModal();
}

async function shareCurrentView(): Promise<void> {
  const shareState: AtlasState = { ...atlasState, reportOpen: false };
  const url = stateUrl(shareState);
  const title = atlasState.selectedSection ? "Madrid census section" : "Madrid Interactive Atlas";
  try {
    const outcome = await shareOrCopy(
      { title, url },
      {
        share: navigator.share?.bind(navigator),
        copy: (value) => navigator.clipboard.writeText(value),
      },
    );
    if (outcome === "copied") {
      showToast(atlasState.selectedSection ? "Section + layer link copied" : "View link copied");
    }
    if (outcome !== "aborted") shareDialog.close();
  } catch {
    showToast("Copy the URL from the address bar to share it");
  }
}

function stateUrl(state: AtlasState): string {
  const url = new URL(window.location.href);
  url.hash = serializeState(state);
  return url.toString();
}

async function copyUrl(url: string, successMessage: string): Promise<void> {
  try {
    await navigator.clipboard.writeText(url);
    showToast(successMessage);
  } catch {
    showToast("Copy the URL from the address bar to share it");
  }
}

function renderSearchResults(): void {
  void renderSearchResultsAsync();
}

async function renderSearchResultsAsync(): Promise<void> {
  const query = normaliseSearchText(searchInput.value);
  if (query.length < 2) {
    hideSearchResults();
    return;
  }
  const placeMatches = places
    .filter((place) => normaliseSearchText(`${place.name} ${place.district ?? ""}`).includes(query))
    .slice(0, 8);

  if (query.length >= 3) await loadAddressIndex();
  if (normaliseSearchText(searchInput.value) !== query) return;

  const addressMatches: Array<{ record: AddressRecord; index: number }> = [];
  if (query.length >= 3) {
    for (let index = 0; index < addressSearchText.length && addressMatches.length < 8; index += 1) {
      if (addressSearchText[index]?.includes(query)) {
        addressMatches.push({ record: addresses[index]!, index });
      }
    }
  }

  const shownAddresses = addressMatches.slice(0, Math.max(0, 8 - placeMatches.length));
  if (placeMatches.length === 0 && shownAddresses.length === 0) {
    searchResults.innerHTML = '<p class="feature-empty" style="padding:8px">No place found.</p>';
  } else {
    searchResults.innerHTML =
      placeMatches
        .map(
          (place) => `
        <button class="search-result" type="button" role="option" data-place="${escapeHtml(place.id)}">
          <span>${escapeHtml(place.name)}</span>
          <small>${escapeHtml(place.kind)}</small>
        </button>`,
        )
        .join("") +
      shownAddresses
        .map(
          ({ record, index }) => `
        <button class="search-result" type="button" role="option" data-address="${index}">
          <span>${escapeHtml(record[1])}</span>
          <small>Address · ${escapeHtml(record[2])}</small>
        </button>`,
        )
        .join("");
    searchResults.querySelectorAll<HTMLButtonElement>(".search-result").forEach((button) => {
      button.addEventListener("click", () => {
        if (button.dataset.address !== undefined) {
          const address = addresses[Number(button.dataset.address)];
          if (address) selectAddress(address);
          return;
        }
        const place = places.find((item) => item.id === button.dataset.place);
        if (place) selectPlace(place);
      });
    });
  }
  searchResults.hidden = false;
  searchInput.setAttribute("aria-expanded", "true");
}

async function loadAddressIndex(): Promise<void> {
  if (addresses.length > 0) return;
  if (addressLoadPromise) return addressLoadPromise;
  addressLoadPromise = fetchJson<AddressIndex>(addressesUrl)
    .then((index) => {
      addresses = index.records;
      addressSearchText = addresses.map((record) =>
        normaliseSearchText(`${record[1]} ${record[2]}`),
      );
    })
    .catch((error) => {
      console.warn("Street-address index could not be loaded", error);
    });
  return addressLoadPromise;
}

function normaliseSearchText(value: string): string {
  return value
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLocaleLowerCase("es")
    .replace(/\s+/g, " ")
    .trim();
}

function handleSearchKeys(event: KeyboardEvent): void {
  if (event.key === "Escape") hideSearchResults();
  if (event.key === "ArrowDown") {
    event.preventDefault();
    searchResults.querySelector<HTMLButtonElement>(".search-result")?.focus();
  }
  if (event.key === "Enter") {
    const first = searchResults.querySelector<HTMLButtonElement>(".search-result");
    if (first) first.click();
  }
}

function selectPlace(place: Place): void {
  if (!place.bbox.every(Number.isFinite)) {
    showToast("This place does not have a valid map extent");
    return;
  }
  map.fitBounds(
    [
      [place.bbox[0], place.bbox[1]],
      [place.bbox[2], place.bbox[3]],
    ],
    {
      padding: window.matchMedia("(max-width: 860px)").matches ? 50 : 70,
      maxZoom: place.kind === "district" ? 13 : 15,
      duration: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 750,
    },
  );
  searchInput.value = place.name;
  searchMarker?.remove();
  searchMarker = undefined;
  hideSearchResults();
}

function selectAddress(address: AddressRecord): void {
  const [, name, , longitude, latitude] = address;
  if (![longitude, latitude].every(Number.isFinite)) {
    showToast("This address does not have valid coordinates");
    return;
  }
  map.easeTo({
    center: [longitude, latitude],
    zoom: 17,
    duration: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 750,
  });
  searchMarker?.remove();
  searchMarker = new maplibregl.Marker({ color: "#fb6107" })
    .setLngLat([longitude, latitude])
    .addTo(map);
  searchInput.value = name;
  hideSearchResults();
}

function hideSearchResults(): void {
  searchResults.hidden = true;
  searchInput.setAttribute("aria-expanded", "false");
}

function isMobileViewport(): boolean {
  return window.matchMedia("(max-width: 860px)").matches;
}

function toggleMobilePanel(view: MobilePanelView): void {
  const isSameOpenView = panel.classList.contains("is-open") && panel.dataset.mobileView === view;
  if (isSameOpenView) {
    setSheetOpen(false);
    return;
  }
  setMobilePanel(true, view);
}

function setMobilePanel(open: boolean, view: MobilePanelView): void {
  panel.dataset.mobileView = view;
  mobileSheetTitle.textContent = {
    layers: "Choose map layers",
    legend: "Map legend",
    details: atlasState.selectedSection ? "Section details" : "Map details",
    info: "Map information",
  }[view];
  setSheetOpen(open);
}

function setSheetOpen(open: boolean): void {
  panel.classList.toggle("is-open", open);
  syncPanelAccessibility();
  sheetToggle.setAttribute("aria-expanded", String(open));
  const activeView = panel.dataset.mobileView as MobilePanelView;
  mobileLayersButton.setAttribute("aria-expanded", String(open && activeView === "layers"));
  mobileLayersButton.setAttribute("aria-pressed", String(open && activeView === "layers"));
  mobileLegendButton.setAttribute("aria-expanded", String(open && activeView === "legend"));
  mobileLegendButton.setAttribute("aria-pressed", String(open && activeView === "legend"));
  mobileInfoButton.setAttribute("aria-expanded", String(open && activeView === "info"));
  mobileInfoButton.setAttribute("aria-pressed", String(open && activeView === "info"));
}

function syncPanelAccessibility(): void {
  panel.inert = isMobileViewport() && !panel.classList.contains("is-open");
}

function updateDetailsToggleLabel(): void {
  const fallback = `${groupLabel(atlasState.group)} details`;
  sheetToggleLabel.textContent = currentFeatureTitle ? `Details · ${currentFeatureTitle}` : fallback;
}

function scheduleHashUpdate(immediate = false): void {
  window.clearTimeout(hashTimer);
  const update = (): void => {
    const next = serializeState(atlasState);
    if (window.location.hash !== next) history.replaceState(null, "", next);
  };
  if (immediate) update();
  else hashTimer = window.setTimeout(update, 180);
}

function setStatus(message: string, isError = false): void {
  status.querySelector("span:last-child")!.textContent = message;
  infoStatusText.textContent = message;
  status.classList.toggle("is-ready", !isError && message.startsWith("Ready"));
  status.classList.toggle("is-error", isError);
}

function showToast(message: string): void {
  window.clearTimeout(toastTimer);
  toast.textContent = message;
  toast.classList.add("is-visible");
  toastTimer = window.setTimeout(() => toast.classList.remove("is-visible"), 2200);
}

function groupLabel(group: LayerGroup): string {
  return {
    population: "Population",
    "education-work": "Education & Work",
    buildings: "Buildings",
    elections: "Elections",
    income: "Income & inequality",
    transport: "Transport networks",
  }[group];
}

function shortDate(value: string): string {
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return new Intl.DateTimeFormat("en-GB", { month: "short", year: "numeric" }).format(
      new Date(`${value}T12:00:00Z`),
    );
  }
  return value;
}

function formatValue(
  value: number | string,
  format: ValueFormat,
  suffix = "",
  minimumFractionDigits = 0,
): string {
  if (typeof value === "string") return value;
  if (!Number.isFinite(value)) return "No data";
  const locale = "en-GB";
  const spacedSuffix = suffix && !suffix.startsWith(" ") ? ` ${suffix}` : suffix;
  switch (format) {
    case "integer":
      return `${new Intl.NumberFormat(locale, { maximumFractionDigits: 0 }).format(value)}${spacedSuffix}`;
    case "decimal":
      return `${new Intl.NumberFormat(locale, { maximumFractionDigits: 1 }).format(value)}${spacedSuffix}`;
    case "percent":
      return `${new Intl.NumberFormat(locale, {
        minimumFractionDigits,
        maximumFractionDigits: 1,
      }).format(value)}%`;
    case "pp":
      return `${new Intl.NumberFormat(locale, {
        minimumFractionDigits,
        maximumFractionDigits: 1,
      }).format(value)} pp`;
    case "currency":
      return new Intl.NumberFormat(locale, {
        style: "currency",
        currency: "EUR",
        maximumFractionDigits: 0,
      }).format(value);
    case "year":
      return String(Math.round(value));
    case "text":
      return String(value);
  }
}

function ordinal(value: number): string {
  const remainder100 = value % 100;
  if (remainder100 >= 11 && remainder100 <= 13) return `${value}th`;
  return `${value}${value % 10 === 1 ? "st" : value % 10 === 2 ? "nd" : value % 10 === 3 ? "rd" : "th"}`;
}

function escapeHtml(value: string): string {
  const element = document.createElement("span");
  element.textContent = value;
  return element.innerHTML;
}
