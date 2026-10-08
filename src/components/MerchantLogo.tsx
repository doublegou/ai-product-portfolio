import { useState } from "react";
import { safeLink } from "../lib/offers";

// Original storefront assets; provenance is recorded in public/logos/merchants/sources.json.
const logos: Record<string, string> = {
  "16688.com.cn": "16688.png",
  "gospv.com": "gospv.webp",
  "dimosky.com": "dimosky.ico",
  "lianduang.com": "lianduang.ico",
  "ai666.id": "ai666.jpg",
  "shop.gpt.ge": "v3.svg",
  "aisou.pro": "aisou.ico",
  "nikoers.com": "nikoers.ico",
  "faka.redeemai.me": "redeemai.png",
};

export function MerchantLogo({ url, name }: { url: string; name: string }) {
  const [failed, setFailed] = useState(false);
  const home = safeLink(url);
  if (!home || failed) return <span className="merchant-logo merchant-logo-fallback" aria-hidden="true">{(name.match(/[\p{L}\p{N}]/u)?.[0] ?? "?").toUpperCase()}</span>;
  const origin = new URL(home);
  const host = origin.hostname.replace(/^www\./, "");
  const asset = logos[host];
  return <img className="merchant-logo" src={asset ? `/logos/merchants/${asset}` : `${origin.origin}/favicon.ico`} alt="" width={30} height={30} loading="lazy" decoding="async" referrerPolicy="no-referrer" onError={() => setFailed(true)} />;
}
