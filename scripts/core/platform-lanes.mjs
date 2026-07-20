export async function mapByPlatform(entries, worker) {
  const groups = new Map();
  entries.forEach((entry, index) => {
    const platform = entry.source?.metadata?.platform ?? entry.id ?? `unknown-${index}`;
    if (!groups.has(platform)) groups.set(platform, []);
    groups.get(platform).push({ entry, index });
  });

  const results = new Array(entries.length);
  await Promise.all([...groups.values()].map(async (group) => {
    for (const { entry, index } of group) results[index] = await worker(entry);
  }));
  return results;
}

