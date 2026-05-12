import { useEffect, useRef } from "react";
import L from "leaflet";
import "leaflet/dist/leaflet.css";

interface Props {
  sr: number;
  o: number;
}

// Deterministic probability field based on sr and o.
// Center latitude shifts with sr, longitude shifts with o.
// Spread inversely related to sr*o.
function computeField(sr: number, o: number) {
  const centerLat = 60 - (sr / 100) * 120; // sr 0..100 -> 60..-60
  const centerLng = -180 + (o / 100) * 360; // o 0..100 -> -180..180
  const sigma = 8 + 40 / Math.max(0.5, (sr * o) / 500 + 0.5);
  return { centerLat, centerLng, sigma };
}

function gaussian(lat: number, lng: number, cLat: number, cLng: number, sigma: number) {
  const d2 = (lat - cLat) ** 2 + (lng - cLng) ** 2;
  return Math.exp(-d2 / (2 * sigma * sigma));
}

export function ProbabilityMap({ sr, o }: Props) {
  const mapEl = useRef<HTMLDivElement>(null);
  const mapRef = useRef<L.Map | null>(null);
  const layerRef = useRef<L.LayerGroup | null>(null);
  const markerRef = useRef<L.Marker | null>(null);

  useEffect(() => {
    if (!mapEl.current || mapRef.current) return;
    const map = L.map(mapEl.current, {
      center: [20, 0],
      zoom: 2,
      worldCopyJump: true,
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
    };
  }, []);

  useEffect(() => {
    const map = mapRef.current;
    const layer = layerRef.current;
    if (!map || !layer) return;
    layer.clearLayers();

    const { centerLat, centerLng, sigma } = computeField(sr, o);
    const step = 4;
    const cells: L.Rectangle[] = [];
    for (let lat = -80; lat < 80; lat += step) {
      for (let lng = -180; lng < 180; lng += step) {
        const p = gaussian(lat + step / 2, lng + step / 2, centerLat, centerLng, sigma);
        if (p < 0.05) continue;
        const hue = 220 - p * 220; // blue -> red
        const rect = L.rectangle(
          [
            [lat, lng],
            [lat + step, lng + step],
          ],
          {
            stroke: false,
            fillColor: `hsl(${hue}, 90%, 55%)`,
            fillOpacity: 0.15 + p * 0.55,
            interactive: false,
          }
        );
        rect.addTo(layer);
        cells.push(rect);
      }
    }

    // Peak marker
    if (markerRef.current) {
      markerRef.current.remove();
    }
    const icon = L.divIcon({
      className: "peak-marker",
      html: `<div class="peak-pulse"></div><div class="peak-dot"></div>`,
      iconSize: [24, 24],
      iconAnchor: [12, 12],
    });
    markerRef.current = L.marker([centerLat, centerLng], { icon })
      .addTo(layer)
      .bindTooltip(
        `<strong>Peak Probability</strong><br/>Lat ${centerLat.toFixed(2)}°, Lng ${centerLng.toFixed(2)}°`,
        { direction: "top", offset: [0, -10] }
      );
  }, [sr, o]);

  return <div ref={mapEl} className="absolute inset-0" />;
}

export function getPeak(sr: number, o: number) {
  const { centerLat, centerLng, sigma } = computeField(sr, o);
  return { lat: centerLat, lng: centerLng, sigma };
}