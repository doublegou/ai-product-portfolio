import json
import re
import time
from datetime import datetime
from pathlib import Path
from urllib.parse import quote
from zoneinfo import ZoneInfo

from src.collectors.xhs_browser import XHS_BASE_URL, _parse_count
from src.collectors.xhs_current_chrome import _execute_chrome_js, _run_chrome_applescript


DEFAULT_BENCHMARK_KEYWORDS = (
    "独立开发者",
    "独立产品",
    "个人开发者",
    "产品经理",
    "产品设计",
    "AI创业",
    "AI工具",
    "AI博主",
    "小众App",
    "iOS应用",
    "App推荐",
    "创业日记",
    "一人公司",
    "数字游民创业",
    "天文App",
    "观鸟",
    "数字谜题",
    "塔罗自我探索",
)


def collect_xhs_benchmark_current_chrome(
    *,
    keywords: list[str] | None = None,
    target_creators: int = 50,
    notes_per_creator: int = 10,
    creators_per_keyword: int = 8,
    collect_note_details: bool = True,
    progress: bool = False,
    account_pause_seconds: float = 10,
    note_pause_seconds: float = 1.5,
    output_dir: Path | str = "data/research/corpus",
) -> Path:
    """Collect creator-level Xiaohongshu benchmark samples from current Chrome."""
    cleaned_keywords = [item.strip() for item in (keywords or DEFAULT_BENCHMARK_KEYWORDS) if item.strip()]
    if not cleaned_keywords:
        raise ValueError("keywords cannot be empty")
    if target_creators < 1:
        raise ValueError("target_creators must be >= 1")
    if notes_per_creator < 1:
        raise ValueError("notes_per_creator must be >= 1")

    output_base = Path(output_dir)
    output_base.mkdir(parents=True, exist_ok=True)
    now = datetime.now(ZoneInfo("Asia/Shanghai"))
    safe_started_at = now.strftime("%Y-%m-%d-%H%M%S")
    path = output_base / f"{safe_started_at}-xhs-benchmark-corpus.json"

    creator_candidates: dict[str, dict] = {}
    searched_keywords: list[dict] = []

    for keyword in cleaned_keywords:
        if progress:
            print(f"Searching keyword: {keyword}", flush=True)

        search_url = f"{XHS_BASE_URL}/search_result?keyword={quote(keyword)}"
        _run_chrome_applescript(
            f'tell application "Google Chrome" to set URL of active tab of front window to "{search_url}"'
        )
        time.sleep(7)
        _scroll_current_tab(rounds=8)
        candidates = _extract_search_creator_candidates(limit=creators_per_keyword)
        searched_keywords.append(
            {
                "keyword": keyword,
                "candidate_count": len(candidates),
                "collected_at": datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(),
            }
        )

        for candidate in candidates:
            key = candidate.get("account_url") or candidate.get("account_name")
            if not key or key in creator_candidates:
                continue
            creator_candidates[key] = {
                "seed_keyword": keyword,
                **candidate,
            }
        if progress:
            print(
                f"Keyword candidates: {keyword} -> {len(candidates)} "
                f"(total unique: {len(creator_candidates)})",
                flush=True,
            )

    accounts = []
    selected_creators = _select_balanced_creators(
        list(creator_candidates.values()),
        keywords=cleaned_keywords,
        limit=target_creators,
    )
    for index, creator in enumerate(selected_creators, start=1):
        account_url = creator.get("account_url")
        if not account_url:
            continue
        if progress:
            print(
                f"Collecting account {index}/{target_creators}: "
                f"{creator.get('account_name') or account_url}",
                flush=True,
            )
        _run_chrome_applescript(
            f'tell application "Google Chrome" to set URL of active tab of front window to "{account_url}"'
        )
        time.sleep(7)
        _scroll_current_tab(rounds=10)
        account_sample = _extract_account_sample(
            fallback_name=creator.get("account_name") or f"creator-{index}",
            fallback_url=account_url,
            notes_per_creator=notes_per_creator,
        )
        account_sample["seed_keyword"] = creator.get("seed_keyword")
        account_sample["discovered_from_note"] = creator.get("discovered_from_note")
        if collect_note_details:
            for note_index, note in enumerate(account_sample.get("notes", []), start=1):
                if progress:
                    print(
                        f"  Detail {note_index}/{len(account_sample.get('notes', []))}: "
                        f"{note.get('title', '')[:32]}",
                        flush=True,
                )
                note.update(_extract_note_detail(note.get("note_url")))
                if note_pause_seconds > 0:
                    time.sleep(note_pause_seconds)
        accounts.append(account_sample)
        _save_benchmark_corpus(
            path,
            keywords=cleaned_keywords,
            searched_keywords=searched_keywords,
            accounts=accounts,
            target_creators=target_creators,
            notes_per_creator=notes_per_creator,
            started_at=now,
            completed=False,
        )
        if account_pause_seconds > 0:
            time.sleep(account_pause_seconds)

    _save_benchmark_corpus(
        path,
        keywords=cleaned_keywords,
        searched_keywords=searched_keywords,
        accounts=accounts,
        target_creators=target_creators,
        notes_per_creator=notes_per_creator,
        started_at=now,
        completed=True,
    )
    return path


def _save_benchmark_corpus(
    path: Path,
    *,
    keywords: list[str],
    searched_keywords: list[dict],
    accounts: list[dict],
    target_creators: int,
    notes_per_creator: int,
    started_at: datetime,
    completed: bool,
) -> None:
    note_count = sum(len(account.get("notes", [])) for account in accounts)
    corpus = {
        "platform": "xiaohongshu",
        "corpus_type": "creator_benchmark",
        "research_goal": (
            "浏览并拆解成熟博主及其高互动笔记，用于反推 content-agent 的最终账号人设、"
            "写作规则、平台方法和验收标准。"
        ),
        "source": "xhs_current_chrome",
        "requirements": {
            "target_creators": target_creators,
            "notes_per_creator": notes_per_creator,
            "target_notes": target_creators * notes_per_creator,
        },
        "coverage": {
            "creator_count": len(accounts),
            "note_count": note_count,
            "keywords": keywords,
            "searched_keywords": searched_keywords,
        },
        "accounts": accounts,
        "collector_meta": {
            "started_at": started_at.isoformat(),
            "last_saved_at": datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(),
            "completed": completed,
            "chrome_profile": "user_current_logged_in_chrome",
            "collection_note": (
                "Only visible page data from the user's logged-in Chrome was collected. "
                "The script does not bypass login, CAPTCHA, or platform protections."
            ),
        },
    }
    path.write_text(json.dumps(corpus, ensure_ascii=False, indent=2), encoding="utf-8")


def _scroll_current_tab(*, rounds: int) -> None:
    for _ in range(rounds):
        _execute_chrome_js("window.scrollBy(0, Math.round(window.innerHeight * 0.9)); 'ok';")
        time.sleep(1.2)


def _select_balanced_creators(
    creators: list[dict],
    *,
    keywords: list[str],
    limit: int,
) -> list[dict]:
    grouped: dict[str, list[dict]] = {keyword: [] for keyword in keywords}
    overflow: list[dict] = []
    for creator in creators:
        keyword = creator.get("seed_keyword")
        if keyword in grouped:
            grouped[keyword].append(creator)
        else:
            overflow.append(creator)

    selected: list[dict] = []
    while len(selected) < limit:
        added = False
        for keyword in keywords:
            if grouped[keyword]:
                selected.append(grouped[keyword].pop(0))
                added = True
                if len(selected) >= limit:
                    break
        if not added:
            break

    if len(selected) < limit:
        selected.extend(overflow[: limit - len(selected)])
    return selected[:limit]


def _extract_search_creator_candidates(*, limit: int) -> list[dict]:
    return json.loads(
        _execute_chrome_js(
            f"""
            JSON.stringify((() => {{
              const anchors = Array.from(document.querySelectorAll('a[href*="/explore/"]'));
              const seen = new Set();
              const creators = [];
              for (const anchor of anchors) {{
                const container = anchor.closest('section, article, div') || anchor;
                const text = (container.innerText || anchor.innerText || '').trim();
                const lines = text.split('\\n').map((line) => line.trim()).filter(Boolean);
                const title = lines.find((line) => line.length >= 4 && !/^\\d+(\\.\\d+)?万?$/.test(line)) || anchor.getAttribute('title') || '';
                const userAnchor = container.querySelector('a[href*="/user/profile/"]') ||
                  anchor.parentElement?.querySelector('a[href*="/user/profile/"]');
                const accountUrl = userAnchor ? userAnchor.href : null;
                const accountName = userAnchor ? (userAnchor.innerText || userAnchor.getAttribute('title') || '').trim() : '';
                if (!accountUrl || seen.has(accountUrl)) continue;
                seen.add(accountUrl);
                creators.push({{
                  account_name: accountName || 'unknown',
                  account_url: accountUrl,
                  discovered_from_note: {{
                    title,
                    note_url: anchor.href,
                    card_text: lines.slice(0, 8).join(' / '),
                  }},
                }});
                if (creators.length >= {limit}) break;
              }}
              return creators;
            }})())
            """
        )
    )


def _extract_account_sample(
    *,
    fallback_name: str,
    fallback_url: str,
    notes_per_creator: int,
) -> dict:
    account = json.loads(
        _execute_chrome_js(
            f"""
            JSON.stringify((() => {{
              const bodyText = document.body ? document.body.innerText : '';
              const parseCountText = (value) => {{
                if (!value) return null;
                const cleaned = String(value).trim().replace('+', '');
                if (/^\\d+(\\.\\d+)?万$/.test(cleaned)) return Math.round(parseFloat(cleaned) * 10000);
                if (/^\\d+$/.test(cleaned)) return parseInt(cleaned, 10);
                return null;
              }};
              const userBox = document.querySelector('.user-info') || document.querySelector('.user') || document.body;
              const descText = userBox.querySelector('.user-desc')?.innerText?.trim() || null;
              const tagText = userBox.querySelector('.user-tags')?.innerText?.trim() || null;
              const countTexts = Array.from(userBox.querySelectorAll('.data-info .count, .user-interactions .count')).map((el) => el.innerText.trim());
              const nameCandidates = [
                document.querySelector('h1')?.innerText,
                document.querySelector('[class*="user-name"]')?.innerText,
                document.querySelector('[class*="nickname"]')?.innerText,
              ].filter(Boolean).map((x) => x.trim()).filter(Boolean);
              const anchors = Array.from(document.querySelectorAll('a[href*="/explore/"]'));
              const seen = new Set();
              const notes = [];
              for (const anchor of anchors) {{
                const href = anchor.href;
                const match = href.match(/\\/explore\\/([A-Za-z0-9]+)/);
                if (!match || seen.has(match[1])) continue;
                seen.add(match[1]);
                const container = anchor.closest('section, article, div') || anchor;
                const text = (container.innerText || anchor.innerText || '').trim();
                const lines = text.split('\\n').map((line) => line.trim()).filter(Boolean);
                const img = container.querySelector('img');
                const title = container.querySelector('.title')?.innerText?.trim() ||
                  lines.find((line) => line.length >= 4 && !/^\\d+(\\.\\d+)?万?\\+?$/.test(line)) ||
                  anchor.getAttribute('title') || img?.alt || '';
                const detailUrl = container.querySelector('a.title')?.href ||
                  container.querySelector('a.cover')?.href ||
                  href;
                const author = container.querySelector('.name')?.innerText?.trim() || nameCandidates[0] || {json.dumps(fallback_name)};
                const likes = container.querySelector('.count')?.innerText?.trim() ||
                  lines.find((line) => /^\\d+(\\.\\d+)?万?\\+?$/.test(line)) || null;
                if (!title) continue;
                notes.push({{
                  account_name: author,
                  title,
                  note_url: detailUrl,
                  cover_text: img?.alt || title,
                  body_excerpt: lines.slice(0, 8).join(' / '),
                  hashtags: [],
                  likes_text: likes,
                  comments: null,
                  saves: null,
                  publish_time: null,
                  visible_comments: [],
                  observed_signals: [
                    `profile_note_title: ${{title}}`,
                    likes ? `visible_likes: ${{likes}}` : '',
                    img?.alt ? `cover_alt: ${{img.alt}}` : '',
                  ].filter(Boolean),
                }});
              }}
              return {{
                account_name: nameCandidates[0] || {json.dumps(fallback_name)},
                account_url: location.href || {json.dumps(fallback_url)},
                bio: [descText, tagText].filter(Boolean).join('\\n'),
                follower_count: parseCountText(countTexts[1]),
                following_count: parseCountText(countTexts[0]),
                liked_count: parseCountText(countTexts[2]),
                positioning_notes: [descText, tagText].filter(Boolean),
                notes,
              }};
            }})())
            """
        )
    )
    notes = account.get("notes", [])
    for note in notes:
        note["likes"] = _parse_count(note.pop("likes_text", None))
    account["notes"] = sorted(
        notes,
        key=lambda item: item.get("likes") if item.get("likes") is not None else -1,
        reverse=True,
    )[:notes_per_creator]
    return account


def _extract_note_detail(note_url: str | None) -> dict:
    if not note_url:
        return {
            "detail_collected": False,
            "detail_error": "missing note_url",
        }

    try:
        _run_chrome_applescript(
            f'tell application "Google Chrome" to set URL of active tab of front window to "{note_url}"'
        )
        time.sleep(4)
        detail = json.loads(
            _execute_chrome_js(
                """
                JSON.stringify((() => {
                  const title = document.querySelector('#detail-title')?.innerText?.trim() ||
                    document.querySelector('.note-content .title')?.innerText?.trim() ||
                    document.title.replace(' - 小红书', '').trim();
                  const body = document.querySelector('#detail-desc')?.innerText?.trim() ||
                    document.querySelector('.note-content .desc')?.innerText?.trim() || '';
                  const hashtags = Array.from(document.querySelectorAll('#hash-tag, a.tag'))
                    .map((el) => el.innerText.trim())
                    .filter(Boolean);
                  const author = document.querySelector('.author .username')?.innerText?.trim() ||
                    document.querySelector('.author .name')?.innerText?.trim() || '';
                  const likeText = document.querySelector('.like-wrapper')?.innerText?.trim() || null;
                  const commentText = document.querySelector('.chat-wrapper')?.innerText?.trim() || null;
                  const collectText = document.querySelector('.collect-wrapper')?.innerText?.trim() || null;
                  const commentItems = Array.from(document.querySelectorAll('.comments-el .comment-item, .comments-el [class*="comment"]'))
                    .map((el) => (el.innerText || '').trim())
                    .filter(Boolean)
                    .slice(0, 10);
                  return {
                    detail_collected: true,
                    resolved_url: location.href,
                    detail_title: title,
                    detail_body: body,
                    detail_hashtags: hashtags,
                    detail_author: author,
                    detail_like_text: likeText,
                    detail_comment_text: commentText,
                    detail_collect_text: collectText,
                    visible_comments: commentItems,
                  };
                })())
                """
            )
        )
    except Exception as exc:
        return {
            "detail_collected": False,
            "detail_error": str(exc),
        }

    detail["hashtags"] = detail.get("detail_hashtags") or []
    if detail.get("detail_title"):
        detail["title"] = detail["detail_title"]
    if detail.get("detail_body"):
        detail["body_excerpt"] = detail["detail_body"][:1200]
    parsed_likes = _parse_count(detail.get("detail_like_text"))
    parsed_comments = _parse_count(detail.get("detail_comment_text"))
    parsed_collects = _parse_count(detail.get("detail_collect_text"))
    if parsed_likes is not None:
        detail["likes"] = parsed_likes
    if parsed_comments is not None:
        detail["comments"] = parsed_comments
    if parsed_collects is not None:
        detail["saves"] = parsed_collects
    return detail
