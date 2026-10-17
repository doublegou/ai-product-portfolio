import {publicOfferRows, publicTransitRows} from './public-fields.ts';
import { validateOffer } from '../src/data/client.ts';
import type { SnapshotManifest } from '../src/data/snapshot.ts';
export type PublicSnapshot = { generated_at: string; offers: unknown[]; transit: unknown[] };
export const SNAPSHOT_HEADERS = `/data/latest.json
  Cache-Control: public, max-age=60, s-maxage=60, must-revalidate
/data/v/*
  Cache-Control: public, max-age=31536000, immutable
/data/*
  X-Content-Type-Options: nosniff
  Strict-Transport-Security: max-age=15552000
  X-Robots-Tag: noindex
`;
export async function buildSnapshot(input: PublicSnapshot) {
  if (!input || !Number.isFinite(Date.parse(input.generated_at)) || !Array.isArray(input.offers) || !Array.isArray(input.transit)) throw Error('Invalid public snapshot');
  input={...input,offers:publicOfferRows(input.offers),transit:publicTransitRows(input.transit)};
  for (const row of input.offers) validateOffer(row);
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(input)));
  const version = Array.from(new Uint8Array(digest), n => n.toString(16).padStart(2, '0')).join('').slice(0, 24);
  const manifest: SnapshotManifest = { schema: 1, version, generated_at: input.generated_at, offers: { count: input.offers.length, pages: [] }, transit: { count: input.transit.length, pages: [] } };
  const files: Record<string, Uint8Array<ArrayBuffer>> = {};
  for (const kind of ['offers', 'transit'] as const) {
    const size = kind === 'offers' ? 1000 : 2;
    for (let offset = 0, page = 0; offset < input[kind].length || page === 0; offset += size, page++) {
      const path = `/data/v/${version}/${kind}-${page}.json.gz`;
      const content = JSON.stringify({ version, generated_at: input.generated_at, [kind]: input[kind].slice(offset, offset + size) });
      const compressed = new Blob([content]).stream().pipeThrough(new CompressionStream('gzip'));
      files[path] = new Uint8Array(await new Response(compressed).arrayBuffer());
      if (files[path].length > 24 * 1024 * 1024) throw Error('Snapshot page exceeds static asset size limit');
      manifest[kind].pages.push(path);
    }
  }
  files['/data/latest.json'] = new TextEncoder().encode(JSON.stringify(manifest));
  return { manifest, files };
}
