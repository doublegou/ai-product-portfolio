export const GA_MEASUREMENT_ID = 'G-72Y2C0JFSE';

declare global {
  interface Window {
    dataLayer?: unknown[];
    gtag?: (...args: unknown[]) => void;
  }
}

let initialized = false;
let previousPath: string | undefined;

export function analyticsUrl(value: string): string {
  try {
    const url = new URL(value);
    return `${url.origin}${url.pathname}`;
  } catch { return ''; }
}

/** Explicit page views: no search/hash payloads, and no duplicate history events. */
export function trackGooglePageView(): void {
  if (typeof window === 'undefined' || window.location.hostname !== 'pricemapai.com') return;
  const page = analyticsUrl(window.location.href);
  if (page === previousPath) return;
  if (!initialized) {
    window.dataLayer = window.dataLayer || [];
    window.gtag = function (..._args: unknown[]) { window.dataLayer!.push(arguments); };
    window.gtag('js', new Date());
    const script = document.createElement('script');
    script.async = true;
    script.src = `https://www.googletagmanager.com/gtag/js?id=${GA_MEASUREMENT_ID}`;
    document.head.appendChild(script);
    initialized = true;
  }
  const referrer = previousPath ?? analyticsUrl(document.referrer);
  window.gtag?.('config', GA_MEASUREMENT_ID, {
    send_page_view: false,
    allow_google_signals: false,
    allow_ad_personalization_signals: false,
    page_location: page,
    page_referrer: referrer,
  });
  window.gtag?.('event', 'page_view', {
    send_to: GA_MEASUREMENT_ID,
    page_title: document.title,
    page_location: page,
    page_referrer: referrer,
  });
  previousPath = page;
}
