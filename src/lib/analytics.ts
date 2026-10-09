type EventParams = Record<string, string | number | boolean | null | undefined>;

declare global {
  interface Window {
    umami?: { track: (name: string, data?: Record<string, string | number | boolean>) => Promise<unknown> | void };
  }
}

/** Analytics must never delay a purchase or break an interaction. */
export function trackAnalyticsEvent(name: string, params: EventParams = {}): void {
  if (typeof window === "undefined" || window.location.hostname !== "pricemapai.com") return;
  const data: Record<string, string | number | boolean> = {};
  for (const [key, value] of Object.entries(params)) {
    if (typeof value === "string") data[key] = value.slice(0, 300);
    else if (typeof value === "boolean" || (typeof value === "number" && Number.isFinite(value))) data[key] = value;
  }
  try {
    void Promise.resolve(window.umami?.track(name, data)).catch(() => {});
  } catch { /* Tracking failure does not affect the site. */ }
}

/** Stable merchant identity without publishing database IDs or referral query strings. */
export function merchantAnalyticsId(baseUrl: string): string {
  try {
    const url = new URL(baseUrl);
    return `${url.hostname.toLowerCase()}${url.pathname.replace(/\/+$/, "")}`;
  } catch { return "unknown"; }
}

/** Preserve affiliate codes/product paths; don't alter signed or authenticated URLs. */
export function withPriceMapUtm(value: string, medium: string, campaign: string, content?: string): string {
  try {
    const url = new URL(value);
    if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) return value;
    if ([...url.searchParams.keys()].some(key => /(^|[-_])(sig(nature)?|token|auth|key|secret|expires?|x-amz)([-_]|$)/i.test(key))) return value;
    for (const [key, item] of Object.entries({ utm_source: "pricemapai.com", utm_medium: medium, utm_campaign: campaign, utm_content: content })) {
      const previous = url.searchParams.get(key);
      if (item && (!previous || /^priceai(?:[._]|$)/i.test(previous))) url.searchParams.set(key, item);
    }
    return url.href;
  } catch { return value; }
}
