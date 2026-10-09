import { StrictMode, useEffect } from "react";
import { createRoot, type Root } from "react-dom/client";
import { BrowserRouter, Route, Routes, useLocation } from "react-router-dom";
import { Layout } from "./components/Layout";
import { SubscriptionLayout } from "./components/SubscriptionLayout";
import { Home } from "./pages/Home";
import { Catalog } from "./pages/Catalog";
import { Detail } from "./pages/Detail";
import { Api } from "./pages/Api";
import { OffersProvider } from "./data";
import { NotFound } from "./pages/NotFound";
import "./styles.css";
import "./glass.css";
import "./redesign.css";
import "./theme.css";
import "./surfaces.css";
import "./components/ContactFooter.css";
import { useDarkMode } from "./lib/colorScheme";
import { trackGooglePageView } from "./lib/google-analytics";

function App() {
  const location = useLocation();
  const dark = useDarkMode();
  useEffect(() => { document.documentElement.dataset.theme = dark ? "dark" : "light"; }, [dark]);
  useEffect(() => {
    document.title = `${location.pathname === "/" ? "AI 渠道汇总比价" : location.pathname === "/api-pricing" ? "API" : "卡网订阅比价"} — PriceMap AI`;
    trackGooglePageView();
  }, [location.pathname]);
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Home />} />
        <Route path="subscriptions" element={<OffersProvider><SubscriptionLayout /></OffersProvider>}>
          <Route index element={<Catalog />} />
          <Route path=":productId" element={<Detail />} />
        </Route>
        <Route path="api-pricing" element={<Api />} />
        <Route path="*" element={<NotFound />} />
      </Route>
    </Routes>
  );
}
// Retain the mounted root if the entry module is replaced during development.
const root: Root =
  import.meta.hot?.data.root ?? createRoot(document.getElementById("root")!);
if (import.meta.hot) import.meta.hot.data.root = root;
root.render(
  <StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </StrictMode>,
);
