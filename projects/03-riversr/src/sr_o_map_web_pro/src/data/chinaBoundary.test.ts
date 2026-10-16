import { describe, expect, it } from "vitest";

import { isCoordinateInChina } from "./chinaBoundary";

describe("isCoordinateInChina", () => {
  it("includes coordinates inside China and excludes nearby countries", () => {
    expect(isCoordinateInChina({ lat: 39.9042, lng: 116.4074 })).toBe(true);
    expect(isCoordinateInChina({ lat: 35.6762, lng: 139.6503 })).toBe(false);
  });
});
