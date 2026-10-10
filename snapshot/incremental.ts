import type { PublicSnapshot } from './build.ts';

export type Patch = { path: string[]; value?: unknown; remove?: true };
export type Change = { key: string; value?: unknown; patches?: Patch[]; remove?: true };
export type Batch = { schema: 1; revision: number; base_revision: number; full: boolean; generated_at: string; changes: Change[] };
export type WorkingSnapshot = { revision: number; dirty_revision?: number; generated_at: string; entities: Record<string, any> };
const forbidden = new Set(['__proto__', 'prototype', 'constructor']);

/** Validate and apply into a copy: a failed batch must not partially advance state. */
export function mergeBatch(previous: WorkingSnapshot | null, batch: Batch): WorkingSnapshot {
  if (batch.schema !== 1 || !Number.isSafeInteger(batch.revision) || batch.revision < 1 ||
      !Number.isSafeInteger(batch.base_revision) || !Number.isFinite(Date.parse(batch.generated_at)) || !Array.isArray(batch.changes)) throw Error('Invalid batch');
  if (previous && batch.revision <= previous.revision) return previous;
  if (!batch.full && (!previous || previous.revision !== batch.base_revision)) throw Error('Full snapshot required');
  const changed = batch.full || batch.changes.length > 0;
  const result: WorkingSnapshot = { revision: batch.revision, dirty_revision: changed ? batch.revision : previous!.dirty_revision ?? previous!.revision,
    generated_at: changed ? batch.generated_at : previous!.generated_at, entities: batch.full ? {} : structuredClone(previous!.entities) };
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
    } else if (key.startsWith('transit:')) transit.push(row);
  }
  return { generated_at: state.generated_at, offers, transit };
}
