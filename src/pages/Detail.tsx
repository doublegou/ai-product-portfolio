import { GlassSelect } from "../components/GlassSelect";
import { useMemo } from "react";
import { Link, useParams, useSearchParams } from "react-router-dom";
import {
  ArrowUpRight,
  ChevronRight,
  Check,
  LayoutGrid,
  List,
} from "lucide-react";
import { PlatformIcon } from "../components/PlatformIcon";
import { MerchantLogo } from "../components/MerchantLogo";
import { EmptyState } from "../components/ProductList";
import { useOffers } from "../data";
import { DataUpdated } from "../components/DataUpdated";
import { useSubscriptionView } from "../lib/useSubscriptionView";
import { productById } from "../data/products";
import { catalogProductById, catalogProductId } from "../lib/catalog";
import { familyById, familyByVariant } from "../lib/catalogGroups";
import { merchantLink } from "../lib/merchant-links";
import type { Offer } from "../data/types";
import {
  classifyProduct,
  durationLabel,
  isAvailable,
  isFresh,
  lowestIds,
  money,
  safeLink,
  stockDisplay,
} from "../lib/offers";
import { NotFound } from "./NotFound";

function OfferRow({ offer, lowest }: { offer: Offer; lowest: boolean }) {
  const { referenceTime } = useOffers();
  const link = merchantLink(offer.purchase_url);
  const home = merchantLink(offer.sources.base_url);
  return (
    <div
      className={`offer-block ${!isFresh(offer, referenceTime) ? "expired" : ""}`}
    >
      <div className="offer-row">
        <div className="merchant-cell">
          <MerchantLogo url={offer.sources.base_url} name={offer.sources.name} />
          <div>
            {home ? <a className="merchant-home" href={home} target="_blank" rel="noopener noreferrer" aria-label={`前往 ${offer.sources.name} 店铺首页`}>
              <strong title={offer.sources.name}>{offer.sources.name}</strong>
              <span className="merchant-home-indicator"><ArrowUpRight size={13} /></span>
            </a> : <strong title={offer.sources.name}>{offer.sources.name}</strong>}
            <span>
              {safeLink(offer.sources.base_url)
                ? new URL(offer.sources.base_url).hostname.replace(/^www\./, "")
                : "来源待确认"}
            </span>
          </div>
        </div>
        <div className="offer-original" title={[offer.raw_title, offer.price_note].filter(Boolean).join("\n")}>{offer.raw_title}</div>
        <div className="offer-spec">
          <span>{offer.delivery === "未知" ? "—" : offer.delivery}</span>
          {offer.duration_days !== null && <><span className="offer-spec-dot">·</span><span>{durationLabel(offer.duration_days).split(" / ").pop()}</span></>}
        </div>
        <div className="offer-price">
          <strong>{money(offer.price, offer.currency)}</strong>
          {lowest && (
            <span className="lowest-label">
              <Check size={10} />
              同规格最低
            </span>
          )}
        </div>
        <div className="offer-stock" title={offer.stock_text || "库存数量和状态以原站公布的信息为准"}>
          {stockDisplay(offer, referenceTime)}
        </div>
        <DataUpdated className="offer-updated" at={offer.last_seen_at}/>
        {link ? (
          <a
            className="merchant-link"
            href={link}
            target="_blank"
            rel="noopener noreferrer"
            aria-label={`前往 ${offer.sources.name} 原站购买`}
          >
            原站购买 <ChevronRight size={16} />
          </a>
        ) : (
          <span className="muted">链接待确认</span>
        )}
      </div>
    </div>
  );
}

export function Detail() {
  const { offers: allOffers, referenceTime } = useOffers();
  const { productId } = useParams();
  const [params, setParams] = useSearchParams();
  const get = (name: string, fallback = "") => params.get(name) ?? fallback;
  const directProduct = catalogProductById.get(productId ?? "");
  const family = familyById.get(productId ?? "") ?? familyByVariant.get(directProduct?.id ?? "");
  const requestedVariant = get("variant", directProduct?.id);
  const selectedVariant = family?.variants.find(variant => variant.id === requestedVariant) ?? family?.variants[0];
  const catalogProduct = selectedVariant ? catalogProductById.get(selectedVariant.id) : directProduct;
  const legacyProduct = productById.get(productId ?? "");
  const product = catalogProduct ?? (legacyProduct ? { ...legacyProduct, subtitle: legacyProduct.description } : undefined);
  const from = get("from");
  const view = useSubscriptionView(params.get("view") ?? new URLSearchParams(from).get("view"));
  const update = (key: string, value: string) => {
    const next = new URLSearchParams(window.location.search);
    for (const key of ["currency", "delivery", "duration", "stock"]) next.delete(key);
    value ? next.set(key, value) : next.delete(key);
    setParams(next);
  };
  const offers = useMemo(
    () => allOffers.filter((o) => o.currency === "CNY" && (catalogProduct ? catalogProductId(o) === catalogProduct.id : classifyProduct(o) === productId)),
    [productId, catalogProduct, allOffers],
  );
  const lowest = lowestIds(offers, referenceTime);
  const filtered = offers
    .filter(o => !get("q").trim() || `${o.sources.name} ${o.raw_title}`.toLowerCase().includes(get("q").trim().toLowerCase()))
    .sort((a, b) =>
      get("sort") === "updated"
        ? Date.parse(b.last_seen_at) - Date.parse(a.last_seen_at)
        : Number(isAvailable(b, referenceTime)) -
            Number(isAvailable(a, referenceTime)) || a.price - b.price,
    );
  const clear = () => {
    const next = new URLSearchParams();
    if (from) next.set("from", from);
    if (selectedVariant) next.set("variant", selectedVariant.id);
    setParams(next);
  };
  if (!product) return <NotFound />;
  return (
    <div className="detail-page embedded-detail">
      <div className="detail-directory-toolbar">
        <div className="detail-tabs-group">
          {family && <nav className="detail-variant-pills" aria-label="套餐类型">
            {family.variants.map(variant => {
              const next = new URLSearchParams();
              if (from) next.set("from", from);
              next.set("variant", variant.id);
              next.set("view", view);
              return <Link key={variant.id} className={variant.id === selectedVariant?.id ? "active" : ""} aria-current={variant.id === selectedVariant?.id ? "page" : undefined} to={`/subscriptions/${family.id}?${next}`}><PlatformIcon platform={product.platform} small />{variant.label}</Link>;
            })}
          </nav>}
        </div>
        <div className="detail-display-actions">
          <GlassSelect aria-label="报价排序" value={get("sort")} onChange={value => update("sort", value)}>
            <option value="">有货优先 · 价格升序</option>
            <option value="updated">最近更新</option>
          </GlassSelect>
          <button className="view-switch" type="button" aria-label={view === "list" ? "切换为网格" : "切换为列表"} onClick={() => update("view", view === "list" ? "grid" : "list")}>
            {view === "list" ? <LayoutGrid size={18} /> : <List size={18} />}
          </button>
        </div>
      </div>
      <section className="quotes-section compact-quotes">
        <p className="inventory-note">库存沿用原站公布的数量或状态；“库存充足”等文字不代表商家公布了具体件数。</p>
        <div className={`quotes-table ${view === "grid" ? "quotes-grid" : "quotes-list"}`}>
          {view === "list" && <div className="offer-table-head">
            <span>商家</span>
            <span>原始商品信息</span>
            <span>交付方式</span>
            <span>报价</span>
            <span title="数量或状态来自原站；库存充足等文字不代表公布了具体件数">库存（原站公布）</span>
            <span>更新</span>
            <span>操作</span>
          </div>}
          {filtered.length ? (
            filtered.map((o) => (
              <OfferRow key={o.id} offer={o} lowest={lowest.has(o.id)} />
            ))
          ) : (
            <EmptyState
              title={offers.length ? "暂无符合条件的报价" : "暂无报价"}
              description={offers.length ? "没有匹配的商家或商品。" : "该类目暂未收录渠道报价。"}
              onReset={offers.length ? clear : undefined}
            />
          )}
        </div>
      </section>
    </div>
  );
}
