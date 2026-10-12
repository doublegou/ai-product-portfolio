import type { PublicSnapshot } from './build.ts';
import { createHash } from 'node:crypto';

export type Patch = { path: string[]; value?: unknown; remove?: true };
export type Change = { key: string; value?: unknown; patches?: Patch[]; remove?: true };
export type Batch = { schema: 1 | 2; revision: number; base_revision: number; full: boolean; generated_at: string; changes: Change[] };
export type WorkingSnapshot = { revision: number; dirty_revision?: number; generated_at: string; entities: Record<string, any> };
const forbidden = new Set(['__proto__', 'prototype', 'constructor']);

// Schema 2 indexes prices by stable IDs, independent of array order or length.
// Convert the existing checkpoint locally so upgrading needs no full transfer.
export function indexedTransit(row: any) {
  if (!Array.isArray(row?.data?.prices)) return row;
  const prices: Record<string, any> = {};
  for (const price of row.data.prices) {
    if (typeof price.id !== 'string' || !price.id) throw Error('Missing stable price ID');
    const key = createHash('md5').update(price.id).digest('hex');
    if (Object.hasOwn(prices, key)) throw Error('Duplicate price ID');
    prices[key] = price;
  }
  return { ...row, data: { ...row.data, prices } };
}

/** Validate and apply into a copy: a failed batch must not partially advance state. */
export function mergeBatch(previous: WorkingSnapshot | null, batch: Batch): WorkingSnapshot {
  if (![1, 2].includes(batch.schema) || !Number.isSafeInteger(batch.revision) || batch.revision < 1 ||
      !Number.isSafeInteger(batch.base_revision) || !Number.isFinite(Date.parse(batch.generated_at)) || !Array.isArray(batch.changes)) throw Error('Invalid batch');
  if (previous && batch.revision <= previous.revision) return previous;
  if (!batch.full && (!previous || previous.revision !== batch.base_revision)) throw Error('Full snapshot required');
  const changed = batch.full || batch.changes.length > 0;
  const result: WorkingSnapshot = { revision: batch.revision, dirty_revision: changed ? batch.revision : previous!.dirty_revision ?? previous!.revision,
    generated_at: changed ? batch.generated_at : previous!.generated_at, entities: batch.full ? {} : structuredClone(previous!.entities) };
  if (batch.schema === 2) {
    for (const key of Object.keys(result.entities)) {
      if (key.startsWith('transit:')) result.entities[key] = indexedTransit(result.entities[key]);
    }
  }
  for (const change of batch.changes) {
    if (!/^(offers|transit|freshness):[a-zA-Z0-9:-]+$/.test(change.key)) throw Error('Invalid entity key');
    if (change.remove) { delete result.entities[change.key]; continue; }
    if (Object.hasOwn(change, 'value')) { result.entities[change.key] = structuredClone(change.value); continue; }
    if (!Array.isArray(change.patches) || !Object.hasOwn(result.entities, change.key)) throw Error('Missing patch base');
    for (const patch of change.patches) {
      if (!Array.isArray(patch.path) || patch.path.some(part => typeof part !== 'string' || forbidden.has(part))) throw Error('Unsafe patch path');
      if (!patch.path.length) {
        if (patch.remove) throw Error('Cannot remove patch root');
        result.entities[change.key] = structuredClone(patch.value); continue;
      }
      let target = result.entities[change.key];
      for (const part of patch.path.slice(0, -1)) {
        if (!target || typeof target !== 'object' || !Object.hasOwn(target, part)) throw Error('Missing patch parent');
        target = target[part];
      }
      if (!target || typeof target !== 'object') throw Error('Invalid patch parent');
      const key = patch.path.at(-1)!;
      if (Array.isArray(target) && (!/^\d+$/.test(key) || Number(key) >= target.length || patch.remove)) throw Error('Invalid array patch');
      if (patch.remove) delete target[key]; else target[key] = structuredClone(patch.value);
    }
  }
  return result;
}

export function publicSnapshot(state: WorkingSnapshot): PublicSnapshot {
  const offers: any[] = [], transit: any[] = [];
  for (const key of Object.keys(state.entities).sort()) {
    const row = state.entities[key];
    if (key.startsWith('offers:')) {
      const heartbeat = state.entities[`freshness:${row._source_id}`];
      if (!heartbeat) throw Error('Missing offer freshness');
      offers.push({ last_seen_at: heartbeat.last_seen_at, expires_at: heartbeat.expires_at, ...row });
    } else if (key.startsWith('transit:')) transit.push(Array.isArray(row.data?.prices) ? row :
      { ...row, data: { ...row.data, prices: Object.keys(row.data.prices).sort().map(id => row.data.prices[id]) } });
  }
  return { generated_at: state.generated_at, offers, transit };
}
