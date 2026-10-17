import test from 'node:test';
import assert from 'node:assert/strict';
import { analyticsUrl, GA_MEASUREMENT_ID, trackGooglePageView } from '../src/lib/google-analytics';

test('GA4 sends one page view per route, strips search/hash and stays off previews', () => {
  const oldWindow = Object.getOwnPropertyDescriptor(globalThis, 'window');
  const oldDocument = Object.getOwnPropertyDescriptor(globalThis, 'document');
  const scripts: Record<string, unknown>[] = [];
  const win = { location: { hostname: 'localhost', href: 'https://pricemapai.com/' }, dataLayer: [] as Array<IArguments> };
  const doc = { title: 'PriceMap AI', referrer: 'https://example.com/search?email=private#token', createElement: () => ({}), head: { appendChild: (script: Record<string, unknown>) => scripts.push(script) } };
  Object.defineProperty(globalThis, 'window', { configurable: true, value: win });
  Object.defineProperty(globalThis, 'document', { configurable: true, value: doc });
  try {
    trackGooglePageView();
    assert.equal(scripts.length, 0);
    win.location.hostname = 'pricemapai.com';
    trackGooglePageView();
    trackGooglePageView(); // React StrictMode effect replay.
    win.location.href = 'https://pricemapai.com/subscriptions?q=private#contact';
    trackGooglePageView();
    win.location.href = 'https://pricemapai.com/subscriptions?q=changed';
    trackGooglePageView();
    const calls = win.dataLayer.map(args => Array.from(args));
    const views = calls.filter(args => args[0] === 'event' && args[1] === 'page_view');
    assert.equal(scripts.length, 1);
    assert.equal(scripts[0].src, `https://www.googletagmanager.com/gtag/js?id=${GA_MEASUREMENT_ID}`);
    assert.equal(views.length, 2);
    assert.deepEqual(views.map(args => args[2]), [
      { send_to: GA_MEASUREMENT_ID, page_title: 'PriceMap AI', page_location: 'https://pricemapai.com/', page_referrer: 'https://example.com/search' },
      { send_to: GA_MEASUREMENT_ID, page_title: 'PriceMap AI', page_location: 'https://pricemapai.com/subscriptions', page_referrer: 'https://pricemapai.com/' },
    ]);
    for (const args of calls.filter(args => args[0] === 'config')) assert.equal((args[2] as any).send_page_view, false);
    assert.equal(analyticsUrl('invalid'), '');
  } finally {
    if (oldWindow) Object.defineProperty(globalThis, 'window', oldWindow); else Reflect.deleteProperty(globalThis, 'window');
    if (oldDocument) Object.defineProperty(globalThis, 'document', oldDocument); else Reflect.deleteProperty(globalThis, 'document');
  }
});
