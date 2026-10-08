import { useLayoutEffect, useRef } from "react";
import { useLocation, useNavigationType } from "react-router-dom";

/** Restore navigation before paint, without letting shorter results move the sidebar. */
export function usePageScroll() {
  const location = useLocation();
  const navigation = useNavigationType();
  const positions = useRef(new Map<string, number>());
  const previous = useRef<{ key: string; url: string; pathname: string; y: number } | null>(null);

  useLayoutEffect(() => {
    const original = history.scrollRestoration;
    history.scrollRestoration = "manual";
    const remember = () => {
      if (previous.current) previous.current.y = window.scrollY;
    };
    window.addEventListener("scroll", remember, { passive: true });
    return () => {
      history.scrollRestoration = original;
      window.removeEventListener("scroll", remember);
    };
  }, []);

  useLayoutEffect(() => {
    const url = location.pathname + location.search;
    const last = previous.current;
    if (last?.key === location.key) return;
    if (last) {
      positions.current.set(last.key, last.y);
      positions.current.set(last.url, last.y);
    }

    let y = last ? 0 : window.scrollY;
    const saved = positions.current.get(location.key);
    if (navigation === "POP" && saved !== undefined) {
      y = saved;
    } else if (last?.pathname.startsWith("/subscriptions/") && location.pathname === "/subscriptions") {
      y = positions.current.get(url) ?? 0;
    } else if (last?.pathname === location.pathname || (last?.pathname.startsWith("/subscriptions") && location.pathname.startsWith("/subscriptions"))) {
      y = last.y;
      const layout = document.querySelector<HTMLElement>(".catalog-layout");
      const sidebar = document.querySelector<HTMLElement>(".catalog-sidebar");
      if (layout && sidebar) {
        const header = document.querySelector(".site-header")?.getBoundingClientRect().height ?? 56;
        const inset = parseFloat(getComputedStyle(sidebar).top) || header + 16;
        // Keep a pinned sidebar pinned and reveal the beginning of the new results.
        y = Math.min(y, Math.max(0, layout.getBoundingClientRect().top + window.scrollY - inset));
      }
    }

    window.scrollTo({ top: y, behavior: "instant" });
    previous.current = { key: location.key, url, pathname: location.pathname, y: window.scrollY };
  }, [location.key, location.pathname, location.search, navigation]);
}
