const PUBLIC_CACHE_CONTROL = "public,max-age=60,s-maxage=300";
// Only callers serving public, read-only data may use this cache.
export async function cachedPublic(
  key: Request,
  ctx: ExecutionContext | undefined,
  load: () => Promise<Response>,
): Promise<Response> {
  const cache = typeof caches !== "undefined" && "default" in caches
    ? (caches as CacheStorage & { default: Cache }).default : undefined;
  if (cache && ctx) {
    try {
      const hit = await cache.match(key);
      if (hit) {
        const headers = new Headers(hit.headers);
        // Cache storage may apply the zone's default browser TTL. Keep quote
        // freshness independent of that TTL when returning a cached response.
        headers.set("Cache-Control", PUBLIC_CACHE_CONTROL);
        headers.set("X-PriceMap-Cache", "HIT");
        return new Response(hit.body, { status: hit.status, headers });
      }
    } catch { /* A cache outage must not prevent a database read. */ }
  }
  const response = await load();
  if (response.status !== 200 || response.headers.has("Set-Cookie")) return response;
  const headers = new Headers(response.headers);
  headers.set("Cache-Control", PUBLIC_CACHE_CONTROL);
  headers.set("X-PriceMap-Cache", cache && ctx ? "MISS" : "BYPASS");
  const result = new Response(response.body, { status: response.status, headers });
  if (cache && ctx) ctx.waitUntil(cache.put(key, result.clone()).catch(() => {}));
  return result;
}

export function publicCacheKey(url: URL, params: Record<string, number> = {}): Request {
  const key = new URL(url.pathname, url.origin);
  key.searchParams.set("schema", "public-v1");
  for (const [name, value] of Object.entries(params)) key.searchParams.set(name, String(value));
  return new Request(key);
}
