import { gunzipSync } from 'node:zlib';
import { clientFor, workerEnv } from './shared.ts';

const env = workerEnv(), client = clientFor(env);
const origin = 'https://pricemapai.com';
const manifestResponse = await fetch(`${origin}/data/latest.json`, { cache: 'no-cache' });
if (!manifestResponse.ok) throw Error(`Manifest HTTP ${manifestResponse.status}`);
const manifest = await manifestResponse.json() as any;
const rows = (await Promise.all(manifest.offers.pages.map(async (path: string) => {
  if (!path.startsWith('/data/') || path.includes('..')) throw Error('Invalid public snapshot path');
  const response = await fetch(new URL(path, origin));
  if (!response.ok) throw Error(`Snapshot HTTP ${response.status}`);
  const buffer = Buffer.from(await response.arrayBuffer());
  const page = JSON.parse((path.endsWith('.gz') ? gunzipSync(buffer) : buffer).toString());
  if (page.version !== manifest.version || page.generated_at !== manifest.generated_at) throw Error('Mixed snapshot versions');
  return page.offers;
}))).flat();
const query = await client.from('offers').select('id,price,currency,stock_status,last_seen_at,expires_at')
  .not('hot_verified_at', 'is', null).lte('last_seen_at', manifest.generated_at).eq('active', true).limit(120);
if (query.error) throw Error(query.error.message);
if (!query.data.length) throw Error('No completed hot verification yet represented by this static snapshot');
for (const expected of query.data) {
  const actual = rows.find(row => row.id === expected.id);
  if (!actual || ['price', 'currency', 'stock_status'].some(key => actual[key] !== (expected as any)[key])
    || Date.parse(actual.last_seen_at) !== Date.parse(expected.last_seen_at)
    || Date.parse(actual.expires_at) !== Date.parse(expected.expires_at)) throw Error(`Hot quote not correctly published: ${expected.id}`);
  if ('hot_verified_at' in actual || 'raw_data' in actual || 'lease_token' in actual) throw Error('Private fields in public snapshot');
}
const adminResponse = await fetch(`${origin}/api/admin/sources`, { headers: { Authorization: `Bearer ${env.ADMIN_TOKEN}` } });
if (!adminResponse.ok) throw Error(`Admin HTTP ${adminResponse.status}`);
const admin = await adminResponse.json() as any;
if (!admin.sources.some((s: any) => s.hot_last_success_at)) throw Error('Admin has no separate verification timestamps');
console.log(JSON.stringify({ version: manifest.version, generated_at: manifest.generated_at,
  public_offers: rows.length, verified_quotes_matched: query.data.length,
  admin_hot_sources: admin.sources.filter((s: any) => s.hot_last_success_at).length }));
