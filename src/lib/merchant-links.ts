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

/** Source-specific landing pages also apply to previously published snapshots. */
export function merchantPurchaseLink(value: string, source: string): string | undefined {
  const home = merchantLink(source);
  if (home) {
    const url = new URL(home);
    if (url.hostname === 'aicz.ink' && !url.port) return 'https://aicz.ink/';
  }
  return merchantLink(value);
}
