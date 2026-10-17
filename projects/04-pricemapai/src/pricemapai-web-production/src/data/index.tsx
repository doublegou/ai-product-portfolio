import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import { loadOffers } from "./client";
import type { Offer } from "./types";
import previewSnapshot from "@preview-snapshot";

type OffersState = { offers: Offer[]; loading: boolean; loaded: boolean; error: string | null; referenceTime: number; preview: boolean };
const preview = import.meta.env.DEV && import.meta.env.MODE === "design";
const initial: OffersState = { offers: [], loading: true, loaded: false, error: null, referenceTime: Date.now(), preview };
const OffersContext = createContext<OffersState & { retry: () => void }>({ ...initial, retry() {} });
export const useOffers = () => useContext(OffersContext);

export function OffersProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState(initial);
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    let active = true, pending = false;
    let controller: AbortController | undefined;
    const refresh = async () => {
      if (pending) return;
      pending = true;
      controller = new AbortController();
      const timeout = setTimeout(() => controller?.abort(), 30000);
      try {
        const snapshot = preview ? previewSnapshot : null;
        const offers = snapshot ? snapshot.offers : await loadOffers(fetch, controller.signal);
        if (active) setState({ offers, loading: false, loaded: true, error: null, preview,
          referenceTime: snapshot ? Date.parse(snapshot.capturedAt) : Date.now() });
      } catch (error) {
        if (active) setState(old => ({ ...old, loading: false, referenceTime: Date.now(), error: error instanceof Error ? error.message : "报价加载失败" }));
      } finally {
        clearTimeout(timeout);
        pending = false;
      }
    };
    void refresh();
    const onVisible = () => { if (document.visibilityState === "visible") void refresh(); };
    const timer = setInterval(onVisible, 300000);
    window.addEventListener("focus", onVisible);
    return () => { active = false; controller?.abort(); clearInterval(timer); window.removeEventListener("focus", onVisible); };
  }, [revision]);
  return <OffersContext.Provider value={{ ...state, retry: () => setRevision(n => n + 1) }}>{children}</OffersContext.Provider>;
}
