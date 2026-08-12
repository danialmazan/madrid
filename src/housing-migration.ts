import "./housing-migration.css";
import {
  DISTRICT_COLOURS,
  renderCityDiagnosticChart,
  renderCohortOutcomeChart,
  renderDistributionChart,
  renderSectionAgeChart,
} from "./housing-migration-charts";
import {
  parseAnalysisState,
  serialiseAnalysisState,
  toggleDistrict,
} from "./housing-migration-state";
import type { HousingMigrationAnalysis } from "./housing-migration-types";

const required = <T extends Element>(selector: string): T => {
  const element = document.querySelector<T>(selector);
  if (!element) throw new Error(`Missing required element ${selector}`);
  return element;
};

const fetchAnalysis = async (): Promise<HousingMigrationAnalysis> => {
  const response = await fetch(`${import.meta.env.BASE_URL}data/housing-migration-analysis.json`);
  if (!response.ok) throw new Error(`Could not load analysis data (${response.status})`);
  return response.json() as Promise<HousingMigrationAnalysis>;
};

const formatSigned = (value: number): string => value.toLocaleString("en-GB", { signDisplay: "always" });

function buildSources(data: HousingMigrationAnalysis): void {
  const list = required<HTMLElement>("#source-list");
  list.replaceChildren();
  for (const source of data.sources) {
    const article = document.createElement("article");
    const heading = document.createElement("h3");
    const link = document.createElement("a");
    link.href = source.url;
    link.textContent = source.title;
    link.target = "_blank";
    link.rel = "noreferrer";
    heading.append(link);
    const publisher = document.createElement("p");
    publisher.textContent = `${source.publisher} · ${source.vintage}`;
    const detail = document.createElement("p");
    detail.textContent = `${source.geography}. ${source.status}.`;
    article.append(heading, publisher, detail);
    list.append(article);
  }
}

function populateFacts(data: HousingMigrationAnalysis): void {
  const carabanchel = data.districts.find((district) => district.code === "11");
  if (!carabanchel) throw new Error("Carabanchel is missing from the analysis payload");
  required("#hero-sixties-share").textContent = `${carabanchel.shareDwellings1961To1970Pct.toFixed(1)}%`;
  required("#hero-migration-change").textContent = formatSigned(carabanchel.foreignBorn.countChange);
  required("#hero-city-dwellings").textContent = data.coverage.recordedDwellings.toLocaleString("en-GB");
  required("#coverage-note").textContent = `Coverage: ${data.coverage.residentialBuildings.toLocaleString("en-GB")} residential building records with valid construction years; ${data.coverage.recordedDwellings.toLocaleString("en-GB")} recorded dwellings; ${data.coverage.sectionsWithPositiveDwellingWeight.toLocaleString("en-GB")} of ${data.coverage.currentSections.toLocaleString("en-GB")} current sections have positive dwelling weight. Generated ${new Date(data.generatedAt).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" })}.`;
  required("#city-diagnostic-reading").textContent = `Carabanchel combines a ${carabanchel.shareDwellings1961To1970Pct.toFixed(1)}% 1961–1970 dwelling share with ${formatSigned(carabanchel.foreignBorn.countChange)} foreign-born residents from 2021 to 2025. Compare that with Latina, Moratalaz, Ciudad Lineal and Puente de Vallecas: similar or older housing profiles do not produce one uniform migration outcome.`;
}

function initialise(data: HousingMigrationAnalysis): void {
  const validCodes = new Set(data.districts.map((district) => district.code));
  let state = parseAnalysisState(window.location.hash, validCodes);
  const selector = required<HTMLElement>("#district-selector");
  const selectionMessage = required<HTMLElement>("#selection-message");
  const legend = required<HTMLElement>("#district-legend");
  const chartElements = {
    sectionAge: required<HTMLElement>("#section-age-chart"),
    distribution: required<HTMLElement>("#distribution-chart"),
    cohortOutcome: required<HTMLElement>("#cohort-outcome-chart"),
    cityDiagnostic: required<HTMLElement>("#city-diagnostic-chart"),
  };

  const updateUrl = (): void => {
    const hash = serialiseAnalysisState(state);
    if (window.location.hash !== hash) history.replaceState(null, "", hash);
  };

  const renderSelector = (): void => {
    selector.replaceChildren();
    const atLimit = state.districtCodes.length >= data.maximumDistrictSelections;
    for (const district of [...data.districts].sort((a, b) => a.name.localeCompare(b.name))) {
      const label = document.createElement("label");
      label.className = "district-option";
      const input = document.createElement("input");
      input.type = "checkbox";
      input.value = district.code;
      input.checked = state.districtCodes.includes(district.code);
      input.disabled = atLimit && !input.checked;
      const swatch = document.createElement("i");
      swatch.style.setProperty("--district-colour", DISTRICT_COLOURS[district.code] ?? "#176b87");
      const name = document.createElement("span");
      name.textContent = district.name;
      input.addEventListener("change", () => {
        state = { ...state, districtCodes: toggleDistrict(state.districtCodes, district.code, data.maximumDistrictSelections) };
        renderAll();
      });
      label.append(input, swatch, name);
      selector.append(label);
    }
    const names = state.districtCodes.map((code) => data.districts.find((district) => district.code === code)?.name).filter(Boolean);
    selectionMessage.textContent = atLimit
      ? `${names.join(", ")} selected. Three-district comparison limit reached.`
      : `${names.join(", ")} selected. Add ${data.maximumDistrictSelections - state.districtCodes.length} more.`;
  };

  const renderLegend = (): void => {
    legend.replaceChildren();
    for (const code of state.districtCodes) {
      const district = data.districts.find((item) => item.code === code);
      if (!district) continue;
      const item = document.createElement("span");
      const swatch = document.createElement("i");
      swatch.style.background = DISTRICT_COLOURS[code] ?? "#176b87";
      item.append(swatch, district.name);
      legend.append(item);
    }
  };

  const syncRadios = (): void => {
    for (const input of document.querySelectorAll<HTMLInputElement>('input[name="section-outcome"]')) input.checked = input.value === state.sectionOutcome;
    for (const input of document.querySelectorAll<HTMLInputElement>('input[name="district-outcome"]')) input.checked = input.value === state.districtOutcome;
  };

  const renderCharts = (): void => {
    const context = { data, districtCodes: state.districtCodes };
    renderSectionAgeChart(chartElements.sectionAge, context);
    renderDistributionChart(chartElements.distribution, context);
    renderCohortOutcomeChart(chartElements.cohortOutcome, context, state.sectionOutcome);
    renderCityDiagnosticChart(chartElements.cityDiagnostic, context, state.districtOutcome);
  };

  const renderAll = (): void => {
    updateUrl();
    renderSelector();
    renderLegend();
    syncRadios();
    renderCharts();
  };

  for (const input of document.querySelectorAll<HTMLInputElement>('input[name="section-outcome"]')) {
    input.addEventListener("change", () => {
      state = { ...state, sectionOutcome: input.value === "change" ? "change" : "share" };
      renderAll();
    });
  }
  for (const input of document.querySelectorAll<HTMLInputElement>('input[name="district-outcome"]')) {
    input.addEventListener("change", () => {
      state = { ...state, districtOutcome: input.value === "change" ? "change" : "count" };
      renderAll();
    });
  }
  window.addEventListener("hashchange", () => {
    state = parseAnalysisState(window.location.hash, validCodes);
    renderAll();
  });

  renderAll();
}

document.body.classList.add("is-loading");
fetchAnalysis()
  .then((data) => {
    populateFacts(data);
    buildSources(data);
    initialise(data);
    document.body.classList.remove("is-loading");
  })
  .catch((error: unknown) => {
    document.body.classList.remove("is-loading");
    document.body.classList.add("has-error");
    const message = document.createElement("p");
    message.className = "load-error";
    message.textContent = error instanceof Error ? error.message : "The analysis could not be loaded.";
    required("#analysis").prepend(message);
  });
