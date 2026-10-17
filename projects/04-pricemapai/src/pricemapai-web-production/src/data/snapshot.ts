export type SnapshotManifest = {
  schema: 1; version: string; generated_at: string;
  offers: { count: number; pages: string[] };
  transit: { count: number; pages: string[] };
};
export function validateManifest(value: unknown): SnapshotManifest {
  const m = value as SnapshotManifest;
  if (!m || m.schema !== 1 || !/^[a-f0-9]{24}$/.test(m.version) || !Number.isFinite(Date.parse(m.generated_at)))
    throw Error('报价快照格式异常');
  for (const kind of ['offers', 'transit'] as const) {
    const dataset = m[kind];
    if (!dataset || !Number.isSafeInteger(dataset.count) || dataset.count < 0 || dataset.count > 100000 ||
      !Array.isArray(dataset.pages) || !dataset.pages.length || dataset.pages.length > 1000 ||
      dataset.pages.some((path, i) => path !== `/data/v/${m.version}/${kind}-${i}.json.gz`))
      throw Error('报价快照分页格式异常');
  }
  return m;
}
export async function readSnapshotPages(kind: 'offers' | 'transit', fetcher: typeof fetch, signal?: AbortSignal): Promise<unknown[]> {
  // Never fall back to a database API. A stale manifest may outlive retained files;
  // retry with a fresh manifest once, without mixing versions or partial results.
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const response = await fetcher('/data/latest.json', { signal, cache: attempt ? 'reload' : 'default' });
      if (!response.ok) throw Error('报价快照暂时无法读取，请稍后重试');
      const manifest = validateManifest(await response.json());
      const rows: unknown[] = [];
      for (const path of manifest[kind].pages) {
        const page = await fetcher(path, { signal });
        if (!page.ok) throw Error('报价快照分页暂时无法读取，请稍后重试');
        if (!page.body) throw Error('报价快照分页为空');
        const body = await new Response(page.body.pipeThrough(new DecompressionStream('gzip'))).json() as Record<string, any>;
        if (body.version !== manifest.version || body.generated_at !== manifest.generated_at || !Array.isArray(body[kind]))
          throw Error('报价快照版本不一致');
        rows.push(...body[kind]);
      }
      if (rows.length !== manifest[kind].count) throw Error('报价快照不完整');
      return rows;
    } catch (error) {
      if (attempt || signal?.aborted) throw error;
    }
  }
  throw Error('报价快照暂时无法读取');
}
