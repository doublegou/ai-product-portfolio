function canonicalTitle(title) {
  return title
    .normalize("NFKC")
    .toLocaleLowerCase()
    .replace(/https?:\/\/\S+/g, "")
    .replace(/[\p{P}\p{S}\s]+/gu, "")
    .replace(/(最新|突发|重磅|热搜)$/u, "");
}

function bigrams(value) {
  if (value.length < 2) return new Set([value]);
  const grams = new Set();
  for (let index = 0; index < value.length - 1; index += 1) grams.add(value.slice(index, index + 2));
  return grams;
}

function titleSimilarity(left, right) {
  const a = canonicalTitle(left);
  const b = canonicalTitle(right);
  if (!a || !b) return 0;
  if (a === b) return 1;
  const shorter = a.length <= b.length ? a : b;
  const longer = a.length > b.length ? a : b;
  if (longer.includes(shorter) && shorter.length / longer.length >= 0.82) return 0.92;

  const aSet = bigrams(a);
  const bSet = bigrams(b);
  let overlap = 0;
  for (const gram of aSet) if (bSet.has(gram)) overlap += 1;
  return (2 * overlap) / (aSet.size + bSet.size);
}

export function groupSimilarItems(items, threshold = 0.88) {
  const groups = [];

  for (const item of items) {
    const existing = groups.find((group) => titleSimilarity(group.title, item.title) >= threshold);
    if (!existing) {
      groups.push({
        ...item,
        sources: [item.source],
        sourceCount: 1,
        related: [{
          source: item.source,
          sourceName: item.sourceName,
          title: item.title,
          url: item.url,
          rank: item.rank,
          publishedAt: item.publishedAt,
          heat: item.heat,
        }],
      });
      continue;
    }

    existing.related.push({
      source: item.source,
      sourceName: item.sourceName,
      title: item.title,
      url: item.url,
      rank: item.rank,
      publishedAt: item.publishedAt,
      heat: item.heat,
    });
    existing.sources = [...new Set(existing.related.map((entry) => entry.source))];
    existing.sourceCount = existing.sources.length;
    if (item.rank < existing.rank) {
      existing.title = item.title;
      existing.url = item.url;
      existing.rank = item.rank;
      existing.source = item.source;
      existing.sourceName = item.sourceName;
    }
  }

  return groups.sort((left, right) =>
    right.sourceCount - left.sourceCount || left.rank - right.rank || left.title.localeCompare(right.title),
  );
}

