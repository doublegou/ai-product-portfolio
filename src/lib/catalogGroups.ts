import { catalogEntries, catalogProductById, summarizeCatalogEntry, type CatalogEntry, type CatalogProduct } from "./catalog";
import type { Offer } from "../data/types";

export type ProductFamily = CatalogProduct & { variants: { id: string; label: string }[] };
const definitions = [
  ["chatgpt-plus-family", "ChatGPT Plus", [["chatgpt-plus-recharge", "充值"], ["chatgpt-plus", "成品号"]]],
  ["chatgpt-pro-family", "ChatGPT Pro", [["chatgpt-pro-5x", "100 刀档 · 5x"], ["chatgpt-pro-20x", "200 刀档 · 20x"], ["chatgpt-pro-500", "500 刀档"]]],
  ["claude-max-family", "Claude Max", [["claude-max-5x", "5x"], ["claude-max-20x", "20x"]]],
  ["claude-team-family", "Claude Team", [["claude-team-standard", "Standard · 1.25x"], ["claude-team-premium", "Premium · 6.25x"]]],
  ["gemini-pro-family", "Gemini Pro", [["gemini-pro-year", "成品号"], ["gemini-pro-recharge", "充值 / 开通"]]],
  ["gemini-ultra-family", "Google AI Ultra", [["gemini-ultra-5x", "5x"], ["gemini-ultra", "20x / 未注明档位"]]],
  ["super-grok-family", "SuperGrok", [["super-grok-lite", "Lite"], ["super-grok", "Super"], ["super-grok-heavy", "Heavy"]]],
] as const;

export const productFamilies: ProductFamily[] = definitions.map(([id, name, variants]) => {
  const base = catalogProductById.get(variants[0][0])!;
  const subtitle = variants.map(([, label]) => label).join(" · ");
  return { ...base, id, name, subtitle, description: subtitle, tagline: subtitle, variants: variants.map(([id, label]) => ({ id, label })) };
});
export const familyById = new Map(productFamilies.map(family => [family.id, family]));
export const familyByVariant = new Map(productFamilies.flatMap(family => family.variants.map(variant => [variant.id, family] as const)));

// Only the directory is aggregated. Each detail tab retains its own precise taxonomy and quotes.
export function groupedCatalogEntries(offers: Offer[], now: number): CatalogEntry[] {
  const entries = catalogEntries(offers, now);
  const emitted = new Set<string>();
  return entries.flatMap(entry => {
    const family = familyByVariant.get(entry.id);
    if (!family) return [entry];
    if (emitted.has(family.id)) return [];
    emitted.add(family.id);
    const ids = new Set(family.variants.map(variant => variant.id));
    return [summarizeCatalogEntry(family, entries.filter(item => ids.has(item.id)).flatMap(item => item.offers), now)];
  });
}
