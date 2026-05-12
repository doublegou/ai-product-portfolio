import { useEffect, useRef, useState } from "react";
import type * as LType from "leaflet";

export interface Range {
  min: number;
  max: number;
}

interface Props {
  sr: Range;
  o: Range;
}

// Asia bounding box for the synthetic field.
const ASIA = { latMin: 0, latMax: 60, lngMin: 60, lngMax: 150 };

// Deterministic synthetic isotope field over Asia.
// Returns expected Sr (87Sr/86Sr ~ 0.704–0.730) and δ18O (~ -18 .. 0 ‰ VSMOW)
// at a given lat/lng. Smooth, repeatable functions — replace with real data later.
function fieldAt(lat: number, lng: number) {
  const sr =
    0.7165 +
    0.012 * Math.sin((lat - 12) * 0.18) * Math.cos((lng - 95) * 0.07) +
    0.004 * Math.sin((lng + lat) * 0.05);
  const o =
    -8 +
    7 * Math.sin((lat - 5) * 0.09) +
    3 * Math.cos((lng - 100) * 0.05) -
    0.06 * (lat - 25);
  return { sr, o };
}

function inRangeScore(value: number, r: Range) {
  const lo = Math.min(r.min, r.max);
  const hi = Math.max(r.min, r.max);
  const mid = (lo + hi) / 2;
  const half = Math.max((hi - lo) / 2, 1e-9);
  // 1.0 in the middle, ~0.6 at the edge, falls off outside
  const x = (value - mid) / half;
  return Math.exp(-(x * x) * 0.9);
}

export function ProbabilityMap({ sr, o }: Props) {
  const mapEl = useRef<HTMLDivElement>(null);
  const mapRef = useRef<LType.Map | null>(null);
  const layerRef = useRef<LType.LayerGroup | null>(null);
  const markerRef = useRef<LType.Marker | null>(null);
  const [L, setL] = useState<typeof LType | null>(null);

  // Client-only leaflet load (avoid SSR window error)
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const mod = await import("leaflet");
      await import("leaflet/dist/leaflet.css");
      if (!cancelled) setL(mod.default ?? (mod as unknown as typeof LType));
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!L || !mapEl.current || mapRef.current) return;
    const map = L.map(mapEl.current, {
      center: [30, 100],
      zoom: 4,
      minZoom: 3,
      zoomControl: false,
      attributionControl: false,
    });
    L.tileLayer(
      "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png",
      { subdomains: "abcd", maxZoom: 19 }
    ).addTo(map);
    L.control.zoom({ position: "bottomright" }).addTo(map);
    layerRef.current = L.layerGroup().addTo(map);
    mapRef.current = map;
    return () => {
      map.remove();
      mapRef.current = null;
      layerRef.current = null;
    };
  }, [L]);

  useEffect(() => {
    if (!L) return;
    const map = mapRef.current;
    const layer = layerRef.current;
    if (!map || !layer) return;
    layer.clearLayers();

    const step = 0.6; // finer resolution -> smaller cells
    let peak = { lat: 30, lng: 100, p: -1 };

    for (let lat = ASIA.latMin; lat < ASIA.latMax; lat += step) {
      for (let lng = ASIA.lngMin; lng < ASIA.lngMax; lng += step) {
        const cLat = lat + step / 2;
        const cLng = lng + step / 2;
        const v = fieldAt(cLat, cLng);
        const p = inRangeScore(v.sr, sr) * inRangeScore(v.o, o);
        if (p < 0.55) continue;
        const t = (p - 0.55) / 0.45; // 0..1
        const hue = 45 - t * 45; // gold -> red
        L.rectangle(
          [
            [lat, lng],
            [lat + step, lng + step],
          ],
          {
            stroke: false,
            fillColor: `hsl(${hue}, 90%, 52%)`,
            fillOpacity: 0.25 + t * 0.55,
            interactive: false,
          }
        ).addTo(layer);
        if (p > peak.p) peak = { lat: cLat, lng: cLng, p };
      }
    }

    if (markerRef.current) markerRef.current.remove();
    if (peak.p > 0) {
      const icon = L.divIcon({
        className: "peak-marker",
        html: `<div class="peak-pulse"></div><div class="peak-dot"></div>`,
        iconSize: [24, 24],
        iconAnchor: [12, 12],
      });
      markerRef.current = L.marker([peak.lat, peak.lng], { icon })
        .addTo(layer)
        .bindTooltip(
          `<strong>Most likely region</strong><br/>Lat ${peak.lat.toFixed(2)}°, Lng ${peak.lng.toFixed(2)}°`,
          { direction: "top", offset: [0, -10] }
        );
    }
  }, [L, sr.min, sr.max, o.min, o.max]);

  return <div ref={mapEl} className="absolute inset-0" />;
}