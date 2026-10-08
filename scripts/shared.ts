import { readFileSync } from "node:fs";
import { createClient } from "@supabase/supabase-js";
import { safeUrl } from "../worker/network";
import type { Env, Source } from "../worker/types";

export type SourceConfig = Pick<Source, "name" | "base_url" | "collector" | "config" | "interval_minutes">;
export function readSources(): SourceConfig[] {
  const rows: SourceConfig[] = JSON.parse(readFileSync(new URL("../config/verified-sources.json", import.meta.url), "utf8"));
  const seen = new Set<string>();
  for (const row of rows) {
    const url = safeUrl(row.base_url);
    if (/(^|\.)priceai\.cc$/i.test(url.hostname)) throw new Error("来源配置必须是店铺原站，不能使用参考站作为采集源");
    if (seen.has(url.href)) throw new Error(`重复店铺：${row.base_url}`);
    seen.add(url.href);
  }
  return rows;
}

export function workerEnv(): Env {
  try { process.loadEnvFile(".dev.vars"); } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
  const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, ADMIN_TOKEN = "" } = process.env;
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) throw new Error("请先在 .dev.vars 配置自己的 Supabase 项目");
  return { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, ADMIN_TOKEN } as Env;
}
export const clientFor = (env: Env) => createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});
