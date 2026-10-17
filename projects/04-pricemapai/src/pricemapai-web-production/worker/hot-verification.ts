import { createClient } from '@supabase/supabase-js';
import { collect } from './collectors.ts';
import { classify } from './classify.ts';
import type { Candidate, Env, Source } from './types.ts';

type HotSource = Source & { hot_run_id: string; hot_external_ids: string[] };
type Result = { source: string; status: string; verified?: number; error?: string };
export const normalizeHotOffers = (offers: Candidate[], externalIds: string[]) => {
  const selected = new Set(externalIds);
  return offers.filter(o => selected.has(o.external_id)).map(o => ({
    ...o, ...classify(o.raw_title),
    ...(o.raw_data?.price_note ? { review_required: true, comparison_key: null } : {}),
  }));
};

export async function verifyHotOffers(env: Pick<Env, 'SUPABASE_URL' | 'SUPABASE_SERVICE_ROLE_KEY'>) {
  const client = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY,
    { auth: { persistSession: false, autoRefreshToken: false } });
  const claimed = await client.rpc('claim_hot_sources', { batch_size: 6 });
  if (claimed.error) throw new Error(claimed.error.message);
  const pending = [...(claimed.data ?? [])] as HotSource[];
  const results: Result[] = [];
  const started = Date.now();
  await Promise.all(Array.from({ length: 3 }, async () => {
    while (pending.length && Date.now() - started < 70000) {
      const source = pending.shift()!;
      let payload: Record<string, unknown>;
      try {
        const snapshot = await collect(source);
        payload = { p_offers: normalizeHotOffers(snapshot.offers, source.hot_external_ids), p_complete: snapshot.complete };
      } catch (error) {
        payload = { p_offers: [], p_complete: false, p_error: error instanceof Error ? error.message : 'Verification failed' };
      }
      const completed = await client.rpc('complete_hot_verification', {
        p_run_id: source.hot_run_id, p_lease_token: source.lease_token, ...payload,
      });
      if (completed.error) throw new Error(completed.error.message);
      results.push({ source: source.name, status: payload.p_error ? 'failed' : 'success', verified: completed.data,
        ...(payload.p_error ? { error: String(payload.p_error) } : {}) });
    }
  }));
  // Cancel unstarted jobs through the same RPC so both the job and shared lease finish.
  for (const source of pending) {
    const result = await client.rpc('complete_hot_verification', {
      p_run_id: source.hot_run_id, p_lease_token: source.lease_token,
      p_offers: [], p_complete: false, p_error: 'Verification execution budget exhausted',
    });
    if (result.error) throw new Error(result.error.message);
  }
  return results;
}
