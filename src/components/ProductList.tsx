import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { ChevronRight, SearchX } from "lucide-react";
import { PlatformIcon } from "./PlatformIcon";
import type { CatalogEntry } from "../lib/catalog";
import { money } from "../lib/offers";
import { DataUpdated } from "./DataUpdated";

export function ProductList({ products, from = "", view = "list" }: { products: CatalogEntry[]; from?: string; view?: "grid" | "list" }) {
  const [now, setNow] = useState(Date.now);
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 60000);
    return () => window.clearInterval(timer);
  }, []);
  const rows = products.map(product => {
    const best = product.priceOffer;
    const deliveries = [...new Set(product.offers.map(offer => offer.delivery).filter(delivery => delivery !== "未知"))].join(" · ") || "—";
    const query = new URLSearchParams();
    if (from) query.set("from", from);
    return { product, best, deliveries, href: `/subscriptions/${product.id}${query.size ? `?${query}` : ""}` };
  });
  if (view === "list") return <div className="catalog-table-wrap subscription-table-wrap">
    <table className="catalog-table subscription-table" aria-label="商品报价列表">
      <colgroup><col className="col-product" /><col className="col-delivery" /><col className="col-status" /><col className="col-price" /><col className="col-updated" /><col className="col-action" /></colgroup>
      <thead><tr><th scope="col">商品</th><th scope="col">交付方式</th><th scope="col">状态</th><th scope="col">最低价 / 参考价</th><th scope="col">更新</th><th scope="col">操作</th></tr></thead>
      <tbody>{rows.map(({product, best, deliveries, href}) => <tr key={product.key}>
        <td><Link className="table-product" to={href}><PlatformIcon platform={product.platform} /><span><strong>{product.name}</strong><small>{product.subtitle}</small></span></Link></td>
        <td className="table-deliveries">{deliveries}</td>
        <td><span className="table-counts"><span>{product.channels} 家商家</span><span>{product.offers.length} 条报价</span></span></td>
        <td><strong className="table-price">{product.referencePrice === null ? "—" : money(product.referencePrice, product.currency)}</strong>{product.priceKind === "reference" && <small className="table-source">参考价 · 库存待确认</small>}<small className="table-source">{best?.sources.name ?? ""}</small></td>
        <td className="table-updated"><DataUpdated at={best?.last_seen_at ?? product.offers.map(o => o.last_seen_at).sort().at(-1)} now={now}/></td>
        <td className="table-action"><Link className="catalog-detail-link" to={href} aria-label={`查看 ${product.name} 详情`}>详情<ChevronRight size={15}/></Link></td>
      </tr>)}</tbody>
    </table>
  </div>;
  return <div className="subscription-grid">{rows.map(({product, best, deliveries, href}) => <Link className="subscription-card glass-surface" key={product.key} to={href}>
    <div className="subscription-card-top"><PlatformIcon platform={product.platform} /><span className="card-counts"><span>{product.channels} 家商家</span><span>{product.offers.length} 条报价</span></span></div>
    <div className="card-identity"><h2>{product.name}</h2><p className="card-specs">{product.subtitle}</p></div>
    <div className="card-price"><div><small>{product.priceKind === "reference" ? "参考价 · 库存待确认" : "最低价"}</small><strong>{product.referencePrice === null ? "—" : money(product.referencePrice, product.currency)}</strong></div><p className="card-source">{best?.sources.name ?? ""}</p></div>
    <div className="card-footer-info"><span className="card-deliveries" aria-label={`交付方式：${deliveries}`}>{deliveries}</span><DataUpdated className="card-updated" at={best?.last_seen_at ?? product.offers.map(o => o.last_seen_at).sort().at(-1)} now={now}/></div>
  </Link>)}</div>;
}

export function EmptyState({
  title = "没有找到符合条件的套餐",
  description = "试试其他关键词，或减少一些筛选条件。",
  onReset,
}: {
  title?: string;
  description?: string;
  onReset?: () => void;
}) {
  return (
    <div className="empty-state">
      <span className="empty-icon">
        <SearchX size={28} />
      </span>
      <h2>{title}</h2>
      <p>{description}</p>
      {onReset && (
        <button className="button secondary" onClick={onReset}>
          重置筛选
        </button>
      )}
    </div>
  );
}
