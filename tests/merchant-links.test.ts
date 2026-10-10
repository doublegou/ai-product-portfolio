import test from 'node:test';
import assert from 'node:assert/strict';
import { merchantLink, merchantPurchaseLink } from '../src/lib/merchant-links';
import { publicOfferRows } from '../snapshot/public-fields';

test('merchant homepage links use the agreed referral codes', () => {
  for (const [host, code] of [['gospv.com','NTJJLYNZ'],['burstpro-ai.online','TSES4VLN'],['xigua.ink','XG53029E3567']]) {
    assert.equal(merchantLink(`https://${host}/`), `https://${host}/?aff=${code}`);
  }
});

test('AI Zhichong uses its landing page even for older snapshots with external checkout links', () => {
  const external = 'https://fe.dtyuedan.cn/shop/ADG1JF0R/';
  assert.equal(merchantPurchaseLink(external, 'https://aicz.ink/'), 'https://aicz.ink/');
  assert.equal(merchantPurchaseLink(external, 'https://other.example/'), external);
  assert.equal(merchantPurchaseLink(external, 'https://aicz.ink.evil.example/'), external);
  assert.equal(merchantPurchaseLink('https://burstpro-ai.online/products/a', 'https://burstpro-ai.online/'), 'https://burstpro-ai.online/products/a?aff=TSES4VLN');
});

test('product links retain the product and options while overriding old referrals', () => {
  const url = new URL(merchantLink('https://gospv.com/products/claude-pro?sku=2&aff=old&aff=another#details')!);
  assert.equal(url.pathname, '/products/claude-pro');
  assert.equal(url.searchParams.get('sku'), '2');
  assert.deepEqual(url.searchParams.getAll('aff'), ['NTJJLYNZ']);
  assert.equal(url.hash, '#details');
  assert.equal(merchantLink(url.href), url.href);
});

test('unrelated merchants are unchanged and unsafe links cannot become purchase links', () => {
  for (const value of ['https://other.example/products/a?aff=original','https://gospv.com.evil.example/','https://sub.gospv.com/','https://gospv.com:8443/']) assert.equal(merchantLink(value), value);
  for (const value of ['javascript:alert(1)','http://gospv.com/','https://user:pass@gospv.com/','invalid']) assert.equal(merchantLink(value), undefined);
});

test('public snapshots include referrals without changing stored collector rows', () => {
  const row = {purchase_url:'https://xigua.ink/products/a', sources:{name:'西瓜小铺',base_url:'https://xigua.ink/',config:{private:true}}};
  const [published] = publicOfferRows([row]);
  assert.equal(published.purchase_url,'https://xigua.ink/products/a?aff=XG53029E3567');
  assert.equal(published.sources.base_url,'https://xigua.ink/?aff=XG53029E3567');
  assert.equal(published.sources.config,undefined);
  assert.equal(row.purchase_url,'https://xigua.ink/products/a');
  assert.equal(row.sources.base_url,'https://xigua.ink/');
});
