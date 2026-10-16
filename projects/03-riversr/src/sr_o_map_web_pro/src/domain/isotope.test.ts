import { describe, expect, it } from "vitest";

import {
  DEFAULT_QUERY,
  buildProbabilityInputs,
  calculateProbabilityGrid,
  convertOxygenInputToWater,
  fieldAt,
  normalDensity,
  type Coordinate,
  type IsotopeFieldValue,
  type ProbabilityGridConfig,
  type SampleQuery,
} from "./isotope";

const FILLED_QUERY: SampleQuery = {
  strontiumCentral50: 0.7134,
  strontiumCentral90: 0.7165,
  oxygenPhosphateVsmowEnamel: 17.63,
  oxygenCarbonateVsmowEnamel: 26.46,
  oxygenCarbonateVpdbEnamel: -4.27,
  oxygenDrinkingWaterVsmow: -6.75,
};

const TEST_GRID_CONFIG: ProbabilityGridConfig = {
  bounds: { latMin: 0, latMax: 4, lngMin: 0, lngMax: 4 },
  step: 1,
  fieldProvider: ({ lat, lng }: Coordinate): IsotopeFieldValue => ({
    sr: 0.71 + lng * 0.001,
    srError: 0.001,
    oxygen: -10 + lat,
    oxygenError: 1,
  }),
};

function expectNormalizedSurface(cells: { score: number }[]) {
  expect(cells.length).toBeGreaterThan(0);
  expect(cells.every((cell) => cell.score >= 0 && cell.score <= 1)).toBe(true);
  expect(Math.max(...cells.map((cell) => cell.score))).toBeCloseTo(1);
}

function highProbabilityCellCount(cells: { score: number }[]) {
  return cells.filter((cell) => cell.score >= 0.5).length;
}

describe("fieldAt", () => {
  it("returns deterministic isotope values in expected synthetic ranges", () => {
    const first = fieldAt({ lat: 30, lng: 100 });
    const second = fieldAt({ lat: 30, lng: 100 });

    expect(second).toEqual(first);
    expect(first.sr).toBeGreaterThan(0.704);
    expect(first.sr).toBeLessThan(0.73);
    expect(first.srError).toBeGreaterThan(0);
    expect(first.oxygen).toBeGreaterThan(-18);
    expect(first.oxygen).toBeLessThan(4);
    expect(first.oxygenError).toBeGreaterThan(0);
  });
});

describe("normalDensity", () => {
  it("is highest at the mean and decays with distance", () => {
    expect(normalDensity(10, 10, 2)).toBeGreaterThan(
      normalDensity(12, 10, 2),
    );
    expect(normalDensity(12, 10, 2)).toBeGreaterThan(
      normalDensity(16, 10, 2),
    );
  });

  it("returns zero for invalid values or non-positive standard deviation", () => {
    expect(normalDensity(Number.NaN, 10, 2)).toBe(0);
    expect(normalDensity(10, Number.POSITIVE_INFINITY, 2)).toBe(0);
    expect(normalDensity(10, 10, 0)).toBe(0);
    expect(normalDensity(10, 10, -1)).toBe(0);
  });
});

describe("convertOxygenInputToWater", () => {
  it("converts phosphate enamel VSMOW to drinking water target", () => {
    expect(
      convertOxygenInputToWater("oxygenPhosphateVsmowEnamel", 17.63),
    ).toBeCloseTo((17.63 - 23.3) / 0.94);
  });

  it("converts carbonate enamel VSMOW to drinking water target", () => {
    expect(
      convertOxygenInputToWater("oxygenCarbonateVsmowEnamel", 26.46),
    ).toBeCloseTo((26.46 * 0.98 - 8.5 - 23.3) / 0.94);
  });

  it("converts carbonate enamel VPDB to drinking water target", () => {
    const carbonateVsmow = -4.27 * 1.03092 + 30.92;

    expect(
      convertOxygenInputToWater("oxygenCarbonateVpdbEnamel", -4.27),
    ).toBeCloseTo((carbonateVsmow * 0.98 - 8.5 - 23.3) / 0.94);
  });

  it("keeps drinking water VSMOW values unchanged", () => {
    expect(
      convertOxygenInputToWater("oxygenDrinkingWaterVsmow", -6.75),
    ).toBe(-6.75);
  });
});

describe("buildProbabilityInputs", () => {
  it("keeps all six entered values as independent constraints", () => {
    const inputs = buildProbabilityInputs(FILLED_QUERY);

    expect(inputs).toHaveLength(6);
    expect(inputs.filter((input) => input.kind === "sr")).toHaveLength(2);
    expect(inputs.filter((input) => input.kind === "oxygen")).toHaveLength(4);
  });

  it("ignores empty values", () => {
    expect(buildProbabilityInputs(DEFAULT_QUERY)).toHaveLength(0);
  });
});

describe("calculateProbabilityGrid", () => {
  it("returns no probability layer before sample values are entered", () => {
    const result = calculateProbabilityGrid(DEFAULT_QUERY, TEST_GRID_CONFIG);

    expect(result.cells).toHaveLength(0);
    expect(result.maxScore).toBe(0);
    expect(result.activeInputs).toHaveLength(0);
  });

  it("returns a normalized China-region surface for a single Sr input", () => {
    const result = calculateProbabilityGrid(
      { ...DEFAULT_QUERY, strontiumCentral50: 0.712 },
      TEST_GRID_CONFIG,
    );

    expect(result.activeInputs).toHaveLength(1);
    expectNormalizedSurface(result.cells);
  });

  it("returns a normalized China-region surface for a single O input", () => {
    const result = calculateProbabilityGrid(
      { ...DEFAULT_QUERY, oxygenDrinkingWaterVsmow: -8 },
      TEST_GRID_CONFIG,
    );

    expect(result.activeInputs).toHaveLength(1);
    expectNormalizedSurface(result.cells);
  });

  it("keeps all cells inside the configured mask", () => {
    const result = calculateProbabilityGrid(
      { ...DEFAULT_QUERY, strontiumCentral50: 0.712 },
      {
        ...TEST_GRID_CONFIG,
        maskProvider: ({ lng }) => lng < 3,
      },
    );

    expect(result.cells).toHaveLength(12);
    expect(
      result.cells.every((cell) => {
        const centerLng =
          cell.southWest.lng + (cell.northEast.lng - cell.southWest.lng) / 2;

        return centerLng < 3;
      }),
    ).toBe(true);
  });

  it("combines independent inputs into a more constrained surface", () => {
    const srOnly = calculateProbabilityGrid(
      { ...DEFAULT_QUERY, strontiumCentral50: 0.712 },
      TEST_GRID_CONFIG,
    );
    const srAndOxygen = calculateProbabilityGrid(
      {
        ...DEFAULT_QUERY,
        strontiumCentral50: 0.712,
        oxygenDrinkingWaterVsmow: -8,
      },
      TEST_GRID_CONFIG,
    );

    expectNormalizedSurface(srAndOxygen.cells);
    expect(highProbabilityCellCount(srAndOxygen.cells)).toBeLessThan(
      highProbabilityCellCount(srOnly.cells),
    );
  });
});
