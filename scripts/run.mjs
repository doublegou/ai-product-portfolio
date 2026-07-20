#!/usr/bin/env node
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs, positiveInteger } from "./core/args.mjs";
import { groupSimilarItems } from "./core/deduplicate.mjs";
import { normalizeItems } from "./core/normalize.mjs";
import { formatReport } from "./core/output.mjs";
import { mapByPlatform } from "./core/platform-lanes.mjs";
import { unpackSourceResult } from "./core/source-result.mjs";
import { resolveSource } from "./sources/index.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const help = `Usage: node scripts/run.mjs [options]

Options:
  --preset NAME        default, core, all, ai, tech, developer, china-hot, social, creator
  --sources IDS        comma-separated source IDs; overrides preset
  --limit N            maximum items per source (default: 20)
  --since-hours N      exclude items explicitly older than N hours
  --format FORMAT      json, markdown, csv (default: json)
  --output FILE        write output to a file instead of stdout
  --no-dedupe          keep every source item separately
  --help               show this help
`;

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    process.stdout.write(help);
    return;
  }

  const presets = JSON.parse(await readFile(path.join(root, "config/presets.json"), "utf8"));
  const preset = args.preset ?? "default";
  const requestedSources = args.sources
    ? args.sources.split(",").map((value) => value.trim()).filter(Boolean)
    : presets[preset];
  if (!requestedSources) throw new Error(`Unknown preset: ${preset}`);
  const resolvedSources = requestedSources.map((requestedId) => ({ requestedId, ...resolveSource(requestedId) }));
  const unknown = resolvedSources.filter((entry) => !entry.source).map((entry) => entry.requestedId);
  if (unknown.length) throw new Error(`Unknown sources: ${unknown.join(", ")}`);
  const selectedSources = [...new Map(resolvedSources.map((entry) => [entry.id, entry])).values()];

  const limit = positiveInteger(args.limit, "--limit", 20);
  const sinceHours = args["since-hours"] == null ? null : positiveInteger(args["since-hours"], "--since-hours");
  const format = args.format ?? "json";
  if (!["json", "markdown", "csv"].includes(format)) throw new Error(`Unsupported format: ${format}`);
  const fetchedAt = new Date().toISOString();

  const results = await mapByPlatform(selectedSources, async ({ id, requestedId, source }) => {
    try {
      const result = unpackSourceResult(await source.fetchSource({ limit }));
      const rawItems = result.items;
      const items = normalizeItems(rawItems, id, source.metadata.name, fetchedAt).slice(0, limit);
      if (!items.length) throw new Error("source returned no valid items");
      return {
        status: {
          source: id,
          requestedAs: requestedId === id ? undefined : requestedId,
          sourceName: source.metadata.name,
          platform: source.metadata.platform,
          stability: source.metadata.stability,
          ok: true,
          count: items.length,
          warnings: result.warnings,
        },
        items,
      };
    } catch (error) {
      return {
        status: {
          source: id,
          requestedAs: requestedId === id ? undefined : requestedId,
          sourceName: source.metadata.name,
          platform: source.metadata.platform,
          stability: source.metadata.stability,
          ok: false,
          count: 0,
          error: error.message,
        },
        items: [],
      };
    }
  });

  const cutoff = sinceHours == null ? null : Date.now() - sinceHours * 3_600_000;
  const rawItems = results.flatMap((result) => result.items).filter((item) =>
    cutoff == null || item.publishedAt == null || new Date(item.publishedAt).valueOf() >= cutoff,
  );
  const items = args["no-dedupe"]
    ? rawItems.map((item) => ({ ...item, sources: [item.source], sourceCount: 1, related: [{ ...item }] }))
    : groupSimilarItems(rawItems);

  const report = {
    schemaVersion: 1,
    fetchedAt,
    preset: args.sources ? null : preset,
    requestedSources,
    resolvedSources: selectedSources.map((entry) => entry.id),
    limitPerSource: limit,
    sinceHours,
    sourceStatus: results.map((result) => result.status),
    rawItemCount: rawItems.length,
    itemCount: items.length,
    items,
  };

  if (!report.sourceStatus.some((status) => status.ok)) {
    throw new Error(`All sources failed: ${report.sourceStatus.map((status) => `${status.source}: ${status.error}`).join("; ")}`);
  }

  const output = formatReport(report, format);
  if (args.output) {
    const outputPath = path.resolve(args.output);
    await mkdir(path.dirname(outputPath), { recursive: true });
    await writeFile(outputPath, output, "utf8");
    process.stderr.write(`Wrote ${report.itemCount} items to ${outputPath}\n`);
  } else {
    process.stdout.write(output);
  }
}

main().catch((error) => {
  process.stderr.write(`daily-trend-radar: ${error.message}\n`);
  process.exitCode = 1;
});
