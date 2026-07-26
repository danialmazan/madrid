import maplibregl, {
  type ExpressionSpecification,
  type MapGeoJSONFeature,
  type MapMouseEvent,
  type Map as MapLibreMap,
} from "maplibre-gl";
import { Protocol } from "pmtiles";
import "./styles.css";
import { MADRID_CAMERA, parseHash, serializeState } from "./state";
import type {
  AtlasState,
  LayerDefinition,
  LayerGroup,
  LayerManifest,
  Place,
  ValueFormat,
} from "./types";

const BASE_URL = import.meta.env.BASE_URL;
const manifestUrl = `${BASE_URL}data/layer-manifest.json`;
const placesUrl = `${BASE_URL}data/places.json`;

const panel = requireElement<HTMLElement>(".atlas-panel");
const controls = requireElement<HTMLElement>("#layer-controls");
const legend = requireElement<HTMLElement>("#legend");
const legendTitle = requireElement<HTMLElement>("#legend-title");
const legendDate = requireElement<HTMLElement>("#legend-date");
const featurePanel = requireElement<HTMLElement>("#feature-panel");
const status = requireElement<HTMLElement>("#map-status");
const searchInput = requireElement<HTMLInputElement>("#place-search");
const searchResults = requireElement<HTMLElement>("#search-results");
const pitchButton = requireElement<HTMLButtonElement>("#pitch-button");
const resetButton = requireElement<HTMLButtonElement>("#reset-button");
const shareButton = requireElement<HTMLButtonElement>("#share-button");
const sheetToggle = requireElement<HTMLButtonElement>("#sheet-toggle");
const sheetToggleLabel = requireElement<HTMLElement>("#sheet-toggle-label");
const aboutDialog = requireElement<HTMLDialogElement>("#about-dialog");
const methodologyContent = requireElement<HTMLElement>("#methodology-content");
const toast = requireElement<HTMLElement>("#toast");

let atlasState: AtlasState = parseHash(window.location.hash);
let manifest: LayerManifest;
let map: MapLibreMap;
let places: Place[] = [];
let activeMapLayerIds: string[] = [];
let hashTimer: number | undefined;
let toastTimer: number | undefined;

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
}

function bindStaticControls(): void {
  document.querySelectorAll<HTMLButtonElement>(".group-tab").forEach((button) => {
    button.addEventListener("click", () => {
      const group = button.dataset.group as LayerGroup;
      selectGroup(group);
    });
  });

  pitchButton.addEventListener("click", () => toggle3d());
  resetButton.addEventListener("click", () => resetView());
  shareButton.addEventListener("click", () => void shareView());
  sheetToggle.addEventListener("click", () => setSheetOpen(true));
  document.querySelector("#about-button")?.addEventListener("click", () => aboutDialog.showModal());
  document.querySelector("#close-about")?.addEventListener("click", () => aboutDialog.close());
  aboutDialog.addEventListener("click", (event) => {
    if (event.target === aboutDialog) aboutDialog.close();
  });

  searchInput.addEventListener("input", renderSearchResults);
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
      setSheetOpen(false);
    }
  });

  window.addEventListener("hashchange", () => {
    const incoming = parseHash(window.location.hash);
    atlasState = incoming;
    normaliseInitialState();
    renderGroupTabs();
    renderControls();
    renderLegend();
    if (map) {
      map.jumpTo({
        center: [incoming.camera.lng, incoming.camera.lat],
        zoom: incoming.camera.zoom,
        bearing: incoming.camera.bearing,
        pitch: incoming.camera.pitch,
      });
      void applyMapLayers();
    }
  });
}

function createMap(): void {
  const protocol = new Protocol();
  maplibregl.addProtocol("pmtiles", protocol.tile);

  try {
    map = new maplibregl.Map({
      container: "atlas-map",
      style: "https://tiles.openfreemap.org/styles/positron",
      center: [atlasState.camera.lng, atlasState.camera.lat],
      zoom: atlasState.camera.zoom,
      bearing: atlasState.camera.bearing,
      pitch: atlasState.is3d ? Math.max(48, atlasState.camera.pitch) : atlasState.camera.pitch,
      minZoom: 8,
      maxZoom: 19,
      hash: false,
      attributionControl: false,
      cooperativeGestures: true,
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
    void applyMapLayers();
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
  const style = map.getStyle();
  for (const layer of style.layers ?? []) {
    const id = layer.id.toLowerCase();
    try {
      if (layer.type === "background") map.setPaintProperty(layer.id, "background-color", "#f5f4ef");
      if (layer.type === "fill" && /(park|wood|grass|landcover)/.test(id)) {
        map.setPaintProperty(layer.id, "fill-color", "#dfe9df");
        map.setPaintProperty(layer.id, "fill-opacity", 0.7);
      }
      if (layer.type === "fill" && /water/.test(id)) {
        map.setPaintProperty(layer.id, "fill-color", "#c8dfe9");
      }
      if (layer.type === "line" && /(road|street|highway)/.test(id)) {
        map.setPaintProperty(layer.id, "line-color", "#d8d5cd");
      }
      if (layer.type === "symbol" && /(poi|transit)/.test(id)) {
        map.setLayoutProperty(layer.id, "visibility", "none");
      }
      if (layer.type === "symbol" && /label/.test(id)) {
        map.setPaintProperty(layer.id, "text-color", "#52524d");
        map.setPaintProperty(layer.id, "text-halo-color", "#fafaf7");
      }
    } catch {
      // OpenFreeMap occasionally changes layer paint capabilities; safe to skip.
    }
  }
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

function resolveAssetUrl(url: string): string {
  if (/^https?:\/\//.test(url)) return url;
  return new URL(url.replace(/^\//, ""), new URL(BASE_URL, window.location.origin)).toString();
}

async function applyMapLayers(): Promise<void> {
  if (!map) return;
  for (const layerId of activeMapLayerIds) {
    if (map.getLayer(layerId)) map.removeLayer(layerId);
  }
  activeMapLayerIds = [];

  const thematic = getSelectedLayer();
  addDefinitionToMap(thematic, false);

  const overlays = manifest.layers.filter(
    (layer) =>
      layer.group === "transport" &&
      layer.control?.transportMode &&
      atlasState.transport.includes(layer.control.transportMode),
  );
  for (const overlay of overlays) addDefinitionToMap(overlay, true);
  pitchButton.setAttribute("aria-pressed", String(atlasState.is3d));
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
      map.addLayer(
        {
          ...common,
          type: "line",
          paint: {
            "line-color": definition.lineColor || [
              "coalesce",
              ["get", "route_color"],
              "#145c9e",
            ],
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
  if (group !== "transport" && getSelectedLayer().group !== group) {
    const first = manifest.layers.find((layer) => layer.group === group);
    if (first) atlasState.layer = first.id;
  }
  renderGroupTabs();
  renderControls();
  renderLegend();
  if (map) void applyMapLayers();
  setSheetOpen(window.matchMedia("(max-width: 860px)").matches);
  scheduleHashUpdate();
}

function selectLayer(layerId: string): void {
  const layer = manifest.layers.find((candidate) => candidate.id === layerId);
  if (!layer || layer.group === "transport") return;
  atlasState.layer = layer.id;
  atlasState.group = layer.group;
  if (layer.control?.election) atlasState.election = layer.control.election;
  if (layer.control?.party) atlasState.party = layer.control.party;
  renderGroupTabs();
  renderControls();
  renderLegend();
  featurePanel.innerHTML =
    '<p class="feature-empty">Select a census section or map feature to see its details.</p>';
  if (map) void applyMapLayers();
  scheduleHashUpdate();
}

function renderGroupTabs(): void {
  document.querySelectorAll<HTMLButtonElement>(".group-tab").forEach((button) => {
    const active = button.dataset.group === atlasState.group;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-current", active ? "page" : "false");
  });
  sheetToggleLabel.textContent = groupLabel(atlasState.group);
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
  controls.innerHTML = `
    <div class="radio-grid" role="radiogroup" aria-label="${escapeHtml(groupLabel(atlasState.group))} layers">
      ${layers
        .map(
          (layer) => `
            <label class="layer-choice">
              <input type="radio" name="thematic-layer" value="${escapeHtml(layer.id)}"
                ${layer.id === atlasState.layer ? "checked" : ""} />
              <span class="choice-label">${escapeHtml(layer.shortLabel || layer.label)}</span>
              <span class="choice-date">${escapeHtml(shortDate(layer.referenceDate))}</span>
            </label>`,
        )
        .join("")}
    </div>`;
  controls.querySelectorAll<HTMLInputElement>('input[name="thematic-layer"]').forEach((input) => {
    input.addEventListener("change", () => selectLayer(input.value));
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
      atlasState.party = first.control?.party || "turnout";
    }
    renderControls();
    renderLegend();
    if (map) void applyMapLayers();
    scheduleHashUpdate();
  });
  controls.querySelector<HTMLSelectElement>("#party-select")?.addEventListener("change", (event) => {
    selectLayer((event.currentTarget as HTMLSelectElement).value);
  });
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
    <div class="transport-list" aria-label="Transport overlays">
      ${modes
        .map(
          ([value, label, note]) => `
          <label class="transport-choice">
            <input type="checkbox" name="transport-mode" value="${value}"
              ${atlasState.transport.includes(value) ? "checked" : ""} />
            <span class="choice-label">${label}</span>
            <span class="choice-date">${note}</span>
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
    <p class="feature-empty">Stops appear as you zoom in. Select one EMT line to reduce clutter.</p>`;

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
  legend.innerHTML = `
    <div class="legend-ramp" style="grid-template-columns:repeat(${selected.palette.length},1fr)">
      ${selected.palette.map((color) => `<i style="background:${escapeHtml(color)}"></i>`).join("")}
    </div>
    <div class="legend-labels">
      <span>${formatValue(low, selected.format, selected.unit)}</span>
      <span>${formatValue(high, selected.format, selected.unit)}</span>
    </div>
    <p class="legend-note">${escapeHtml(selected.description)} Missing observations are shown in grey.</p>`;
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
  return (
    manifest.layers.find((layer) => layer.id === atlasState.layer) ??
    manifest.layers.find((layer) => layer.id === manifest.defaultLayer) ??
    manifest.layers[0]!
  );
}

function handleMapClick(event: MapMouseEvent): void {
  const features = map
    .queryRenderedFeatures(event.point)
    .filter((feature) => activeMapLayerIds.includes(feature.layer.id));
  const feature = features[0];
  if (!feature) {
    featurePanel.innerHTML =
      '<p class="feature-empty">Select a census section or map feature to see its details.</p>';
    return;
  }
  renderFeature(feature);
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
  const definition = manifest.layers.find((candidate) =>
    layerId.startsWith(`atlas-${candidate.id}-`),
  );
  if (!definition) return;
  const properties = feature.properties ?? {};
  const title =
    properties.name ||
    properties.stop_name ||
    properties.route_long_name ||
    properties.section_name ||
    `Census section ${properties.section_id || "—"}`;
  const context = [properties.neighbourhood, properties.district].filter(Boolean).join(" · ");
  const fields = definition.tooltip
    .map((field) => {
      const value = properties[field.property];
      const shown =
        value === null || value === undefined || value === ""
          ? "No data"
          : formatValue(Number.isNaN(Number(value)) ? String(value) : Number(value), field.format, field.suffix ?? "");
      return `
        <div class="feature-stat">
          <dt>${escapeHtml(field.label)}</dt>
          <dd>${escapeHtml(shown)}</dd>
        </div>`;
    })
    .join("");

  featurePanel.innerHTML = `
    <div class="feature-header">
      <h3>${escapeHtml(String(title))}</h3>
      <p>${escapeHtml(context || definition.geography)}</p>
    </div>
    <dl class="feature-grid">${fields}</dl>`;
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
  map.easeTo({
    center: [MADRID_CAMERA.lng, MADRID_CAMERA.lat],
    zoom: MADRID_CAMERA.zoom,
    bearing: 0,
    pitch: 0,
    duration: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 800,
  });
  void applyMapLayers();
}

async function shareView(): Promise<void> {
  scheduleHashUpdate(true);
  try {
    await navigator.clipboard.writeText(window.location.href);
    showToast("View link copied");
  } catch {
    showToast("Copy the URL to share this view");
  }
}

function renderSearchResults(): void {
  const query = searchInput.value.trim().toLocaleLowerCase("en");
  if (query.length < 2) {
    hideSearchResults();
    return;
  }
  const matches = places
    .filter((place) => `${place.name} ${place.district ?? ""}`.toLocaleLowerCase("en").includes(query))
    .slice(0, 8);
  if (matches.length === 0) {
    searchResults.innerHTML = '<p class="feature-empty" style="padding:8px">No place found.</p>';
  } else {
    searchResults.innerHTML = matches
      .map(
        (place) => `
        <button class="search-result" type="button" role="option" data-place="${escapeHtml(place.id)}">
          <span>${escapeHtml(place.name)}</span>
          <small>${escapeHtml(place.kind)}</small>
        </button>`,
      )
      .join("");
    searchResults.querySelectorAll<HTMLButtonElement>(".search-result").forEach((button) => {
      button.addEventListener("click", () => {
        const place = places.find((item) => item.id === button.dataset.place);
        if (place) selectPlace(place);
      });
    });
  }
  searchResults.hidden = false;
  searchInput.setAttribute("aria-expanded", "true");
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
  hideSearchResults();
}

function hideSearchResults(): void {
  searchResults.hidden = true;
  searchInput.setAttribute("aria-expanded", "false");
}

function setSheetOpen(open: boolean): void {
  panel.classList.toggle("is-open", open);
  sheetToggle.setAttribute("aria-expanded", String(open));
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

function formatValue(value: number | string, format: ValueFormat, suffix = ""): string {
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
      return `${new Intl.NumberFormat(locale, { maximumFractionDigits: 1 }).format(value)}%`;
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

function escapeHtml(value: string): string {
  const element = document.createElement("span");
  element.textContent = value;
  return element.innerHTML;
}
