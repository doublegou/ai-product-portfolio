import { timingSafeEqual } from "node:crypto";
import { createClient } from "@supabase/supabase-js";
import type { Env } from "./types";
import { collect } from "./collectors";
import { classify } from "./classify";
import { safeUrl } from "./network";
import { crawl } from "./crawl";
import { publicTransit, adminTransit } from "./transit-routes";
export { crawl } from "./crawl";
const db = (env: Env) =>
  createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
const json = (body: unknown, status = 200, cache = false) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json;charset=utf-8",
      "Cache-Control": cache ? "public,max-age=60" : "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
function checked<T extends { error: any }>(result: T): T {
  if (result.error) throw new Error(result.error.message);
  return result;
}
async function authorized(req: Request, env: Env) {
  if (!env.ADMIN_TOKEN) return false;
  const expected = new TextEncoder().encode(`Bearer ${env.ADMIN_TOKEN}`),
    actual = new TextEncoder().encode(req.headers.get("Authorization") ?? "");
  if (expected.length !== actual.length) return false;
  return timingSafeEqual(expected, actual);
}
async function runCrawl(env: Env, id?: string) {
  if (!env.CRAWLER_FUNCTION_URL) return crawl(env, id);
  const response = await fetch(env.CRAWLER_FUNCTION_URL, {
    method: "POST", headers: { Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`, "Content-Type": "application/json", "X-Crawler-Token": env.CRAWLER_TOKEN ?? "" },
    body: JSON.stringify({ source_id: id }), signal: AbortSignal.timeout(140000),
  });
  if (!response.ok) throw new Error(`采集服务 HTTP ${response.status}`);
  const data = await response.json() as { results: Awaited<ReturnType<typeof crawl>> };
  return data.results;
}
export default {
  async fetch(req: Request, env: Env, ctx?: ExecutionContext): Promise<Response> {
    const url = new URL(req.url);
    if (
      url.pathname === "/admin" ||
      url.pathname.startsWith("/admin/") ||
      url.pathname === "/admin.html"
    ) {
      // Assets serves admin.html at its canonical /admin URL.
      const assetUrl = new URL("/admin", url);
      const response = await env.ASSETS.fetch(new Request(assetUrl, req));
      const headers = new Headers(response.headers);
      headers.set("Cache-Control", "no-store");
      headers.set("X-Robots-Tag", "noindex, nofollow");
      return new Response(response.body, { status: response.status, headers });
    }
    if (!url.pathname.startsWith("/api/")) return env.ASSETS.fetch(req);
    if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) {
      return json({ error: "数据服务尚未配置", code: "DATA_SERVICE_NOT_CONFIGURED" }, 503);
    }
    try {
      const client = db(env);
      if (url.pathname === "/api/transit" && req.method === "GET") return await publicTransit(req, env, ctx);
      if (url.pathname === "/api/health") {
        checked(
          await client
            .from("sources")
            .select("id", { count: "exact", head: true }),
        );
        return json({ ok: true });
      }
      if (url.pathname === "/api/offers" && req.method === "GET") {
        const offset = Number(url.searchParams.get("offset") ?? 0);
        const limit = Number(url.searchParams.get("limit") ?? 1000);
        if (
          !Number.isSafeInteger(offset) ||
          offset < 0 ||
          !Number.isInteger(limit) ||
          limit < 1 ||
          limit > 1000
        )
          return json({ error: "分页参数无效" }, 400);
        const { data, count } = checked(
          await client
            .from("offers")
            .select(
              "id,raw_title,platform,plan,delivery,duration_days,comparison_key,review_required,price,currency,stock_status,purchase_url,last_seen_at,expires_at,sources(name,base_url),price_note:raw_data->>price_note,stock_quantity:raw_data->stock_quantity,stock_text:raw_data->>stock_text",
              { count: "exact" },
            )
            .eq("active", true)
            .order("id")
            .range(offset, offset + limit - 1),
        );
        return json(
          {
            offers: data,
            total: count,
            next_offset:
              offset + (data?.length ?? 0) < (count ?? 0)
                ? offset + (data?.length ?? 0)
                : null,
            generated_at: new Date().toISOString(),
          },
          200,
          true,
        );
      }
      if (url.pathname === "/api/stats" && req.method === "GET") {
        const source = checked(
          await client
            .from("sources")
            .select("id,last_success_at,last_error,enabled"),
        );
        const runs = checked(
          await client
            .from("crawl_runs")
            .select("status,started_at,offer_count")
            .order("started_at", { ascending: false })
            .limit(20),
        );
        return json(
          {
            sources: source.data?.length ?? 0,
            healthy:
              source.data?.filter((s) => s.last_success_at && !s.last_error)
                .length ?? 0,
            last_success:
              source.data
                ?.map((s) => s.last_success_at)
                .filter(Boolean)
                .sort()
                .at(-1) ?? null,
            runs: runs.data,
          },
          200,
          true,
        );
      }
      const history = url.pathname.match(/^\/api\/history\/([0-9a-f-]{36})$/);
      if (history && req.method === "GET") {
        const offer = checked(
          await client
            .from("offers")
            .select("id")
            .eq("id", history[1])
            .eq("active", true)
            .maybeSingle(),
        );
        if (!offer.data) return json({ error: "报价不存在" }, 404);
        const { data } = checked(
          await client
            .from("price_history")
            .select("price,currency,stock_status,observed_at")
            .eq("offer_id", history[1])
            .order("observed_at", { ascending: false })
            .limit(60),
        );
        return json({ history: data }, 200, true);
      }
      if (!url.pathname.startsWith("/api/admin/"))
        return json({ error: "Not found" }, 404);
      if (!(await authorized(req, env)))
        return json({ error: "管理密钥无效" }, 401);
      if (url.pathname.startsWith("/api/admin/transit/")) return await adminTransit(req, env, client);
      if (url.pathname === "/api/admin/sources" && req.method === "GET")
        return json({
          sources: checked(
            await client.from("sources").select("*").order("created_at"),
          ).data,
        });
      if (url.pathname === "/api/admin/runs" && req.method === "GET")
        return json({
          runs: checked(
            await client
              .from("crawl_runs")
              .select("*,sources(name)")
              .order("started_at", { ascending: false })
              .limit(50),
          ).data,
        });
      if (
        (url.pathname === "/api/admin/sources" ||
          url.pathname === "/api/admin/preview") &&
        req.method === "POST"
      ) {
        if (Number(req.headers.get("content-length") ?? 0) > 16000)
          return json({ error: "请求过大" }, 413);
        const body = await req.text();
        if (body.length > 16000) return json({ error: "请求过大" }, 413);
        const b = JSON.parse(body);
        const u = safeUrl(b.base_url);
        if (
          !["kami", "dujiao", "16688", "shopapi", "json", "html"].includes(
            b.collector,
          ) ||
          typeof b.name !== "string" ||
          !b.name.trim() ||
          b.name.length > 100
        )
          return json({ error: "请填写来源名称与采集器类型" }, 400);
        const interval = Number(b.interval_minutes ?? 15);
        if (!Number.isInteger(interval) || interval < 15 || interval > 10080)
          return json({ error: "采集间隔须为 15–10080 分钟" }, 400);
        if (
          b.config &&
          (typeof b.config !== "object" || Array.isArray(b.config))
        )
          return json({ error: "配置必须为 JSON 对象" }, 400);
        const row = {
          name: b.name.trim(),
          base_url: u.href,
          collector: b.collector,
          interval_minutes: interval,
          config: b.config ?? {},
          enabled: b.enabled !== false,
        };
        if (url.pathname === "/api/admin/preview") {
          const snapshot = await collect({
            ...row,
            id: "preview",
            lease_token: "",
            last_success_at: null,
            last_error: null,
            next_crawl_at: new Date().toISOString(),
          });
          return json({
            count: snapshot.offers.length,
            complete: snapshot.complete,
            offers: snapshot.offers
              .slice(0, 10)
              .map((offer) => ({
                ...offer,
                ...classify(offer.raw_title),
                ...(offer.raw_data?.price_note
                  ? { review_required: true, comparison_key: null }
                  : {}),
              })),
          });
        }
        return json(
          {
            source: checked(
              await client.from("sources").insert(row).select().single(),
            ).data,
          },
          201,
        );
      }
      const sourceRoute = url.pathname.match(
        /^\/api\/admin\/sources\/([0-9a-f-]{36})$/,
      );
      if (sourceRoute && req.method === "PATCH") {
        const b = (await req.json()) as any;
        const changes: Record<string, unknown> = {};
        if (b.enabled !== undefined) {
          if (typeof b.enabled !== "boolean")
            return json({ error: "enabled 必须为布尔值" }, 400);
          changes.enabled = b.enabled;
        }
        if (b.name !== undefined) {
          if (
            typeof b.name !== "string" ||
            !b.name.trim() ||
            b.name.length > 100
          )
            return json({ error: "无效来源名称" }, 400);
          changes.name = b.name.trim();
        }
        if (b.base_url !== undefined)
          changes.base_url = safeUrl(b.base_url).href;
        if (b.collector !== undefined) {
          if (
            !["kami", "dujiao", "16688", "shopapi", "json", "html"].includes(
              b.collector,
            )
          )
            return json({ error: "无效采集器" }, 400);
          changes.collector = b.collector;
        }
        if (b.config !== undefined) {
          if (
            !b.config ||
            typeof b.config !== "object" ||
            Array.isArray(b.config) ||
            JSON.stringify(b.config).length > 12000
          )
            return json({ error: "无效采集配置" }, 400);
          changes.config = b.config;
        }
        if (b.interval_minutes !== undefined) {
          if (
            !Number.isInteger(b.interval_minutes) ||
            b.interval_minutes < 15 ||
            b.interval_minutes > 10080
          )
            return json({ error: "采集间隔须为 15–10080 分钟" }, 400);
          changes.interval_minutes = b.interval_minutes;
        }
        if (!Object.keys(changes).length)
          return json({ error: "没有可更新的字段" }, 400);
        return json({
          source: checked(
            await client
              .from("sources")
              .update(changes)
              .eq("id", sourceRoute[1])
              .select()
              .single(),
          ).data,
        });
      }
      if (url.pathname === "/api/admin/crawl" && req.method === "POST") {
        const b = (await req.json()) as any;
        if (b.source_id && !/^[0-9a-f-]{36}$/.test(b.source_id))
          return json({ error: "无效来源" }, 400);
        return json({ results: await runCrawl(env, b.source_id) });
      }
      return json({ error: "Not found" }, 404);
    } catch (e) {
      console.error(e);
      return json(
        { error: e instanceof Error ? e.message : "服务暂不可用" },
        500,
      );
    }
  },
  async scheduled(event: ScheduledController, env: Env, ctx: ExecutionContext) {
    if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) {
      console.error("Scheduled collection skipped: database is not configured");
      return;
    }
    ctx.waitUntil(
      runCrawl(env).then((results) =>
        console.log(
          JSON.stringify({
            trigger: "cloudflare-cron",
            cron: event.cron,
            scheduled_at: new Date(event.scheduledTime).toISOString(),
            results,
          }),
        ),
      ),
    );
  },
} satisfies ExportedHandler<Env>;
