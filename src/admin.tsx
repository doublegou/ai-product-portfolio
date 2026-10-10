import { useState, type FormEvent } from "react";
import { createRoot } from "react-dom/client";
import {
  Radar,
  ArrowUpRight,
  Plus,
  RefreshCw,
  LogOut,
  Search,
  Settings2,
  Activity,
  CheckCircle2,
  Clock,
  X,
  FlaskConical,
  Pause,
  Play,
} from "lucide-react";
import "./style.css";
import "./admin.css";
import {priceMetric,money,type TransitPrice} from "./lib/apiTransit";
import {merchantAnalyticsId} from "./lib/analytics";
import type {HeatSource} from "./lib/collection-heat";

type Source = {
  id: string;
  name: string;
  base_url: string;
  collector: string;
  interval_minutes: number;
  adaptive_enabled?: boolean;
  collection_tier?: string;
  config: Record<string, unknown>;
  enabled: boolean;
  last_success_at: string | null;
  last_error: string | null;
  next_crawl_at: string;
};
type Run = {
  id: string;
  sources: { name: string };
  status: string;
  started_at: string;
  offer_count: number;
  error: string | null;
};
type Preview = {
  prices?:TransitPrice[];
  count: number;
  complete: boolean;
  offers: {
    raw_title: string;
    price: number;
    currency: string;
    stock_status: string;
    purchase_url: string;
  }[];
};
const date = (v: string | null) =>
  v
    ? new Date(v).toLocaleString("zh-CN", {
        hour12: false,
        timeZone: "Asia/Shanghai",
      })
    : "尚未采集";
const initialForm = {
  name: "",
  base_url: "",
  collector: "dujiao",
  interval_minutes: "15",
  adaptive_enabled: true,
  config: "{}",
};
const templates: Record<string, object> = {
  kami: {},
  dujiao: {},
  shopapi: { shop_token: "" },
  "16688": {},
  json: {
    path: "/api/products",
    items_path: "data.products",
    fields: {
      id: "id",
      title: "name",
      price: "price",
      stock: "stock",
      url: "url",
    },
    currency: "CNY",
    full_snapshot: false,
  },
  html: {
    path: "/",
    item_selector: ".product-card",
    title_selector: "h3",
    price_selector: ".price",
    link_selector: "a",
    currency: "CNY",
    full_snapshot: false,
  },
};
function Admin() {
  const [dataset,setDataset]=useState("subscriptions");
  const currentTemplates=dataset==="transit"?{
    transit:{snapshot_url:"https://example.com/api/public/transit/v1/snapshot",pricing_url:"https://example.com/public/transit"},
    newapi:{snapshot_url:"https://example.com/api/pricing",pricing_url:"https://example.com/pricing"},
    zivv:{snapshot_url:"https://example.com/api/models/hub",pricing_url:"https://example.com/model-hub"},
    onehop:{snapshot_url:"https://example.com/public/models?locale=zh-Hans&limit=100",pricing_url:"https://example.com/models"},
    public_models:{snapshot_url:"https://example.com/api/v1/models/public",pricing_url:"https://example.com/models"},
  }:templates;
  const emptyForm=dataset==="transit"?{...initialForm,collector:"transit",config:JSON.stringify(currentTemplates.transit,null,2)}:initialForm;
  const [token, setToken] = useState("");
  const [ready, setReady] = useState(false);
  const [sources, setSources] = useState<Source[]>([]);
  const [runs, setRuns] = useState<Run[]>([]);
  const [heat, setHeat] = useState<{generated_at:string|null;sources:HeatSource[]}|null>(null);
  const [tab, setTab] = useState("sources");
  const [q, setQ] = useState("");
  const [status, setStatus] = useState("all");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [editor, setEditor] = useState<"new" | string | null>(null);
  const [form, setForm] = useState(initialForm);
  const [preview, setPreview] = useState<Preview | null>(null);
  function logout() {
    setToken("");
    setReady(false);
    setSources([]);
    setRuns([]);
    setHeat(null);
    setEditor(null);
    setPreview(null);
    setForm(initialForm);
    setNotice("");
  }
  async function api(path: string, method = "GET", body?: unknown, target=dataset) {
    if(target==="transit")path=path.replace("/api/admin/","/api/admin/transit/");
    const response = await fetch(path, {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
    });
    const data: any = await response.json();
    if (response.status === 401) logout();
    if (!response.ok) throw Error(data.error || "请求失败，请稍后重试");
    return data;
  }
  async function refresh(target=dataset) {
    const [s, r, h] = await Promise.all([
      api("/api/admin/sources","GET",undefined,target),
      api("/api/admin/runs","GET",undefined,target),
      api("/api/admin/collection-heat","GET",undefined,"subscriptions"),
    ]);
    setSources(s.sources);
    setRuns(r.runs);
    setHeat(h.heat);
    setReady(true);
  }
  async function action(fn: () => Promise<void>) {
    setBusy(true);
    setError("");
    setNotice("");
    try {
      await fn();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  function edit(source?: Source) {
    setEditor(source?.id ?? "new");
    setForm(
      source
        ? {
            name: source.name,
            base_url: source.base_url,
            collector: source.collector,
            interval_minutes: String(source.interval_minutes),
            adaptive_enabled: source.adaptive_enabled !== false,
            config: JSON.stringify(source.config, null, 2),
          }
        : emptyForm,
    );
    setPreview(null);
    setError("");
    setNotice("");
  }
  function payload() {
    const config = JSON.parse(form.config);
    if (!config || typeof config !== "object" || Array.isArray(config))
      throw Error("采集配置须为 JSON 对象");
    return { ...form, interval_minutes: Number(form.interval_minutes), config };
  }
  async function crawl(source?: Source) {
    const result = await api(
      "/api/admin/crawl",
      "POST",
      source ? { source_id: source.id } : {},
    );
    setNotice(
      result.results.length
        ? result.results
            .map(
              (r: any) =>
                `${r.source}：${r.status === "success" ? `采集 ${r.count} 条报价` : r.error}`,
            )
            .join("；")
        : "没有到期来源，或来源正在被其他任务采集",
    );
    await refresh();
  }
  const filtered = sources.filter(
    (s) =>
      `${s.name} ${s.base_url}`.toLowerCase().includes(q.toLowerCase()) &&
      (status === "all" ||
        (status === "paused"
          ? !s.enabled
          : status === "error"
            ? s.enabled && !!s.last_error
            : s.enabled && !s.last_error)),
  );
  const healthy = sources.filter(
    (s) => s.enabled && s.last_success_at && !s.last_error,
  ).length;
  function save(event: FormEvent) {
    event.preventDefault();
    action(async () => {
      await api(
        editor === "new"
          ? "/api/admin/sources"
          : `/api/admin/sources/${editor}`,
        editor === "new" ? "POST" : "PATCH",
        payload(),
      );
      setEditor(null);
      setPreview(null);
      setForm(initialForm);
      setNotice("配置已保存，定时任务会按来源间隔采集");
      await refresh();
    });
  }
  if (!ready)
    return (
      <div className="admin-login-page">
        <div className="admin-login-brand">
          <span className="brand-icon">
            <Radar size={23} />
          </span>{" "}
          PriceMap AI
        </div>
        <section className="admin-login-card">
          <div className="eyebrow">PRIVATE WORKSPACE</div>
          <h1>管理后台</h1>
          <p>配置商家来源、检查采集结果与运行状态。</p>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              action(()=>refresh());
            }}
          >
            <label htmlFor="admin-key">管理密钥</label>
            <input
              id="admin-key"
              type="password"
              autoComplete="off"
              required
              value={token}
              onChange={(e) => setToken(e.target.value)}
              placeholder="输入 ADMIN_TOKEN"
            />
            <button className="primary" disabled={busy}>
              {busy ? "正在验证…" : "登录后台"}
              <ArrowUpRight size={16} />
            </button>
          </form>
          {error && (
            <p role="alert" className="error">
              {error}
            </p>
          )}
          <small>密钥仅保留在当前页面内存中，刷新或退出后需重新登录。</small>
        </section>
        <a className="admin-return" href="/">
          返回价格页面 <ArrowUpRight size={14} />
        </a>
      </div>
    );
  return (
    <div className="admin-shell">
      <aside className="admin-sidebar">
        <a className="brand" href="/admin">
          <span className="brand-icon">
            <Radar size={22} />
          </span>
          PriceMap AI
        </a>
        <span className="admin-workspace-label">管理工作台</span>
        <select aria-label="数据类型" value={dataset} disabled={busy} onChange={e=>{const next=e.target.value;action(async()=>{await refresh(next);setDataset(next);setEditor(null);setPreview(null);setQ("");setStatus("all");});}}><option value="subscriptions">卡网订阅</option><option value="transit">API 中转站</option></select>
        <button
          className={tab === "sources" ? "active" : ""}
          onClick={() => setTab("sources")}
        >
          <Settings2 size={17} />
          商家来源<span>{sources.length}</span>
        </button>
        <button
          className={tab === "runs" ? "active" : ""}
          onClick={() => setTab("runs")}
        >
          <Activity size={17} />
          采集日志
        </button>
        <div className="admin-schedule">
          <Clock size={18} />
          <strong>Supabase Cron</strong>
          <p>
            每 1 分钟检查到期来源
            <br />
            {dataset==="transit"?"API 原站独立调度":"卡网原站采集"}<br />
            每家默认 15 分钟更新
          </p>
        </div>
        <a
          className="admin-public-link"
          href="/"
          target="_blank"
          rel="noreferrer"
        >
          查看前台 <ArrowUpRight size={16} />
        </a>
      </aside>
      <div className="admin-content">
        <header className="admin-header">
          <span>工作台 / {tab === "sources" ? "商家来源" : "采集日志"}</span>
          <button className="ghost" disabled={busy} onClick={logout}>
            <LogOut size={15} />
            退出登录
          </button>
        </header>
        <main className="admin-main">
          <div className="admin-heading">
            <div>
              <div className="eyebrow">OPERATIONS</div>
              <h1>{tab === "sources" ? "商家来源" : "采集日志"}</h1>
              <p>
                {tab === "sources"
                  ? "维护来源配置，先试采集，再保存并启用定时刷新。"
                  : "查看最近 50 次采集的结果与失败原因。"}
              </p>
            </div>
            <div className="admin-heading-actions">
              <button
                className="ghost"
                disabled={busy}
                onClick={() => action(()=>refresh())}
              >
                <RefreshCw size={15} className={busy ? "spin" : ""} />
                刷新
              </button>
              {tab === "sources" && (
                <button
                  className="primary"
                  disabled={busy}
                  onClick={() => edit()}
                >
                  <Plus size={16} />
                  添加商家
                </button>
              )}
            </div>
          </div>
          <div className="admin-metrics">
            <div>
              <span>已配置来源</span>
              <strong>{sources.length}</strong>
              <small>启用 {sources.filter((s) => s.enabled).length} 家</small>
            </div>
            <div>
              <span>采集正常</span>
              <strong>{healthy}</strong>
              <small>最近采集成功且无错误</small>
            </div>
            <div>
              <span>需要检查</span>
              <strong>
                {sources.filter((s) => s.enabled && s.last_error).length}
              </strong>
              <small>采集失败保留原报价</small>
            </div>
            <div>
              <span>最近采集</span>
              <strong className="admin-date">
                {runs[0] ? date(runs[0].started_at) : "尚未执行"}
              </strong>
              <small>运行时间以北京时间显示</small>
            </div>
          </div>
          {error && (
            <div role="alert" className="admin-banner error">
              {error}
            </div>
          )}
          {notice && (
            <div role="status" className="admin-banner notice">
              {notice}
            </div>
          )}
          {busy && (
            <div role="status" className="admin-busy">
              正在执行，请稍候…
            </div>
          )}
          {tab === "sources" ? (
            <section className="admin-panel">
              <div className="admin-table-tools">
                <label className="search">
                  <Search size={16} />
                  <input
                    aria-label="搜索来源"
                    placeholder="搜索商家或域名"
                    value={q}
                    onChange={(e) => setQ(e.target.value)}
                  />
                </label>
                <select
                  aria-label="来源状态"
                  value={status}
                  onChange={(e) => setStatus(e.target.value)}
                >
                  <option value="all">全部状态</option>
                  <option value="enabled">已启用，无错误</option>
                  <option value="error">需检查</option>
                  <option value="paused">已暂停</option>
                </select>
                <button
                  className="ghost"
                  disabled={busy}
                  onClick={() => action(() => crawl())}
                >
                  <RefreshCw size={14} />
                  采集到期来源
                </button>
              </div>
              <div className="admin-table-scroll">
                <table className="admin-table">
                  <thead>
                    <tr>
                      <th>商家 / 来源</th>
                      <th>采集配置</th>
                      <th>状态</th>
                      <th>最近成功 / 下次计划</th>
                      <th>操作</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filtered.map((s) => (
                      <tr key={s.id}>
                        <td>
                          <strong>{s.name}</strong>
                          <a href={s.base_url} target="_blank" rel="noreferrer">
                            {s.base_url}
                            <ArrowUpRight size={11} />
                          </a>
                        </td>
                        <td>
                          <b className="admin-collector">{s.collector}</b>
                          <small>每 {s.interval_minutes} 分钟 · {s.adaptive_enabled === false ? '手动间隔' : `自动调度（${s.collection_tier ?? 'normal'}）`}</small>
                          {(() => {
                            const interest=heat?.sources.find(h=>h.id===(dataset==='transit'?s.id:merchantAnalyticsId(s.base_url)));
                            const stale=!heat?.generated_at||Date.now()-Date.parse(heat.generated_at)>7200000;
                            return <small title={`热度汇总于 ${date(heat?.generated_at??null)}；各项按会话去重，同一会话可出现在多项中`}>
                              {stale?'热度待更新':`24小时关注 ${interest?.clicks??0} · 购买 ${interest?.purchase_clicks??0} · 首页 ${interest?.shop_clicks??0} · API外链 ${interest?.pricing_clicks??0} · 详情 ${interest?.detail_views??0}`}
                              {!stale&&interest?.clicks&&(!s.last_success_at||Date.now()-Date.parse(s.last_success_at)>s.interval_minutes*120000)?' · 有关注，采集待更新':''}
                            </small>;
                          })()}
                        </td>
                        <td>
                          <span
                            className={`admin-state ${!s.enabled ? "paused" : s.last_error ? "failed" : s.last_success_at ? "success" : "pending"}`}
                          >
                            {!s.enabled
                              ? "已暂停"
                              : s.last_error
                                ? "需检查"
                                : s.last_success_at
                                  ? "正常"
                                  : "待采集"}
                          </span>
                          {s.last_error && (
                            <small className="error admin-source-error">
                              {s.last_error}
                            </small>
                          )}
                        </td>
                        <td>
                          <small>{date(s.last_success_at)}</small>
                          <small className="muted">
                            下次 {s.enabled ? date(s.next_crawl_at) : "暂停"}
                          </small>
                        </td>
                        <td>
                          <div className="admin-row-actions">
                            <button disabled={busy} onClick={() => edit(s)}>
                              配置
                            </button>
                            <button
                              disabled={busy || !s.enabled}
                              onClick={() => action(() => crawl(s))}
                            >
                              采集
                            </button>
                            <button
                              disabled={busy}
                              onClick={() =>
                                action(async () => {
                                  await api(
                                    `/api/admin/sources/${s.id}`,
                                    "PATCH",
                                    { enabled: !s.enabled },
                                  );
                                  await refresh();
                                })
                              }
                            >
                              {s.enabled ? (
                                <Pause size={13} />
                              ) : (
                                <Play size={13} />
                              )}
                              {s.enabled ? "暂停" : "启用"}
                            </button>
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              {!filtered.length && (
                <div className="empty">
                  {sources.length
                    ? "没有匹配的来源"
                    : "尚未配置商家，点击添加商家开始。"}
                </div>
              )}
            </section>
          ) : (
            <section className="admin-panel">
              <div className="admin-table-scroll">
                <table className="admin-table">
                  <thead>
                    <tr>
                      <th>来源</th>
                      <th>开始时间</th>
                      <th>结果</th>
                      <th>报价数</th>
                      <th>错误详情</th>
                    </tr>
                  </thead>
                  <tbody>
                    {runs.map((r) => (
                      <tr key={r.id}>
                        <td>
                          <strong>{r.sources?.name || "未知来源"}</strong>
                        </td>
                        <td>{date(r.started_at)}</td>
                        <td>
                          <span className={`admin-state ${r.status}`}>
                            {r.status === "success"
                              ? "成功"
                              : r.status === "running"
                                ? "执行中"
                                : "失败"}
                          </span>
                        </td>
                        <td>{r.offer_count}</td>
                        <td className="error">{r.error || "—"}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              {!runs.length && <div className="empty">暂无采集记录</div>}
            </section>
          )}
        </main>
      </div>
      {editor && (
        <div className="admin-editor-bg">
          <section
            className="admin-editor"
            role="dialog"
            aria-modal="true"
            aria-labelledby="editor-title"
          >
            <div className="admin-editor-heading">
              <div>
                <div className="eyebrow">SOURCE CONFIGURATION</div>
                <h2 id="editor-title">
                  {editor === "new" ? "添加商家" : "配置商家"}
                </h2>
              </div>
              <button
                className="ghost"
                disabled={busy}
                aria-label="关闭配置"
                onClick={() => {
                  setEditor(null);
                  setPreview(null);
                }}
              >
                <X size={20} />
              </button>
            </div>
            <form className="source-form" onSubmit={save}>
              <label>
                商家名称
                <input
                  required
                  maxLength={100}
                  value={form.name}
                  onChange={(e) => {
                    setPreview(null);
                    setForm({ ...form, name: e.target.value });
                  }}
                />
              </label>
              <label>
                刷新间隔（分钟）
                <input
                  required
                  type="number"
                  min={10}
                  max={10080}
                  value={form.interval_minutes}
                  onChange={(e) =>
                    setForm({ ...form, interval_minutes: e.target.value })
                  }
                />
              </label>
              <label>
                <span><input type="checkbox" checked={form.adaptive_enabled} onChange={e => setForm({...form, adaptive_enabled: e.target.checked})} /> 根据访问热度与采集状态自动调整间隔</span>
                <small>关闭后使用上面填写的固定间隔。</small>
              </label>
              <label className="wide">
                公开 HTTPS 来源地址
                <input
                  required
                  type="url"
                  placeholder="https://shop.example.com/"
                  value={form.base_url}
                  onChange={(e) => {
                    setPreview(null);
                    setForm({ ...form, base_url: e.target.value });
                  }}
                />
              </label>
              <label className="wide">
                采集器
                <select
                  value={form.collector}
                  onChange={(e) => {
                    setPreview(null);
                    setForm({
                      ...form,
                      collector: e.target.value,
                      config: JSON.stringify(
                        currentTemplates[e.target.value],
                        null,
                        2,
                      ),
                    });
                  }}
                >
                  {Object.keys(currentTemplates).map((c) => (
                    <option key={c} value={c}>
                      {c === "transit" ? "公开中转快照（ai-transit）" : c === "newapi" ? "New API（公开 pricing 接口）" : c === "zivv" ? "Zivv 模型广场" : c === "onehop" ? "OneHop 公开模型" : c === "public_models" ? "Sub2API 公开模型目录" : c === "dujiao"
                        ? "独角数卡（公开 products 接口）"
                        : c === "kami"
                          ? "Kami（commodity 接口）"
                          : c === "16688"
                            ? "16688（完整店铺地址）"
                            : c === "html"
                              ? "HTML（CSS 选择器）"
                              : c === "json"
                                ? "JSON（自定义字段映射）"
                                : "ShopApi（shop_token）"}
                    </option>
                  ))}
                </select>
              </label>
              <label className="wide">
                采集配置 JSON
                <textarea
                  required
                  rows={10}
                  spellCheck={false}
                  value={form.config}
                  onChange={(e) => {
                    setPreview(null);
                    setForm({ ...form, config: e.target.value });
                  }}
                />
              </label>
              <p className="wide admin-form-note">
                {dataset==="transit"?"只读取原站公开价格，不调用付费模型。报价、币种与监测范围按原站字段映射；失败时保留上次数据。":"试采集只读取源站并预览结果，不保存报价。完整快照选项仅在确认覆盖全部商品时启用；库存不明确时保留待确认。"}
              </p>
              <div className="wide admin-form-actions">
                <button
                  className="ghost"
                  type="button"
                  disabled={busy || !form.name || !form.base_url}
                  onClick={() =>
                    action(async () => {
                      const result = await api(
                        "/api/admin/preview",
                        "POST",
                        payload(),
                      );
                      setPreview(result);
                    })
                  }
                >
                  <FlaskConical size={16} />
                  试采集
                </button>
                <button className="primary" disabled={busy}>
                  <CheckCircle2 size={16} />
                  保存配置
                </button>
              </div>
            </form>
            {error && (
              <p role="alert" className="error">
                {error}
              </p>
            )}
            {busy && <p role="status">正在执行，请稍候…</p>}
            {preview && (
              <div className="admin-preview">
                <h3>试采集结果 · {preview.count} 条报价</h3>
                <p>
                  {dataset==="transit"?"原站报价映射预览":preview.complete
                    ? "完整快照：成功采集后可下架消失商品"
                    : "部分快照：不会下架本次未出现的商品"}{" "}
                  · 以下展示前 10 条
                </p>
                {preview.prices?.map((p,i)=><div key={i}><a href={p.sourceUrl??undefined} target="_blank" rel="noreferrer">{p.standardModel} · {p.groupName}</a><strong>{p.fixedPrice!=null?priceMetric(p):`${money(p.inputPrice,p.currency)} / ${money(p.outputPrice,p.currency)}`}</strong><small>{p.fixedPrice!=null?"固定价":"输入 / 输出，每百万 Token"}{p.note?` · ${p.note}`:""}</small></div>)}
                {(preview.offers??[]).map((o, i) => (
                  <div key={i}>
                    <a href={o.purchase_url} target="_blank" rel="noreferrer">
                      {o.raw_title}
                    </a>
                    <strong>
                      {o.currency} {o.price.toFixed(2)}
                    </strong>
                    <small>
                      {o.stock_status === "in_stock"
                        ? "有货"
                        : o.stock_status === "out_of_stock"
                          ? "缺货"
                          : "库存待确认"}
                    </small>
                  </div>
                ))}
                {!preview.count && (
                  <p className="error">未发现商品，请检查选择器后再保存。</p>
                )}
              </div>
            )}
          </section>
        </div>
      )}
    </div>
  );
}
createRoot(document.getElementById("root")!).render(<Admin />);
