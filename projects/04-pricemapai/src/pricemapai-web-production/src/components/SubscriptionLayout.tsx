import { DataStatus } from "./DataStatus";
import { useMemo } from "react";
import { Link, Outlet, useLocation, useNavigate, useParams } from "react-router-dom";
import { ChevronLeft } from "lucide-react";
import { CategoryIcon } from "./CategoryIcon";
import { PlatformIcon } from "./PlatformIcon";
import { SearchField } from "./SearchField";
import { platforms, productById } from "../data/products";
import { catalogProductById, catalogProductId, catalogTabs, filterCatalogEntries, productCategory, selectedCategory, selectCategory } from "../lib/catalog";
import { familyById, familyByVariant, groupedCatalogEntries } from "../lib/catalogGroups";
import { useOffers } from "../data";
import { classifyProduct } from "../lib/offers";
import { useStickyStack } from "../lib/useStickyStack";
import { trackAnalyticsEvent } from "../lib/analytics";

/** The directory and its quote details share one persistent browsing frame. */
export function SubscriptionLayout() {
  const { offers, referenceTime } = useOffers();
  const location = useLocation();
  const stickyRoot = useStickyStack(location.pathname + location.search);
  const navigate = useNavigate();
  const { productId } = useParams();
  const params = new URLSearchParams(location.search);
  const detail = location.pathname !== "/subscriptions" && location.pathname !== "/subscriptions/";
  const product = familyById.get(productId ?? "") ?? catalogProductById.get(productId ?? "") ?? productById.get(productId ?? "");
  const directoryParams = detail ? new URLSearchParams(params.get("from") ?? "") : params;
  if (detail && ["list", "grid"].includes(params.get("view") ?? "")) directoryParams.set("view", params.get("view")!);
  if (detail && !params.has("from") && product) {
    const category = productCategory(product);
    if (platforms.includes(category)) directoryParams.set("platform", category);
    else directoryParams.set("category", category);
  }
  const category = selectedCategory(directoryParams);
  const all = useMemo(() => groupedCatalogEntries(offers, referenceTime), [offers, referenceTime]);
  const matching = filterCatalogEntries(all, directoryParams, referenceTime);
  const categoryTitle = catalogTabs.find(tab => tab.id === category)?.label ?? "全部";
  const offerCount = matching.reduce((count, product) => count + product.offers.length, 0);
  const family = familyById.get(productId ?? "") ?? familyByVariant.get(productId ?? "");
  const variant = family?.variants.find(item => item.id === params.get("variant"))
    ?? family?.variants.find(item => item.id === productId) ?? family?.variants[0];
  const detailId = variant?.id ?? productId;
  const detailQuery = (params.get("q") ?? "").trim().toLowerCase();
  const detailOffers = detail ? offers.filter(offer => offer.currency === "CNY" &&
    (catalogProductById.has(detailId ?? "") ? catalogProductId(offer) === detailId : classifyProduct(offer) === detailId) &&
    `${offer.sources.name} ${offer.raw_title}`.toLowerCase().includes(detailQuery)) : [];

  return <div ref={stickyRoot} className="catalog-page container page-body">
    <div className="directory-heading directory-search-heading catalog-category-heading">
      <h1>卡网订阅</h1>
      <div className="category-heading-summary">
        <div className="category-heading-label">
          {detail && <Link className="detail-title-back" to={`/subscriptions${directoryParams.size ? `?${directoryParams}` : ""}`} onClick={() => trackAnalyticsEvent("scope_change", { scope: "products", platform: product?.platform })} aria-label="返回套餐目录"><ChevronLeft size={30} /></Link>}
          <h2>{detail ? family?.name ?? product?.name ?? categoryTitle : categoryTitle}</h2>
        </div>
        <p>{detail ? `${new Set(detailOffers.map(offer => offer.sources.base_url)).size} 家商家 · ${detailOffers.length} 条报价` : `${matching.length} 类商品 · ${offerCount} 条报价`}</p>
      </div>
      <SearchField value={(detail ? params : directoryParams).get("q") ?? ""} label="搜索套餐或商家" placeholder={detail ? "搜索商家或商品…" : "搜索套餐、平台或商家…"} onChange={value => {
        const next = new URLSearchParams(detail ? params : directoryParams);
        next.delete("page");
        value ? next.set("q", value) : next.delete("q");
        navigate(`${detail ? location.pathname : "/subscriptions"}${next.size ? `?${next}` : ""}`, { replace: true });
      }} />
    </div>
    <div className="catalog-layout">
      <aside className="catalog-sidebar" aria-label="商品分类">
        <div className="catalog-tabs" role="group" aria-label="商品分类">
          {catalogTabs.map(tab => <button key={tab.id} className={category === tab.id ? "active" : ""} aria-pressed={category === tab.id}
            onClick={() => {
              if (category !== tab.id) trackAnalyticsEvent("platform_filter_change", { platform: tab.id || "全部" });
              const next = selectCategory(directoryParams, tab.id).toString();
              navigate(`/subscriptions${next ? `?${next}` : ""}`);
            }}>
            {platforms.includes(tab.id) ? <PlatformIcon platform={tab.id} small /> : <CategoryIcon category={tab.id} />}
            {tab.label}
          </button>)}
        </div>
      </aside>
      <div className="catalog-content"><DataStatus /><Outlet /></div>
    </div>
  </div>;
}
