import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeHotOffers } from '../worker/hot-verification.ts';

test('hot verification only normalizes explicitly selected offers', () => {
  const rows = ['target', 'unselected'].map(external_id => ({ external_id,
    raw_title: 'ChatGPT Plus 代充 1个月', price: 100, currency: 'CNY',
    stock_status: 'in_stock' as const, purchase_url: 'https://shop.example/buy' }));
  const verified = normalizeHotOffers(rows, ['target']);
  assert.equal(verified.length, 1);
  assert.equal(verified[0].external_id, 'target');
  assert.equal(verified[0].plan, 'Plus');
  assert.equal(verified[0].duration_days, 30);
});

test('ambiguous prices remain review-required during hot verification', () => {
  const verified = normalizeHotOffers([{ external_id: 'target', raw_title: 'ChatGPT Plus 代充 1个月',
    price: 100, currency: 'CNY', stock_status: 'unknown', purchase_url: 'https://shop.example/buy',
    raw_data: { price_note: 'starting price' } }], ['target']);
  assert.equal(verified[0].review_required, true);
  assert.equal(verified[0].comparison_key, null);
});
