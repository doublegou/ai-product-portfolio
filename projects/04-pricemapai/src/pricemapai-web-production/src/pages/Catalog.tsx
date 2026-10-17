import { Pagination } from "../components/Pagination";
import { GlassSelect } from "../components/GlassSelect";
import { CategoryIcon } from "../components/CategoryIcon";
import { useMemo } from "react";
import { useSearchParams } from "react-router-dom";
import {
  LayoutGrid,
  List,
} from "lucide-react";
import { ProductList, EmptyState } from "../components/ProductList";
import { useOffers } from "../data";
import { filterCatalogEntries, otherCatalogTabs, selectedCategory } from "../lib/catalog";

import { groupedCatalogEntries } from "../lib/catalogGroups";
import { useSubscriptionView } from "../lib/useSubscriptionView";
import { trackAnalyticsEvent } from "../lib/analytics";

const PAGE_SIZE = 24;
export function Catalog() {
  const { offers, referenceTime } = useOffers();
  const [params, setParams] = useSearchParams();
  const get = (name: string, fallback = "") => params.get(name) ?? fallback;
  const category = selectedCategory(params);
  const view = useSubscriptionView(params.get("view"));
  const detailFrom = new URLSearchParams(params);
  detailFrom.set("view", view);
  const update = (key: string, value: string, replace = false) => {
    if (key === "view" && value !== view) trackAnalyticsEvent("view_change", { view: value, platform: category || "全部", surface: "subscriptions" });
    const next = new URLSearchParams(window.location.search);
    next.delete("saved");
    next.delete("currency");
    for (const key of ["delivery", "duration", "stock", "min", "max"]) next.delete(key);
    value ? next.set(key, value) : next.delete(key);
    if (key !== "page") next.delete("page");
    setParams(next, { replace });
  };
  const all = useMemo(() => groupedCatalogEntries(offers, referenceTime), [offers, referenceTime]);
  const filtered = filterCatalogEntries(all, params, referenceTime)
    .sort((a, b) =>
      get("sort") === "price"
        ? (a.referencePrice ?? Infinity) - (b.referencePrice ?? Infinity)
        : get("sort") === "channels"
          ? b.channels - a.channels
          : 0,
    );
  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const rawPage = Number(get("page", "1"));
  const page = Number.isSafeInteger(rawPage)
    ? Math.max(1, Math.min(totalPages, rawPage))
    : 1;
  const visible = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);
  const reset = () => { trackAnalyticsEvent("advanced_filters_reset"); setParams({}); };
  return (
    <>
      <div className="catalog-toolbar">
        {category === "other" && <nav className="other-category-tabs" aria-label="其他商品分类">
          {otherCatalogTabs.map(tab => <button key={tab.id} type="button" className={get("subtype") === tab.id ? "active" : ""} aria-pressed={get("subtype") === tab.id} onClick={() => update("subtype", tab.id)}><CategoryIcon category={tab.id} />{tab.label}</button>)}
        </nav>}
        <div className="toolbar-actions">
          <label className="sort-field">
            <GlassSelect
              aria-label="套餐排序"
              value={get("sort")}
              onChange={(value) => update("sort", value)}
            >
              <option value="">默认排序</option>
              <option value="price">最低价从低到高</option>
              <option value="channels">商家数量从多到少</option>
            </GlassSelect>
          </label>
          <button className="view-switch" type="button" aria-label={view === "grid" ? "切换为列表" : "切换为网格"} onClick={() => update("view", view === "grid" ? "list" : "grid")}>
            {view === "grid" ? <List size={18} /> : <LayoutGrid size={18} />}
          </button>
        </div>
      </div>
      {visible.length ? (
        <ProductList products={visible} from={detailFrom.toString()} view={view} />
      ) : (
        <EmptyState onReset={reset} />
      )}
      <Pagination page={page} total={totalPages} onChange={value=>update("page", String(value))} label="套餐分页"/>

    </>
  );
}
