// Keep storefront collection addresses separate from this site's referral links.
const referrals: Readonly<Record<string, string>> = {
  "gospv.com": "NTJJLYNZ",
  "burstpro-ai.online": "TSES4VLN",
  "xigua.ink": "XG53029E3567",
};

export function merchantLink(value: string): string | undefined {
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || url.username || url.password) return undefined;
    const referral = !url.port ? referrals[url.hostname] : undefined;
    if (!referral) return url.href;
    // Preserve product paths and other options; replace any previous referral.
    url.searchParams.set("aff", referral);
    return url.href;
  } catch {
    return undefined;
  }
}
