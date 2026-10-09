# PriceMapAI Google Analytics 4

Production website: https://pricemapai.com

| Setting | Value |
| --- | --- |
| Analytics account | Tech Current (`404383122`) |
| Separate GA4 property | pricemapai.com (`558220968`) |
| Web stream | PriceMapAI (`16096529687`) |
| Measurement ID | `G-72Y2C0JFSE` |
| Reporting timezone / currency | China GMT+08 / CNY |

Dashboard: https://analytics.google.com/analytics/web/#/a404383122p558220968/realtime/overview

Grant collaborators Viewer access through this property's **Property access management**, not the parent account. This separates PriceMapAI reporting from other websites. The measurement ID is a public tag identifier, not an API credential; no GitHub Secret is required.

On 2026-10-09, `doublegou@gmail.com` was granted Viewer directly on property `558220968`, with email notification enabled. The property's permissions table confirmed the Viewer row after submission.

## Collection

`src/lib/google-analytics.ts` loads Google's tag only on `pricemapai.com`. Page views are sent explicitly when the pathname changes. URL query strings and fragments are removed from both page locations and referrers; query-only filtering changes do not count as additional page views. Enhanced measurement is disabled in the web stream to prevent automatic history tracking from duplicating these page views. Google signals and advertising personalization signals are disabled in the tag configuration.

The existing Umami business events are also sent to GA4 through `trackAnalyticsEvent`:

- `advanced_filters_reset`
- `api_provider_click`
- `api_station_detail_open`
- `api_type_change`
- `merchant_shop_click`
- `platform_filter_change`
- `platform_product_detail_open`
- `product_detail_open`
- `purchase_link_click`
- `scope_change`
- `view_change`

The providers fail independently and do not block purchases or navigation. Search text, passwords, API keys, and affiliate query strings are not included in business event parameters. The separate admin entry point does not load the public site's GA4 module.

These events measure browsing and outbound clicks, not merchant checkout completion. Event parameters are transmitted; using them as dimensions in standard GA4 reports requires custom definitions in GA4. Ad blockers and networks that cannot reach Google may prevent GA4 collection; Umami remains available independently.

## Validation

- `npm run build`
- `npx tsc --noEmit`
- `npx tsx --test tests/analytics.test.ts tests/google-analytics.test.ts tests/security-cache.test.ts` (7 tests)
- Production Cloudflare deployment: `7ae7b140-8252-4f16-a6c1-ccfc86cf0aa7`
- Browser DOM confirmed the production JavaScript and tag `gtag/js?id=G-72Y2C0JFSE` were present.

Collaborator access was confirmed in the property's permissions table. Realtime still showed no received data during the 2026-10-09 browser check; end-to-end GA4 collection has not yet been confirmed.

## Reference parity

The inspected PriceAI revision `b3092c4487ab96e58dd9d1fb97016ac692ea116e` uses `src/lib/analytics.ts` to send each business event to both `window.gtag` and `window.umami`. PriceMapAI now follows that same shared-event approach for its existing features. See `deploy/umami/analytics-alignment.md` for matching event names, parameters, merchant identifiers, and features that are absent from this site.

PriceAI's `GoogleAnalytics.tsx` initializes `gtag` with `send_page_view: true`; this SPA explicitly sends pathname page views and disables enhanced measurement to avoid duplicate route views and exclude query strings. This is equivalent coverage with a deliberately different page-view implementation, not an exact copy of all PriceAI features or private GA4 report settings.
