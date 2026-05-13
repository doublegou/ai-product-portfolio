import { useEffect, useMemo, useRef } from "react";
import L, {
  type ImageOverlay,
  type Map as LeafletMap,
  type LatLngBoundsExpression,
} from "leaflet";
import type { GeoJsonObject } from "geojson";

import {
  CHINA_BOUNDARY,
  CHINA_CENTER,
  CHINA_GRID_BOUNDS,
  CHINA_VIEW_BOUNDS,
  isCoordinateInChina,
} from "../data/chinaBoundary";
import {
  DEFAULT_GRID_CONFIG,
  type Bounds,
  type Coordinate,
  type ProbabilityGridConfig,
  type ProbabilityRasterCell,
  calculateProbabilityGrid,
  type SampleQuery,
} from "../domain/isotope";

interface ProbabilityMapProps {
  query: SampleQuery;
  gridConfig?: ProbabilityGridConfig;
}

interface RgbaColor {
  r: number;
  g: number;
  b: number;
  a: number;
}

const PROBABILITY_STOPS = [
  { value: 0, color: { r: 255, g: 255, b: 255, a: 18 } },
  { value: 0.18, color: { r: 251, g: 220, b: 209, a: 58 } },
  { value: 0.36, color: { r: 239, g: 178, b: 97, a: 98 } },
  { value: 0.54, color: { r: 224, g: 216, b: 53, a: 138 } },
  { value: 0.74, color: { r: 130, g: 205, b: 47, a: 176 } },
  { value: 1, color: { r: 0, g: 166, b: 38, a: 214 } },
] as const;

const SURFACE_CANVAS_WIDTH = 920;
const MOUNTAIN_BANDS: Coordinate[][] = [
  [
    { lat: 41.4, lng: 75.0 },
    { lat: 39.4, lng: 82.0 },
    { lat: 37.4, lng: 90.0 },
    { lat: 36.0, lng: 98.0 },
    { lat: 35.8, lng: 106.0 },
  ],
  [
    { lat: 31.0, lng: 78.0 },
    { lat: 30.4, lng: 85.5 },
    { lat: 30.0, lng: 93.0 },
    { lat: 29.2, lng: 101.0 },
  ],
  [
    { lat: 41.0, lng: 94.0 },
    { lat: 38.0, lng: 100.0 },
    { lat: 36.0, lng: 106.0 },
    { lat: 34.4, lng: 111.0 },
  ],
];

function fitMapToChina(map: LeafletMap, animate = true) {
  const isCompact = window.matchMedia("(max-width: 760px)").matches;

  map.fitBounds(CHINA_VIEW_BOUNDS, {
    animate,
    maxZoom: 5,
    paddingBottomRight: isCompact ? [20, 340] : [420, 60],
    paddingTopLeft: isCompact ? [20, 80] : [44, 72],
  });
}

function addChinaBoundary(map: LeafletMap) {
  const haloPane = map.createPane("china-boundary-halo");
  haloPane.style.zIndex = "455";
  const boundaryPane = map.createPane("china-boundary");
  boundaryPane.style.zIndex = "456";

  L.geoJSON(CHINA_BOUNDARY as GeoJsonObject, {
    interactive: false,
    pane: "china-boundary-halo",
    style: {
      color: "#ffffff",
      fill: false,
      lineCap: "round",
      lineJoin: "round",
      opacity: 0.42,
      weight: 3,
    },
  }).addTo(map);

  L.geoJSON(CHINA_BOUNDARY as GeoJsonObject, {
    interactive: false,
    pane: "china-boundary",
    style: {
      color: "#5f91ad",
      fill: true,
      fillColor: "#2368a2",
      fillOpacity: 0.014,
      lineCap: "round",
      lineJoin: "round",
      opacity: 0.5,
      weight: 1.35,
    },
  }).addTo(map);
}

function addRecenterControl(map: LeafletMap) {
  const recenterControl = new L.Control({ position: "bottomright" });

  recenterControl.onAdd = () => {
    const container = L.DomUtil.create(
      "div",
      "leaflet-control leaflet-control-recenter",
    );
    const button = L.DomUtil.create(
      "button",
      "recenter-control-button",
      container,
    );

    button.type = "button";
    button.title = "Recenter on China";
    button.setAttribute("aria-label", "Recenter map on China");
    button.innerHTML = '<span class="recenter-target" aria-hidden="true"></span>';

    L.DomEvent.disableClickPropagation(container);
    L.DomEvent.disableScrollPropagation(container);
    L.DomEvent.on(button, "click", () => fitMapToChina(map));

    return container;
  };

  recenterControl.addTo(map);
}

function colorForProbability(score: number): RgbaColor {
  const safeScore = Math.max(0, Math.min(1, score));

  for (let index = 1; index < PROBABILITY_STOPS.length; index += 1) {
    const previous = PROBABILITY_STOPS[index - 1];
    const next = PROBABILITY_STOPS[index];

    if (safeScore > next.value) {
      continue;
    }

    const range = next.value - previous.value || 1;
    const amount = (safeScore - previous.value) / range;

    return {
      r: Math.round(previous.color.r + (next.color.r - previous.color.r) * amount),
      g: Math.round(previous.color.g + (next.color.g - previous.color.g) * amount),
      b: Math.round(previous.color.b + (next.color.b - previous.color.b) * amount),
      a: Math.round(previous.color.a + (next.color.a - previous.color.a) * amount),
    };
  }

  return PROBABILITY_STOPS[PROBABILITY_STOPS.length - 1].color;
}

function gaussian(
  coordinate: Coordinate,
  center: Coordinate,
  spread: Coordinate,
  weight: number,
): number {
  const latDistance = (coordinate.lat - center.lat) / spread.lat;
  const lngDistance = (coordinate.lng - center.lng) / spread.lng;

  return weight * Math.exp(-0.5 * (latDistance ** 2 + lngDistance ** 2));
}

function scaledPoint(coordinate: Coordinate) {
  const longitudeScale = Math.cos((coordinate.lat * Math.PI) / 180);

  return {
    x: coordinate.lng * longitudeScale,
    y: coordinate.lat,
  };
}

function distanceToSegment(
  coordinate: Coordinate,
  start: Coordinate,
  end: Coordinate,
): number {
  const point = scaledPoint(coordinate);
  const from = scaledPoint(start);
  const to = scaledPoint(end);
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  const lengthSquared = dx * dx + dy * dy;

  if (lengthSquared === 0) {
    return Math.hypot(point.x - from.x, point.y - from.y);
  }

  const amount = Math.max(
    0,
    Math.min(1, ((point.x - from.x) * dx + (point.y - from.y) * dy) / lengthSquared),
  );
  const projected = {
    x: from.x + amount * dx,
    y: from.y + amount * dy,
  };

  return Math.hypot(point.x - projected.x, point.y - projected.y);
}

function bandScore(
  coordinate: Coordinate,
  path: Coordinate[],
  spread: number,
  weight: number,
): number {
  let minDistance = Number.POSITIVE_INFINITY;

  for (let index = 1; index < path.length; index += 1) {
    minDistance = Math.min(
      minDistance,
      distanceToSegment(coordinate, path[index - 1], path[index]),
    );
  }

  return weight * Math.exp(-0.5 * (minDistance / spread) ** 2);
}

function smoothStep(value: number): number {
  return value * value * (3 - 2 * value);
}

function hashNoise(x: number, y: number): number {
  const value = Math.sin(x * 127.1 + y * 311.7) * 43758.5453123;

  return value - Math.floor(value);
}

function valueNoise(coordinate: Coordinate, scale: number): number {
  const x = coordinate.lng / scale;
  const y = coordinate.lat / scale;
  const x0 = Math.floor(x);
  const y0 = Math.floor(y);
  const tx = smoothStep(x - x0);
  const ty = smoothStep(y - y0);
  const top =
    hashNoise(x0, y0) * (1 - tx) + hashNoise(x0 + 1, y0) * tx;
  const bottom =
    hashNoise(x0, y0 + 1) * (1 - tx) + hashNoise(x0 + 1, y0 + 1) * tx;

  return top * (1 - ty) + bottom * ty;
}

function textureAt(coordinate: Coordinate): number {
  return (
    valueNoise(coordinate, 2.8) * 0.5 +
    valueNoise(coordinate, 1.35) * 0.32 +
    valueNoise(coordinate, 0.62) * 0.18
  );
}

function displayProbabilityAt(coordinate: Coordinate): number {
  const ridgeScore =
    bandScore(coordinate, MOUNTAIN_BANDS[0], 1.75, 0.42) +
    bandScore(coordinate, MOUNTAIN_BANDS[1], 1.35, 0.34) +
    bandScore(coordinate, MOUNTAIN_BANDS[2], 1.65, 0.28);
  const centralPatch = gaussian(
    coordinate,
    { lat: 36.8, lng: 108.4 },
    { lat: 4.2, lng: 3.2 },
    0.32,
  );
  const westernPatch = gaussian(
    coordinate,
    { lat: 39.5, lng: 80.0 },
    { lat: 3.8, lng: 5.0 },
    0.3,
  );
  const southWestPatch = gaussian(
    coordinate,
    { lat: 25.5, lng: 100.0 },
    { lat: 4.0, lng: 4.5 },
    0.2,
  );
  const eastLowWash = gaussian(
    coordinate,
    { lat: 34.0, lng: 116.0 },
    { lat: 10.0, lng: 9.0 },
    0.08,
  );
  const nationalWash = gaussian(
    coordinate,
    { lat: 34.0, lng: 101.0 },
    { lat: 13.0, lng: 22.0 },
    0.1,
  );
  const texture = textureAt(coordinate);
  const ruggedness = 0.45 + texture * 0.9;
  const speckle = Math.max(0, texture - 0.55) * 0.18;

  return Math.max(
    0.04,
    Math.min(
      1,
      0.055 +
        ridgeScore * ruggedness +
        centralPatch * (0.72 + texture * 0.38) +
        westernPatch * ruggedness +
        southWestPatch * (0.62 + texture * 0.3) +
        eastLowWash +
        nationalWash +
        speckle,
    ),
  );
}

function probabilityOverlayBounds(bounds: Bounds): LatLngBoundsExpression {
  return [
    [bounds.latMin, bounds.lngMin],
    [bounds.latMax, bounds.lngMax],
  ];
}

function renderProbabilitySurface(
  cells: ProbabilityRasterCell[],
  bounds: Bounds,
): string | null {
  if (cells.length === 0) {
    return null;
  }

  const lngRange = bounds.lngMax - bounds.lngMin;
  const latRange = bounds.latMax - bounds.latMin;
  const columns = SURFACE_CANVAS_WIDTH;
  const rows = Math.max(1, Math.round(columns * (latRange / lngRange)));
  const canvas = document.createElement("canvas");
  canvas.width = columns;
  canvas.height = rows;

  const context = canvas.getContext("2d");
  if (!context) {
    return null;
  }

  const imageData = context.createImageData(columns, rows);
  const northWest = L.CRS.EPSG3857.project(L.latLng(bounds.latMax, bounds.lngMin));
  const southEast = L.CRS.EPSG3857.project(L.latLng(bounds.latMin, bounds.lngMax));
  const projectedWidth = southEast.x - northWest.x;
  const projectedHeight = southEast.y - northWest.y;

  for (let y = 0; y < rows; y += 1) {
    for (let x = 0; x < columns; x += 1) {
      const projected = L.point(
        northWest.x + ((x + 0.5) / columns) * projectedWidth,
        northWest.y + ((y + 0.5) / rows) * projectedHeight,
      );
      const latLng = L.CRS.EPSG3857.unproject(projected);
      const coordinate = { lat: latLng.lat, lng: latLng.lng };

      if (!isCoordinateInChina(coordinate)) {
        continue;
      }

      const offset = (y * columns + x) * 4;
      const color = colorForProbability(displayProbabilityAt(coordinate));

      imageData.data[offset] = color.r;
      imageData.data[offset + 1] = color.g;
      imageData.data[offset + 2] = color.b;
      imageData.data[offset + 3] = color.a;
    }
  }

  context.putImageData(imageData, 0, 0);
  return canvas.toDataURL("image/png");
}

export function ProbabilityMap({ query, gridConfig }: ProbabilityMapProps) {
  const mapEl = useRef<HTMLDivElement>(null);
  const mapRef = useRef<LeafletMap | null>(null);
  const overlayRef = useRef<ImageOverlay | null>(null);

  const effectiveGridConfig = useMemo<ProbabilityGridConfig>(
    () => ({
      bounds: CHINA_GRID_BOUNDS,
      maskProvider: isCoordinateInChina,
      ...gridConfig,
    }),
    [gridConfig],
  );

  const grid = useMemo(
    () => calculateProbabilityGrid(query, effectiveGridConfig),
    [effectiveGridConfig, query],
  );

  useEffect(() => {
    if (!mapEl.current || mapRef.current) {
      return;
    }

    const map = L.map(mapEl.current, {
      center: CHINA_CENTER,
      zoom: 4,
      minZoom: 3,
      maxZoom: 8,
      zoomControl: false,
      attributionControl: false,
    });

    map.createPane("probability-surface").style.zIndex = "440";

    L.tileLayer(
      "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png",
      {
        subdomains: "abcd",
        maxZoom: 19,
      },
    ).addTo(map);

    addChinaBoundary(map);
    L.control.zoom({ position: "bottomright" }).addTo(map);
    addRecenterControl(map);
    mapRef.current = map;

    window.requestAnimationFrame(() => {
      map.invalidateSize();
      fitMapToChina(map, false);
    });

    return () => {
      map.remove();
      mapRef.current = null;
      overlayRef.current = null;
    };
  }, []);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) {
      return;
    }

    if (overlayRef.current) {
      overlayRef.current.remove();
      overlayRef.current = null;
    }

    const bounds = effectiveGridConfig.bounds ?? DEFAULT_GRID_CONFIG.bounds;
    const imageUrl = renderProbabilitySurface(grid.cells, bounds);

    if (!imageUrl) {
      return;
    }

    overlayRef.current = L.imageOverlay(imageUrl, probabilityOverlayBounds(bounds), {
      className: "probability-surface",
      interactive: false,
      opacity: 1,
      pane: "probability-surface",
    }).addTo(map);
  }, [effectiveGridConfig.bounds, grid.cells]);

  return (
    <section
      aria-label="Probability map of isotope domains across China"
      className="map-region"
    >
      <div ref={mapEl} className="map-canvas" />
    </section>
  );
}
