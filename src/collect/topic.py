from __future__ import annotations

import json
import os
import re
import subprocess
import xml.etree.ElementTree as ET
from datetime import datetime
from html import unescape
from typing import Any
from urllib.error import URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


DEFAULT_TIMEOUT_SECONDS = 20
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36"
)

DEFAULT_EXTERNAL_HOTSPOT_SOURCES = (
    "google_trends_rss",
    "google_news_rss",
    "baidu_realtime",
    "weibo_realtime",
    "youtube_most_popular",
    "tiktok_research_api",
    "douyin_hotspot",
)

DEFAULT_GOOGLE_TRENDS_GEOS = ("US", "HK", "SG", "JP")
DEFAULT_GOOGLE_NEWS_QUERIES = (
    "AI 科技 热点",
    "生活方式 热点",
    "户外 自然",
    "情绪 关系",
    "天文 国际空间站",
)


def collect_external_hotspots(
    *,
    limit_per_source: int = 6,
    sources: tuple[str, ...] | list[str] | None = None,
    google_news_queries: tuple[str, ...] | list[str] | None = None,
    google_trends_geos: tuple[str, ...] | list[str] | None = None,
) -> dict[str, Any]:
    """Collect broad topic signals from public external sources."""
    selected_sources = tuple(sources or DEFAULT_EXTERNAL_HOTSPOT_SOURCES)
    source_results = []
    for source in selected_sources:
        collector = globals().get(f"_collect_{source}")
        if collector is None:
            source_results.append(
                {
                    "source": source,
                    "status": "error",
                    "error": f"Unknown hotspot source: {source}",
                    "items": [],
                }
            )
            continue

        try:
            if source == "google_news_rss":
                result = collector(
                    limit_per_source=limit_per_source,
                    queries=tuple(google_news_queries or DEFAULT_GOOGLE_NEWS_QUERIES),
                )
            elif source == "google_trends_rss":
                result = collector(
                    limit_per_source=limit_per_source,
                    geos=tuple(google_trends_geos or DEFAULT_GOOGLE_TRENDS_GEOS),
                )
            else:
                result = collector(limit_per_source=limit_per_source)
        except Exception as exc:
            result = {
                "source": source,
                "status": "error",
                "error": str(exc),
                "items": [],
            }
        source_results.append(result)

    items = [
        item
        for result in source_results
        for item in result.get("items", [])
    ]
    return {
        "mode": "external_broad_hotspot_sources",
        "collected_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "source_results": source_results,
        "items": items,
    }


def _collect_google_trends_rss(
    *,
    limit_per_source: int,
    geos: tuple[str, ...] = DEFAULT_GOOGLE_TRENDS_GEOS,
) -> dict[str, Any]:
    items: list[dict[str, Any]] = []
    errors: list[str] = []
    per_geo_limit = max(1, limit_per_source)
    for geo in geos:
        url = f"https://trends.google.com/trending/rss?geo={geo}"
        try:
            for item in _read_rss_items(url, limit=per_geo_limit):
                items.append(
                    {
                        "source": "google_trends_rss",
                        "geo": geo,
                        "title": item.get("title"),
                        "url": item.get("link"),
                        "summary": item.get("description"),
                    }
                )
        except Exception as exc:
            errors.append(f"{geo}: {exc}")
    return _source_result("google_trends_rss", items[: limit_per_source * len(geos)], errors)


def _collect_google_news_rss(
    *,
    limit_per_source: int,
    queries: tuple[str, ...] = DEFAULT_GOOGLE_NEWS_QUERIES,
) -> dict[str, Any]:
    items: list[dict[str, Any]] = []
    errors: list[str] = []
    per_query_limit = max(1, min(limit_per_source, 5))
    for query in queries:
        params = urlencode(
            {
                "q": query,
                "hl": "zh-CN",
                "gl": "CN",
                "ceid": "CN:zh-Hans",
            }
        )
        url = f"https://news.google.com/rss/search?{params}"
        try:
            for item in _read_rss_items(url, limit=per_query_limit):
                items.append(
                    {
                        "source": "google_news_rss",
                        "query": query,
                        "title": item.get("title"),
                        "url": item.get("link"),
                        "summary": item.get("description"),
                    }
                )
        except Exception as exc:
            errors.append(f"{query}: {exc}")
    return _source_result("google_news_rss", items, errors)


def _collect_baidu_realtime(*, limit_per_source: int) -> dict[str, Any]:
    url = "https://top.baidu.com/board?tab=realtime"
    html = _fetch_text(url)
    items: list[dict[str, Any]] = []
    seen = set()
    for match in re.finditer(r'"word"\s*:\s*"([^"]+)"', html):
        title = _clean_json_text(match.group(1))
        if not title or title in seen:
            continue
        seen.add(title)
        items.append(
            {
                "source": "baidu_realtime",
                "title": title,
                "url": url,
            }
        )
        if len(items) >= limit_per_source:
            break
    return _source_result("baidu_realtime", items, [])


def _collect_weibo_realtime(*, limit_per_source: int) -> dict[str, Any]:
    url = "https://s.weibo.com/top/summary?cate=realtimehot"
    html = _fetch_text(url)
    pattern = r'<td class="td-02">\s*(?:<i[^>]*>.*?</i>\s*)?<a href="([^"]+)"[^>]*>(.*?)</a>'
    items: list[dict[str, Any]] = []
    for match in re.finditer(pattern, html, flags=re.S):
        href, raw_title = match.groups()
        title = _strip_tags(raw_title)
        if not title or title in {"更多", "查看更多"}:
            continue
        full_url = href if href.startswith("http") else f"https://s.weibo.com{href}"
        items.append(
            {
                "source": "weibo_realtime",
                "title": title,
                "url": full_url,
            }
        )
        if len(items) >= limit_per_source:
            break
    return _source_result("weibo_realtime", items, [])


def _collect_youtube_most_popular(*, limit_per_source: int) -> dict[str, Any]:
    api_key = os.getenv("YOUTUBE_API_KEY", "").strip()
    if not api_key:
        return {
            "source": "youtube_most_popular",
            "status": "skipped",
            "reason": "Missing YOUTUBE_API_KEY.",
            "items": [],
        }

    region = os.getenv("YOUTUBE_REGION", "US").strip() or "US"
    params = urlencode(
        {
            "part": "snippet,statistics",
            "chart": "mostPopular",
            "regionCode": region,
            "maxResults": min(limit_per_source, 50),
            "key": api_key,
        }
    )
    url = f"https://www.googleapis.com/youtube/v3/videos?{params}"
    data = json.loads(_fetch_text(url))
    items = []
    for video in data.get("items", []):
        snippet = video.get("snippet", {})
        stats = video.get("statistics", {})
        video_id = video.get("id")
        items.append(
            {
                "source": "youtube_most_popular",
                "region": region,
                "title": snippet.get("title"),
                "summary": snippet.get("description"),
                "channel": snippet.get("channelTitle"),
                "views": _safe_int(stats.get("viewCount")),
                "url": f"https://www.youtube.com/watch?v={video_id}" if video_id else None,
            }
        )
    return _source_result("youtube_most_popular", items, [])


def _collect_tiktok_research_api(*, limit_per_source: int) -> dict[str, Any]:
    return {
        "source": "tiktok_research_api",
        "status": "skipped",
        "reason": (
            "TikTok Research API requires eligibility approval and authenticated access; "
            "wire credentials before enabling this source."
        ),
        "items": [],
    }


def _collect_douyin_hotspot(*, limit_per_source: int) -> dict[str, Any]:
    return {
        "source": "douyin_hotspot",
        "status": "skipped",
        "reason": "No stable official public hotspot API is configured; use browser-based source later.",
        "items": [],
    }


def _read_rss_items(url: str, *, limit: int) -> list[dict[str, str | None]]:
    root = ET.fromstring(_fetch_bytes(url))
    channel = root.find("channel")
    if channel is None:
        return []
    items = []
    for item in channel.findall("item")[:limit]:
        items.append(
            {
                "title": _element_text(item, "title"),
                "link": _element_text(item, "link"),
                "description": _strip_tags(_element_text(item, "description") or ""),
            }
        )
    return items


def _fetch_text(url: str) -> str:
    return _fetch_bytes(url).decode("utf-8", errors="replace")


def _fetch_bytes(url: str) -> bytes:
    req = Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urlopen(req, timeout=DEFAULT_TIMEOUT_SECONDS) as response:
            return response.read()
    except URLError:
        return _fetch_bytes_with_curl(url)


def _fetch_bytes_with_curl(url: str) -> bytes:
    result = subprocess.run(
        [
            "curl",
            "-L",
            "-sS",
            "--max-time",
            str(DEFAULT_TIMEOUT_SECONDS),
            "-A",
            USER_AGENT,
            url,
        ],
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.decode("utf-8", errors="replace")[:500])
    return result.stdout


def _source_result(source: str, items: list[dict[str, Any]], errors: list[str]) -> dict[str, Any]:
    status = "ok" if items else "empty"
    return {
        "source": source,
        "status": status,
        "errors": errors,
        "items": items,
    }


def _element_text(item: ET.Element, name: str) -> str | None:
    child = item.find(name)
    if child is None or child.text is None:
        return None
    return child.text.strip()


def _strip_tags(value: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", unescape(value))).strip()


def _clean_json_text(value: str) -> str:
    try:
        return json.loads(f'"{value}"')
    except json.JSONDecodeError:
        return _strip_tags(value)


def _safe_int(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None
