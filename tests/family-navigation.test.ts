import { test } from 'node:test';
import assert from 'node:assert/strict';
import { catalogDetailHref, familyById, groupedCatalogEntries, selectFamilyVariant } from '../src/lib/catalogGroups';
import { catalogProductId } from '../src/lib/catalog';
import { demo } from '../src/data/demo';

const now = Date.now();
const offers = [
  { ...demo.offers[0], id: 'account', platform: 'Gemini', plan: 'Pro',
    raw_title: 'Gemini Pro 成品账号', delivery: '成品号', price: 30, stock_status: 'in_stock', expires_at: new Date(now+60000).toISOString() },
  { ...demo.offers[0], id: 'recharge', platform: 'Gemini', plan: 'Pro',
    raw_title: 'Gemini Pro 18个月直充兑换链接', delivery: '代充', price: 8, stock_status: 'in_stock', expires_at: new Date(now+60000).toISOString() },
];

test('a family card opens the variant that supplied its displayed price', () => {
  const entry = groupedCatalogEntries(offers, now).find(entry => entry.id === 'gemini-pro-family')!;
  assert.equal(entry.referencePrice, 8);
  const href = new URL(catalogDetailHref(entry, 'platform=Gemini&view=grid'), 'https://pricemapai.com');
  assert.equal(href.searchParams.get('variant'), 'gemini-pro-recharge');
  assert.equal(href.searchParams.get('from'), 'platform=Gemini&view=grid');
  const family = familyById.get(entry.id)!;
  const selected = selectFamilyVariant(family, href.searchParams.get('variant')!, offers, now);
  assert.ok(offers.filter(offer => catalogProductId(offer) === selected.id).some(offer => offer.price === entry.referencePrice));
  assert.equal(selectFamilyVariant(family, undefined, offers, now).id, selected.id);
  assert.equal(selectFamilyVariant(family, 'gemini-pro-year', offers, now).id, 'gemini-pro-year');
});

test('family defaults use the same fresh-stock and reference-price rules as cards', () => {
  const family = familyById.get('gemini-pro-family')!;
  const expired = [{ ...offers[0], expires_at: new Date(now-1).toISOString() }, { ...offers[1], stock_status: 'unknown' }];
  assert.equal(selectFamilyVariant(family, undefined, expired, now).id, 'gemini-pro-recharge');
  const sold = [offers[0], { ...offers[1], stock_status: 'out_of_stock' }];
  assert.equal(selectFamilyVariant(family, undefined, sold, now).id, 'gemini-pro-year');
  assert.equal(selectFamilyVariant(family, undefined, [], now).id, family.variants[0].id);
});
