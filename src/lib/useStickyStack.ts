import { useLayoutEffect, useRef } from "react";

/** Measure each sticky row so wrapped controls never overlap the next row. */
export function useStickyStack(route: string) {
  const root = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    const element = root.current;
    if (!element) return;
    const heading = element.querySelector<HTMLElement>(".catalog-category-heading");
    const toolbar = element.querySelector<HTMLElement>(".catalog-toolbar, .detail-directory-toolbar");
    const resultSelector = ".catalog-table tbody, .subscription-grid, .offer-block, .catalog-content .empty-state, .api-cards, .api-official-list, .api-station-profile, .inventory-note, .api-data-status";
    let results: HTMLElement[] = [];
    let frame = 0;
    const updatePinned = () => {
      // Live quotes and their table header mount after the first API response.
      // Resolve current nodes instead of retaining the initial empty list.
      const stickyRows = [heading, toolbar, element.querySelector<HTMLElement>(".catalog-table thead, .offer-table-head"), element.querySelector<HTMLElement>(".catalog-sidebar")].filter((row): row is HTMLElement => !!row);
      results = [...element.querySelectorAll<HTMLElement>(resultSelector)];
      let boundary = 0;
      for (const row of stickyRows) {
        const style = getComputedStyle(row);
        const top = parseFloat(style.top);
        const rect = row.getBoundingClientRect();
        const pinned = style.position === "sticky" && Number.isFinite(top) && rect.top <= top + .5;
        row.classList.toggle("is-pinned", pinned);
        // Desktop side navigation does not cover the content column.
        if (pinned && (!row.classList.contains("catalog-sidebar") || window.innerWidth <= 760)) boundary = Math.max(boundary, rect.bottom);
      }
      for (const result of results) {
        const clipped = Math.max(0, boundary - result.getBoundingClientRect().top);
        result.style.clipPath = clipped ? `inset(${clipped}px -32px -32px -32px)` : "";
      }
    };
    const onScroll = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(updatePinned);
    };
    const measure = () => {
      element.style.setProperty("--directory-heading-height", `${heading?.getBoundingClientRect().height ?? 0}px`);
      element.style.setProperty("--directory-toolbar-height", `${toolbar?.getBoundingClientRect().height ?? 0}px`);
      updatePinned();
    };
    const onContentChange = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(measure);
    };
    measure();
    const observer = new ResizeObserver(onContentChange);
    observer.observe(element);
    if (heading) observer.observe(heading);
    if (toolbar) observer.observe(toolbar);
    // Also handle equal-height replacements and data arriving at a restored
    // scroll position, before the user generates another scroll event.
    const contentObserver = new MutationObserver(onContentChange);
    contentObserver.observe(element, { childList: true, subtree: true });
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onContentChange);
    return () => {
      observer.disconnect();
      contentObserver.disconnect();
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onContentChange);
      cancelAnimationFrame(frame);
      for (const result of results) result.style.clipPath = "";
    };
  }, [route]);
  return root;
}
