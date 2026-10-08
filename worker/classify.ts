import type { Classification } from "./types.ts";
export function classify(title: string): Classification {
  const t = title.normalize("NFKC").toLowerCase();
  const ancillary =
    /虚拟卡|visa卡|visa虚拟|邀请码|资格|优惠券|兑换券|接码|接马|接碼|接馬|手机号|纯邮箱|空白账号/.test(
      t,
    );
  const platform = /chat\s*gpt|openai|g[.·\s]*p[.·\s]*t/.test(t)
    ? "ChatGPT"
    : /claude/.test(t)
      ? "Claude"
      : /gemini|google\s*ai|谷歌.*(?:pro|ultra|会员|订阅)/.test(t)
        ? "Gemini"
        : /grok/.test(t)
          ? "Grok"
          : /cursor/.test(t)
            ? "Cursor"
            : "其他";
  // The first plan in the title is the product; later mentions can describe upgrades.
  const planMatch = t.match(/\b(ultra|plus|max|team|pro|go)(?=\d|[^a-z]|$)/);
  const plan = ancillary
    ? "未知"
    : planMatch
      ? (
          {
            ultra: "Ultra",
            plus: "Plus",
            max: "Max",
            team: "Team",
            pro: "Pro",
            go: "Go",
          } as Record<string, string>
        )[planMatch[1]]
      : /团队/.test(t)
        ? "Team"
        : "未知";
  const delivery = ancillary
    ? "未知"
    : /共享|拼车|合租/.test(t)
      ? "共享"
      : /成品|账号购买|帐号购买/.test(t)
        ? "成品号"
        : /cdk|卡密|兑换码/.test(t)
          ? "CDK"
          : /代充|直充|充值/.test(t)
            ? "代充"
            : "未知";
  let duration_days: number | null = null;
  const d = t.match(/(\d+)\s*(天|日|个月|月|年)/);
  if (d)
    duration_days =
      Number(d[1]) * ({ 天: 1, 日: 1, 个月: 30, 月: 30, 年: 365 }[d[2]] ?? 1);
  else if (/年卡|年付|一年/.test(t)) duration_days = 365;
  else if (/月卡|月付|一个月/.test(t)) duration_days = 30;
  const review_required =
    ancillary ||
    platform === "其他" ||
    plan === "未知" ||
    delivery === "未知" ||
    !duration_days ||
    /试用|体验|学生|首月|新客|地区|[美欧日菲港]区|[美歐日菲港]區|菲律宾|印度|土耳其|质保|网页|日抛|额度|ios|卡付|卡充|覆盖|到期|续费|\d+\s*[x×]|\d+\s*(人|位)|\d+\s*倍/.test(
      t,
    );
  return {
    platform,
    plan,
    delivery,
    duration_days,
    review_required,
    comparison_key: review_required
      ? null
      : `${platform}:${plan}:${delivery}:${duration_days}`,
  };
}
