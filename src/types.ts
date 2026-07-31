export type LayerGroup = "population" | "buildings" | "elections" | "income" | "transport";
export type LayerKind = "choropleth" | "fill" | "fill-extrusion" | "transport-line" | "transport-stop";
export type ValueFormat = "integer" | "decimal" | "percent" | "currency" | "year" | "text";
export type ElectionKey = "general" | "local" | "assembly";

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
  election?: ElectionKey;
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
  election: ElectionKey;
  party: string;
  transport: string[];
  route: string;
  camera: CameraState;
  is3d: boolean;
  selectedSection: string | null;
  reportOpen: boolean;
}

export interface ReportMetricValue {
  value: number | null;
  percentile: number | null;
}

export interface ReportDistribution {
  label: string;
  format: ValueFormat;
  unit: string;
  breaks: number[];
  counts: number[];
  observationCount: number;
  minimum: number | null;
  maximum: number | null;
  percentileValues: number[];
  percentileRanks: number[];
}

export interface ReportVintageMatch {
  sectionId: string;
  overlapShare: number;
  boundaryChanged: boolean;
}

export interface ReportElectionResult {
  key: string;
  label: string;
  color: string;
  share: number | null;
  votes?: number;
}

export interface SectionElectionReport {
  turnoutPct: number | null;
  validVotes: number | null;
  blankVotes: number | null;
  leadingParty: string | null;
  results: ReportElectionResult[];
}

export interface CityElectionReport {
  label: string;
  referenceDate: string;
  census: number;
  votesCast: number;
  validVotes: number;
  blankVotes: number;
  turnoutPct: number;
  shownCoveragePct: number;
  results: ReportElectionResult[];
}

export interface BuildingReport {
  buildingCount: number;
  dwellings: number;
  medianConstructionYear: number | null;
  constructionEras: number[];
}

export interface SectionReport {
  id: string;
  name: string;
  district: string;
  matches: Record<"2023" | "2025", ReportVintageMatch>;
  population: Record<string, ReportMetricValue>;
  income: Record<string, ReportMetricValue>;
  elections: Record<ElectionKey, SectionElectionReport>;
  buildings: BuildingReport;
}

export interface SectionReportIndex {
  generatedAt: string;
  version: string;
  canonicalVintage: "2026";
  geographyVintages: {
    canonical: string;
    foreignBorn: string;
    incomeAndElections: string;
  };
  dataDates: {
    population: string;
    foreignBorn: string;
    income: string;
    buildings: string;
  };
  methodologyUrl: string;
  distributions: Record<string, ReportDistribution>;
  constructionEras: string[];
  cityBuildings: BuildingReport;
  cityElections: Record<ElectionKey, CityElectionReport>;
  references: SourceReference[];
  sections: Record<string, SectionReport>;
}
