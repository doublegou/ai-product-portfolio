import { test } from 'node:test';
import assert from 'node:assert/strict';
import { catalogPriceStatus, catalogProductById, summarizeCatalogEntry } from '../src/lib/catalog';
import { demo } from '../src/data/demo';

test('missing catalog prices distinguish no quotes, sold out, and expired quotes', () => {
  const now = Date.now();
  const product = catalogProductById.get('paypal-phone-verification')!;
  const soldOut = { ...demo.offers[0], price: 2.5, currency: 'CNY', stock_status: 'out_of_stock', expires_at: new Date(now + 60000).toISOString() };
  const empty = summarizeCatalogEntry(product, [], now);
  assert.equal(catalogPriceStatus(empty, now), '暂无报价');
  const sold = summarizeCatalogEntry(product, [soldOut], now);
  assert.equal(sold.referencePrice, null);
  assert.equal(catalogPriceStatus(sold, now), '暂时缺货');
  const expired = { ...soldOut, stock_status: 'in_stock', expires_at: new Date(now - 1).toISOString() };
  assert.equal(catalogPriceStatus(summarizeCatalogEntry(product, [expired], now), now), '报价待更新');
  const historical = summarizeCatalogEntry(product, [expired, soldOut], now);
  assert.equal(catalogPriceStatus(historical, now), '报价待更新');
  assert.equal(historical.referencePrice, 2.5);
  assert.equal(historical.priceKind, 'stale');
  assert.equal(historical.available, 0);
  const expiredSold = summarizeCatalogEntry(product, [{...soldOut, expires_at: new Date(now-1).toISOString()}], now);
  assert.equal(expiredSold.referencePrice, null);
  const unknown = summarizeCatalogEntry(product, [{ ...soldOut, stock_status: 'unknown' }], now);
  assert.equal(unknown.referencePrice, 2.5);
  assert.equal(unknown.priceKind, 'reference');
});
