import { mkdirSync, readFileSync, writeFileSync } from "node:fs";

// Reference-only discovery: retain shop identity, never import reference quotes.
type Merchant = { name: string; url: string; entry_url: string; collector: string };
function identity(value: string) {
  try {
    const url = new URL(value);
    if (!/^https?:$/.test(url.protocol)) return null;
    url.protocol = "https:";
    url.hostname = url.hostname.toLowerCase().replace(/^www\./, "");
    url.hash = "";
    url.pathname = url.pathname.replace(/\/$/, "") || "/";
    return url.href;
  } catch { return null; }
}
mkdirSync("artifacts", { recursive: true });
const rows: Merchant[] = [];
let total = 1;
for (let offset = 0; offset < total; offset += 30) {
  const response = await fetch(`https://priceai.cc/api/merchants?scope=third_party&limit=30&offset=${offset}`, { signal: AbortSignal.timeout(30000) });
  if (!response.ok) throw new Error(`Reference HTTP ${response.status}`);
  const page: any = await response.json();
  if (page.degraded || !Array.isArray(page.rows) || !page.rows.length) throw new Error(`Incomplete reference page at ${offset}`);
  total = page.total;
  rows.push(...page.rows.map((s: any) => ({ name: s.name, url: s.shopUrl || s.entryUrl || "", entry_url: s.entryUrl, collector: s.collectorKind })));
}
const unique = new Map(rows.filter(row => identity(row.url)).map(row => [identity(row.url)!, row]));
const own = JSON.parse(readFileSync("config/verified-sources.json", "utf8")) as { name: string; base_url: string }[];
const local = new Map(own.map(row => [identity(row.base_url)!, row]));
const missing = [...unique].filter(([key]) => !local.has(key)).map(([, row]) => row);
const extra = [...local].filter(([key]) => !unique.has(key)).map(([, row]) => ({ name: row.name, url: row.base_url }));
const report = {
  captured_at: new Date().toISOString(), reference: "https://priceai.cc/channels?view=merchants",
  reference_total: total, fetched_rows: rows.length, unique_merchants: unique.size,
  unidentified: rows.filter(row => !identity(row.url)), duplicate_rows: rows.filter(row => identity(row.url)).length - unique.size,
  our_registered: own.length, shared: [...local.keys()].filter(key => unique.has(key)).length,
  missing, extra, reference_merchants: [...unique.values()],
};
writeFileSync("artifacts/merchant-comparison.json", JSON.stringify(report, null, 2));
console.log(JSON.stringify({ ...report, missing: missing.length, reference_merchants: undefined,
  missing_by_collector: missing.reduce<Record<string, number>>((all, row) => ({ ...all, [row.collector]: (all[row.collector] ?? 0) + 1 }), {}),
}, null, 2));
