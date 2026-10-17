import { timingSafeEqual } from 'node:crypto';
import { DurableObject } from 'cloudflare:workers';
import { buildSnapshot } from './build.ts';
import { mergeBatch, publicSnapshot, type Batch, type WorkingSnapshot } from './incremental.ts';
import { publishAssets, retainCurrentSnapshot } from './publish.ts';
import { normalizeHeatSource, type HeatSource } from '../src/lib/collection-heat.ts';

type Env = { CRAWLER_TOKEN: string; UMAMI_HEAT_TOKEN: string; CLOUDFLARE_SNAPSHOT_API_TOKEN: string; WORKING_SNAPSHOTS: R2Bucket; COORDINATOR: DurableObjectNamespace; PUBLISH_INTERVAL_SECONDS: string };
type Heat = { generated_at: string; sources: HeatSource[] };
function authorized(request: Request, env: Env) {
  const isHeat = new URL(request.url).pathname === '/heat';
  const a = new TextEncoder().encode(request.headers.get(isHeat ? 'X-Heat-Token' : 'X-Crawler-Token') ?? ''), b = new TextEncoder().encode((isHeat ? env.UMAMI_HEAT_TOKEN : env.CRAWLER_TOKEN) ?? '');
  return b.length > 0 && a.length === b.length && timingSafeEqual(a, b);
}
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method !== 'POST' || !authorized(request, env)) return new Response('Unauthorized', { status: 401 });
    if (!['/sync', '/heat', '/status'].includes(new URL(request.url).pathname)) return new Response('Not found', { status: 404 });
    // No parsing/compression in this 10ms Worker; the SQLite DO serializes work.
    return env.COORDINATOR.get(env.COORDINATOR.idFromName('public-snapshot')).fetch(request);
  }
};

export class SnapshotCoordinator extends DurableObject<Env> {
  private queue: Promise<unknown> = Promise.resolve();
  async fetch(request: Request): Promise<Response> {
    if (!authorized(request, this.env)) return new Response('Unauthorized', { status: 401 });
    const run = this.queue.then(() => this.handle(request));
    this.queue = run.catch(() => {});
    return run.catch(error => {
      console.error('Snapshot sync failed', String(error));
      return Response.json({ error: 'Sync failed; previous static publication retained' }, { status: 500 });
    });
  }
  private async handle(request: Request): Promise<Response> {
    const path = new URL(request.url).pathname;
    if (path === '/heat') {
      const heat = await request.json() as Heat;
      if (!Number.isFinite(Date.parse(heat.generated_at)) || Math.abs(Date.now() - Date.parse(heat.generated_at)) > 3600000 ||
          !Array.isArray(heat.sources) || heat.sources.length > 1000 || heat.sources.some(s => typeof s.id !== 'string' || s.id.length > 300 || !Number.isSafeInteger(s.clicks) || s.clicks < 0) || new Set(heat.sources.map(s=>s.id)).size !== heat.sources.length) return Response.json({ error: 'Invalid heat report' }, { status: 400 });
      try { heat.sources = heat.sources.map(normalizeHeatSource); }
      catch { return Response.json({ error: 'Invalid heat counters' }, { status: 400 }); }
      await this.ctx.storage.put('heat', heat);
      return Response.json({ received: heat.sources.length });
    }
    if (path === '/status') return Response.json({ publication: await this.ctx.storage.get('publication') ?? null, heat: await this.ctx.storage.get('heat') ?? null });
    const batch = await request.json() as Batch;
    const object = await this.env.WORKING_SNAPSHOTS.get('working/latest.json');
    const previous = object ? await object.json<WorkingSnapshot>() : null;
    let state: WorkingSnapshot;
    try { state = mergeBatch(previous, batch); }
    catch (error) {
      if (String(error).includes('Full snapshot required')) return Response.json({ need_full: true }, { status: 409 });
      throw error;
    }
    // Durable R2 checkpoint BEFORE acknowledgement; retries are idempotent.
    if (state !== previous) await this.env.WORKING_SNAPSHOTS.put('working/latest.json', JSON.stringify(state), { httpMetadata: { contentType: 'application/json' } });
    const publication = await this.ctx.storage.get<{ at: number; revision: number; version: string }>('publication');
    if ((!publication || (state.dirty_revision ?? state.revision) > publication.revision) && (!publication || Date.now() - publication.at >= Number(this.env.PUBLISH_INTERVAL_SECONDS) * 1000)) {
      const snapshot = await buildSnapshot(publicSnapshot(state));
      const previousFiles = await retainCurrentSnapshot();
      await publishAssets({ ...previousFiles, ...snapshot.files }, this.env.CLOUDFLARE_SNAPSHOT_API_TOKEN);
      await this.ctx.storage.put('publication', { at: Date.now(), revision: state.revision, version: snapshot.manifest.version });
    }
    return Response.json({ acknowledged_revision: state.revision, publication: await this.ctx.storage.get('publication'), heat: await this.ctx.storage.get('heat') ?? null });
  }
}
