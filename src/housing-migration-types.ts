export interface AnalysisSource {
  publisher: string;
  title: string;
  url: string;
  geography: string;
  vintage: string;
  status: string;
}

export interface ConstructionYearQuantiles {
  p10: number | null;
  q1: number | null;
  median: number | null;
  q3: number | null;
  p90: number | null;
}

export interface AnalysisSection {
  id: string;
  districtCode: string;
  districtName: string;
  foreignBornPct2025: number;
  foreignBornChangePp: number | null;
  residentialBuildingCount: number;
  dwellingCount: number;
  constructionYear: ConstructionYearQuantiles;
  medianYearBucket: { startYear: number | null; label: string | null };
}

export interface DistrictCohort {
  order: number;
  startYear: number | null;
  label: string;
  buildingCount: number;
  dwellingCount: number;
  buildingSharePct: number;
  dwellingSharePct: number;
}

export interface AnalysisDistrict {
  code: string;
  name: string;
  sectionCount: number;
  residentialBuildingCount: number;
  dwellingCount: number;
  shareDwellings1961To1970Pct: number;
  foreignBorn: {
    population2021: number;
    population2025: number;
    count2021: number;
    count2025: number;
    countChange: number;
    growthPct: number;
    share2021: number;
    share2025: number;
    shareChangePp: number;
  };
  distribution: DistrictCohort[];
}

export interface HousingMigrationAnalysis {
  version: "1.0.0";
  generatedAt: string;
  title: string;
  canonicalGeography: string;
  defaultDistrictCode: string;
  maximumDistrictSelections: number;
  sources: AnalysisSource[];
  calculationNotes: Record<string, string>;
  coverage: {
    currentSections: number;
    sectionsWithResidentialBuildings: number;
    sectionsWithPositiveDwellingWeight: number;
    sectionsWithForeignBorn2025: number;
    comparableSectionChanges: number;
    missingSectionChanges: number;
    residentialBuildings: number;
    zeroDwellingResidentialBuildings: number;
    recordedDwellings: number;
    buildingSectionAssignmentPct: number;
  };
  districts: AnalysisDistrict[];
  sections: AnalysisSection[];
}
