import json
import re
import time
from datetime import datetime
from functools import wraps
from pathlib import Path
from typing import Any, TypedDict
from urllib.parse import quote
from zoneinfo import ZoneInfo

from src.base.run_log import log_event
from src.collect.collect_infra import (
    ChromeContentBounds,
    capture_chrome_session,
    click_screen_point,
    cleanup_chrome_session,
    close_current_chrome_tab,
    current_chrome_content_bounds,
    drag_screen_points,
    execute_current_chrome_js,
    move_mouse_screen_point,
    navigate_current_chrome_back,
    navigate_current_chrome_top,
    open_current_chrome_url,
    press_current_chrome_key,
    scroll_current_chrome_wheel,
)


XHS_BASE_URL = "https://www.xiaohongshu.com"
XHS_HIGH_LIKE_THRESHOLD = 500
XHS_HIGH_COMMENT_THRESHOLD = 100
XHS_HIGH_SAVE_THRESHOLD = 500
XHS_STRATEGY_MIN_FOLLOWERS = 5000
XHS_FEED_SCROLL_PULSE_CLICKS = 55
XHS_FEED_SCROLL_PULSE_PAUSE_SECONDS = 0.14
XHS_FEED_ADVANCE_WATCHDOG_SECONDS = 8.0
XHS_QUERY_WATCHDOG_SECONDS = 180.0
XHS_PROFILE_WATCHDOG_SECONDS = 180.0
XHS_DETAIL_OPEN_WATCHDOG_SECONDS = 12.0
XHS_DETAIL_WATCHDOG_SECONDS = 90.0
XHS_GALLERY_WATCHDOG_SECONDS = 45.0
XHS_DETAIL_INITIAL_DWELL_SECONDS = 1.8
XHS_DETAIL_SCROLL_PULSE_CLICKS = 70
XHS_DETAIL_SCROLL_PULSE_PAUSE_SECONDS = 0.14
XHS_DETAIL_VIEWPORT_WATCHDOG_SECONDS = 6.0
XHS_DETAIL_IMAGE_STEP_PAUSE_SECONDS = 0.75


class VisibleNoteTarget(TypedDict, total=False):
    note_id: str
    note_url: str
    title: str
    account_name: str
    account_url: str
    likes: int | None
    comments: int | None
    saves: int | None
    pinned: bool
    screen_x: int
    screen_y: int
    author_screen_x: int
    author_screen_y: int
    author_opens_new_tab: bool
    viewport_top: int


class XhsNote(TypedDict, total=False):
    note_id: str
    note_url: str
    account_name: str
    author_url: str
    title: str
    subtitle: str
    body: str
    hashtags: list[str]
    likes: int | None
    comments: int | None
    saves: int | None
    shares: int | None
    publish_time: str
    location: str
    images: list[dict[str, Any]]
    video: dict[str, Any] | None
    comment_items: list[dict[str, Any]]
    collection_meta: dict[str, Any]


class FeedObservation(TypedDict, total=False):
    cards: list[VisibleNoteTarget]
    url: str
    title: str
    viewport_height: int
    scroll_top: int
    scroll_height: int
    at_end: bool
    scroll_screen_x: int
    scroll_screen_y: int


DEFAULT_STRATEGY_RESEARCH_KEYWORDS = (
    "独立开发者",
    "独立产品",
    "个人开发者",
    "产品设计",
    "产品经理",
    "一人公司",
    "产品手记",
    "开发者日常",
    "自有App",
    "小众App",
    "iOS App",
    "App开发",
    "好奇心",
    "自然观察",
    "天文科普",
    "观鸟",
    "逻辑谜题",
    "轻量思考",
    "自我探索",
)


# Public workflows


def _cleanup_chrome_after_collection(function):
    @wraps(function)
    def wrapped(*args, **kwargs):
        initial_session = None
        try:
            initial_session = capture_chrome_session()
        except Exception as exc:
            log_event(
                "xhs_chrome_session_capture_failed",
                level="warning",
                error_message=str(exc),
            )
        try:
            return function(*args, **kwargs)
        finally:
            if initial_session is not None:
                cleanup = cleanup_chrome_session(initial_session)
                log_event(
                    "xhs_chrome_session_cleaned",
                    level="warning" if cleanup["errors"] else "info",
                    **cleanup,
                )

    return wrapped


@_cleanup_chrome_after_collection
def collect_xhs_deep_search_current_chrome(
    keyword: str,
    *,
    limit: int = 10,
    output_dir: Path | str = "data/research/inputs",
    note_pause_seconds: float = 1.5,
) -> Path:
    """Collect complete note details through a visible, result-driven XHS search."""
    keyword = keyword.strip()
    if not keyword:
        raise ValueError("keyword cannot be empty")
    if limit < 1:
        raise ValueError("limit must be >= 1")
    if note_pause_seconds < 0:
        raise ValueError("note_pause_seconds must be >= 0")

    target_count = limit

    output_base = Path(output_dir)
    output_base.mkdir(parents=True, exist_ok=True)

    notes: list[XhsNote] = []
    detail_errors: list[dict[str, Any]] = []
    searched_queries: list[dict[str, Any]] = []
    warnings: list[str] = []
    last_page = None
    attempted_note_ids: set[str] = set()

    for query in _build_xhs_writing_search_queries(keyword):
        if len(notes) >= target_count:
            break
        result = _browse_xhs_writing_query_current_chrome(
            query,
            target_count=target_count - len(notes),
            known_note_ids=attempted_note_ids,
            note_pause_seconds=note_pause_seconds,
        )
        attempted_note_ids.update(result["attempted_note_ids"])
        notes.extend(result["notes"])
        detail_errors.extend(result["detail_errors"])
        warnings.extend(result["warnings"])
        last_page = result["page"]
        searched_queries.append(
            {
                "query": query,
                "observed_card_count": result["observed_card_count"],
                "qualified_card_count": result["qualified_card_count"],
                "detail_requested_count": result["detail_requested_count"],
                "detail_success_count": len(result["notes"]),
                "viewport_advance_count": result["viewport_advance_count"],
                "completion_reason": result["completion_reason"],
                "page_url": last_page.get("url") if last_page else None,
            }
        )

    field_coverage = _field_coverage(notes)
    log_event(
        "collect_attempt",
        level="info" if len(notes) >= target_count and not warnings else "warning",
        platform="xhs",
        collector="visible_result_driven_writing",
        query=keyword,
        searched_queries=[item["query"] for item in searched_queries],
        requested_limit=target_count,
        collected_count=len(notes),
        detail_error_count=len(detail_errors),
        enough_samples=len(notes) >= target_count,
        field_coverage=field_coverage,
        warnings=warnings,
        page_url=last_page.get("url") if last_page else None,
    )

    research_input = {
        "platform": "xiaohongshu",
        "research_goal": f"深入分析与「{keyword}」相关的小红书完整笔记内容与互动表达",
        "source": "xhs_current_chrome_visible_detail",
        "accounts": [],
        "loose_notes": notes,
        "collector_meta": {
            "keyword": keyword,
            "searched_queries": searched_queries,
            "page_title": last_page.get("title") if last_page else None,
            "page_url": last_page.get("url") if last_page else None,
            "collected_at": datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(),
            "requested_limit": target_count,
            "collected_count": len(notes),
            "detail_error_count": len(detail_errors),
            "detail_errors": detail_errors[:20],
            "visible_selection_threshold": _writing_quality_threshold(),
            "browsing_method": "visible_observe_click_read_return",
            "field_coverage": field_coverage,
            "warnings": warnings,
        },
    }

    now = datetime.now(ZoneInfo("Asia/Shanghai"))
    safe_keyword = re.sub(r"[^0-9A-Za-z\u4e00-\u9fff]+", "-", keyword).strip("-")[:40]
    path = output_base / f"{now.strftime('%Y-%m-%d-%H%M%S')}-xhs-deep-{safe_keyword}.json"
    path.write_text(json.dumps(research_input, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


@_cleanup_chrome_after_collection
def collect_xhs_strategy_corpus_current_chrome(
    *,
    keywords: list[str] | None = None,
    target_creators: int = 50,
    notes_per_creator: int = 10,
    creators_per_keyword: int = 8,
    progress: bool = False,
    account_pause_seconds: float = 10,
    note_pause_seconds: float = 1.5,
    output_dir: Path | str = "data/research/corpus",
) -> Path:
    """Collect complete creator profiles and complete qualified note details."""
    cleaned_keywords = list(
        dict.fromkeys(
            item.strip()
            for item in (keywords or DEFAULT_STRATEGY_RESEARCH_KEYWORDS)
            if item.strip()
        )
    )
    if not cleaned_keywords:
        raise ValueError("keywords cannot be empty")
    if target_creators < 1:
        raise ValueError("target_creators must be >= 1")
    if notes_per_creator < 1:
        raise ValueError("notes_per_creator must be >= 1")
    if creators_per_keyword < 1:
        raise ValueError("creators_per_keyword must be >= 1")
    if account_pause_seconds < 0:
        raise ValueError("account_pause_seconds must be >= 0")
    if note_pause_seconds < 0:
        raise ValueError("note_pause_seconds must be >= 0")

    output_base = Path(output_dir)
    output_base.mkdir(parents=True, exist_ok=True)
    started_at = datetime.now(ZoneInfo("Asia/Shanghai"))
    path = output_base / (
        f"{started_at.strftime('%Y-%m-%d-%H%M%S')}-xhs-strategy-corpus.json"
    )

    accounts: list[dict[str, Any]] = []
    rejected_creators: list[dict[str, Any]] = []
    searched_keywords: list[dict[str, Any]] = []
    visited_creator_ids: set[str] = set()

    for keyword in cleaned_keywords:
        if len(accounts) >= target_creators:
            break
        if progress:
            print(
                f"Searching creators: {keyword} "
                f"(qualified {len(accounts)}/{target_creators})",
                flush=True,
            )

        result = _browse_xhs_strategy_keyword_current_chrome(
            keyword,
            creator_inspection_target=creators_per_keyword,
            qualified_creator_target=target_creators - len(accounts),
            notes_per_creator=notes_per_creator,
            visited_creator_ids=visited_creator_ids,
            progress=progress,
            note_pause_seconds=note_pause_seconds,
            account_pause_seconds=account_pause_seconds,
        )
        accounts.extend(result["accounts"])
        rejected_creators.extend(result["rejected_creators"])
        searched_keywords.append(
            {
                "keyword": keyword,
                "inspected_creator_count": result["inspected_creator_count"],
                "qualified_creator_count": len(result["accounts"]),
                "viewport_advance_count": result["viewport_advance_count"],
                "completion_reason": result["completion_reason"],
                "warnings": result["warnings"],
                "collected_at": datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(),
            }
        )
        _save_strategy_corpus(
            path,
            keywords=cleaned_keywords,
            searched_keywords=searched_keywords,
            accounts=accounts,
            target_creators=target_creators,
            notes_per_creator=notes_per_creator,
            started_at=started_at,
            completed=False,
            rejected_creators=rejected_creators,
        )

    _save_strategy_corpus(
        path,
        keywords=cleaned_keywords,
        searched_keywords=searched_keywords,
        accounts=accounts,
        target_creators=target_creators,
        notes_per_creator=notes_per_creator,
        started_at=started_at,
        completed=len(accounts) >= target_creators,
        rejected_creators=rejected_creators,
    )
    log_event(
        "xhs_strategy_collection_completed",
        level="info" if len(accounts) >= target_creators else "warning",
        target_creators=target_creators,
        collected_creators=len(accounts),
        rejected_creators=len(rejected_creators),
        collected_notes=sum(len(account.get("notes", [])) for account in accounts),
        corpus_path=path,
    )
    return path



# Writing search flow


def _build_xhs_writing_search_queries(keyword: str) -> list[str]:
    base = re.sub(r"\s+", " ", keyword).strip()
    candidates = [
        base,
        f"{base} 热门",
        f"{base} 经验",
        f"{base} 记录",
        f"{base} 避坑",
    ]
    queries = []
    seen = set()
    for query in candidates:
        normalized = query.strip()
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        queries.append(normalized)
    return queries


def _open_xhs_search_page(search_url: str) -> FeedObservation:
    latest: FeedObservation = {}
    for _ in range(2):
        open_current_chrome_url(search_url, wait_seconds=3)
        deadline = time.monotonic() + XHS_DETAIL_OPEN_WATCHDOG_SECONDS
        while time.monotonic() < deadline:
            latest = _observe_xhs_note_feed()
            if (
                "xiaohongshu.com" in str(latest.get("url") or "")
                and "/search_result" in str(latest.get("url") or "")
            ):
                navigate_current_chrome_top(wait_seconds=0.6)
                render_deadline = (
                    time.monotonic() + XHS_DETAIL_OPEN_WATCHDOG_SECONDS
                )
                while time.monotonic() < render_deadline:
                    latest = _observe_xhs_note_feed()
                    if latest.get("cards"):
                        return latest
                    time.sleep(0.4)
                return latest
            time.sleep(0.4)
    log_event(
        "xhs_search_navigation_failed",
        level="error",
        expected_url=search_url,
        actual_url=latest.get("url"),
    )
    return latest


def _is_xhs_search_page(observation: FeedObservation) -> bool:
    url = str(observation.get("url") or "")
    return "xiaohongshu.com" in url and "/search_result" in url


def _browse_xhs_writing_query_current_chrome(
    query: str,
    *,
    target_count: int,
    known_note_ids: set[str],
    note_pause_seconds: float,
) -> dict[str, Any]:
    search_url = f"{XHS_BASE_URL}/search_result?keyword={quote(query)}"
    observation = _open_xhs_search_page(search_url)
    if not _is_xhs_search_page(observation):
        return {
            "notes": [],
            "page": observation,
            "warnings": [f"search_navigation_failed for '{query}'"],
            "observed_card_count": 0,
            "qualified_card_count": 0,
            "detail_requested_count": 0,
            "detail_errors": [],
            "viewport_advance_count": 0,
            "completion_reason": "navigation_failed",
        }

    attempted_note_ids = set(known_note_ids)
    observed_note_ids: set[str] = set()
    notes: list[XhsNote] = []
    detail_errors: list[dict[str, Any]] = []
    warnings: list[str] = []
    qualified_card_count = 0
    detail_requested_count = 0
    viewport_advance_count = 0
    completion_reason = "query_watchdog"
    started_at = time.monotonic()

    while time.monotonic() - started_at < XHS_QUERY_WATCHDOG_SECONDS:
        for card in observation.get("cards", []):
            note_id = card.get("note_id")
            if note_id:
                observed_note_ids.add(note_id)

        target = _next_visible_writing_target(
            observation.get("cards", []),
            attempted_note_ids=attempted_note_ids,
        )
        if target:
            qualified_card_count += 1
            detail_requested_count += 1
            log_event(
                "xhs_note_target_selected",
                platform="xhs",
                workflow="writing",
                query=query,
                note_id=target.get("note_id"),
                title=target.get("title"),
                visible_likes=target.get("likes"),
                visible_comments=target.get("comments"),
                visible_saves=target.get("saves"),
            )
            result = _collect_complete_note_by_click(
                target,
                source_page="search",
                source_query=query,
            )
            if result.get("ok"):
                note = result["note"]
                if _meets_writing_like_threshold(note):
                    notes.append(note)
                else:
                    detail_errors.append(
                        {
                            "query": query,
                            "note_url": target.get("note_url"),
                            "title": target.get("title"),
                            "error": "complete detail did not meet the writing like threshold",
                        }
                    )
            else:
                detail_errors.append(
                    {
                        "query": query,
                        "note_url": target.get("note_url"),
                        "title": target.get("title"),
                        "error": result.get("error"),
                    }
                )
            if len(notes) >= target_count:
                completion_reason = "target_reached"
                break
            if note_pause_seconds > 0:
                time.sleep(note_pause_seconds)
            observation = _observe_xhs_note_feed()
            continue

        advance = _advance_xhs_feed(
            observation,
            attempted_note_ids=attempted_note_ids,
            require_writing_like_threshold=True,
        )
        observation = advance["observation"]
        status = advance["status"]
        if status == "advanced" or status == "target_visible":
            viewport_advance_count += 1
            continue
        completion_reason = "feed_end" if status == "end" else "feed_stalled"
        if status == "stalled":
            warnings.append(f"feed_stalled for query '{query}'")
        break
    else:
        warnings.append(f"query_watchdog_reached for '{query}'")

    if len(notes) < target_count:
        warnings.append(
            f"high_quality_notes_incomplete: {len(notes)}/{target_count} for query '{query}'"
        )

    return {
        "notes": notes,
        "page": observation,
        "warnings": warnings,
        "observed_card_count": len(observed_note_ids),
        "qualified_card_count": qualified_card_count,
        "detail_requested_count": detail_requested_count,
        "detail_errors": detail_errors,
        "attempted_note_ids": sorted(attempted_note_ids),
        "viewport_advance_count": viewport_advance_count,
        "completion_reason": completion_reason,
    }


# Shared feed semantics and pointer safety


def _next_visible_writing_target(
    cards: list[VisibleNoteTarget],
    *,
    attempted_note_ids: set[str],
) -> VisibleNoteTarget | None:
    for card in cards:
        note_id = card.get("note_id")
        if not note_id or note_id in attempted_note_ids:
            continue
        if not _meets_writing_like_threshold(card):
            attempted_note_ids.add(note_id)
            continue
        if card.get("screen_x") is not None and card.get("screen_y") is not None:
            attempted_note_ids.add(note_id)
            return card
    return None


def _next_visible_strategy_note_target(
    cards: list[VisibleNoteTarget],
    *,
    attempted_note_ids: set[str],
) -> VisibleNoteTarget | None:
    unseen = [
        card
        for card in cards
        if card.get("note_id") and card["note_id"] not in attempted_note_ids
    ]
    for card in unseen:
        if (
            _is_high_quality_xhs_card(card)
            and card.get("screen_x") is not None
            and card.get("screen_y") is not None
        ):
            attempted_note_ids.add(card["note_id"])
            return card

    for card in unseen:
        if card.get("screen_x") is None or card.get("screen_y") is None:
            continue
        attempted_note_ids.add(card["note_id"])
        return card
    return None


def _observe_xhs_note_feed() -> FeedObservation:
    payload = json.loads(
        execute_current_chrome_js(
            r"""
            JSON.stringify((() => {
              const clean = (value) => String(value || '').replace(/\s+/g, ' ').trim();
              const parseCountText = (value) => {
                const cleaned = clean(value).replace(/[,+]/g, '');
                if (/^\d+(\.\d+)?万$/.test(cleaned)) {
                  return Math.round(parseFloat(cleaned) * 10000);
                }
                if (/^\d+$/.test(cleaned)) return parseInt(cleaned, 10);
                return null;
              };
              const countNearLabel = (text, labels) => {
                const compact = clean(text);
                for (const label of labels) {
                  const before = compact.match(
                    new RegExp('([0-9]+(?:\\.[0-9]+)?万?\\+?)\\s*' + label)
                  );
                  if (before) return parseCountText(before[1]);
                  const after = compact.match(
                    new RegExp(label + '\\s*([0-9]+(?:\\.[0-9]+)?万?\\+?)')
                  );
                  if (after) return parseCountText(after[1]);
                }
                return null;
              };
              const visible = (el) => {
                if (!el) return false;
                const rect = el.getBoundingClientRect();
                const style = window.getComputedStyle(el);
                return rect.width > 80 && rect.height > 90 &&
                  rect.bottom > 110 && rect.top < window.innerHeight - 24 &&
                  style.visibility !== 'hidden' && style.display !== 'none';
              };
              const visiblePoint = (rect) => {
                if (!rect) return null;
                const inset = 8;
                const left = Math.max(rect.left + inset, inset);
                const right = Math.min(
                  rect.right - inset,
                  window.innerWidth - inset
                );
                const top = Math.max(rect.top + inset, 12);
                const bottom = Math.min(
                  rect.bottom - inset,
                  window.innerHeight - 16
                );
                if (right - left < 12 || bottom - top < 12) return null;
                return {
                  x: Math.round(window.screenX + (left + right) / 2),
                  y: Math.round(
                    window.screenY + toolbarHeight + (top + bottom) / 2
                  ),
                };
              };
              const toolbarHeight = Math.max(0, window.outerHeight - window.innerHeight);
              const anchors = Array.from(document.querySelectorAll('a[href*="/explore/"]'));
              const seen = new Set();
              const cards = [];
              for (const anchor of anchors) {
                const match = anchor.href.match(/\/explore\/([A-Za-z0-9]+)/);
                if (!match || seen.has(match[1])) continue;
                const container =
                  anchor.closest('[class*="note-item"], [class*="feed"], section, article') ||
                  anchor.closest('div') ||
                  anchor;
                if (!visible(container)) continue;
                seen.add(match[1]);

                const rect = container.getBoundingClientRect();
                const rawText = container.innerText || anchor.innerText || '';
                const text = clean(rawText);
                const lines = rawText
                  .split(/\n+/)
                  .map((line) => clean(line))
                  .filter(Boolean);
                const image = container.querySelector('img');
                const title = clean(
                  container.querySelector('.title')?.innerText ||
                  anchor.getAttribute('title') ||
                  image?.alt ||
                  lines.find(
                    (line) =>
                      line.length >= 4 &&
                      !/^\d+(\.\d+)?万?\+?$/.test(line)
                  ) ||
                  ''
                );
                if (!title) continue;

                const likeText = clean(
                  container.querySelector('.like-wrapper .count')?.innerText ||
                  container.querySelector('[class*="like"] [class*="count"]')?.innerText ||
                  container.querySelector('.count')?.innerText ||
                  ''
                );
                const fallbackCount =
                  lines.slice().reverse().find(
                    (line) => /^\d+(\.\d+)?万?\+?$/.test(line)
                  ) || '';
                const likes = parseCountText(likeText) ?? parseCountText(fallbackCount);
                const comments = countNearLabel(text, ['评论', '回复']);
                const saves = countNearLabel(text, ['收藏', '收藏数']);
                const userAnchor = container.querySelector('a[href*="/user/profile/"]');
                const clickAnchor =
                  container.querySelector('a.cover, a.title') || anchor;
                const clickRect = clickAnchor.getBoundingClientRect();
                const userRect = userAnchor?.getBoundingClientRect();
                const clickPoint = visiblePoint(clickRect);
                const userPoint = visiblePoint(userRect);

                cards.push({
                  note_id: match[1],
                  note_url: anchor.href,
                  title,
                  account_name: clean(
                    container.querySelector('.name')?.innerText ||
                    userAnchor?.innerText ||
                    ''
                  ) || 'unknown',
                  account_url: userAnchor?.href || null,
                  likes,
                  comments,
                  saves,
                  pinned: text.includes('置顶'),
                  screen_x: clickPoint?.x ?? null,
                  screen_y: clickPoint?.y ?? null,
                  author_screen_x: userPoint?.x ?? null,
                  author_screen_y: userPoint?.y ?? null,
                  author_opens_new_tab:
                    clean(userAnchor?.getAttribute('target')) === '_blank',
                  viewport_top: Math.round(rect.top),
                });
              }

              const scrolling = document.scrollingElement || document.documentElement;
              const scrollTop = Math.round(scrolling.scrollTop || 0);
              const scrollHeight = Math.round(
                scrolling.scrollHeight || document.body.scrollHeight || 0
              );
              const viewportHeight = Math.round(window.innerHeight || 0);
              return {
                cards: cards.sort((a, b) => a.viewport_top - b.viewport_top),
                url: location.href,
                title: document.title,
                viewport_height: viewportHeight,
                scroll_top: scrollTop,
                scroll_height: scrollHeight,
                at_end: scrollTop + viewportHeight >= scrollHeight - 32,
                scroll_screen_x: Math.round(window.screenX + window.innerWidth * 0.78),
                scroll_screen_y: Math.round(
                  window.screenY + toolbarHeight + window.innerHeight * 0.58
                ),
              };
            })())
            """
        )
    )
    payload["cards"] = [
        card
        for card in payload.get("cards", [])
        if card.get("note_id") and card.get("title")
    ]
    return payload


def _advance_xhs_feed(
    previous: FeedObservation,
    *,
    attempted_note_ids: set[str],
    require_writing_like_threshold: bool,
    require_visible_author: bool = False,
) -> dict[str, Any]:
    if previous.get("at_end"):
        return {"status": "end", "observation": previous}

    old_cards = previous.get("cards", [])
    old_ids = {card.get("note_id") for card in old_cards if card.get("note_id")}
    old_bottom_id = old_cards[-1].get("note_id") if old_cards else None
    old_scroll_top = int(previous.get("scroll_top") or 0)
    deadline = time.monotonic() + XHS_FEED_ADVANCE_WATCHDOG_SECONDS

    if previous.get("scroll_screen_x") is not None:
        _move_mouse_to_xhs_screen_point(
            int(previous["scroll_screen_x"]),
            int(previous["scroll_screen_y"]),
            action="feed_scroll_focus",
            wait_seconds=0.05,
        )

    latest = previous
    while time.monotonic() < deadline:
        scroll_current_chrome_wheel(
            clicks=XHS_FEED_SCROLL_PULSE_CLICKS,
            direction="down",
            pause_seconds=XHS_FEED_SCROLL_PULSE_PAUSE_SECONDS,
        )
        latest = _observe_xhs_note_feed()
        cards = latest.get("cards", [])

        if _has_actionable_visible_note(
            cards,
            attempted_note_ids=attempted_note_ids,
            require_writing_like_threshold=require_writing_like_threshold,
            require_visible_author=require_visible_author,
        ):
            return {"status": "target_visible", "observation": latest}

        current_ids = {card.get("note_id") for card in cards if card.get("note_id")}
        new_ids = current_ids - old_ids
        old_bottom = next(
            (card for card in cards if card.get("note_id") == old_bottom_id),
            None,
        )
        anchor_advanced = (
            old_bottom is None
            or int(old_bottom.get("viewport_top") or 0)
            <= int(latest.get("viewport_height") or 0) * 0.42
        )
        page_moved = int(latest.get("scroll_top") or 0) > old_scroll_top
        if new_ids and anchor_advanced and page_moved:
            return {"status": "advanced", "observation": latest}
        if latest.get("at_end") and page_moved:
            return {"status": "advanced", "observation": latest}

    log_event(
        "xhs_feed_stalled",
        level="warning",
        page_url=latest.get("url"),
        old_scroll_top=old_scroll_top,
        current_scroll_top=latest.get("scroll_top"),
        visible_note_ids=[
            card.get("note_id") for card in latest.get("cards", [])
        ],
    )
    return {
        "status": "end" if latest.get("at_end") else "stalled",
        "observation": latest,
    }


def _has_actionable_visible_note(
    cards: list[VisibleNoteTarget],
    *,
    attempted_note_ids: set[str],
    require_writing_like_threshold: bool,
    require_visible_author: bool,
) -> bool:
    for card in cards:
        note_id = card.get("note_id")
        if not note_id or note_id in attempted_note_ids:
            continue
        if card.get("screen_x") is None or card.get("screen_y") is None:
            continue
        if require_visible_author and (
            card.get("author_screen_x") is None
            or card.get("author_screen_y") is None
        ):
            continue
        if (
            not require_writing_like_threshold
            or _meets_writing_like_threshold(card)
        ):
            return True
    return False



def _is_high_quality_xhs_card(card: dict[str, Any]) -> bool:
    likes = card.get("likes")
    comments = card.get("comments")
    saves = card.get("saves")
    parsed_likes = _parse_count(likes) if isinstance(likes, str) else likes
    parsed_comments = _parse_count(comments) if isinstance(comments, str) else comments
    parsed_saves = _parse_count(saves) if isinstance(saves, str) else saves
    return (
        isinstance(parsed_likes, int) and parsed_likes >= XHS_HIGH_LIKE_THRESHOLD
    ) or (
        isinstance(parsed_comments, int)
        and parsed_comments >= XHS_HIGH_COMMENT_THRESHOLD
    ) or (
        isinstance(parsed_saves, int) and parsed_saves >= XHS_HIGH_SAVE_THRESHOLD
    )


def _meets_writing_like_threshold(card: dict[str, Any]) -> bool:
    likes = card.get("likes")
    parsed_likes = _parse_count(likes) if isinstance(likes, str) else likes
    return (
        isinstance(parsed_likes, int)
        and parsed_likes >= XHS_HIGH_LIKE_THRESHOLD
    )


def _field_coverage(items: list[dict[str, Any]]) -> dict[str, int]:
    fields = [
        "account_name",
        "author_url",
        "body",
        "comment_items",
        "comments",
        "hashtags",
        "images",
        "likes",
        "location",
        "note_id",
        "note_url",
        "publish_time",
        "saves",
        "shares",
        "subtitle",
        "title",
        "video",
    ]
    return {
        field: sum(1 for item in items if item.get(field) not in (None, "", []))
        for field in fields
    }


def _parse_count(value: str | None) -> int | None:
    if not value:
        return None
    value = re.sub(r"[,\s+]", "", value.strip())
    match = re.search(r"([0-9]+(?:\.[0-9]+)?)(万)?", value)
    if not match:
        return None
    try:
        number = float(match.group(1))
        if match.group(2):
            number *= 10000
        return int(number)
    except ValueError:
        return None


def _note_quality_threshold() -> dict[str, int]:
    return {
        "min_likes": XHS_HIGH_LIKE_THRESHOLD,
        "min_comments": XHS_HIGH_COMMENT_THRESHOLD,
        "min_saves": XHS_HIGH_SAVE_THRESHOLD,
    }


def _writing_quality_threshold() -> dict[str, int]:
    return {"visible_min_likes": XHS_HIGH_LIKE_THRESHOLD}


def _validate_xhs_screen_point(
    x: int,
    y: int,
    *,
    action: str,
    margin: int = 6,
) -> ChromeContentBounds:
    bounds = current_chrome_content_bounds()
    x = int(x)
    y = int(y)
    url = bounds["url"]
    on_xhs = "xiaohongshu.com" in url
    inside = (
        bounds["left"] + margin <= x <= bounds["right"] - margin
        and bounds["top"] + margin <= y <= bounds["bottom"] - margin
    )
    if on_xhs and inside:
        return bounds

    log_event(
        "xhs_pointer_action_blocked",
        level="error",
        action=action,
        screen_x=x,
        screen_y=y,
        chrome_content_bounds=bounds,
        reason="not_on_xhs" if not on_xhs else "outside_chrome_content",
    )
    if not on_xhs:
        raise RuntimeError(
            f"blocked {action}: active Chrome tab is not Xiaohongshu ({url})"
        )
    raise RuntimeError(
        f"blocked {action}: screen point ({x}, {y}) is outside "
        f"Chrome content bounds {bounds}"
    )


def _click_xhs_screen_point(
    x: int,
    y: int,
    *,
    action: str,
    wait_seconds: float = 0.2,
) -> None:
    _validate_xhs_screen_point(x, y, action=action)
    click_screen_point(x, y, wait_seconds=wait_seconds)


def _move_mouse_to_xhs_screen_point(
    x: int,
    y: int,
    *,
    action: str,
    wait_seconds: float = 0.1,
) -> None:
    _validate_xhs_screen_point(x, y, action=action)
    move_mouse_screen_point(x, y, wait_seconds=wait_seconds)


def _drag_xhs_screen_points(
    start_x: int,
    start_y: int,
    end_x: int,
    end_y: int,
    *,
    action: str,
    duration_seconds: float = 0.35,
) -> None:
    _validate_xhs_screen_point(start_x, start_y, action=f"{action}_start")
    _validate_xhs_screen_point(end_x, end_y, action=f"{action}_end")
    drag_screen_points(
        start_x,
        start_y,
        end_x,
        end_y,
        duration_seconds=duration_seconds,
    )


# Strategy creator flow


def _save_strategy_corpus(
    path: Path,
    *,
    keywords: list[str],
    searched_keywords: list[dict],
    accounts: list[dict],
    target_creators: int,
    notes_per_creator: int,
    started_at: datetime,
    completed: bool,
    rejected_creators: list[dict[str, Any]] | None = None,
) -> None:
    note_count = sum(len(account.get("notes", [])) for account in accounts)
    rejected_creators = rejected_creators or []
    corpus = {
        "platform": "xiaohongshu",
        "corpus_type": "creator_strategy_research",
        "research_goal": (
            "浏览并拆解成熟博主及其高互动笔记，用于反推 content-agent 的最终账号人设、"
            "写作规则、平台方法和验收标准。"
        ),
        "source": "xhs_current_chrome_visible_detail",
        "requirements": {
            "target_creators": target_creators,
            "notes_per_creator": notes_per_creator,
            "target_notes": target_creators * notes_per_creator,
            "target_creator_min_followers": XHS_STRATEGY_MIN_FOLLOWERS,
            "note_quality_threshold": _note_quality_threshold(),
            "note_detail_required": True,
        },
        "coverage": {
            "creator_count": len(accounts),
            "rejected_creator_count": len(rejected_creators),
            "note_count": note_count,
            "target_met": len(accounts) >= target_creators,
            "keywords": keywords,
            "searched_keywords": searched_keywords,
        },
        "accounts": accounts,
        "rejected_creators": rejected_creators[:200],
        "collector_meta": {
            "started_at": started_at.isoformat(),
            "last_saved_at": datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(),
            "completed": completed,
            "chrome_profile": "user_current_logged_in_chrome",
            "browsing_method": "visible_observe_click_read_return",
            "collection_note": (
                "Creators were inspected one by one through the visible page. "
                "Qualified creator notes contain complete detail-page data."
            ),
        },
    }
    path.write_text(json.dumps(corpus, ensure_ascii=False, indent=2), encoding="utf-8")


def _browse_xhs_strategy_keyword_current_chrome(
    keyword: str,
    *,
    creator_inspection_target: int,
    qualified_creator_target: int,
    notes_per_creator: int,
    visited_creator_ids: set[str],
    progress: bool,
    note_pause_seconds: float,
    account_pause_seconds: float,
) -> dict[str, Any]:
    search_url = f"{XHS_BASE_URL}/search_result?keyword={quote(keyword)}"
    observation = _open_xhs_search_page(search_url)
    if not _is_xhs_search_page(observation):
        return {
            "accounts": [],
            "rejected_creators": [],
            "inspected_creator_count": 0,
            "viewport_advance_count": 0,
            "completion_reason": "navigation_failed",
            "warnings": [f"search_navigation_failed for '{keyword}'"],
        }

    accounts: list[dict[str, Any]] = []
    rejected_creators: list[dict[str, Any]] = []
    examined_search_note_ids: set[str] = set()
    warnings: list[str] = []
    inspected_creator_count = 0
    viewport_advance_count = 0
    completion_reason = "query_watchdog"
    started_at = time.monotonic()

    while time.monotonic() - started_at < XHS_QUERY_WATCHDOG_SECONDS:
        if len(accounts) >= qualified_creator_target:
            completion_reason = "qualified_creator_target_reached"
            break
        if inspected_creator_count >= creator_inspection_target:
            completion_reason = "creator_inspection_target_reached"
            break

        target = _next_visible_creator_target(
            observation.get("cards", []),
            visited_creator_ids=visited_creator_ids,
            examined_search_note_ids=examined_search_note_ids,
        )
        if target:
            creator_id = _creator_id_from_url(target.get("account_url"))
            if creator_id:
                visited_creator_ids.add(creator_id)
            inspected_creator_count += 1
            if progress:
                print(
                    f"  Inspecting creator {inspected_creator_count}/"
                    f"{creator_inspection_target}: {target.get('account_name')}",
                    flush=True,
                )
            log_event(
                "xhs_creator_target_selected",
                workflow="strategy",
                query=keyword,
                discovery_method="visible_search_result_author_click",
                creator_id=creator_id,
                account_name=target.get("account_name"),
                account_url=target.get("account_url"),
                discovered_note_id=target.get("note_id"),
            )

            click_result = _click_visible_creator_target(target)
            profile = (
                _wait_for_xhs_profile(
                    fallback_name=target.get("account_name") or "unknown",
                    fallback_url=target.get("account_url") or "",
                )
                if click_result.get("clicked")
                else {
                    "profile_ready": False,
                    "profile_error": click_result.get("error"),
                }
            )
            if (
                not profile.get("profile_ready")
                and "/search_result" in str(profile.get("account_url") or "")
            ):
                retry_observation = _observe_xhs_note_feed()
                retry_target = next(
                    (
                        card
                        for card in retry_observation.get("cards", [])
                        if _creator_id_from_url(card.get("account_url"))
                        == creator_id
                        and card.get("author_screen_x") is not None
                        and card.get("author_screen_y") is not None
                    ),
                    None,
                )
                if retry_target:
                    retry_click = _click_visible_creator_target(retry_target)
                    if retry_click.get("clicked"):
                        profile = _wait_for_xhs_profile(
                            fallback_name=target.get("account_name") or "unknown",
                            fallback_url=target.get("account_url") or "",
                        )
            follower_count = profile.get("follower_count")
            if (
                profile.get("profile_ready")
                and isinstance(follower_count, int)
                and follower_count > XHS_STRATEGY_MIN_FOLLOWERS
            ):
                note_result = _browse_xhs_profile_notes_current_chrome(
                    profile,
                    target_count=notes_per_creator,
                    note_pause_seconds=note_pause_seconds,
                )
                profile.pop("profile_ready", None)
                profile.pop("profile_error", None)
                profile["notes"] = note_result["notes"]
                profile["seed_keyword"] = keyword
                profile["discovered_from_note"] = {
                    "note_id": target.get("note_id"),
                    "title": target.get("title"),
                    "note_url": target.get("note_url"),
                    "likes": target.get("likes"),
                    "comments": target.get("comments"),
                    "saves": target.get("saves"),
                }
                profile["collection_meta"] = {
                    "profile_complete": True,
                    "target_creator_min_followers": XHS_STRATEGY_MIN_FOLLOWERS,
                    "note_target": notes_per_creator,
                    "note_count": len(note_result["notes"]),
                    "note_completion_reason": note_result["completion_reason"],
                    "note_errors": note_result["detail_errors"][:20],
                    "viewport_advance_count": note_result["viewport_advance_count"],
                    "collected_at": datetime.now(
                        ZoneInfo("Asia/Shanghai")
                    ).isoformat(),
                }
                if len(note_result["notes"]) >= notes_per_creator:
                    accounts.append(profile)
                    if progress:
                        print(
                            f"    Qualified: followers={follower_count}, "
                            f"notes={len(note_result['notes'])}/{notes_per_creator}",
                            flush=True,
                        )
                    log_event(
                        "xhs_creator_collected",
                        workflow="strategy",
                        query=keyword,
                        creator_id=profile.get("account_id"),
                        follower_count=follower_count,
                        note_count=len(note_result["notes"]),
                        note_completion_reason=note_result["completion_reason"],
                    )
                else:
                    reason = (
                        "qualified_creator_note_target_incomplete: "
                        f"{len(note_result['notes'])}/{notes_per_creator}"
                    )
                    rejected_creators.append(
                        {
                            "account_id": profile.get("account_id"),
                            "account_name": profile.get("account_name"),
                            "account_url": profile.get("account_url"),
                            "follower_count": follower_count,
                            "collected_note_count": len(note_result["notes"]),
                            "reason": reason,
                            "seed_keyword": keyword,
                        }
                    )
                    if progress:
                        print(f"    Skipped: {reason}", flush=True)
                    log_event(
                        "xhs_creator_rejected",
                        level="warning",
                        workflow="strategy",
                        query=keyword,
                        creator_id=profile.get("account_id"),
                        follower_count=follower_count,
                        reason=reason,
                    )
            else:
                reason = profile.get("profile_error") or (
                    f"follower_count_not_above_{XHS_STRATEGY_MIN_FOLLOWERS}: "
                    f"{follower_count}"
                )
                rejected_creators.append(
                    {
                        "account_id": profile.get("account_id") or creator_id,
                        "account_name": profile.get("account_name")
                        or target.get("account_name"),
                        "account_url": profile.get("account_url")
                        or target.get("account_url"),
                        "follower_count": follower_count,
                        "reason": reason,
                        "seed_keyword": keyword,
                    }
                )
                if progress:
                    print(f"    Skipped: {reason}", flush=True)
                log_event(
                    "xhs_creator_rejected",
                    level="warning",
                    workflow="strategy",
                    query=keyword,
                    creator_id=profile.get("account_id") or creator_id,
                    follower_count=follower_count,
                    reason=reason,
                )

            _return_to_xhs_search(
                search_url,
                opened_new_tab=bool(target.get("author_opens_new_tab")),
            )
            if account_pause_seconds > 0:
                time.sleep(account_pause_seconds)
            observation = _observe_xhs_note_feed()
            continue

        advance = _advance_xhs_feed(
            observation,
            attempted_note_ids=examined_search_note_ids,
            require_writing_like_threshold=False,
            require_visible_author=True,
        )
        observation = advance["observation"]
        status = advance["status"]
        if status == "advanced" or status == "target_visible":
            viewport_advance_count += 1
            continue
        completion_reason = "feed_end" if status == "end" else "feed_stalled"
        if status == "stalled":
            warnings.append(f"creator_search_feed_stalled for '{keyword}'")
        break
    else:
        warnings.append(f"creator_query_watchdog_reached for '{keyword}'")

    return {
        "accounts": accounts,
        "rejected_creators": rejected_creators,
        "inspected_creator_count": inspected_creator_count,
        "viewport_advance_count": viewport_advance_count,
        "completion_reason": completion_reason,
        "warnings": warnings,
    }


def _next_visible_creator_target(
    cards: list[VisibleNoteTarget],
    *,
    visited_creator_ids: set[str],
    examined_search_note_ids: set[str],
) -> VisibleNoteTarget | None:
    for card in cards:
        note_id = card.get("note_id")
        if not note_id or note_id in examined_search_note_ids:
            continue
        if (
            card.get("author_screen_x") is None
            or card.get("author_screen_y") is None
        ):
            continue
        examined_search_note_ids.add(note_id)
        creator_id = _creator_id_from_url(card.get("account_url"))
        if (
            not creator_id
            or creator_id in visited_creator_ids
        ):
            continue
        return card
    return None


def _click_visible_creator_target(
    target: VisibleNoteTarget,
) -> dict[str, Any]:
    """Open a profile by clicking its visible avatar/name, never its URL."""
    try:
        _click_xhs_screen_point(
            int(target["author_screen_x"]),
            int(target["author_screen_y"]),
            action="search_result_author_identity",
        )
        return {"clicked": True}
    except Exception as exc:
        return {"clicked": False, "error": f"creator click failed: {exc}"}


def _wait_for_xhs_profile(
    *,
    fallback_name: str,
    fallback_url: str,
) -> dict[str, Any]:
    deadline = time.monotonic() + XHS_DETAIL_OPEN_WATCHDOG_SECONDS
    latest: dict[str, Any] = {
        "profile_ready": False,
        "profile_error": "profile did not become readable",
    }
    while time.monotonic() < deadline:
        time.sleep(0.6)
        latest = _read_xhs_profile(
            fallback_name=fallback_name,
            fallback_url=fallback_url,
        )
        if latest.get("profile_ready"):
            return latest
        if "/search_result" in str(latest.get("account_url") or ""):
            return latest
    return latest


def _read_xhs_profile(
    *,
    fallback_name: str,
    fallback_url: str,
) -> dict[str, Any]:
    try:
        return json.loads(
            execute_current_chrome_js(
                f"""
                JSON.stringify((() => {{
                  const clean = (value) =>
                    String(value || '').replace(/\\s+/g, ' ').trim();
                  const parseCountText = (value) => {{
                    const cleaned = clean(value).replace(/[,+]/g, '');
                    if (/^\\d+(\\.\\d+)?万$/.test(cleaned)) {{
                      return Math.round(parseFloat(cleaned) * 10000);
                    }}
                    if (/^\\d+$/.test(cleaned)) return parseInt(cleaned, 10);
                    return null;
                  }};
                  const countNearLabel = (text, labels) => {{
                    const compact = clean(text);
                    for (const label of labels) {{
                      const before = compact.match(
                        new RegExp(
                          '([0-9]+(?:\\\\.[0-9]+)?万?\\\\+?)\\\\s*' + label
                        )
                      );
                      if (before) return parseCountText(before[1]);
                      const after = compact.match(
                        new RegExp(
                          label + '\\\\s*([0-9]+(?:\\\\.[0-9]+)?万?\\\\+?)'
                        )
                      );
                      if (after) return parseCountText(after[1]);
                    }}
                    return null;
                  }};
                  const profileMatch = location.pathname.match(
                    /\\/user\\/profile\\/([A-Za-z0-9]+)/
                  );
                  if (!profileMatch) {{
                    return {{
                      profile_ready: false,
                      profile_error: 'current page is not an XHS profile',
                      account_url: location.href,
                    }};
                  }}
                  const root =
                    document.querySelector('.user-info') ||
                    document.querySelector('[class*="user-info"]') ||
                    document.querySelector('main') ||
                    document.body;
                  const profileText = clean(root.innerText || '');
                  const name = clean(
                    root.querySelector('h1')?.innerText ||
                    root.querySelector('[class*="user-name"]')?.innerText ||
                    root.querySelector('[class*="nickname"]')?.innerText ||
                    {json.dumps(fallback_name)}
                  );
                  const bio = clean(
                    root.querySelector('.user-desc')?.innerText ||
                    root.querySelector('[class*="user-desc"]')?.innerText ||
                    root.querySelector('[class*="desc"]')?.innerText ||
                    ''
                  );
                  const tags = Array.from(
                    root.querySelectorAll(
                      '.user-tags span, [class*="user-tag"], [class*="tag-item"]'
                    )
                  )
                    .map((el) => clean(el.innerText))
                    .filter(Boolean);
                  const avatar = root.querySelector(
                    'img[class*="avatar"], .avatar img'
                  );
                  const redIdMatch = profileText.match(
                    /小红书号[：:]?\\s*([^\\s]+)/
                  );
                  const locationMatch = profileText.match(
                    /IP属地[：:]?\\s*([^\\s]+)/
                  );
                  const followerCount = countNearLabel(profileText, ['粉丝']);
                  return {{
                    profile_ready: Boolean(name && followerCount !== null),
                    profile_error:
                      followerCount === null ? 'follower count is not readable' : null,
                    account_id: profileMatch[1],
                    account_name: name || {json.dumps(fallback_name)},
                    account_url: location.href || {json.dumps(fallback_url)},
                    avatar_url: avatar?.currentSrc || avatar?.src || null,
                    red_id: redIdMatch?.[1] || null,
                    ip_location: locationMatch?.[1] || null,
                    bio: bio || null,
                    follower_count: followerCount,
                    following_count: countNearLabel(profileText, ['关注']),
                    liked_count: countNearLabel(
                      profileText,
                      ['获赞与收藏', '获赞', '赞和收藏']
                    ),
                    positioning_notes: [bio, ...tags].filter(Boolean),
                  }};
                }})())
                """
            )
        )
    except Exception as exc:
        return {
            "profile_ready": False,
            "profile_error": str(exc),
            "account_name": fallback_name,
            "account_url": fallback_url,
        }


def _browse_xhs_profile_notes_current_chrome(
    profile: dict[str, Any],
    *,
    target_count: int,
    note_pause_seconds: float,
) -> dict[str, Any]:
    attempted_note_ids: set[str] = set()
    observed_positions: dict[str, int] = {}
    notes: list[XhsNote] = []
    detail_errors: list[dict[str, Any]] = []
    viewport_advance_count = 0
    completion_reason = "profile_watchdog"
    started_at = time.monotonic()
    observation = _observe_xhs_note_feed()

    while time.monotonic() - started_at < XHS_PROFILE_WATCHDOG_SECONDS:
        for card in observation.get("cards", []):
            note_id = card.get("note_id")
            if note_id and note_id not in observed_positions:
                observed_positions[note_id] = len(observed_positions) + 1

        target = _next_visible_strategy_note_target(
            observation.get("cards", []),
            attempted_note_ids=attempted_note_ids,
        )
        if target:
            result = _collect_complete_note_by_click(
                target,
                source_page="profile",
                source_query=None,
                creator=profile,
            )
            if result.get("ok"):
                note = result["note"]
                if _is_high_quality_xhs_card(note):
                    note.setdefault("collection_meta", {}).update(
                        {
                            "homepage_position": observed_positions.get(
                                target.get("note_id")
                            ),
                            "pinned": bool(target.get("pinned")),
                        }
                    )
                    notes.append(note)
                else:
                    detail_errors.append(
                        {
                            "note_id": target.get("note_id"),
                            "note_url": target.get("note_url"),
                            "title": target.get("title"),
                            "error": "complete detail did not meet the note quality threshold",
                        }
                    )
            else:
                detail_errors.append(
                    {
                        "note_id": target.get("note_id"),
                        "note_url": target.get("note_url"),
                        "title": target.get("title"),
                        "error": result.get("error"),
                    }
                )
            if len(notes) >= target_count:
                completion_reason = "target_reached"
                break
            if note_pause_seconds > 0:
                time.sleep(note_pause_seconds)
            observation = _observe_xhs_note_feed()
            continue

        advance = _advance_xhs_feed(
            observation,
            attempted_note_ids=attempted_note_ids,
            require_writing_like_threshold=False,
        )
        observation = advance["observation"]
        status = advance["status"]
        if status == "advanced" or status == "target_visible":
            viewport_advance_count += 1
            continue
        completion_reason = "feed_end" if status == "end" else "feed_stalled"
        break
    else:
        detail_errors.append(
            {
                "error": "profile_watchdog_reached",
                "account_id": profile.get("account_id"),
            }
        )

    return {
        "notes": notes,
        "detail_errors": detail_errors,
        "viewport_advance_count": viewport_advance_count,
        "completion_reason": completion_reason,
    }


def _return_to_xhs_search(
    search_url: str,
    *,
    opened_new_tab: bool,
) -> None:
    try:
        if opened_new_tab:
            close_current_chrome_tab(wait_seconds=1.0)
        else:
            navigate_current_chrome_back(wait_seconds=1.0)
        deadline = time.monotonic() + XHS_DETAIL_OPEN_WATCHDOG_SECONDS
        while time.monotonic() < deadline:
            observation = _observe_xhs_note_feed()
            if "/search_result" in str(observation.get("url") or ""):
                return
            time.sleep(0.4)
    except Exception as exc:
        log_event(
            "xhs_search_return_failed",
            level="warning",
            error_message=str(exc),
            search_url=search_url,
        )
    open_current_chrome_url(search_url, wait_seconds=5)


def _creator_id_from_url(url: str | None) -> str | None:
    if not url:
        return None
    match = re.search(r"/user/profile/([A-Za-z0-9]+)", url)
    return match.group(1) if match else None



# Complete note-detail collection


def _collect_complete_note_by_click(
    target: VisibleNoteTarget,
    *,
    source_page: str,
    source_query: str | None,
    creator: dict[str, Any] | None = None,
) -> dict[str, Any]:
    clicked = _click_visible_note_card(target)
    if not clicked.get("clicked"):
        return {
            "ok": False,
            "error": clicked.get("error") or "could not click visible note card",
        }

    raw: dict[str, Any] = {
        "status": "pending",
        "error": "detail did not become readable",
    }
    try:
        deadline = time.monotonic() + XHS_DETAIL_OPEN_WATCHDOG_SECONDS
        while time.monotonic() < deadline:
            time.sleep(0.6)
            raw = _read_current_note_detail()
            if raw.get("status") != "pending":
                break

        if raw.get("status") != "ready":
            log_event(
                "xhs_note_detail_open_failed",
                level="warning",
                workflow="strategy" if source_page == "profile" else "writing",
                expected_note_id=target.get("note_id"),
                expected_note_url=target.get("note_url"),
                resolved_url=raw.get("resolved_url"),
                page_title=raw.get("page_title"),
                error_message=raw.get("error"),
            )
            return {
                "ok": False,
                "error": raw.get("error") or "detail did not become readable",
            }

        expected_note_id = target.get("note_id")
        resolved_note_id = raw.get("note_id")
        if expected_note_id and resolved_note_id and expected_note_id != resolved_note_id:
            log_event(
                "xhs_note_detail_mismatch",
                level="warning",
                workflow="strategy" if source_page == "profile" else "writing",
                expected_note_id=expected_note_id,
                resolved_note_id=resolved_note_id,
                resolved_url=raw.get("resolved_url"),
            )
            return {
                "ok": False,
                "error": (
                    f"opened note mismatch: expected {expected_note_id}, "
                    f"got {resolved_note_id}"
                ),
            }

        raw = _browse_complete_xhs_note_detail(raw)
        note = _finalize_xhs_note(
            raw,
            target=target,
            source_page=source_page,
            source_query=source_query,
            creator=creator,
        )
        complete, missing = _is_complete_xhs_note(note)
        note.setdefault("collection_meta", {})["complete"] = complete
        note["collection_meta"]["missing_fields"] = missing
        if not complete:
            log_event(
                "xhs_note_detail_incomplete",
                level="warning",
                workflow="strategy" if source_page == "profile" else "writing",
                note_id=note.get("note_id"),
                note_url=note.get("note_url"),
                missing_fields=missing,
                collection_meta=note.get("collection_meta"),
            )
            return {
                "ok": False,
                "error": f"incomplete note detail: {', '.join(missing)}",
                "partial_note": note,
            }

        log_event(
            "xhs_note_detail_completed",
            workflow="strategy" if source_page == "profile" else "writing",
            note_id=note.get("note_id"),
            title=note.get("title"),
            image_count=len(note.get("images") or []),
            comment_item_count=len(note.get("comment_items") or []),
            completion_reason=note.get("collection_meta", {}).get(
                "detail_completion_reason"
            ),
            gallery_completion_reason=note.get("collection_meta", {}).get(
                "gallery_completion_reason"
            ),
            comment_completion_reason=note.get("collection_meta", {}).get(
                "comment_completion_reason"
            ),
            expanded_reply_control_count=note.get("collection_meta", {}).get(
                "expanded_reply_control_count"
            ),
        )
        return {"ok": True, "note": note}
    finally:
        close_result = _close_current_note_detail()
        if not close_result.get("closed"):
            log_event(
                "xhs_note_detail_close_failed",
                level="warning",
                note_id=target.get("note_id"),
                error_message=close_result.get("error"),
            )


def _browse_complete_xhs_note_detail(
    initial: dict[str, Any],
) -> dict[str, Any]:
    merged = dict(initial)
    merged["collection_progress"] = {
        "detail_completion_reason": "not_started",
        "gallery_completion_reason": "not_started",
        "viewport_advance_count": 0,
        "gallery_advance_count": 0,
        "expanded_control_count": 0,
        "expanded_reply_control_count": 0,
        "expanded_body_control_count": 0,
        "comment_completion_reason": "not_started",
        "gallery_total": None,
        "gallery_last_position": None,
        "image_resource_count": len(initial.get("images") or []),
    }
    time.sleep(XHS_DETAIL_INITIAL_DWELL_SECONDS)
    merged = _browse_xhs_detail_gallery(merged)

    deadline = time.monotonic() + XHS_DETAIL_WATCHDOG_SECONDS
    expanded_controls: set[str] = set()
    previous_signature = _xhs_note_payload_signature(merged)
    previous_scroll_top = _detail_scroll_top(merged)

    while time.monotonic() < deadline:
        expand_control = _next_xhs_expand_control(
            merged,
            expanded_controls=expanded_controls,
        )
        if expand_control:
            key = str(expand_control.get("key") or "")
            try:
                _click_xhs_screen_point(
                    int(expand_control["screen_x"]),
                    int(expand_control["screen_y"]),
                    action="detail_expand_control",
                    wait_seconds=0.1,
                )
                if key:
                    expanded_controls.add(key)
                time.sleep(0.6)
                merged = _merge_xhs_note_payloads(
                    merged,
                    _read_current_note_detail(),
                )
                progress = merged["collection_progress"]
                progress["expanded_control_count"] = (
                    int(progress.get("expanded_control_count") or 0) + 1
                )
                control_kind = str(expand_control.get("kind") or "body")
                progress_key = (
                    "expanded_reply_control_count"
                    if control_kind == "comment_replies"
                    else "expanded_body_control_count"
                )
                progress[progress_key] = int(progress.get(progress_key) or 0) + 1
                previous_signature = _xhs_note_payload_signature(merged)
                previous_scroll_top = _detail_scroll_top(merged)
                continue
            except Exception as exc:
                log_event(
                    "xhs_detail_expand_failed",
                    level="warning",
                    control_key=key,
                    error_message=str(exc),
                )

        scroll_state = merged.get("scroll_state") or {}
        if scroll_state.get("at_bottom"):
            time.sleep(0.7)
            settled = _read_current_note_detail()
            settled_signature = _xhs_note_payload_signature(
                _merge_xhs_note_payloads(merged, settled)
            )
            settled_scroll_height = (
                (settled.get("scroll_state") or {}).get("scroll_height")
            )
            current_scroll_height = scroll_state.get("scroll_height")
            merged = _merge_xhs_note_payloads(merged, settled)
            if (
                settled_signature == previous_signature
                and settled_scroll_height == current_scroll_height
                and not _next_xhs_expand_control(
                    merged,
                    expanded_controls=expanded_controls,
                )
            ):
                merged["collection_progress"][
                    "detail_completion_reason"
                ] = "reached_detail_bottom"
                merged["collection_progress"][
                    "comment_completion_reason"
                ] = _comment_completion_reason(merged)
                break
            previous_signature = _xhs_note_payload_signature(merged)
            previous_scroll_top = _detail_scroll_top(merged)
            continue

        advance = _advance_xhs_detail_viewport(merged)
        merged = advance["payload"]
        progress = merged["collection_progress"]
        progress["viewport_advance_count"] = (
            int(progress.get("viewport_advance_count") or 0) + 1
        )
        if advance["status"] == "stalled":
            progress["detail_completion_reason"] = "detail_scroll_stalled"
            progress["comment_completion_reason"] = "comment_browse_incomplete"
            break
        current_signature = _xhs_note_payload_signature(merged)
        current_scroll_top = _detail_scroll_top(merged)
        if (
            current_scroll_top == previous_scroll_top
            and current_signature == previous_signature
        ):
            progress["detail_completion_reason"] = "detail_scroll_stalled"
            progress["comment_completion_reason"] = "comment_browse_incomplete"
            break
        previous_signature = current_signature
        previous_scroll_top = current_scroll_top
    else:
        merged["collection_progress"][
            "detail_completion_reason"
        ] = "detail_watchdog"
        merged["collection_progress"][
            "comment_completion_reason"
        ] = "comment_browse_incomplete"

    return merged


def _comment_completion_reason(payload: dict[str, Any]) -> str:
    reported_count = _parse_metric_count(payload.get("comment_text"))
    collected_count = len(payload.get("comment_items") or [])
    if reported_count == 0:
        return "no_comments"
    if collected_count > 0:
        return "reached_comment_bottom"
    if reported_count is None:
        return "comments_unavailable"
    return "comments_not_readable"


def _browse_xhs_detail_gallery(
    initial: dict[str, Any],
) -> dict[str, Any]:
    merged = dict(initial)
    progress = merged.setdefault("collection_progress", {})
    deadline = time.monotonic() + XHS_GALLERY_WATCHDOG_SECONDS
    seen_active_sources: set[str] = set()
    gallery_advance_count = 0

    while time.monotonic() < deadline:
        gallery = merged.get("gallery_state") or {}
        images = merged.get("images") or []
        total = gallery.get("total")
        current = gallery.get("current")
        if isinstance(total, int):
            progress["gallery_total"] = total
        if isinstance(current, int):
            progress["gallery_last_position"] = current
        progress["image_resource_count"] = len(images)
        has_pagination = isinstance(total, int) and isinstance(current, int)
        active_source = str(gallery.get("active_source") or "")
        if active_source and not has_pagination:
            if active_source in seen_active_sources and gallery_advance_count > 0:
                progress["gallery_completion_reason"] = "gallery_cycle_complete"
                break
            seen_active_sources.add(active_source)

        if isinstance(total, int) and total <= 1:
            progress["gallery_completion_reason"] = "single_image"
            break
        if (
            isinstance(total, int)
            and isinstance(current, int)
            and total > 0
            and current >= total
        ):
            progress["gallery_completion_reason"] = "reached_last_image"
            break

        next_point = gallery.get("next_point")
        swipe = gallery.get("swipe")
        if not next_point and not swipe:
            progress["gallery_completion_reason"] = (
                "all_image_resources_loaded"
                if len(images) > 1
                else "no_gallery"
            )
            break

        before_marker = _xhs_gallery_marker(gallery)
        try:
            if next_point:
                _click_xhs_screen_point(
                    int(next_point["screen_x"]),
                    int(next_point["screen_y"]),
                    action="gallery_next",
                    wait_seconds=0.1,
                )
            else:
                _swipe_xhs_gallery(swipe)
        except Exception as exc:
            progress["gallery_completion_reason"] = (
                f"gallery_navigation_failed: {exc}"
            )
            break
        time.sleep(XHS_DETAIL_IMAGE_STEP_PAUSE_SECONDS)
        merged = _merge_xhs_note_payloads(
            merged,
            _read_current_note_detail(),
        )
        progress = merged.setdefault("collection_progress", progress)
        after_marker = _xhs_gallery_marker(
            merged.get("gallery_state") or {}
        )
        if after_marker == before_marker and next_point and swipe:
            _swipe_xhs_gallery(swipe)
            time.sleep(XHS_DETAIL_IMAGE_STEP_PAUSE_SECONDS)
            merged = _merge_xhs_note_payloads(
                merged,
                _read_current_note_detail(),
            )
            progress = merged.setdefault("collection_progress", progress)
            after_marker = _xhs_gallery_marker(
                merged.get("gallery_state") or {}
            )
        if after_marker == before_marker:
            progress["gallery_completion_reason"] = (
                "single_image"
                if not has_pagination and len(images) <= 1
                else "gallery_navigation_stalled"
            )
            break
        gallery_advance_count += 1
        progress["gallery_advance_count"] = gallery_advance_count
    else:
        progress["gallery_completion_reason"] = "gallery_watchdog"

    progress["image_resource_count"] = len(merged.get("images") or [])
    return merged


def _xhs_gallery_marker(gallery: dict[str, Any]) -> tuple[Any, str]:
    src = str(gallery.get("active_source") or "")
    resource = _xhs_image_resource_key(src)
    return gallery.get("current"), resource


def _xhs_image_resource_key(src: str) -> str:
    path = src.split("?", 1)[0]
    if "/spectrum/" in path:
        path = path.split("/spectrum/", 1)[1]
    else:
        path = path.rsplit("/", 1)[-1]
    return path.split("!", 1)[0]


def _swipe_xhs_gallery(swipe: dict[str, Any]) -> None:
    _drag_xhs_screen_points(
        int(swipe["start_x"]),
        int(swipe["start_y"]),
        int(swipe["end_x"]),
        int(swipe["end_y"]),
        action="gallery_swipe",
        duration_seconds=0.35,
    )


def _next_xhs_expand_control(
    payload: dict[str, Any],
    *,
    expanded_controls: set[str],
) -> dict[str, Any] | None:
    for control in payload.get("expand_controls") or []:
        key = str(control.get("key") or "")
        if key and key not in expanded_controls:
            return control
    return None


def _move_to_xhs_detail_scroll_area(payload: dict[str, Any]) -> None:
    state = payload.get("scroll_state") or {}
    if state.get("screen_x") is None or state.get("screen_y") is None:
        return
    _move_mouse_to_xhs_screen_point(
        int(state["screen_x"]),
        int(state["screen_y"]),
        action="detail_scroll_focus",
        wait_seconds=0.05,
    )


def _advance_xhs_detail_viewport(
    payload: dict[str, Any],
) -> dict[str, Any]:
    merged = payload
    initial_state = payload.get("scroll_state") or {}
    initial_top = int(initial_state.get("scroll_top") or 0)
    client_height = max(int(initial_state.get("client_height") or 0), 1)
    target_distance = max(int(client_height * 0.62), 280)
    deadline = time.monotonic() + XHS_DETAIL_VIEWPORT_WATCHDOG_SECONDS
    _move_to_xhs_detail_scroll_area(payload)

    while time.monotonic() < deadline:
        scroll_current_chrome_wheel(
            clicks=XHS_DETAIL_SCROLL_PULSE_CLICKS,
            direction="down",
            pause_seconds=XHS_DETAIL_SCROLL_PULSE_PAUSE_SECONDS,
        )
        merged = _merge_xhs_note_payloads(
            merged,
            _read_current_note_detail(),
        )
        state = merged.get("scroll_state") or {}
        current_top = int(state.get("scroll_top") or 0)
        if state.get("at_bottom"):
            return {"status": "end", "payload": merged}
        if current_top - initial_top >= target_distance:
            return {"status": "advanced", "payload": merged}

    final_top = int((merged.get("scroll_state") or {}).get("scroll_top") or 0)
    return {
        "status": "advanced" if final_top > initial_top else "stalled",
        "payload": merged,
    }


def _detail_scroll_top(payload: dict[str, Any]) -> int | None:
    value = (payload.get("scroll_state") or {}).get("scroll_top")
    return int(value) if isinstance(value, (int, float)) else None


def _xhs_note_payload_signature(
    payload: dict[str, Any],
) -> tuple[Any, ...]:
    return (
        len(str(payload.get("title") or "")),
        len(str(payload.get("body") or "")),
        len(payload.get("hashtags") or []),
        len(payload.get("images") or []),
        len(payload.get("comment_items") or []),
        payload.get("like_text"),
        payload.get("comment_text"),
        payload.get("save_text"),
        payload.get("share_text"),
        (payload.get("scroll_state") or {}).get("scroll_height"),
    )


def _merge_xhs_note_payloads(
    primary: dict[str, Any],
    secondary: dict[str, Any],
) -> dict[str, Any]:
    if not secondary or secondary.get("status") not in {None, "ready"}:
        return primary
    merged = dict(primary)
    progress = dict(primary.get("collection_progress") or {})
    for key, value in secondary.items():
        if value in (None, "", []):
            continue
        if key == "body":
            if len(str(value)) > len(str(merged.get("body") or "")):
                merged[key] = value
        elif key == "hashtags":
            merged[key] = _merge_unique_strings(
                merged.get(key) or [],
                value or [],
            )
        elif key == "images":
            merged[key] = _merge_unique_images(
                merged.get(key) or [],
                value or [],
            )
        elif key == "comment_items":
            merged[key] = _merge_unique_comments(
                merged.get(key) or [],
                value or [],
            )
        elif key == "video":
            merged[key] = {
                **(merged.get(key) or {}),
                **value,
            }
        elif key == "collection_progress":
            continue
        else:
            merged[key] = value
    merged["collection_progress"] = progress
    return merged


def _merge_unique_strings(
    primary: list[Any],
    secondary: list[Any],
) -> list[str]:
    items: list[str] = []
    seen: set[str] = set()
    for value in [*primary, *secondary]:
        text = str(value or "").strip()
        if not text or text in seen:
            continue
        seen.add(text)
        items.append(text)
    return items


def _merge_unique_images(
    primary: list[dict[str, Any]],
    secondary: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    images: list[dict[str, Any]] = []
    seen: set[str] = set()
    for image in [*primary, *secondary]:
        if not isinstance(image, dict):
            continue
        src = str(image.get("src") or "")
        if not src:
            continue
        key = _xhs_image_resource_key(src)
        if key in seen:
            continue
        seen.add(key)
        images.append(image)
    for index, image in enumerate(images, start=1):
        image["index"] = index
    return images


def _merge_unique_comments(
    primary: list[dict[str, Any]],
    secondary: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    comments: list[dict[str, Any]] = []
    seen: set[str] = set()
    for comment in [*primary, *secondary]:
        if not isinstance(comment, dict):
            continue
        text = str(comment.get("text") or comment.get("raw_text") or "").strip()
        author = str(comment.get("author") or "").strip()
        parent_text = str(comment.get("parent_text") or "").strip()
        parent_author = str(comment.get("parent_author") or "").strip()
        if not text:
            continue
        key = f"{parent_author}\n{parent_text}\n{author}\n{text}"
        if key in seen:
            continue
        seen.add(key)
        comments.append(comment)
    return comments


def _click_visible_note_card(
    target: VisibleNoteTarget,
) -> dict[str, Any]:
    if target.get("screen_x") is None or target.get("screen_y") is None:
        return {
            "clicked": False,
            "error": "visible note target has no screen coordinate",
        }
    try:
        _click_xhs_screen_point(
            int(target["screen_x"]),
            int(target["screen_y"]),
            action="note_card",
        )
        return {"clicked": True}
    except Exception as exc:
        return {"clicked": False, "error": f"note click failed: {exc}"}


# Detail-page extraction and normalization


def _read_current_note_detail() -> dict[str, Any]:
    try:
        return json.loads(
            execute_current_chrome_js(
                r"""
                JSON.stringify((() => {
                  const clean = (value) =>
                    String(value || '').replace(/\s+/g, ' ').trim();
                  const visible = (el) => {
                    if (!el) return false;
                    const rect = el.getBoundingClientRect();
                    const style = window.getComputedStyle(el);
                    return rect.width > 0 && rect.height > 0 &&
                      rect.bottom > 0 && rect.top < window.innerHeight &&
                      style.visibility !== 'hidden' &&
                      style.display !== 'none' &&
                      Number(style.opacity || 1) > 0.05;
                  };
                  const pageText = clean(document.body?.innerText || '');
                  const unavailable = [
                    '当前笔记暂时无法浏览',
                    '请打开小红书App扫码查看',
                    '你访问的页面不见了',
                    '页面不见了',
                    '404'
                  ].find((text) => pageText.includes(text));
                  if (location.pathname.startsWith('/404') || unavailable) {
                    return {
                      status: 'error',
                      error: unavailable || 'xhs 404 page',
                      resolved_url: location.href,
                    };
                  }

                  const detailRoot = [
                    '#noteContainer',
                    '.note-detail-mask',
                    '.note-detail-container',
                    '.note-container',
                    '[class*="note-detail"]',
                    '[class*="detail-container"]',
                    '[role="dialog"]'
                  ]
                    .map((selector) =>
                      Array.from(document.querySelectorAll(selector)).find(visible)
                    )
                    .find(Boolean);
                  if (!detailRoot) {
                    return {
                      status: 'pending',
                      error: 'XHS detail container is not visible yet',
                      resolved_url: location.href,
                      page_title: document.title || null,
                    };
                  }
                  const root = detailRoot;
                  const rootRect = root.getBoundingClientRect();
                  const toolbarHeight = Math.max(
                    0,
                    window.outerHeight - window.innerHeight
                  );
                  const visibleScreenPoint = (rect) => {
                    if (!rect) return null;
                    const left = Math.max(rect.left + 3, 6);
                    const right = Math.min(
                      rect.right - 3,
                      window.innerWidth - 6
                    );
                    const top = Math.max(rect.top + 3, 6);
                    const bottom = Math.min(
                      rect.bottom - 3,
                      window.innerHeight - 12
                    );
                    if (right - left < 6 || bottom - top < 6) return null;
                    return {
                      x: Math.round(window.screenX + (left + right) / 2),
                      y: Math.round(
                        window.screenY + toolbarHeight + (top + bottom) / 2
                      ),
                    };
                  };
                  const noteMatch = location.href.match(
                    /\/explore\/([A-Za-z0-9]+)/
                  );

                  const title = clean(
                    root.querySelector('#detail-title')?.innerText ||
                    root.querySelector('.note-content .title')?.innerText ||
                    root.querySelector('.note-content [class*="title"]')?.innerText ||
                    document.title.replace(' - 小红书', '')
                  );
                  const body = clean(
                    root.querySelector('#detail-desc')?.innerText ||
                    root.querySelector('.note-content .desc')?.innerText ||
                    root.querySelector('.note-content [class*="desc"]')?.innerText ||
                    ''
                  );
                  const subtitle = clean(
                    root.querySelector('.subtitle')?.innerText ||
                    root.querySelector('[class*="subtitle"]')?.innerText ||
                    root.querySelector('[class*="sub-title"]')?.innerText ||
                    ''
                  );
                  const hashtags = Array.from(
                    root.querySelectorAll(
                      '#hash-tag, a.tag, [class*="tag"] a, a[href*="search_result"]'
                    )
                  )
                    .map((el) => clean(el.innerText))
                    .filter((text) => text.startsWith('#'));
                  const authorArea =
                    root.querySelector('.author-container') ||
                    root.querySelector('[class*="author-container"]') ||
                    root.querySelector('.author');
                  const authorLink = authorArea?.querySelector(
                    'a[href*="/user/profile/"]'
                  );
                  const author = clean(
                    authorArea?.querySelector('.username')?.innerText ||
                    authorArea?.querySelector('.name')?.innerText ||
                    authorArea?.querySelector('[class*="name"]')?.innerText ||
                    authorLink?.innerText ||
                    ''
                  );
                  const editLine = String(root.innerText || '')
                    .split(/\n+/)
                    .map((line) => clean(line))
                    .find((line) => line.startsWith('编辑于')) || '';
                  const editParts = editLine
                    .replace(/^编辑于\s*/, '')
                    .split(/\s+/)
                    .filter(Boolean);
                  const publishTime = clean(
                    editParts[0] ||
                    root.querySelector('.date')?.innerText ||
                    root.querySelector('[class*="publish-time"]')?.innerText ||
                    ''
                  );
                  const locationText = clean(
                    editParts.slice(1).join(' ') ||
                    root.querySelector('[class*="ip-location"]')?.innerText ||
                    ''
                  );

                  const images = [];
                  const seenImages = new Set();
                  const allImages = Array.from(root.querySelectorAll('img'));
                  for (const img of allImages) {
                    const rect = img.getBoundingClientRect();
                    const src = img.currentSrc || img.src || '';
                    const key = src.split('?', 1)[0];
                    if (!src || seenImages.has(key)) continue;
                    if (
                      src.includes('avatar') ||
                      src.includes('picasso-static') ||
                      src.includes('logo')
                    ) continue;
                    const width = Math.round(
                      img.naturalWidth || rect.width || 0
                    );
                    const height = Math.round(
                      img.naturalHeight || rect.height || 0
                    );
                    const isDisplayedMedia =
                      rect.width >= 180 &&
                      rect.height >= 180 &&
                      rect.right > rootRect.left &&
                      rect.left < rootRect.left + rootRect.width * 0.68 &&
                      rect.bottom > rootRect.top &&
                      rect.top < rootRect.bottom;
                    if (!isDisplayedMedia || width < 240 || height < 240) {
                      continue;
                    }
                    seenImages.add(key);
                    images.push({
                      src,
                      srcset: img.srcset || null,
                      alt: clean(img.alt),
                      title: clean(img.getAttribute('title')),
                      width,
                      height,
                      index: images.length + 1,
                    });
                  }

                  const videoEl = root.querySelector('video');
                  const video = videoEl
                    ? {
                        src:
                          videoEl.currentSrc ||
                          videoEl.querySelector('source')?.src ||
                          null,
                        poster: videoEl.poster || null,
                        duration: Number.isFinite(videoEl.duration)
                          ? Math.round(videoEl.duration * 1000) / 1000
                          : null,
                        width: videoEl.videoWidth || null,
                        height: videoEl.videoHeight || null,
                      }
                    : null;

                  const commentNodes = Array.from(
                    root.querySelectorAll(
                      '.comments-el .comment-item, [class*="comment-item"]'
                    )
                  );
                  const commentItems = [];
                  const seenComments = new Set();
                  for (const item of commentNodes) {
                    const rawText = clean(item.innerText);
                    const isReply =
                      item.classList.contains('comment-item-sub') ||
                      Boolean(item.closest('.reply-container'));
                    const parentContainer = item.closest('.parent-comment');
                    const parentItem = isReply
                      ? parentContainer?.querySelector(
                          '.comment-item:not(.comment-item-sub)'
                        )
                      : null;
                    const text = clean(
                      item.querySelector(
                        '.note-text, .comment-content, [class*="content"]'
                      )?.innerText || rawText
                    );
                    const commentAuthor = clean(
                      item.querySelector(
                        '.name, [class*="author"], [class*="username"]'
                      )?.innerText || ''
                    );
                    const parentText = clean(
                      parentItem?.querySelector(
                        '.note-text, .comment-content, [class*="content"]'
                      )?.innerText || ''
                    );
                    const parentAuthor = clean(
                      parentItem?.querySelector(
                        '.name, [class*="author"], [class*="username"]'
                      )?.innerText || ''
                    );
                    if (!text || text === '评论' || text === '回复') continue;
                    const key =
                      parentAuthor + '\n' + parentText + '\n' +
                      commentAuthor + '\n' + text;
                    if (seenComments.has(key)) continue;
                    seenComments.add(key);
                    const likeText = clean(
                      item.querySelector(
                        '.like .count, [class*="like"] [class*="count"]'
                      )?.innerText || ''
                    );
                    const threadText = clean(
                      parentContainer?.innerText || rawText
                    );
                    const replyMatch = threadText.match(
                      /展开\s*([0-9]+)\s*条?回复/
                    );
                    commentItems.push({
                      author: commentAuthor || null,
                      text,
                      is_reply: isReply,
                      parent_author: parentAuthor || null,
                      parent_text: parentText || null,
                      likes_text: likeText || null,
                      reply_count: replyMatch
                        ? parseInt(replyMatch[1], 10)
                        : null,
                      is_author_reply:
                        rawText.includes('作者') ||
                        Boolean(item.querySelector('[class*="author-tag"]')),
                      raw_text: rawText,
                    });
                  }

                  const scrollCandidates = Array.from(
                    root.querySelectorAll(
                      '.interaction-container, .comments-container, ' +
                      '[class*="comment"][class*="scroll"], ' +
                      '[class*="interaction"], [class*="scroll"]'
                    )
                  )
                    .filter((el) => {
                      const rect = el.getBoundingClientRect();
                      return visible(el) &&
                        el.scrollHeight > el.clientHeight + 16 &&
                        rect.left >= rootRect.left + rootRect.width * 0.35;
                    })
                    .map((el) => {
                      const rect = el.getBoundingClientRect();
                      return {
                        el,
                        rect,
                        score:
                          rect.width * rect.height +
                          (String(el.className).includes('interaction')
                            ? 1000000
                            : 0),
                      };
                    })
                    .sort((a, b) => b.score - a.score);
                  const scrollTarget =
                    scrollCandidates[0]?.el ||
                    (root.scrollHeight > root.clientHeight + 16
                      ? root
                      : null);
                  const scrollRect = scrollTarget?.getBoundingClientRect();
                  const scrollTop = Math.round(scrollTarget?.scrollTop || 0);
                  const clientHeight = Math.round(
                    scrollTarget?.clientHeight || rootRect.height || 0
                  );
                  const scrollHeight = Math.round(
                    scrollTarget?.scrollHeight || clientHeight
                  );
                  const atBottom =
                    !scrollTarget ||
                    scrollTop + clientHeight >= scrollHeight - 24;

                  const galleryImages = allImages
                    .filter(visible)
                    .map((img) => ({
                      img,
                      src: img.currentSrc || img.src || '',
                      rect: img.getBoundingClientRect(),
                    }))
                    .filter(
                      (item) =>
                        item.src &&
                        !item.src.includes('avatar') &&
                        item.rect.width >= 240 &&
                        item.rect.height >= 240 &&
                        item.rect.right > rootRect.left &&
                        item.rect.left <
                          rootRect.left + rootRect.width * 0.68
                    )
                    .sort(
                      (a, b) =>
                        b.rect.width * b.rect.height -
                        a.rect.width * a.rect.height
                    );
                  const activeSlideImage = Array.from(
                    root.querySelectorAll(
                      '.swiper-slide-active img, [class*="swiper-slide-active"] img'
                    )
                  ).find(visible);
                  const activeSlideRect = activeSlideImage?.getBoundingClientRect();
                  const activeImage =
                    activeSlideImage && activeSlideRect
                      ? {
                          img: activeSlideImage,
                          src:
                            activeSlideImage.currentSrc ||
                            activeSlideImage.src ||
                            '',
                          rect: activeSlideRect,
                        }
                      : galleryImages[0];
                  const contentImages = activeImage
                    ? [{
                        src: activeImage.src,
                        srcset: activeImage.img.srcset || null,
                        alt: clean(activeImage.img.alt),
                        title: clean(activeImage.img.getAttribute('title')),
                        width: Math.round(
                          activeImage.img.naturalWidth ||
                          activeImage.rect.width ||
                          0
                        ),
                        height: Math.round(
                          activeImage.img.naturalHeight ||
                          activeImage.rect.height ||
                          0
                        ),
                        index: 1,
                      }]
                    : images.slice(0, 1);
                  const paginationText = clean(
                    root.querySelector(
                      '.swiper-pagination, [class*="pagination"], ' +
                      '[class*="indicator"]'
                    )?.innerText || ''
                  );
                  const paginationMatch =
                    paginationText.match(/([0-9]+)\s*\/\s*([0-9]+)/) ||
                    clean(root.innerText)
                      .slice(0, 400)
                      .match(/([0-9]+)\s*\/\s*([0-9]+)/);
                  const controls = Array.from(
                    root.querySelectorAll(
                      'button, [role="button"], [class*="arrow"], ' +
                      '[class*="next"]'
                    )
                  )
                    .filter(visible)
                    .map((el) => {
                      const rect = el.getBoundingClientRect();
                      const label = clean(
                        [
                          el.getAttribute('aria-label'),
                          el.getAttribute('title'),
                          el.className,
                          el.innerText,
                        ].join(' ')
                      ).toLowerCase();
                      return {el, rect, label};
                    })
                    .filter(
                      (item) =>
                        item.rect.width <= 120 &&
                        item.rect.height <= 120 &&
                        !item.label.includes('swiper-slide') &&
                        item.rect.left <
                          rootRect.left + rootRect.width * 0.68 &&
                        (
                          item.label.includes('next') ||
                          item.label.includes('right') ||
                          item.label.includes('下一') ||
                          (
                            item.label.includes('arrow') &&
                            item.rect.left >
                              rootRect.left + rootRect.width * 0.35
                          )
                        )
                    )
                    .sort((a, b) => b.rect.left - a.rect.left);
                  const nextControl = controls[0];

                  const expandPattern =
                    /展开.*回复|查看更多回复|更多回复|展开全文/;
                  const expandControls = Array.from(
                    root.querySelectorAll(
                      'button, [role="button"], a, span, div'
                    )
                  )
                    .filter(visible)
                    .map((el) => {
                      const text = clean(el.innerText);
                      const rect = el.getBoundingClientRect();
                      return {
                        el,
                        text,
                        rect,
                        point: visibleScreenPoint(rect),
                      };
                    })
                    .filter(
                      (item) =>
                        item.text.length <= 48 &&
                        item.point &&
                        expandPattern.test(item.text) &&
                        !Array.from(item.el.children).some((child) =>
                          expandPattern.test(clean(child.innerText))
                        )
                    )
                    .map((item) => ({
                      key:
                        item.text +
                        ':' +
                        Math.round(item.rect.left) +
                        ':' +
                        Math.round(item.rect.top),
                      text: item.text,
                      kind: item.text.includes('回复')
                        ? 'comment_replies'
                        : 'body',
                      screen_x: item.point.x,
                      screen_y: item.point.y,
                    }));

                  const detailText = clean(root.innerText || '');
                  const loadingCore =
                    detailText.includes('加载中') &&
                    !body &&
                    !contentImages.length &&
                    !video;
                  const readable = Boolean(
                    title &&
                    author &&
                    !loadingCore &&
                    (body || contentImages.length || video)
                  );
                  if (!readable) {
                    return {
                      status: 'pending',
                      error: 'detail core content is not readable yet',
                      resolved_url: location.href,
                    };
                  }
                  return {
                    status: 'ready',
                    note_id: noteMatch?.[1] || null,
                    resolved_url: location.href,
                    title,
                    subtitle: subtitle || null,
                    body: body || null,
                    hashtags: Array.from(new Set(hashtags)),
                    account_name: author || null,
                    author_url: authorLink?.href || null,
                    publish_time: publishTime || null,
                    location: locationText || null,
                    like_text:
                      clean(root.querySelector('.like-wrapper')?.innerText) ||
                      null,
                    comment_text:
                      clean(root.querySelector('.chat-wrapper')?.innerText) ||
                      null,
                    save_text:
                      clean(root.querySelector('.collect-wrapper')?.innerText) ||
                      null,
                    share_text:
                      clean(root.querySelector('.share-wrapper')?.innerText) ||
                      null,
                    images: contentImages,
                    video,
                    comment_items: commentItems,
                    scroll_state: {
                      scroll_top: scrollTop,
                      client_height: clientHeight,
                      scroll_height: scrollHeight,
                      at_bottom: atBottom,
                      screen_x: scrollRect
                        ? Math.round(
                            window.screenX +
                            scrollRect.left +
                            scrollRect.width * 0.55
                          )
                        : Math.round(
                            window.screenX +
                            rootRect.left +
                            rootRect.width * 0.76
                          ),
                      screen_y: scrollRect
                        ? Math.round(
                            window.screenY +
                            toolbarHeight +
                            scrollRect.top +
                            scrollRect.height * 0.55
                          )
                        : Math.round(
                            window.screenY +
                            toolbarHeight +
                            rootRect.top +
                            rootRect.height * 0.58
                          ),
                    },
                    gallery_state: {
                      current: paginationMatch
                        ? parseInt(paginationMatch[1], 10)
                        : null,
                      total: paginationMatch
                        ? parseInt(paginationMatch[2], 10)
                        : null,
                      active_source: activeImage?.src || null,
                      next_point: nextControl
                        ? {
                            screen_x: Math.round(
                              window.screenX +
                              nextControl.rect.left +
                              nextControl.rect.width / 2
                            ),
                            screen_y: Math.round(
                              window.screenY +
                              toolbarHeight +
                              nextControl.rect.top +
                              nextControl.rect.height / 2
                            ),
                          }
                        : null,
                      swipe: activeImage
                        ? {
                            start_x: Math.round(
                              window.screenX +
                              activeImage.rect.left +
                              activeImage.rect.width * 0.78
                            ),
                            start_y: Math.round(
                              window.screenY +
                              toolbarHeight +
                              activeImage.rect.top +
                              activeImage.rect.height * 0.5
                            ),
                            end_x: Math.round(
                              window.screenX +
                              activeImage.rect.left +
                              activeImage.rect.width * 0.22
                            ),
                            end_y: Math.round(
                              window.screenY +
                              toolbarHeight +
                              activeImage.rect.top +
                              activeImage.rect.height * 0.5
                            ),
                          }
                        : null,
                    },
                    expand_controls: expandControls,
                  };
                })())
                """
            )
        )
    except Exception as exc:
        return {"status": "error", "error": str(exc)}


def _finalize_xhs_note(
    raw: dict[str, Any],
    *,
    target: VisibleNoteTarget,
    source_page: str,
    source_query: str | None,
    creator: dict[str, Any] | None,
) -> XhsNote:
    note_id = raw.get("note_id") or target.get("note_id")
    note_url = raw.get("resolved_url") or target.get("note_url")
    like_count = _parse_metric_count(raw.get("like_text"))
    comment_count = _parse_metric_count(raw.get("comment_text"))
    save_count = _parse_metric_count(raw.get("save_text"))
    share_count = _parse_metric_count(raw.get("share_text"))
    progress = raw.get("collection_progress") or {}

    note: XhsNote = {
        "note_id": str(note_id or ""),
        "note_url": str(note_url or ""),
        "account_name": str(
            (creator or {}).get("account_name")
            or raw.get("account_name")
            or target.get("account_name")
            or "unknown"
        ),
        "author_url": str(
            (creator or {}).get("account_url")
            or raw.get("author_url")
            or target.get("account_url")
            or ""
        ),
        "title": str(raw.get("title") or target.get("title") or ""),
        "subtitle": str(raw.get("subtitle") or ""),
        "body": str(raw.get("body") or ""),
        "hashtags": list(raw.get("hashtags") or []),
        "likes": _prefer_larger_count(like_count, target.get("likes")),
        "comments": _prefer_larger_count(
            comment_count,
            target.get("comments"),
        ),
        "saves": _prefer_larger_count(save_count, target.get("saves")),
        "shares": share_count,
        "publish_time": str(raw.get("publish_time") or ""),
        "location": str(raw.get("location") or ""),
        "images": list(raw.get("images") or []),
        "video": raw.get("video"),
        "comment_items": _normalize_comment_items(
            raw.get("comment_items") or []
        ),
        "collection_meta": {
            "source_page": source_page,
            "source_query": source_query,
            "detail_completion_reason": progress.get(
                "detail_completion_reason"
            ),
            "gallery_completion_reason": progress.get(
                "gallery_completion_reason"
            ),
            "viewport_advance_count": progress.get(
                "viewport_advance_count",
                0,
            ),
            "gallery_advance_count": progress.get(
                "gallery_advance_count",
                0,
            ),
            "expanded_control_count": progress.get(
                "expanded_control_count",
                0,
            ),
            "expanded_reply_control_count": progress.get(
                "expanded_reply_control_count",
                0,
            ),
            "expanded_body_control_count": progress.get(
                "expanded_body_control_count",
                0,
            ),
            "comment_completion_reason": progress.get(
                "comment_completion_reason"
            ),
            "gallery_total": progress.get("gallery_total"),
            "gallery_last_position": progress.get(
                "gallery_last_position"
            ),
            "image_resource_count": len(raw.get("images") or []),
            "comment_item_count": len(raw.get("comment_items") or []),
            "reported_comment_count": _prefer_larger_count(
                comment_count,
                target.get("comments"),
            ),
            "unavailable_fields": [],
            "collected_at": datetime.now(
                ZoneInfo("Asia/Shanghai")
            ).isoformat(),
        },
    }
    note["collection_meta"]["unavailable_fields"] = [
        field
        for field in ("likes", "comments", "saves", "shares")
        if note.get(field) is None
    ]
    return note


def _normalize_comment_items(
    comments: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    normalized = []
    for source_index, comment in enumerate(comments, start=1):
        item = dict(comment)
        item["likes"] = _parse_metric_count(item.pop("likes_text", None))
        item["source_index"] = source_index
        value_signals = []
        if item.get("is_author_reply"):
            value_signals.append("author_reply")
        if isinstance(item.get("likes"), int) and item["likes"] > 0:
            value_signals.append("liked_comment")
        if isinstance(item.get("reply_count"), int) and item["reply_count"] > 0:
            value_signals.append("active_reply_thread")
        item["value_signals"] = value_signals
        normalized.append(item)
    return normalized


def _prefer_larger_count(*values: Any) -> int | None:
    parsed = [
        value
        for value in values
        if isinstance(value, int) and not isinstance(value, bool)
    ]
    return max(parsed) if parsed else None


def _parse_metric_count(value: Any) -> int | None:
    text = str(value or "").strip()
    return _parse_count(text)


def _is_complete_xhs_note(
    note: XhsNote,
) -> tuple[bool, list[str]]:
    missing: list[str] = []
    for field in ("note_id", "note_url", "account_name", "title"):
        if not note.get(field):
            missing.append(field)
    if not (
        note.get("body")
        or note.get("images")
        or note.get("video")
    ):
        missing.append("content")
    meta = note.get("collection_meta") or {}
    if meta.get("detail_completion_reason") != "reached_detail_bottom":
        missing.append("detail_not_fully_browsed")
    if meta.get("comment_completion_reason") not in {
        "reached_comment_bottom",
        "no_comments",
        "comments_unavailable",
    }:
        missing.append("comments_not_fully_browsed")
    if meta.get("gallery_completion_reason") not in {
        "single_image",
        "reached_last_image",
        "gallery_cycle_complete",
        "all_image_resources_loaded",
        "no_gallery",
    }:
        missing.append("gallery_not_fully_browsed")
    return not missing, missing


def _close_current_note_detail() -> dict[str, Any]:
    try:
        close_point = _find_xhs_close_button_point()
        if close_point:
            _click_xhs_screen_point(
                close_point["screen_x"],
                close_point["screen_y"],
                action="detail_close",
            )
        else:
            press_current_chrome_key("Escape")
        time.sleep(0.8)

        state = _read_xhs_detail_presence()
        if state.get("detail_visible"):
            press_current_chrome_key("Escape")
            time.sleep(0.8)
            state = _read_xhs_detail_presence()
        if state.get("detail_url"):
            navigate_current_chrome_back(wait_seconds=1.2)
            state = _read_xhs_detail_presence()
        if state.get("detail_visible"):
            return {"closed": False, "error": "detail remained visible"}
        return {"closed": True}
    except Exception as exc:
        return {"closed": False, "error": str(exc)}


def _read_xhs_detail_presence() -> dict[str, Any]:
    try:
        return json.loads(
            execute_current_chrome_js(
                """
                JSON.stringify((() => {
                  const visible = (el) => {
                    if (!el) return false;
                    const rect = el.getBoundingClientRect();
                    const style = window.getComputedStyle(el);
                    return rect.width > 0 && rect.height > 0 &&
                      style.visibility !== 'hidden' &&
                      style.display !== 'none';
                  };
                  const root = [
                    '#noteContainer',
                    '.note-detail-mask',
                    '.note-detail-container',
                    '[class*="note-detail"]',
                    '[role="dialog"]'
                  ]
                    .map((selector) =>
                      Array.from(document.querySelectorAll(selector)).find(visible)
                    )
                    .find(Boolean);
                  return {
                    detail_visible: Boolean(root),
                    detail_url: location.pathname.includes('/explore/'),
                    url: location.href,
                  };
                })())
                """
            )
        )
    except Exception as exc:
        return {
            "detail_visible": True,
            "detail_url": False,
            "error": str(exc),
        }


def _find_xhs_close_button_point() -> dict[str, int] | None:
    point = json.loads(
        execute_current_chrome_js(
            """
            JSON.stringify((() => {
              const visible = (el) => {
                if (!el) return false;
                const rect = el.getBoundingClientRect();
                const style = window.getComputedStyle(el);
                return rect.width > 0 && rect.height > 0 &&
                  style.visibility !== 'hidden' &&
                  style.display !== 'none';
              };
              const button = [
                '.close-box',
                '.close-circle',
                '.note-detail-mask [class*="close"]',
                '[aria-label="关闭"]',
                '[aria-label="close"]'
              ]
                .map((selector) =>
                  Array.from(document.querySelectorAll(selector)).find(visible)
                )
                .find(Boolean);
              if (!button) return null;
              const rect = button.getBoundingClientRect();
              const toolbarHeight = Math.max(
                0,
                window.outerHeight - window.innerHeight
              );
              return {
                screen_x: Math.round(
                  window.screenX + rect.left + rect.width / 2
                ),
                screen_y: Math.round(
                  window.screenY +
                  toolbarHeight +
                  rect.top +
                  rect.height / 2
                ),
              };
            })())
            """
        )
    )
    if not point:
        return None
    return {
        "screen_x": int(point["screen_x"]),
        "screen_y": int(point["screen_y"]),
    }
