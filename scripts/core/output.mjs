function escapeCsv(value) {
  const text = value == null ? "" : String(value);
  return /[",\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

export function toMarkdown(report) {
  const lines = [
    `# 热点雷达 · ${report.fetchedAt}`,
    "",
    `预设：${report.preset ?? "自定义"}｜来源：${report.requestedSources.join(", ")}｜事件：${report.items.length}`,
    "",
    "## 来源状态",
    "",
    ...report.sourceStatus.map((status) =>
      `- ${status.ok ? "✅" : "❌"} ${status.sourceName}: ${status.ok ? `${status.count} 条${status.warnings?.length ? `；⚠️ ${status.warnings.join("；")}` : ""}` : status.error}`,
    ),
    "",
    "## 热点",
    "",
  ];

  report.items.forEach((item, index) => {
    const resonance = item.sourceCount > 1 ? ` · ${item.sourceCount} 个来源共振` : "";
    lines.push(`${index + 1}. [${item.title}](${item.url}) — ${item.sourceName}${resonance}`);
    if (item.publishedAt || item.heat || item.summary) {
      lines.push(`   ${[item.publishedAt, item.heat, item.summary].filter(Boolean).join(" · ")}`);
    }
    if (item.related.length > 1) {
      lines.push(`   相关：${item.related.map((entry) => `[${entry.sourceName}](${entry.url})`).join("、")}`);
    }
  });

  return `${lines.join("\n")}\n`;
}

export function toCsv(report) {
  const header = ["title", "url", "source", "rank", "publishedAt", "heat", "summary", "sourceCount", "fetchedAt"];
  const rows = report.items.map((item) => [
    item.title,
    item.url,
    item.sources.join("|"),
    item.rank,
    item.publishedAt,
    item.heat,
    item.summary,
    item.sourceCount,
    item.fetchedAt,
  ]);
  return `${[header, ...rows].map((row) => row.map(escapeCsv).join(",")).join("\n")}\n`;
}

export function formatReport(report, format) {
  if (format === "json") return `${JSON.stringify(report, null, 2)}\n`;
  if (format === "markdown") return toMarkdown(report);
  if (format === "csv") return toCsv(report);
  throw new Error(`Unsupported format: ${format}`);
}
