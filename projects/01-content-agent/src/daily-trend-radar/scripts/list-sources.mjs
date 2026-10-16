#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { aliases, sources } from "./sources/index.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const presets = JSON.parse(await readFile(path.join(root, "config/presets.json"), "utf8"));

process.stdout.write("Sources:\n");
for (const source of sources.values()) {
  const meta = source.metadata;
  process.stdout.write(`- ${meta.id.padEnd(20)} ${meta.name} (${meta.kind}, ${meta.language}, ${meta.stability})\n`);
}
process.stdout.write("\nAliases:\n");
for (const [alias, target] of aliases) process.stdout.write(`- ${alias.padEnd(20)} -> ${target}\n`);
process.stdout.write("\nPresets:\n");
for (const [name, ids] of Object.entries(presets)) process.stdout.write(`- ${name.padEnd(12)} ${ids.join(", ")}\n`);
