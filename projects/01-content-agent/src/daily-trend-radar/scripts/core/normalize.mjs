function cleanText(value) {
  if (value == null) return null;
  const cleaned = String(value).replace(/\s+/g, " ").trim();
  return cleaned || null;
}

function normalizeDate(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? null : date.toISOString();
}

export function normalizeItems(items, source, sourceName, fetchedAt = new Date().toISOString()) {
  const seen = new Set();
  const normalized = [];

  for (const [index, item] of items.entries()) {
    const title = cleanText(item.title);
    const url = cleanText(item.url);
    if (!title || !url) continue;

    const id = cleanText(item.id) ?? url;
    const key = `${source}:${id}`;
    if (seen.has(key)) continue;
    seen.add(key);

    normalized.push({
      source,
      sourceName,
      id,
      title,
      url,
      publishedAt: normalizeDate(item.publishedAt),
      rank: Number.isFinite(item.rank) ? item.rank : index + 1,
      heat: cleanText(item.heat),
      summary: cleanText(item.summary),
      fetchedAt,
      tags: Array.isArray(item.tags) ? item.tags.map(cleanText).filter(Boolean) : [],
      language: item.language ?? null,
    });
  }

  return normalized;
}

