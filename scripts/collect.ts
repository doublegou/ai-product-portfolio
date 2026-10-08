import { collect } from "../worker/collectors";
import { classify } from "../worker/classify";
import { crawl } from "../worker/index";
import type { Source } from "../worker/types";
import { readSources, workerEnv, clientFor } from "./shared";

try {
  const args = process.argv.slice(2);
  const rows = readSources();
  if (args.includes("--initial") && args.includes("--write")) {
    const env = workerEnv();
    const { data, error } = await clientFor(env).from("sources").select("id,name")
      .eq("enabled", true).is("last_success_at", null).is("last_error", null).order("created_at");
    if (error) throw error;
    const pending = [...(data ?? [])];
    const totals = { success: 0, failed: 0, skipped: 0, offers: 0 };
    // Two independent shops at a time; database leases prevent overlap with Cron.
    await Promise.all(Array.from({ length: 2 }, async () => {
      while (pending.length) {
        const source = pending.shift()!;
        const results = await crawl(env, source.id);
        if (!results.length) totals.skipped++;
        for (const result of results) {
          if (result.status === "success") { totals.success++; totals.offers += result.count ?? 0; }
          else totals.failed++;
          console.log(JSON.stringify(result));
        }
      }
    }));
    console.log(JSON.stringify({ initial_collection: totals }));
    if (totals.failed) process.exitCode = 1;
  } else if (args.includes("--due") && args.includes("--write")) {
    const results = await crawl(workerEnv());
    console.log(JSON.stringify(results, null, 2));
    if (results.some(row => row.status === "failed")) process.exitCode = 1;
  } else {
    const key = args[args.indexOf("--source") + 1];
    if (!args.includes("--source") || !key) throw new Error("用法：npm run collect -- --source 店铺原站地址 [--write]，或 --due --write / --initial --write");
    const source = rows.find(row => row.base_url === key || row.name === key);
    if (!source) throw new Error("未找到店铺，请先加入 config/verified-sources.json");
    if (args.includes("--write")) {
      const env = workerEnv();
      const { data, error } = await clientFor(env).from("sources").select("id").eq("base_url", source.base_url).single();
      if (error || !data) throw new Error("数据库中未找到该来源，请先执行 sources:import -- --write");
      const results = await crawl(env, data.id);
      if (!results.length) throw new Error("该来源已暂停或正在采集中，本次未领取任务");
      console.log(JSON.stringify(results, null, 2));
      if (results.some(row => row.status === "failed")) process.exitCode = 1;
    } else {
      const snapshot = await collect({ ...source, id: "preview", enabled: true, lease_token: "", next_crawl_at: "", last_success_at: null, last_error: null } satisfies Source);
      console.log(JSON.stringify({ source: source.base_url, count: snapshot.offers.length, complete: snapshot.complete,
        preview: snapshot.offers.slice(0, 5).map(offer => ({ ...offer, ...classify(offer.raw_title),
          ...(offer.raw_data?.price_note ? { review_required: true, comparison_key: null } : {}) })), written: false }, null, 2));
    }
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : "采集失败");
  process.exitCode = 1;
}
