export interface Source {
  id: string;
  name: string;
  base_url: string;
  collector: "kami" | "dujiao" | "16688" | "shopapi" | "json" | "html";
  config: Record<string, any>;
  interval_minutes: number;
  enabled: boolean;
  lease_token: string;
  last_success_at: string | null;
  last_error: string | null;
  next_crawl_at: string;
}
export interface Candidate {
  external_id: string;
  raw_title: string;
  price: number;
  currency: string;
  stock_status: "in_stock" | "out_of_stock" | "unknown";
  purchase_url: string;
  raw_data?: Record<string, unknown>;
}
export interface Classification {
  platform: string;
  plan: string;
  delivery: string;
  duration_days: number | null;
  comparison_key: string | null;
  review_required: boolean;
}
export interface Env {
  SUPABASE_URL: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
  ADMIN_TOKEN: string;
  CRAWLER_FUNCTION_URL?: string;
  CRAWLER_TOKEN?: string;
  SNAPSHOT_SYNC?: Fetcher;
  ASSETS: Fetcher;
}
