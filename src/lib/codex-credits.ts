// Credit top-ups are separate from accounts, subscriptions and referral rewards.
export function isCodexCredits(title: string): boolean {
  const text = title.normalize('NFKC').toLowerCase();
  if (!/codex/.test(text)) return false;
  if (/邀请|奖励|赠送|赠品|接码|接马|接碼|接馬|接🐎|手机号|教程|工具|成品|共享|合租|月卡|年卡|会员|订阅|(?:账号|帐号).*(?:出售|购买)|(?:free|plus|pro|team|go).*账号/.test(text)) return false;
  return /额度充值|点数|credits|积分|\d+\s*(?:额度|点(?:使用额度)?)/.test(text);
}
