import json
import re
import subprocess
import tempfile
import time
from datetime import datetime
from pathlib import Path
from urllib.parse import quote
from zoneinfo import ZoneInfo

from src.collectors.xhs_browser import XHS_BASE_URL, _parse_count


def collect_xhs_current_chrome(
    keyword: str,
    *,
    limit: int = 10,
    output_dir: Path | str = "data/research/inputs",
) -> Path:
    """Collect Xiaohongshu search notes from the user's current logged-in Chrome."""
    keyword = keyword.strip()
    if not keyword:
        raise ValueError("keyword cannot be empty")

    output_base = Path(output_dir)
    output_base.mkdir(parents=True, exist_ok=True)

    search_url = f"{XHS_BASE_URL}/search_result?keyword={quote(keyword)}"
    _run_chrome_applescript(
        f'tell application "Google Chrome" to set URL of active tab of front window to "{search_url}"'
    )
    time.sleep(8)
    for _ in range(6):
        _execute_chrome_js("window.scrollBy(0, 900); 'ok';")
        time.sleep(1.5)

    page_info = json.loads(
        _execute_chrome_js(
            """
            JSON.stringify({
              title: document.title,
              url: location.href,
              text: document.body ? document.body.innerText.slice(0, 1200) : '',
              cards: (() => {
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
                  const title = lines.find((line) => line.length >= 4 && !/^\\d+$/.test(line)) || anchor.getAttribute('title') || img?.alt || '';
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
                      `search_card_title: ${title}`,
                      img?.alt ? `cover_alt: ${img.alt}` : '',
                      ].filter(Boolean),
                  });
                }
                return cards;
              })()
            })
            """
        )
    )

    cards = page_info.get("cards", [])[:limit]
    research_input = {
        "platform": "xiaohongshu",
        "research_goal": f"自动分析与「{keyword}」相关的小红书笔记结构和流量表达",
        "source": "xhs_current_chrome",
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
            "page_title": page_info.get("title"),
            "page_url": page_info.get("url"),
            "page_text_sample": page_info.get("text"),
            "collected_at": datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(),
            "requested_limit": limit,
            "collected_count": len(cards),
        },
    }

    now = datetime.now(ZoneInfo("Asia/Shanghai"))
    safe_keyword = re.sub(r"[^0-9A-Za-z\u4e00-\u9fff]+", "-", keyword).strip("-")[:40]
    path = output_base / f"{now.strftime('%Y-%m-%d-%H%M%S')}-xhs-current-{safe_keyword}.json"
    path.write_text(json.dumps(research_input, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


def _execute_chrome_js(script: str) -> str:
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8") as tmp:
        tmp.write(script)
        tmp_path = Path(tmp.name)

    try:
        return _run_chrome_applescript(
            f'set jsSource to read POSIX file "{tmp_path}"\n'
            'tell application "Google Chrome" to execute active tab of front window javascript jsSource'
        )
    finally:
        tmp_path.unlink(missing_ok=True)


def _run_chrome_applescript(script: str) -> str:
    result = subprocess.run(
        ["osascript", "-e", script],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        message = result.stderr.strip() or result.stdout.strip()
        if "Executing JavaScript through AppleScript is turned off" in message:
            raise RuntimeError(
                "Current Chrome collection can use your existing Xiaohongshu login, "
                "but DOM extraction needs one Chrome setting: "
                "View > Developer > Allow JavaScript from Apple Events. "
                "Turn it on once, keep your logged-in Xiaohongshu tab available, then rerun."
            )
        raise RuntimeError(message)
    return result.stdout.strip()
