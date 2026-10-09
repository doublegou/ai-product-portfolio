import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import worker from "../worker/index";
import { cachedPublic, publicCacheKey } from "../worker/public-cache";
import type { Env } from "../worker/types";

const env = {
  SUPABASE_URL: "https://example.supabase.co",
  SUPABASE_SERVICE_ROLE_KEY: "test-only",
  ADMIN_TOKEN: "test-admin",
  ASSETS: { fetch: async () => new Response("page") },
} as unknown as Env;

async function withCache(run: (flush: () => Promise<void>, size: () => number) => Promise<void>) {
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, "caches");
  const entries = new Map<string, Response>();
  const pending: Promise<unknown>[] = [];
  Object.defineProperty(globalThis, "caches", { configurable: true, value: { default: {
    match: async (key: Request) => entries.get(key.url)?.clone(),
    put: async (key: Request, response: Response) => {
      const headers = new Headers(response.headers);
      headers.set("Cache-Control", "public,max-age=14400,s-maxage=300");
      entries.set(key.url, new Response(response.body, { status: response.status, headers }));
    },
  } } });
  context = { waitUntil: (promise: Promise<unknown>) => pending.push(promise) } as unknown as ExecutionContext;
  try { await run(async () => { await Promise.all(pending); }, () => entries.size); }
  finally {
    if (descriptor) Object.defineProperty(globalThis, "caches", descriptor);
    else Reflect.deleteProperty(globalThis, "caches");
  }
}
let context: ExecutionContext;

test("public offer cache reuses normalized pages and validates bounds before serving a hit", async () => {
  const original = globalThis.fetch;
  let queries = 0;
  globalThis.fetch = async () => {
    queries++;
    return new Response(JSON.stringify([{ id: "a" }]), { headers: {
      "Content-Type": "application/json", "Content-Range": "0-0/1",
    } });
  };
  try {
    await withCache(async (flush) => {
      const request = (query: string) => worker.fetch(new Request("https://app.example.com/api/offers" + query), env, context);
      const first = await request("?limit=1000&offset=0&tracking=first");
      assert.equal(first.headers.get("X-PriceMap-Cache"), "MISS");
      assert.equal(first.headers.get("Cache-Control"), "public,max-age=60,s-maxage=300");
      const body = await first.json();
      await flush();
      const second = await request("?tracking=second");
      assert.equal(second.headers.get("X-PriceMap-Cache"), "HIT");
      assert.equal(second.headers.get("Cache-Control"), "public,max-age=60,s-maxage=300");
      assert.deepEqual(await second.json(), body);
      assert.equal(queries, 1);
      await request("?limit=1");
      assert.equal(queries, 2);
      assert.equal((await request("?offset=1000001")).status, 400);
      assert.equal(queries, 2);
    });
  } finally { globalThis.fetch = original; }
});

test("cache never stores error responses or responses that set cookies", async () => {
  await withCache(async (flush, size) => {
    const key = publicCacheKey(new URL("https://app.example.com/api/offers"));
    for (const response of [Response.json({ error: "down" }, { status: 500 }), new Response("private", { headers: { "Set-Cookie": "session=private" } })]) {
      await cachedPublic(key, context, async () => response);
    }
    await flush();
    assert.equal(size(), 0);
  });
});

test("admin responses bypass the public cache and remain uncached", async () => {
  const original = globalThis.fetch;
  let queries = 0;
  globalThis.fetch = async () => { queries++; return Response.json([]); };
  try {
    await withCache(async (flush, size) => {
      for (let i = 0; i < 2; i++) {
        const response = await worker.fetch(new Request("https://app.example.com/api/admin/sources", { headers: { Authorization: "Bearer test-admin" } }), env, context);
        assert.equal(response.status, 200);
        assert.equal(response.headers.get("Cache-Control"), "no-store");
        assert.equal(response.headers.get("X-PriceMap-Cache"), null);
      }
      assert.equal((await worker.fetch(new Request("https://app.example.com/api/admin/sources"), env, context)).status, 401);
      await flush();
      assert.equal(queries, 2);
      assert.equal(size(), 0);
    });
  } finally { globalThis.fetch = original; }
});

test("public failures conceal upstream details and are never cached", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async () => Response.json({ message: "private-schema-detail", code: "XX000" }, { status: 500 });
  const originalError = console.error;
  console.error = () => {};
  try {
    const response = await worker.fetch(new Request("https://app.example.com/api/offers"), env);
    assert.equal(response.status, 500);
    assert.equal(response.headers.get("Cache-Control"), "no-store");
    assert.doesNotMatch(await response.text(), /private-schema-detail/);
  } finally { globalThis.fetch = original; console.error = originalError; }
});

test("security headers prevent framing and allow only the known inline theme initializer", async () => {
  const response = await worker.fetch(new Request("https://app.example.com/admin"), env);
  const csp = response.headers.get("Content-Security-Policy")!;
  assert.equal(response.headers.get("X-Frame-Options"), "DENY");
  assert.match(csp, /frame-ancestors 'none'/);
  assert.match(csp, /connect-src 'self'/);
  const script = readFileSync(new URL("../index.html", import.meta.url), "utf8").match(/<script>(.*?)<\/script>/s)![1];
  const hash = createHash("sha256").update(script).digest("base64");
  assert.ok(csp.includes(`'sha256-${hash}'`));
  assert.ok(readFileSync(new URL("../public/_headers", import.meta.url), "utf8").includes(csp));
});
