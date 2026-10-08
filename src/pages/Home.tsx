import { Link } from "react-router-dom";
import { SlidersHorizontal, ExternalLink, Clock3 } from "lucide-react";
import { HeroMascot } from "../components/HeroMascot";
import { HeroCarousel } from "../components/HeroCarousel";

export function Home() {
  return <div className="home-v2 container">
    <section className="subscription-hero">
      <div className="entry-copy">
        <h1>全网 AI 渠道<br/><span>一站汇总比价</span></h1>
        <p>订阅、代充、成品号，直接比较各渠道报价。</p>
        <Link className="btn-17" to="/subscriptions">
          <span className="text-container"><span className="text">卡网订阅</span></span>
        </Link>
      </div>
      <HeroMascot />
    </section>
    <section className="api-entry">
      <div className="entry-copy">
        <h2>各家 API 渠道<br/><span>模型价格一站比</span></h2>
        <p>汇总官方与中转渠道，比较模型、价格与接入方式。</p>
        <Link className="btn-17" to="/api-pricing">
          <span className="text-container"><span className="text">API</span></span>
        </Link>
      </div>
      <HeroCarousel />
    </section>
    <section className="home-notes" aria-label="比价说明">
      <article className="home-note glass-surface">
        <SlidersHorizontal size={20} strokeWidth={1.5} aria-hidden="true" />
        <h2>报价口径</h2>
        <p>参考价可能对应不同规格。同规格最低价，仅比较有货且有效的报价。</p>
      </article>
      <article className="home-note glass-surface">
        <ExternalLink size={20} strokeWidth={1.5} aria-hidden="true" />
        <h2>交易与售后</h2>
        <p>本站汇总渠道信息，购买前往商家原站。成交价、交付和售后以商家说明为准。</p>
      </article>
      <article className="home-note glass-surface">
        <Clock3 size={20} strokeWidth={1.5} aria-hidden="true" />
        <h2>报价时间</h2>
        <p>每条报价保留记录时间。价格与库存可能变化，下单前请到原站确认。</p>
      </article>
    </section>
  </div>;
}
