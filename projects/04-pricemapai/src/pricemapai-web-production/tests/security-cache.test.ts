import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import worker from "../worker/index";
import type { Env } from "../worker/types";

const env = {
  SUPABASE_URL: "https://example.supabase.co",
  SUPABASE_SERVICE_ROLE_KEY: "test-only",
  ADMIN_TOKEN: "test-admin",
  ASSETS: { fetch: async () => new Response("page") },
} as unknown as Env;

test("legacy public endpoints and health never reach the database", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async () => { throw Error("Database must not be queried"); };
  try {
    for (const path of ["/api/offers?offset=99999", "/api/transit", "/api/stats", "/api/history/00000000-0000-0000-0000-000000000000"]) {
      assert.equal((await worker.fetch(new Request("https://app.example.com" + path), env)).status, 410);
    }
    assert.equal((await worker.fetch(new Request("https://app.example.com/api/health"), env)).status, 200);
    assert.equal((await worker.fetch(new Request("https://app.example.com/api/admin/sources"), env)).status, 401);
  } finally { globalThis.fetch = original; }
});

test("authenticated admin responses remain uncached and conceal upstream failures", async () => {
  const original = globalThis.fetch, originalError = console.error;
  console.error = () => {};
  try {
    globalThis.fetch = async () => Response.json([]);
    const request = new Request("https://app.example.com/api/admin/sources", { headers: { Authorization: "Bearer test-admin" } });
    const response = await worker.fetch(request, env);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("Cache-Control"), "no-store");
    globalThis.fetch = async () => Response.json({ message: "private-schema-detail", code: "XX000" }, { status: 500 });
    const failure = await worker.fetch(request, env);
    assert.equal(failure.status, 500);
    assert.doesNotMatch(await failure.text(), /private-schema-detail/);
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
