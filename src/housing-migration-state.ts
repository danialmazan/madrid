export type SectionOutcome = "share" | "change";
export type DistrictOutcome = "count" | "change";

export interface AnalysisState {
  districtCodes: string[];
  sectionOutcome: SectionOutcome;
  districtOutcome: DistrictOutcome;
}

export const DEFAULT_ANALYSIS_STATE: AnalysisState = {
  districtCodes: ["11"],
  sectionOutcome: "share",
  districtOutcome: "count",
};

export function parseAnalysisState(hash: string, validCodes: ReadonlySet<string>): AnalysisState {
  const params = new URLSearchParams(hash.replace(/^#/, ""));
  const districtCodes = (params.get("districts") ?? "")
    .split(",")
    .filter((code, index, values) => validCodes.has(code) && values.indexOf(code) === index)
    .slice(0, 3);
  const sectionOutcome = params.get("section") === "change" ? "change" : "share";
  const districtOutcome = params.get("district") === "change" ? "change" : "count";
  return {
    districtCodes: districtCodes.length ? districtCodes : [...DEFAULT_ANALYSIS_STATE.districtCodes],
    sectionOutcome,
    districtOutcome,
  };
}

export function serialiseAnalysisState(state: AnalysisState): string {
  const params = new URLSearchParams();
  params.set("districts", state.districtCodes.join(","));
  params.set("section", state.sectionOutcome);
  params.set("district", state.districtOutcome);
  return `#${params.toString()}`;
}

export function toggleDistrict(codes: readonly string[], code: string, maximum = 3): string[] {
  if (codes.includes(code)) {
    return codes.length === 1 ? [...codes] : codes.filter((item) => item !== code);
  }
  return codes.length >= maximum ? [...codes] : [...codes, code];
}
