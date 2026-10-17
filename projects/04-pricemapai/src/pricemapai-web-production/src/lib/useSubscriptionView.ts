import { useEffect, useState } from "react";

type View = "list" | "grid";
const STORAGE_KEY = "pricemap.subscription.view";
const isView = (value: string | null): value is View => value === "list" || value === "grid";

/** Explicit links take priority; ordinary entries restore the last chosen layout. */
export function useSubscriptionView(requested: string | null): View {
  const [saved, setSaved] = useState<View>(() => {
    try {
      const value = window.localStorage.getItem(STORAGE_KEY);
      return isView(value) ? value : "list";
    } catch {
      return "list";
    }
  });
  useEffect(() => {
    if (!isView(requested)) return;
    setSaved(requested);
    try { window.localStorage.setItem(STORAGE_KEY, requested); } catch { /* URL switching still works if storage is unavailable. */ }
  }, [requested]);
  return isView(requested) ? requested : saved;
}
