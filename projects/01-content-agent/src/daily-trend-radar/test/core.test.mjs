import assert from "node:assert/strict";
import test from "node:test";
import { parseArgs, positiveInteger } from "../scripts/core/args.mjs";
import { parseChineseRelativeDate } from "../scripts/core/date.mjs";
import { groupSimilarItems } from "../scripts/core/deduplicate.mjs";
import { normalizeItems } from "../scripts/core/normalize.mjs";
import { toCsv } from "../scripts/core/output.mjs";
import { mapByPlatform } from "../scripts/core/platform-lanes.mjs";
import { unpackSourceResult } from "../scripts/core/source-result.mjs";
import { resolveSource, sources } from "../scripts/sources/index.mjs";

test("parses CLI options", () => {
  assert.deepEqual(parseArgs(["--preset", "ai", "--limit=10", "--no-dedupe"]), {
    preset: "ai",
    limit: "10",
    "no-dedupe": true,
  });
  assert.equal(positiveInteger("3", "limit"), 3);
  assert.throws(() => positiveInteger("0", "limit"));
});

test("normalizes and rejects incomplete items", () => {
  const [item] = normalizeItems([
    { title: "  Hello   world ", url: "https://example.com/a", publishedAt: "2026-01-01T00:00:00Z" },
    { title: "missing URL" },
  ], "test", "Test", "2026-01-02T00:00:00.000Z");
  assert.equal(item.title, "Hello world");
  assert.equal(item.rank, 1);
  assert.equal(item.publishedAt, "2026-01-01T00:00:00.000Z");
});

test("groups highly similar cross-source titles", () => {
  const base = {
    id: "1", sourceName: "A", publishedAt: null, heat: null, summary: null,
    fetchedAt: "2026-01-01T00:00:00.000Z", tags: [], language: "zh",
  };
  const groups = groupSimilarItems([
    { ...base, source: "a", title: "OpenAI 发布全新模型 GPT-X", url: "https://a.test", rank: 3 },
    { ...base, source: "b", title: "重磅：OpenAI 发布全新模型 GPT-X", url: "https://b.test", rank: 1 },
  ]);
  assert.equal(groups.length, 1);
  assert.equal(groups[0].sourceCount, 2);
});

test("escapes CSV fields", () => {
  const csv = toCsv({ items: [{
    title: "a, b", url: "https://example.com", sources: ["x"], rank: 1,
    publishedAt: null, heat: null, summary: 'say "hi"', sourceCount: 1, fetchedAt: "now",
  }] });
  assert.match(csv, /"a, b"/);
  assert.match(csv, /"say ""hi"""/);
});

test("parses common Chinese relative dates", () => {
  const now = Date.parse("2026-07-17T05:00:00.000Z");
  assert.equal(parseChineseRelativeDate("10分钟前", now), "2026-07-17T04:50:00.000Z");
  assert.equal(parseChineseRelativeDate("未知", now), null);
});

test("registers 18 leaderboard adapters and resolves aliases", () => {
  assert.equal(sources.size, 18);
  assert.equal(resolveSource("36kr").id, "36kr-quick");
  assert.equal(resolveSource("bilibili").id, "bilibili-hot-search");
});

test("unpacks normal and degraded source results", () => {
  assert.deepEqual(unpackSourceResult([1]), { items: [1], warnings: [] });
  assert.deepEqual(unpackSourceResult({ items: [1], warnings: ["fallback"] }), {
    items: [1], warnings: ["fallback"],
  });
});

test("runs entries from the same platform sequentially", async () => {
  let active = 0;
  let maximum = 0;
  const entries = [1, 2].map((id) => ({ id, source: { metadata: { platform: "same" } } }));
  const results = await mapByPlatform(entries, async ({ id }) => {
    active += 1;
    maximum = Math.max(maximum, active);
    await new Promise((resolve) => setTimeout(resolve, 5));
    active -= 1;
    return id;
  });
  assert.deepEqual(results, [1, 2]);
  assert.equal(maximum, 1);
});
