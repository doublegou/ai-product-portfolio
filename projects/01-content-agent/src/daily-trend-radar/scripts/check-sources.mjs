#!/usr/bin/env node
import { parseArgs, positiveInteger } from "./core/args.mjs";
import { mapByPlatform } from "./core/platform-lanes.mjs";
import { unpackSourceResult } from "./core/source-result.mjs";
import { resolveSource, sources } from "./sources/index.mjs";

const args = parseArgs(process.argv.slice(2));
const limit = positiveInteger(args.limit, "--limit", 3);
const selected = args.sources ? args.sources.split(",").map((value) => value.trim()) : [...sources.keys()];
let failed = 0;

const entries = selected.map((requestedId) => ({ requestedId, ...resolveSource(requestedId) }));
const results = await mapByPlatform(entries, async ({ requestedId, ...resolved }) => {
  const source = resolved.source;
  if (!source) return { id: requestedId, ok: false, message: "unknown source" };
  const startedAt = Date.now();
  try {
    const result = unpackSourceResult(await source.fetchSource({ limit }));
    const items = result.items;
    if (!items.length) throw new Error("returned no items");
    return {
      id: resolved.id,
      ok: true,
      stability: source.metadata.stability,
      message: `${items.length} items in ${Date.now() - startedAt}ms${result.warnings.length ? `; WARN ${result.warnings.join("; ")}` : ""}`,
    };
  } catch (error) {
    return { id: resolved.id, ok: false, stability: source.metadata.stability, message: error.message };
  }
});

for (const result of results) {
  if (!result.ok) failed += 1;
  process.stdout.write(`${result.ok ? "OK  " : "FAIL"} ${result.id.padEnd(20)} ${(result.stability ?? "-").padEnd(11)} ${result.message}\n`);
}
process.exitCode = failed ? 1 : 0;
