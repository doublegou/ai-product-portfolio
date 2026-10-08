import { useEffect } from "react";
import { Link, NavLink, Outlet, useLocation } from "react-router-dom";
import { usePageScroll } from "../lib/usePageScroll";
import { ContactFooter } from "./ContactFooter";

export function Layout() {
  usePageScroll();
  const location = useLocation();
  useEffect(() => {
    if (location.pathname !== "/" || location.hash !== "#contact") return;
    const contact = document.getElementById("contact");
    contact?.scrollIntoView({ behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth", block: "start" });
    contact?.focus({ preventScroll: true });
  }, [location.key, location.pathname, location.hash]);

  return <>
    <a className="skip-link" href="#main-content">跳到主要内容</a>
    <header className="site-header">
      <div className="container header-inner">
        <Link to="/" className="brand" aria-label="PriceMap AI 首页">
          <span className="brand-image"><img src="/brand/pricemap-ai.png" alt="PriceMap AI" width={2172} height={724} draggable={false}/></span>
        </Link>
        <nav className="main-nav" aria-label="主导航">
          <NavLink to="/" end>首页</NavLink>
          <NavLink to="/subscriptions">卡网订阅</NavLink>
          <NavLink to="/api-pricing">API</NavLink>
        </nav>
        <Link className="header-contact" to="/#contact">联系我们</Link>
      </div>
    </header>
    <main id="main-content"><Outlet /></main>
    {location.pathname === "/" && <ContactFooter />}
  </>;
}
