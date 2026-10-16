export type SampleValue = number | null;

export interface SampleQuery {
  strontiumCentral50: SampleValue;
  strontiumCentral90: SampleValue;
  oxygenPhosphateVsmowEnamel: SampleValue;
  oxygenCarbonateVsmowEnamel: SampleValue;
  oxygenCarbonateVpdbEnamel: SampleValue;
  oxygenDrinkingWaterVsmow: SampleValue;
}

export interface Coordinate {
  lat: number;
  lng: number;
}

export interface IsotopeFieldValue {
  sr: number;
  srError: number;
  oxygen: number;
  oxygenError: number;
}

export type IsotopeValue = IsotopeFieldValue;

export interface ProbabilityRasterCell {
  southWest: Coordinate;
  northEast: Coordinate;
  score: number;
}

export type ProbabilityCell = ProbabilityRasterCell;

export interface ProbabilityInput {
  key: keyof SampleQuery;
  label: string;
  target: number;
  kind: "sr" | "oxygen";
}

export interface ProbabilitySurfaceResult {
  cells: ProbabilityRasterCell[];
  maxScore: number;
  activeInputs: ProbabilityInput[];
}

export type ProbabilityGridResult = ProbabilitySurfaceResult;

export interface ProbabilityGridConfig {
  bounds?: Bounds;
  step?: number;
  srError?: number;
  oxygenError?: number;
  srTolerance?: number;
  oxygenTolerance?: number;
  maskProvider?: (coordinate: Coordinate) => boolean;
  fieldProvider?: (coordinate: Coordinate) => IsotopeFieldValue;
}

export interface Bounds {
  latMin: number;
  latMax: number;
  lngMin: number;
  lngMax: number;
}

type OxygenQueryKey =
  | "oxygenPhosphateVsmowEnamel"
  | "oxygenCarbonateVsmowEnamel"
  | "oxygenCarbonateVpdbEnamel"
  | "oxygenDrinkingWaterVsmow";

export const ASIA_BOUNDS: Bounds = {
  latMin: 0,
  latMax: 60,
  lngMin: 60,
  lngMax: 150,
};

export const DEFAULT_SR_ERROR = 0.0015;
export const DEFAULT_OXYGEN_ERROR = 3;

export const DEFAULT_GRID_CONFIG = {
  bounds: ASIA_BOUNDS,
  step: 0.35,
  srError: DEFAULT_SR_ERROR,
  oxygenError: DEFAULT_OXYGEN_ERROR,
} as const;

export const DEFAULT_QUERY: SampleQuery = {
  strontiumCentral50: null,
  strontiumCentral90: null,
  oxygenPhosphateVsmowEnamel: null,
  oxygenCarbonateVsmowEnamel: null,
  oxygenCarbonateVpdbEnamel: null,
  oxygenDrinkingWaterVsmow: null,
};

function isFiniteSampleValue(value: SampleValue): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

// Synthetic, deterministic isotope field over Asia. Replace this provider when
// a real raster, GeoJSON layer, or API-backed model is available.
export function fieldAt(coordinate: Coordinate): IsotopeFieldValue {
  const { lat, lng } = coordinate;
  const sr =
    0.7165 +
    0.012 * Math.sin((lat - 12) * 0.18) * Math.cos((lng - 95) * 0.07) +
    0.004 * Math.sin((lng + lat) * 0.05);
  const oxygen =
    -8 +
    7 * Math.sin((lat - 5) * 0.09) +
    3 * Math.cos((lng - 100) * 0.05) -
    0.06 * (lat - 25);

  return {
    sr,
    srError: DEFAULT_SR_ERROR,
    oxygen,
    oxygenError: DEFAULT_OXYGEN_ERROR,
  };
}

export function normalDensity(
  value: number,
  mean: number,
  standardDeviation: number,
): number {
  if (
    !Number.isFinite(value) ||
    !Number.isFinite(mean) ||
    !Number.isFinite(standardDeviation) ||
    standardDeviation <= 0
  ) {
    return 0;
  }

  const z = (value - mean) / standardDeviation;
  return (
    Math.exp(-0.5 * z * z) /
    (standardDeviation * Math.sqrt(2 * Math.PI))
  );
}

export function closenessScore(
  value: number,
  target: number,
  tolerance: number,
): number {
  if (!Number.isFinite(value) || !Number.isFinite(target)) {
    return 0;
  }

  if (tolerance === Number.POSITIVE_INFINITY) {
    return 1;
  }

  const safeTolerance = Math.max(Math.abs(tolerance), 1e-9);
  const normalizedDistance = (value - target) / safeTolerance;
  return Math.exp(-(normalizedDistance * normalizedDistance));
}

export function convertOxygenInputToWater(
  key: OxygenQueryKey,
  value: number,
): number {
  switch (key) {
    case "oxygenPhosphateVsmowEnamel":
      return (value - 23.3) / 0.94;
    case "oxygenCarbonateVsmowEnamel":
      return (value * 0.98 - 8.5 - 23.3) / 0.94;
    case "oxygenCarbonateVpdbEnamel": {
      const carbonateVsmow = value * 1.03092 + 30.92;
      return (carbonateVsmow * 0.98 - 8.5 - 23.3) / 0.94;
    }
    case "oxygenDrinkingWaterVsmow":
      return value;
  }
}

export function buildProbabilityInputs(query: SampleQuery): ProbabilityInput[] {
  const inputs: ProbabilityInput[] = [];

  if (isFiniteSampleValue(query.strontiumCentral50)) {
    inputs.push({
      key: "strontiumCentral50",
      label: "Sr central 50%",
      target: query.strontiumCentral50,
      kind: "sr",
    });
  }

  if (isFiniteSampleValue(query.strontiumCentral90)) {
    inputs.push({
      key: "strontiumCentral90",
      label: "Sr central 90%",
      target: query.strontiumCentral90,
      kind: "sr",
    });
  }

  const oxygenKeys: OxygenQueryKey[] = [
    "oxygenPhosphateVsmowEnamel",
    "oxygenCarbonateVsmowEnamel",
    "oxygenCarbonateVpdbEnamel",
    "oxygenDrinkingWaterVsmow",
  ];

  for (const key of oxygenKeys) {
    const value = query[key];
    if (!isFiniteSampleValue(value)) {
      continue;
    }

    inputs.push({
      key,
      label: key,
      target: convertOxygenInputToWater(key, value),
      kind: "oxygen",
    });
  }

  return inputs;
}

interface RawProbabilityCell {
  southWest: Coordinate;
  northEast: Coordinate;
  layerScores: number[];
}

export function calculateProbabilityGrid(
  query: SampleQuery,
  config: ProbabilityGridConfig = {},
): ProbabilitySurfaceResult {
  const bounds = config.bounds ?? DEFAULT_GRID_CONFIG.bounds;
  const step = config.step ?? DEFAULT_GRID_CONFIG.step;
  const srError =
    config.srError ?? config.srTolerance ?? DEFAULT_GRID_CONFIG.srError;
  const oxygenError =
    config.oxygenError ??
    config.oxygenTolerance ??
    DEFAULT_GRID_CONFIG.oxygenError;
  const maskProvider = config.maskProvider;
  const fieldProvider = config.fieldProvider ?? fieldAt;
  const activeInputs = buildProbabilityInputs(query);

  if (step <= 0) {
    throw new Error("Invalid probability grid configuration.");
  }

  if (activeInputs.length === 0) {
    return { cells: [], maxScore: 0, activeInputs };
  }

  const rawCells: RawProbabilityCell[] = [];
  const layerMaxes = activeInputs.map(() => 0);

  for (let lat = bounds.latMin; lat < bounds.latMax; lat += step) {
    for (let lng = bounds.lngMin; lng < bounds.lngMax; lng += step) {
      const southWest = { lat, lng };
      const northEast = {
        lat: Math.min(lat + step, bounds.latMax),
        lng: Math.min(lng + step, bounds.lngMax),
      };
      const center = {
        lat: southWest.lat + (northEast.lat - southWest.lat) / 2,
        lng: southWest.lng + (northEast.lng - southWest.lng) / 2,
      };

      if (maskProvider && !maskProvider(center)) {
        continue;
      }

      const field = fieldProvider(center);
      const layerScores = activeInputs.map((input, index) => {
        const score =
          input.kind === "sr"
            ? normalDensity(input.target, field.sr, field.srError || srError)
            : normalDensity(
                input.target,
                field.oxygen,
                field.oxygenError || oxygenError,
              );

        layerMaxes[index] = Math.max(layerMaxes[index], score);
        return score;
      });

      rawCells.push({ southWest, northEast, layerScores });
    }
  }

  const productScores = rawCells.map((cell) =>
    cell.layerScores.reduce((product, score, index) => {
      const layerMax = layerMaxes[index];
      return product * (layerMax > 0 ? score / layerMax : 0);
    }, 1),
  );
  const maxScore = productScores.reduce(
    (max, score) => Math.max(max, score),
    0,
  );

  const cells = rawCells.map((cell, index) => ({
    southWest: cell.southWest,
    northEast: cell.northEast,
    score: maxScore > 0 ? productScores[index] / maxScore : 0,
  }));

  return { cells, maxScore, activeInputs };
}
