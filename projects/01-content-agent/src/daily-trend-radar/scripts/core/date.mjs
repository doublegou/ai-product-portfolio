const SHANGHAI_OFFSET = "+08:00";

export function parseChineseRelativeDate(value, now = Date.now()) {
  if (!value) return null;
  const text = String(value).trim();
  if (text === "刚刚") return new Date(now).toISOString();

  const relative = text.match(/^(\d+)\s*(秒|分钟|小时|天)前$/);
  if (relative) {
    const units = { "秒": 1_000, "分钟": 60_000, "小时": 3_600_000, "天": 86_400_000 };
    return new Date(now - Number(relative[1]) * units[relative[2]]).toISOString();
  }

  const monthDay = text.match(/^(\d{1,2})月(\d{1,2})日(?:\s+(\d{1,2}):(\d{2}))?$/);
  if (monthDay) {
    const year = new Intl.DateTimeFormat("en", { year: "numeric", timeZone: "Asia/Shanghai" }).format(now);
    const [, month, day, hour = "00", minute = "00"] = monthDay;
    const date = new Date(`${year}-${month.padStart(2, "0")}-${day.padStart(2, "0")}T${hour.padStart(2, "0")}:${minute}:00${SHANGHAI_OFFSET}`);
    return Number.isNaN(date.valueOf()) ? null : date.toISOString();
  }

  return null;
}

