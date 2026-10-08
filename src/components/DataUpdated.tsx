import { relativeTime } from "../lib/offers";

/** Use our collection timestamp, rather than the source site's update time. */
export function DataUpdated({ at, now = Date.now(), className = "" }: { at: string | null | undefined; now?: number; className?: string }) {
  if (!at || !Number.isFinite(Date.parse(at))) return <span className={`data-updated ${className}`}>—</span>;
  return <time className={`data-updated ${className}`} dateTime={at} title={`本站数据更新：${new Date(at).toLocaleString("zh-CN")}`}>{relativeTime(at, now)}</time>;
}
