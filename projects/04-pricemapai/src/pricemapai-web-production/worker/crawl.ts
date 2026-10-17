import { createClient } from "@supabase/supabase-js";
import type { Env, Source } from "./types.ts";
import { collect } from "./collectors.ts";
import { classify } from "./classify.ts";
const db = (env: Pick<Env,"SUPABASE_URL"|"SUPABASE_SERVICE_ROLE_KEY">) => createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
function checked<T extends {error: any}>(result: T): T { if(result.error) throw new Error(result.error.message); return result; }
export async function crawl(env: Pick<Env,"SUPABASE_URL"|"SUPABASE_SERVICE_ROLE_KEY">, id?: string, batchSize = 64) {
  const client = db(env);
  const { data } = checked(
    await client.rpc("claim_sources", {
      batch_size: id ? 1 : batchSize,
      requested_id: id ?? null,
    }),
  );
  const results: { source: string; count?: number; error?: string; status: string }[] = [];
  const pending = [...(data ?? [])] as Source[];
  const started = Date.now();
  await Promise.all(Array.from({ length: 4 }, async () => {
   while (pending.length && Date.now() - started < 70000) {
    const source = pending.shift()!;
    const run = checked(
      await client
        .from("crawl_runs")
        .insert({ source_id: source.id })
        .select("id")
        .single(),
    ).data!;
    try {
      const snapshot = await collect(source);
      const normalized = snapshot.offers.map((o) => ({
        ...o,
        ...classify(o.raw_title),
        ...(o.raw_data?.price_note
          ? { review_required: true, comparison_key: null }
          : {}),
      }));
      checked(
        await client.rpc("complete_crawl", {
          p_source_id: source.id,
          p_lease_token: source.lease_token,
          p_run_id: run.id,
          p_offers: normalized,
          p_complete: snapshot.complete,
        }),
      );
      results.push({
        source: source.name,
        count: normalized.length,
        status: "success",
      });
    } catch (e) {
      const error = e instanceof Error ? e.message : "采集失败";
      checked(
        await client.rpc("complete_crawl", {
          p_source_id: source.id,
          p_lease_token: source.lease_token,
          p_run_id: run.id,
          p_offers: [],
          p_complete: false,
          p_error: error,
        }),
      );
      results.push({ source: source.name, error, status: "failed" });
    }
   }
  }));
  // Leave time for in-flight requests to finish within the free function duration.
  // Unstarted work returns to the queue instead of waiting out a ten-minute lease.
  if (pending.length) checked(await client.from("sources").update({ lease_until: null, lease_token: null })
    .in("id", pending.map(s => s.id)).in("lease_token", pending.map(s => s.lease_token)));
  return results;
}
