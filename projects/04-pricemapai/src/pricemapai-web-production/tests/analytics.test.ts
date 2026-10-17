import test from 'node:test';
import assert from 'node:assert/strict';
import { merchantAnalyticsId, trackAnalyticsEvent, withPriceMapUtm } from '../src/lib/analytics';
import { merchantLink } from '../src/lib/merchant-links';
import { GA_MEASUREMENT_ID } from '../src/lib/google-analytics';

test('outbound attribution keeps the agreed affiliate code, product path and options', () => {
  const link = withPriceMapUtm(merchantLink('https://gospv.com/products/pro?sku=2&aff=old#plan')!, 'card_offer', 'pricemapai_card_shop', 'offer-1');
  const url = new URL(link);
  assert.equal(url.pathname, '/products/pro');
  assert.equal(url.hash, '#plan');
  assert.equal(url.searchParams.get('sku'), '2');
  assert.equal(url.searchParams.get('aff'), 'NTJJLYNZ');
  assert.equal(url.searchParams.get('utm_source'), 'pricemapai.com');
  assert.equal(url.searchParams.get('utm_content'), 'offer-1');
  assert.equal(withPriceMapUtm(link, 'card_offer', 'pricemapai_card_shop', 'offer-1'), link);
});

test('signed links are unchanged; previous PriceAI attribution is replaced', () => {
  for (const value of ['https://shop.example/buy?token=private', 'https://shop.example/buy?X-Amz-Signature=signed', '/local', 'mailto:user@example.com']) {
    assert.equal(withPriceMapUtm(value, 'card_offer', 'pricemapai_card_shop'), value);
  }
  const url = new URL(withPriceMapUtm('https://shop.example/?utm_source=priceai&utm_campaign=priceai_card_shop', 'card_offer', 'pricemapai_card_shop'));
  assert.equal(url.searchParams.get('utm_source'), 'pricemapai.com');
  assert.equal(url.searchParams.get('utm_campaign'), 'pricemapai_card_shop');
  assert.equal(merchantAnalyticsId('https://shop.example/store/?aff=secret#section'), 'shop.example/store');
});

test('events are production-only and tracker failures never block user actions', async () => {
  const oldWindow = Object.getOwnPropertyDescriptor(globalThis, 'window');
  const calls: unknown[][] = [];
  const googleCalls: unknown[][] = [];
  const windowMock = { location: { hostname: 'localhost' }, gtag: (...args: unknown[]) => { googleCalls.push(args); }, umami: { track: (...args: unknown[]) => { calls.push(args); } } };
  Object.defineProperty(globalThis, 'window', { configurable: true, value: windowMock });
  try {
    trackAnalyticsEvent('purchase_link_click', { source_id: 'shop.example', available: true });
    assert.equal(calls.length, 0);
    assert.equal(googleCalls.length, 0);
    windowMock.location.hostname = 'pricemapai.com';
    trackAnalyticsEvent('purchase_link_click', { source_id: 'shop.example', available: true, missing: null, invalid: NaN });
    assert.deepEqual(calls, [['purchase_link_click', { source_id: 'shop.example', available: true }]]);
    assert.deepEqual(googleCalls, [['event', 'purchase_link_click', { source_id: 'shop.example', available: true, send_to: GA_MEASUREMENT_ID }]]);
    windowMock.umami.track = () => { throw Error('tracker unavailable'); };
    assert.doesNotThrow(() => trackAnalyticsEvent('scope_change', { scope: 'offers' }));
    assert.equal(googleCalls.length, 2);
    windowMock.umami.track = () => Promise.reject(Error('network failure'));
    trackAnalyticsEvent('scope_change');
    await new Promise(resolve => setTimeout(resolve, 0));
  } finally {
    if (oldWindow) Object.defineProperty(globalThis, 'window', oldWindow);
    else Reflect.deleteProperty(globalThis, 'window');
  }
});
