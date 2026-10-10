import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isCodexCredits } from '../src/lib/codex-credits';
import { classify } from '../worker/classify';
import { catalogEntries, catalogProductId } from '../src/lib/catalog';
import { demo } from '../src/data/demo';

test('legacy Codex-only titles reach the credit category and display their actual prices', () => {
  const now = Date.now();
  const titles = ['【官方直充】Codex 500点使用额度｜非API额度｜直充自己号',
    '【官方充值】Codex 2500额度 充个人账号 非Api', 'codex500额度',
    'Codex 点数250 正规卡付', 'Codex Credits 额度充值', 'Ｃｏｄｅｘ ５００额度'];
  const offers = titles.map((raw_title, i) => ({ ...demo.offers[0], id: `credits-${i}`,
    raw_title, platform: '其他', plan: '未知', price: 100+i, stock_status: 'in_stock',
    expires_at: new Date(now+60000).toISOString() }));
  for (const offer of offers) {
    assert.equal(catalogProductId(offer), 'chatgpt-codex-credits', offer.raw_title);
    const parsed = classify(offer.raw_title);
    assert.equal(parsed.platform, 'ChatGPT');
    assert.equal(parsed.plan, 'Credits');
    assert.equal(parsed.comparison_key, null); // Different credit quantities are not equivalent.
    assert.equal(parsed.review_required, true);
  }
  const entry = catalogEntries(offers, now).find(e => e.id === 'chatgpt-codex-credits')!;
  assert.equal(entry.offers.length, titles.length);
  assert.equal(entry.referencePrice, 100);
  assert.equal(entry.priceKind, 'lowest');
});

test('Codex accounts, subscriptions, referral rewards and verification services are not credit top-ups', () => {
  for (const title of ['Codex 好友邀请奖励｜额度增加', 'Codex 邀请奖励 500点',
    'Codex Free 账号｜20$ 额度', 'Codex 成品号 500额度', 'Codex Plus 月卡',
    'Codex Pro 500刀会员充值', 'Codex 接马服务 500点', 'Kiro Pro 积分充值']) {
    assert.equal(isCodexCredits(title), false, title);
    assert.notEqual(catalogProductId({ ...demo.offers[0], raw_title: title, platform: '其他' }), 'chatgpt-codex-credits', title);
  }
});
