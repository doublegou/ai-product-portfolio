/** Public offer shape retained from aimarketing. */
export type Offer = {
  id: string;
  raw_title: string;
  price_note?: string | null;
  platform: string;
  plan: string;
  delivery: string;
  duration_days: number | null;
  comparison_key: string | null;
  review_required: boolean;
  price: number;
  currency: string;
  stock_status: string;
  stock_quantity?: number | null;
  stock_text?: string | null;
  purchase_url: string;
  last_seen_at: string;
  expires_at: string;
  sources: { name: string; base_url: string };
};

export type Product = {
  id: string;
  name: string;
  platform: string;
  plan: string;
  category: "subscription" | "accessory" | "unclassified";
  description: string;
  tagline: string;
};

export type ProductSummary = Product & {
  offers: Offer[];
  channels: number;
  referencePrice: number | null;
  currency: string;
  available: number;
};

export type Snapshot = {
  mode: "demo" | "snapshot";
  capturedAt: string;
  offers: Offer[];
};
