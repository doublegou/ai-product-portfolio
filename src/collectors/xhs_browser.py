import json
import re
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.parse import quote
from zoneinfo import ZoneInfo

from playwright.sync_api import TimeoutError as PlaywrightTimeoutError
from playwright.sync_api import sync_playwright


XHS_BASE_URL = "https://www.xiaohongshu.com"
CHROME_EXECUTABLE = (
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
)


def collect_xhs_search(
    keyword: str,
    *,
    limit: int = 10,
    output_dir: Path | str = "data/research/inputs",
    user_data_dir: Path | str = "data/browser/xhs-chrome",
    headless: bool = False,
) -> Path:
    """Collect visible Xiaohongshu search note cards through real Chrome."""
    keyword = keyword.strip()
    if not keyword:
        raise ValueError("keyword cannot be empty")

    output_base = Path(output_dir)
    output_base.mkdir(parents=True, exist_ok=True)
    Path(user_data_dir).mkdir(parents=True, exist_ok=True)

    with sync_playwright() as playwright:
        context = playwright.chromium.launch_persistent_context(
            user_data_dir=str(user_data_dir),
            executable_path=CHROME_EXECUTABLE,
            headless=headless,
            viewport={"width": 1440, "height": 1000},
            locale="zh-CN",
            args=[
                "--disable-blink-features=AutomationControlled",
                "--no-first-run",
                "--no-default-browser-check",
            ],
        )
        page = context.pages[0] if context.pages else context.new_page()
        search_url = f"{XHS_BASE_URL}/search_result?keyword={quote(keyword)}"
        try:
            page.goto(search_url, wait_until="commit", timeout=45000)
        except PlaywrightTimeoutError:
            if keyword not in page.url:
                raise

        _wait_for_search_or_login(page)
        _scroll_for_results(page, target_count=limit)
        cards = _extract_note_cards(page, limit=limit)
        title = page.title()
        url = page.url
        context.close()

    research_input = {
        "platform": "xiaohongshu",
        "research_goal": f"自动分析与「{keyword}」相关的小红书笔记结构和流量表达",
        "source": "xhs_browser",
        "accounts": [],
        "loose_notes": [
            {
                "account_name": card.get("account_name") or "unknown",
                "title": card["title"],
                "note_url": card.get("note_url"),
                "cover_text": card.get("cover_text"),
                "body_excerpt": card.get("body_excerpt"),
                "hashtags": [],
                "likes": _parse_count(card.get("likes")),
                "comments": None,
                "saves": None,
                "publish_time": None,
                "visible_comments": [],
                "observed_signals": card.get("observed_signals", []),
            }
            for card in cards
        ],
        "collector_meta": {
            "keyword": keyword,
            "page_title": title,
            "page_url": url,
            "collected_at": datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(),
            "requested_limit": limit,
            "collected_count": len(cards),
        },
    }

    now = datetime.now(ZoneInfo("Asia/Shanghai"))
    safe_keyword = re.sub(r"[^0-9A-Za-z\u4e00-\u9fff]+", "-", keyword).strip("-")[:40]
    path = output_base / f"{now.strftime('%Y-%m-%d-%H%M%S')}-xhs-{safe_keyword}.json"
    path.write_text(json.dumps(research_input, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


def _wait_for_search_or_login(page: Any) -> None:
    """Wait until the page shows search content or a login state."""
    try:
        page.wait_for_load_state("networkidle", timeout=15000)
    except PlaywrightTimeoutError:
        pass

    page.wait_for_timeout(4000)
    visible_text = _page_visible_text(page)
    if "登录" in visible_text and "搜索" not in visible_text and "笔记" not in visible_text:
        raise RuntimeError(
            "Xiaohongshu opened, but the automation Chrome appears to need login. "
            "Please log in once in the opened Chrome window, then rerun the command."
        )


def _scroll_for_results(page: Any, *, target_count: int) -> None:
    for _ in range(8):
        count = page.evaluate(
            """() => Array.from(document.querySelectorAll('a[href*="/explore/"]')).length"""
        )
        if count >= target_count:
            return
        page.mouse.wheel(0, 900)
        page.wait_for_timeout(1500)


def _extract_note_cards(page: Any, *, limit: int) -> list[dict[str, Any]]:
    raw_cards = page.evaluate(
        """
        (limit) => {
          const anchors = Array.from(document.querySelectorAll('a[href*="/explore/"]'));
          const seen = new Set();
          const cards = [];
          for (const anchor of anchors) {
            const href = anchor.href;
            const match = href.match(/\\/explore\\/([A-Za-z0-9]+)/);
            if (!match || seen.has(match[1])) continue;
            seen.add(match[1]);

            const container = anchor.closest('section, article, div') || anchor;
            const text = (container.innerText || anchor.innerText || '').trim();
            const lines = text.split('\\n').map((line) => line.trim()).filter(Boolean);
            const img = container.querySelector('img');
            const title = lines.find((line) => line.length >= 4 && !/^\\d+$/.test(line)) || anchor.getAttribute('title') || '';
            const likes = lines.find((line) => /^\\d+(\\.\\d+)?万?$/.test(line)) || null;
            const account = lines.find((line) => line !== title && line !== likes && line.length >= 2 && line.length <= 24) || '';

            if (!title) continue;
            cards.push({
              title,
              note_url: href,
              cover_text: img?.alt || title,
              body_excerpt: lines.slice(0, 6).join(' / '),
              account_name: account,
              likes,
              observed_signals: [
                `搜索结果卡片标题: ${title}`,
                img?.alt ? `封面alt: ${img.alt}` : '',
              ].filter(Boolean),
            });
            if (cards.length >= limit) break;
          }
          return cards;
        }
        """,
        limit,
    )

    return [
        card
        for card in raw_cards
        if isinstance(card, dict) and card.get("title") and card.get("note_url")
    ][:limit]


def _page_visible_text(page: Any) -> str:
    return page.evaluate(
        """() => document.body ? document.body.innerText.slice(0, 3000) : ''"""
    )


def _parse_count(value: str | None) -> int | None:
    if not value:
        return None
    value = value.strip().replace("+", "")
    try:
        if value.endswith("万"):
            return int(float(value[:-1]) * 10000)
        return int(value)
    except ValueError:
        return None
