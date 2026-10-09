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

Realtime receipt and collaborator access should be checked in the dashboard before treating either as confirmed.
