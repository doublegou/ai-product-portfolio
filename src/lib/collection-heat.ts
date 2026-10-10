export const heatCounters = ['purchase_clicks', 'shop_clicks', 'pricing_clicks', 'detail_views'] as const;
export type HeatSource = { id: string; clicks: number } & Partial<Record<typeof heatCounters[number], number>>;
export function normalizeHeatSource(value: HeatSource): HeatSource {
  if (!value || typeof value.id !== 'string' || !value.id || value.id.length > 300 ||
      !Number.isSafeInteger(value.clicks) || value.clicks < 0 || value.clicks > 1000000) throw Error('Invalid heat source');
  const result: HeatSource = { id: value.id, clicks: value.clicks };
  for (const key of heatCounters) {
    if (value[key] === undefined) continue;
    if (!Number.isSafeInteger(value[key]) || value[key]! < 0 || value[key]! > value.clicks) throw Error('Invalid heat counter');
    result[key] = value[key];
  }
  return result;
}
