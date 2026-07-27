export type LayerGroup = "population" | "buildings" | "elections" | "income" | "transport";
export type LayerKind = "choropleth" | "fill" | "fill-extrusion" | "transport-line" | "transport-stop";
export type ValueFormat = "integer" | "decimal" | "percent" | "currency" | "year" | "text";

export interface SourceDefinition {
  id: string;
  url: string;
  sourceLayer: string;
  attribution: string;
  minzoom?: number;
  maxzoom?: number;
}

export interface TooltipField {
  property: string;
  label: string;
  format: ValueFormat;
  suffix?: string;
  percentileProperty?: string;
}

export interface ElectionResultField {
  property: string;
  label: string;
  color: string;
}

export interface LayerControl {
  election?: "general" | "local" | "assembly";
  party?: string;
  transportMode?: "metro" | "metro-ligero" | "cercanias" | "emt" | "bicimad";
  routeProperty?: string;
  routes?: Array<{ value: string; label: string }>;
  results?: ElectionResultField[];
}

export interface LayerDefinition {
  id: string;
  group: LayerGroup;
  kind: LayerKind;
  label: string;
  shortLabel?: string;
  description: string;
  methodology?: string;
  unit: string;
  referenceDate: string;
  geography: string;
  sourceIds: string[];
  property: string;
  palette: string[];
  breaks: number[];
  format: ValueFormat;
  minzoom?: number;
  maxzoom?: number;
  opacity?: number;
  lineColor?: string;
  lineWidth?: number;
  tooltip: TooltipField[];
  control?: LayerControl;
}

export interface SourceReference {
  title: string;
  organisation: string;
  url: string;
  licence: string;
  retrieved: string;
}

export interface LayerManifest {
  generatedAt: string;
  version: string;
  defaultLayer: string;
  sources: SourceDefinition[];
  layers: LayerDefinition[];
  references: SourceReference[];
  notes: string[];
}

export interface Place {
  id: string;
  name: string;
  kind: "district" | "neighbourhood";
  district?: string;
  bbox: [number, number, number, number];
}

export type AddressRecord = [
  id: string,
  name: string,
  district: string,
  longitude: number,
  latitude: number,
];

export interface AddressIndex {
  referenceDate: string;
  records: AddressRecord[];
}

export interface CameraState {
  lng: number;
  lat: number;
  zoom: number;
  bearing: number;
  pitch: number;
}

export interface AtlasState {
  group: LayerGroup;
  layer: string;
  dataLayerVisible: boolean;
  election: "general" | "local" | "assembly";
  party: string;
  transport: string[];
  route: string;
  camera: CameraState;
  is3d: boolean;
}
