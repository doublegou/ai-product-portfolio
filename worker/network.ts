const UA =
  "AIMarketingPriceObserver/1.0 (+public price comparison; 15-minute refresh)";
const nextRequest = new Map<string, number>();
const unavailableUntil = new Map<string, number>();
async function politeFetch(url: URL | string, init: RequestInit): Promise<Response> {
  const origin = new URL(url).origin;
  if ((unavailableUntil.get(origin) ?? 0) > Date.now()) throw new Error("同域原站暂不可用，本轮暂停继续请求");
  const at = Math.max(Date.now(), nextRequest.get(origin) ?? 0);
  nextRequest.set(origin, at + 500);
  if (at > Date.now()) await new Promise(r => setTimeout(r, at - Date.now()));
  if ((unavailableUntil.get(origin) ?? 0) > Date.now()) throw new Error("同域原站暂不可用，本轮暂停继续请求");
  const response = await fetch(url, init);
  if ([429, 502, 503, 520].includes(response.status)) unavailableUntil.set(origin, Date.now() + 60000);
  return response;
}
export function safeUrl(value: string, base?: string): URL {
  const u = new URL(value, base);
  const h = u.hostname.toLowerCase();
  if (
    u.protocol !== "https:" ||
    u.username ||
    u.password ||
    u.port ||
    !h.includes(".") ||
    /^[\d.]+$/.test(h) ||
    h.includes(":") ||
    /(^|\.)(localhost|local|internal|test|invalid)$/.test(h) ||
    h.endsWith(".local") ||
    h.endsWith(".internal")
  )
    throw new Error("来源必须使用公开域名的 HTTPS 地址");
  return u;
}
export async function download(
  url: string,
  init: RequestInit = {},
  origin?: string,
): Promise<Response> {
  const u = safeUrl(url);
  if (origin && u.origin !== origin) throw new Error("不允许跨域抓取");
  const res = await politeFetch(u, {
    ...init,
    redirect: "manual",
    signal: init.signal ?? AbortSignal.timeout(15000),
    headers: { "User-Agent": UA, ...init.headers },
  });
  if (res.status >= 300 && res.status < 400)
    throw new Error("来源发生跳转，请确认并更新来源 URL");
  if (!res.ok) throw new Error(`源站 HTTP ${res.status}`);
  const length = Number(res.headers.get("content-length") ?? 0);
  if (length > 2_000_000) throw new Error("响应过大");
  return res;
}
export async function readLimited(res: Response): Promise<string> {
  const reader = res.body!.getReader();
  let total = 0;
  const chunks: Uint8Array[] = [];
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.length;
    if (total > 2_000_000) {
      await reader.cancel();
      throw new Error("响应超过 2MB");
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let off = 0;
  for (const c of chunks) {
    out.set(c, off);
    off += c.length;
  }
  return new TextDecoder().decode(out);
}
export async function assertRobots(base: string, paths: string[]) {
  const u = safeUrl(base);
  const r = await politeFetch(`${u.origin}/robots.txt`, {
    redirect: "manual",
    signal: AbortSignal.timeout(10000),
    headers: { "User-Agent": UA },
  });
  if (r.status === 404) return;
  if (!r.ok) throw new Error(`无法确认 robots.txt (${r.status})`);
  const text = await readLimited(r);
  let agents: string[] = [];
  let rules: { allow: boolean; path: string }[] = [];
  let groupRules = false;
  const groups: { agents: string[]; rules: typeof rules }[] = [];
  for (const line of text.split(/\r?\n/)) {
    const m = line
      .replace(/#.*$/, "")
      .trim()
      .match(/^(user-agent|allow|disallow)\s*:\s*(.*)$/i);
    if (!m) continue;
    if (m[1].toLowerCase() === "user-agent") {
      if (groupRules) {
        groups.push({ agents, rules });
        agents = [];
        rules = [];
        groupRules = false;
      }
      agents.push(m[2].toLowerCase());
    } else {
      groupRules = true;
      if (m[2])
        rules.push({ allow: m[1].toLowerCase() === "allow", path: m[2] });
    }
  }
  groups.push({ agents, rules });
  const specific = groups.filter((g) =>
    g.agents.some((a) => a !== "*" && UA.toLowerCase().includes(a)),
  );
  const selected = specific.length
    ? specific
    : groups.filter((g) => g.agents.includes("*"));
  for (const path of paths) {
    const matches = selected
      .flatMap((g) => g.rules)
      .filter((r) =>
        new RegExp(
          "^" +
            r.path
              .split("*")
              .map((s) => s.replace(/[.+?^{}()|[\]\\]/g, "\\$&"))
              .join(".*")
              .replace(/\\\$$/, "$"),
        ).test(path),
      )
      .sort(
        (a, b) =>
          b.path.length - a.path.length || Number(b.allow) - Number(a.allow),
      );
    if (matches[0] && !matches[0].allow)
      throw new Error("robots.txt 禁止该路径采集");
  }
}
