import json
import re
import time
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.parse import quote
from zoneinfo import ZoneInfo

from src.base.run_log import log_event
from src.collect.collect_infra import (
    ExtractionResult,
    build_extraction_result,
    click_screen_point,
    execute_current_chrome_js,
    open_current_chrome_url,
    press_current_chrome_key,
    scroll_current_chrome_wheel,
    semantic_extract_items_from_snapshot,
    snapshot_current_chrome,
)


XHS_BASE_URL = "https://www.xiaohongshu.com"
XHS_HIGH_LIKE_THRESHOLD = 500
XHS_HIGH_COMMENT_THRESHOLD = 100
XHS_HIGH_SAVE_THRESHOLD = 500
XHS_STRATEGY_MIN_FOLLOWERS = 5000
XHS_SEARCH_SCROLL_CLICKS = 55
XHS_SEARCH_SCROLL_PAUSE_SECONDS = 0.2
XHS_DETAIL_INITIAL_DWELL_SECONDS = 1.8
XHS_DETAIL_MAX_SCROLL_ROUNDS = 14
XHS_DETAIL_STABLE_ROUNDS_TO_STOP = 2
XHS_DETAIL_SCROLL_CLICKS = 11
XHS_DETAIL_SCROLL_PAUSE_SECONDS = 1.0
XHS_DETAIL_IMAGE_MAX_STEPS = 18
XHS_DETAIL_IMAGE_STABLE_STEPS_TO_STOP = 2
XHS_DETAIL_IMAGE_STEP_PAUSE_SECONDS = 0.75

DEFAULT_STRATEGY_RESEARCH_KEYWORDS = (
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


def collect_xhs_deep_search_current_chrome(
    keyword: str,
    *,
    limit: int = 10,
    detail_limit: int | None = None,
    output_dir: Path | str = "data/research/inputs",
    note_pause_seconds: float = 1.5,
) -> Path:
    """Browse XHS search like a human, opening high-interaction notes for writing research."""
    keyword = keyword.strip()
    if not keyword:
        raise ValueError("keyword cannot be empty")

    output_base = Path(output_dir)
    output_base.mkdir(parents=True, exist_ok=True)

    target_success_count = min(limit, detail_limit if detail_limit is not None else limit)
    search_queries = _build_xhs_writing_search_queries(keyword)
    cards: list[dict[str, Any]] = []
    detail_count = 0
    detail_errors: list[dict[str, Any]] = []
    searched_queries: list[dict[str, Any]] = []
    extraction_warnings: list[str] = []
    last_page = None
    extraction_confidence = 0.85

    for query in search_queries:
        if len(cards) >= target_success_count:
            break
        remaining = target_success_count - len(cards)
        browsing_result = _collect_xhs_high_quality_notes_linear_current_chrome(
            query,
            target_count=remaining,
            known_note_ids={_note_id_from_url(card.get("note_url")) for card in cards},
            note_pause_seconds=note_pause_seconds,
        )
        cards.extend(browsing_result["cards"])
        detail_count += browsing_result["detail_requested_count"]
        detail_errors.extend(browsing_result["detail_errors"])
        extraction_warnings.extend(browsing_result["warnings"])
        last_page = browsing_result["page"]
        extraction_confidence = min(extraction_confidence, browsing_result["confidence"])
        searched_queries.append(
            {
                "query": query,
                "scanned_card_count": browsing_result["scanned_card_count"],
                "qualified_card_count": browsing_result["qualified_card_count"],
                "detail_requested_count": browsing_result["detail_requested_count"],
                "detail_success_count": len(browsing_result["cards"]),
                "scroll_count": browsing_result["scroll_count"],
                "page_url": last_page.url if last_page else None,
            }
        )

    detail_success_count = len(cards)
    field_coverage = _field_coverage(cards)
    log_event(
        "collect_attempt",
        level=(
            "info" if detail_success_count >= limit and not extraction_warnings else "warning"
        ),
        platform="xhs",
        collector="current_chrome_linear_deep",
        query=keyword,
        searched_queries=[item["query"] for item in searched_queries],
        requested_limit=limit,
        collected_count=detail_success_count,
        search_card_count=sum(item["scanned_card_count"] for item in searched_queries),
        detail_requested_count=detail_count,
        detail_success_count=detail_success_count,
        detail_error_count=len(detail_errors),
        enough_samples=detail_success_count >= limit,
        extraction_method="linear_visible_card_click",
        extraction_confidence=extraction_confidence,
        field_coverage=field_coverage,
        warnings=extraction_warnings,
        page_url=last_page.url if last_page else None,
    )

    research_input = {
        "platform": "xiaohongshu",
        "research_goal": f"深入分析与「{keyword}」相关的小红书笔记结构、正文、标签和互动表达",
        "source": "xhs_current_chrome_deep",
        "accounts": [],
        "loose_notes": [
            {
                "account_name": card.get("detail_author")
                or card.get("account_name")
                or "unknown",
                "title": card.get("title") or card.get("detail_title") or "",
                "subtitle": card.get("subtitle") or card.get("detail_subtitle"),
                "note_url": card.get("note_url") or card.get("resolved_url"),
                "cover_text": card.get("cover_text"),
                "body_excerpt": card.get("body_excerpt"),
                "hashtags": card.get("hashtags") or [],
                "likes": _parse_count(card.get("likes"))
                if isinstance(card.get("likes"), str)
                else card.get("likes"),
                "comments": card.get("comments"),
                "saves": card.get("saves"),
                "shares": card.get("shares"),
                "publish_time": card.get("publish_time"),
                "author_url": card.get("author_url"),
                "images": card.get("images") or [],
                "detail_browse_rounds": card.get("detail_browse_rounds"),
                "detail_completion_reason": card.get("detail_completion_reason"),
                "detail_image_browse_steps": card.get("detail_image_browse_steps"),
                "detail_image_completion_reason": card.get("detail_image_completion_reason"),
                "visible_comments": card.get("visible_comments") or [],
                "observed_signals": [
                    *card.get("observed_signals", []),
                    "detail_collected" if card.get("detail_collected") else "",
                    f"detail_error: {card.get('detail_error')}" if card.get("detail_error") else "",
                ],
            }
            for card in cards
            if card.get("detail_collected") and (card.get("title") or card.get("detail_title"))
        ],
        "collector_meta": {
            "keyword": keyword,
            "searched_queries": searched_queries,
            "page_title": last_page.title if last_page else None,
            "page_url": last_page.url if last_page else None,
            "page_text_sample": last_page.visible_text[:1200] if last_page else None,
            "collected_at": datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(),
            "requested_limit": limit,
            "collected_count": detail_success_count,
            "search_card_count": sum(item["scanned_card_count"] for item in searched_queries),
            "detail_requested_count": detail_count,
            "detail_success_count": detail_success_count,
            "detail_error_count": len(detail_errors),
            "detail_errors": detail_errors[:10],
            "quality_threshold": {
                "min_likes": XHS_HIGH_LIKE_THRESHOLD,
                "min_comments": XHS_HIGH_COMMENT_THRESHOLD,
                "min_saves": XHS_HIGH_SAVE_THRESHOLD,
            },
            "extraction_method": "linear_visible_card_click",
            "extraction_confidence": extraction_confidence,
            "field_coverage": field_coverage,
            "extraction_warnings": extraction_warnings,
        },
    }

    now = datetime.now(ZoneInfo("Asia/Shanghai"))
    safe_keyword = re.sub(r"[^0-9A-Za-z\u4e00-\u9fff]+", "-", keyword).strip("-")[:40]
    path = output_base / f"{now.strftime('%Y-%m-%d-%H%M%S')}-xhs-deep-{safe_keyword}.json"
    path.write_text(json.dumps(research_input, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


def collect_xhs_strategy_corpus_current_chrome(
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
    """Collect creator-level Xiaohongshu strategy samples from current Chrome."""
    cleaned_keywords = [item.strip() for item in (keywords or DEFAULT_STRATEGY_RESEARCH_KEYWORDS) if item.strip()]
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
    path = output_base / f"{safe_started_at}-xhs-strategy-corpus.json"

    creator_candidates: dict[str, dict] = {}
    searched_keywords: list[dict] = []

    for keyword in cleaned_keywords:
        if progress:
            print(f"Searching keyword: {keyword}", flush=True)

        candidates = _collect_ranked_search_creator_candidates(
            keyword,
            limit=creators_per_keyword,
        )
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
    rejected_creators: list[dict[str, Any]] = []
    selected_creators = _select_balanced_creators(
        list(creator_candidates.values()),
        keywords=cleaned_keywords,
        limit=len(creator_candidates),
    )
    for index, creator in enumerate(selected_creators, start=1):
        if len(accounts) >= target_creators:
            break
        account_url = creator.get("account_url")
        if not account_url:
            continue
        if progress:
            print(
                f"Collecting account candidate {index}/{len(selected_creators)} "
                f"(qualified {len(accounts)}/{target_creators}): "
                f"{creator.get('account_name') or account_url}",
                flush=True,
            )
        account_sample = _collect_account_sample_with_ranked_notes(
            fallback_name=creator.get("account_name") or f"creator-{index}",
            fallback_url=account_url,
            notes_per_creator=notes_per_creator,
        )
        account_sample["seed_keyword"] = creator.get("seed_keyword")
        account_sample["discovered_from_note"] = creator.get("discovered_from_note")
        if not account_sample.get("target_creator_qualified"):
            rejected_creators.append(
                {
                    "account_name": account_sample.get("account_name"),
                    "account_url": account_sample.get("account_url") or account_url,
                    "follower_count": account_sample.get("follower_count"),
                    "reason": account_sample.get("target_creator_reject_reason"),
                    "seed_keyword": creator.get("seed_keyword"),
                }
            )
            if progress:
                print(
                    "  Skipped: "
                    f"followers={account_sample.get('follower_count')} "
                    f"need>{XHS_STRATEGY_MIN_FOLLOWERS}",
                    flush=True,
                )
            continue
        if collect_note_details:
            note_candidates = account_sample.get("notes", [])
            detailed_notes = []
            detail_errors = []
            for note_index, note in enumerate(note_candidates, start=1):
                if progress:
                    print(
                        f"  Detail {note_index}/{len(note_candidates)}: "
                        f"{note.get('title', '')[:32]}",
                        flush=True,
                    )
                detail = _extract_note_detail_by_click(note)
                note.update(detail)
                if detail.get("detail_collected") and _is_high_quality_xhs_card(note):
                    detailed_notes.append(note)
                else:
                    detail_errors.append(
                        {
                            "index": note_index,
                            "note_url": note.get("note_url"),
                            "error": detail.get("detail_error")
                            or "detail did not meet strategy note quality threshold",
                        }
                    )
                if note_pause_seconds > 0:
                    time.sleep(note_pause_seconds)
            account_sample["notes"] = detailed_notes
            account_sample["detail_requested_count"] = len(note_candidates)
            account_sample["detail_success_count"] = len(detailed_notes)
            account_sample["detail_errors"] = detail_errors[:10]
        accounts.append(account_sample)
        _save_strategy_corpus(
            path,
            keywords=cleaned_keywords,
            searched_keywords=searched_keywords,
            accounts=accounts,
            target_creators=target_creators,
            notes_per_creator=notes_per_creator,
            started_at=now,
            completed=False,
            rejected_creators=rejected_creators,
        )
        if account_pause_seconds > 0:
            time.sleep(account_pause_seconds)

    _save_strategy_corpus(
        path,
        keywords=cleaned_keywords,
        searched_keywords=searched_keywords,
        accounts=accounts,
        target_creators=target_creators,
        notes_per_creator=notes_per_creator,
        started_at=now,
        completed=True,
        rejected_creators=rejected_creators,
    )
    return path


def _extract_xhs_search_cards_current_chrome(*, limit: int) -> ExtractionResult:
    """Extract search cards from current Chrome, with semantic fallback."""
    selector_cards = _extract_xhs_search_cards_by_selector(limit=limit)
    snapshot = snapshot_current_chrome()
    warnings = []
    if len(selector_cards) < limit:
        warnings.append(
            f"selector_collected_less_than_requested: {len(selector_cards)}/{limit}"
        )
    selector_result = build_extraction_result(
        selector_cards,
        method="selector",
        confidence=0.9 if len(selector_cards) >= limit else 0.65,
        page=snapshot,
        warnings=warnings,
    )
    if len(selector_cards) >= limit:
        return selector_result

    try:
        semantic_result = semantic_extract_items_from_snapshot(
            snapshot,
            item_description=(
                "Xiaohongshu search result note cards visible on the page. "
                "Extract real note/post results only, not navigation, tabs, login prompts, "
                "footer links, or generic platform controls."
            ),
            required_fields=["title"],
            optional_fields=[
                "note_url",
                "cover_text",
                "body_excerpt",
                "account_name",
                "likes",
            ],
            max_items=limit,
            label="Xiaohongshu semantic search card extractor",
        )
    except (RuntimeError, ValueError) as exc:
        selector_result.warnings.append(f"semantic_fallback_failed: {exc}")
        return selector_result

    semantic_cards = [_normalize_semantic_search_card(item) for item in semantic_result.items]
    merged_cards = _merge_note_cards(selector_cards, semantic_cards, limit=limit)
    return build_extraction_result(
        merged_cards,
        method="mixed" if selector_cards else "semantic",
        confidence=max(selector_result.confidence, semantic_result.confidence * 0.9),
        page=snapshot,
        warnings=[*selector_result.warnings, *semantic_result.warnings],
    )


def _collect_ranked_xhs_search_candidates_current_chrome(
    keyword: str,
    *,
    target_success_count: int,
    candidate_pool_size: int,
    max_scroll_attempts: int = 12,
) -> tuple[list[dict[str, Any]], ExtractionResult]:
    """Discover enough search candidates, prioritizing high-interaction notes."""
    search_url = f"{XHS_BASE_URL}/search_result?keyword={quote(keyword)}"
    open_current_chrome_url(search_url, wait_seconds=8)

    candidates: list[dict[str, Any]] = []
    extraction = _extract_xhs_search_cards_current_chrome(limit=candidate_pool_size)
    warnings: list[str] = []
    for attempt in range(max_scroll_attempts + 1):
        extraction = _extract_xhs_search_cards_current_chrome(limit=candidate_pool_size)
        candidates = _merge_note_cards(candidates, extraction.items, limit=candidate_pool_size * 2)
        ranked = _rank_xhs_note_cards(candidates)
        high_interaction_count = sum(1 for card in ranked if _interaction_score(card) > 0)
        if len(ranked) >= candidate_pool_size and high_interaction_count >= target_success_count:
            candidates = ranked
            break
        if attempt >= 3 and len(ranked) >= target_success_count * 3 and high_interaction_count >= target_success_count:
            candidates = ranked
            break
        if attempt < max_scroll_attempts:
            scroll_current_chrome_wheel(clicks=7, direction="down", pause_seconds=1.2)
    else:
        warnings.append(
            f"candidate_pool_incomplete: {len(candidates)}/{candidate_pool_size}"
        )

    ranked_candidates = _rank_xhs_note_cards(candidates)[:candidate_pool_size]
    return ranked_candidates, build_extraction_result(
        ranked_candidates,
        method=extraction.method,
        confidence=extraction.confidence,
        page=extraction.page,
        warnings=[*extraction.warnings, *warnings],
    )


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


def _collect_xhs_high_quality_notes_linear_current_chrome(
    query: str,
    *,
    target_count: int,
    known_note_ids: set[str | None],
    note_pause_seconds: float,
    max_scroll_attempts: int = 24,
) -> dict[str, Any]:
    """Move down the search feed and open only high-quality visible notes."""
    search_url = f"{XHS_BASE_URL}/search_result?keyword={quote(query)}"
    open_current_chrome_url(search_url, wait_seconds=5)

    known_note_ids = {note_id for note_id in known_note_ids if note_id}
    scanned_note_ids: set[str] = set()
    cards: list[dict[str, Any]] = []
    detail_errors: list[dict[str, Any]] = []
    warnings: list[str] = []
    qualified_card_count = 0
    detail_requested_count = 0
    scroll_count = 0
    last_page = snapshot_current_chrome()

    for attempt in range(max_scroll_attempts + 1):
        visible_cards = _extract_visible_xhs_search_cards(limit=30)
        opened_detail = False

        for card in visible_cards:
            note_id = _note_id_from_url(card.get("note_url"))
            if not note_id or note_id in known_note_ids or note_id in scanned_note_ids:
                continue
            scanned_note_ids.add(note_id)
            if not _is_high_quality_xhs_card(card):
                continue

            qualified_card_count += 1
            detail = _extract_note_detail_by_click(card)
            detail_requested_count += 1
            card.update(detail)
            opened_detail = True

            if detail.get("detail_collected"):
                known_note_ids.add(note_id)
                cards.append(card)
                if len(cards) >= target_count:
                    break
            else:
                detail_errors.append(
                    {
                        "query": query,
                        "note_url": card.get("note_url"),
                        "title": card.get("title"),
                        "likes": card.get("likes"),
                        "comments": card.get("comments"),
                        "saves": card.get("saves"),
                        "error": detail.get("detail_error"),
                    }
                )

            if note_pause_seconds > 0:
                time.sleep(note_pause_seconds)
            break

        last_page = snapshot_current_chrome()
        if len(cards) >= target_count:
            break
        if attempt < max_scroll_attempts:
            scroll_current_chrome_wheel(
                clicks=XHS_SEARCH_SCROLL_CLICKS if not opened_detail else max(14, XHS_SEARCH_SCROLL_CLICKS - 4),
                direction="down",
                pause_seconds=XHS_SEARCH_SCROLL_PAUSE_SECONDS,
            )
            scroll_count += 1

    if len(cards) < target_count:
        warnings.append(
            f"high_quality_notes_incomplete: {len(cards)}/{target_count} for query '{query}'"
        )

    return {
        "cards": cards,
        "page": last_page,
        "confidence": 0.85 if cards else 0.6,
        "warnings": warnings,
        "scanned_card_count": len(scanned_note_ids),
        "qualified_card_count": qualified_card_count,
        "detail_requested_count": detail_requested_count,
        "detail_errors": detail_errors,
        "scroll_count": scroll_count,
    }


def _extract_visible_xhs_search_cards(*, limit: int) -> list[dict[str, Any]]:
    return json.loads(
        execute_current_chrome_js(
            f"""
            JSON.stringify((() => {{
              const clean = (value) => String(value || '').replace(/\\s+/g, ' ').trim();
              const parseCountText = (value) => {{
                const cleaned = clean(value).replace('+', '');
                if (/^\\d+(\\.\\d+)?万$/.test(cleaned)) return Math.round(parseFloat(cleaned) * 10000);
                if (/^\\d+$/.test(cleaned)) return parseInt(cleaned, 10);
                return null;
              }};
              const countFromText = (text, label) => {{
                const compact = clean(text);
                const labeled = compact.match(new RegExp(label + '\\\\s*([0-9]+(?:\\\\.[0-9]+)?万?\\\\+?)'));
                if (labeled) return parseCountText(labeled[1]);
                return null;
              }};
              const visible = (el) => {{
                if (!el) return false;
                const rect = el.getBoundingClientRect();
                const style = window.getComputedStyle(el);
                return rect.width > 80 && rect.height > 100 &&
                  rect.bottom > 120 && rect.top < window.innerHeight - 40 &&
                  style.visibility !== 'hidden' && style.display !== 'none';
              }};
              const anchors = Array.from(document.querySelectorAll('a[href*="/explore/"]'));
              const seen = new Set();
              const cards = [];
              for (const anchor of anchors) {{
                const href = anchor.href;
                const match = href.match(/\\/explore\\/([A-Za-z0-9]+)/);
                if (!match || seen.has(match[1])) continue;
                const container = anchor.closest('[class*="note-item"], [class*="feed"], section, article') ||
                  anchor.closest('div') ||
                  anchor;
                if (!visible(container)) continue;
                seen.add(match[1]);

                const rect = container.getBoundingClientRect();
                const text = clean(container.innerText || anchor.innerText || '');
                const lines = text.split('\\n').map((line) => clean(line)).filter(Boolean);
                const img = container.querySelector('img');
                const title = clean(
                  container.querySelector('.title')?.innerText ||
                  anchor.getAttribute('title') ||
                  img?.alt ||
                  lines.find((line) => line.length >= 4 && !/^\\d+(\\.\\d+)?万?\\+?$/.test(line)) ||
                  ''
                );
                const likeText = clean(
                  container.querySelector('.like-wrapper .count')?.innerText ||
                  container.querySelector('[class*="like"] [class*="count"]')?.innerText ||
                  container.querySelector('.count')?.innerText ||
                  ''
                );
                const fallbackCount = lines.slice().reverse().find((line) => /^\\d+(\\.\\d+)?万?\\+?$/.test(line)) || '';
                const likes = parseCountText(likeText) ?? parseCountText(fallbackCount);
                const comments = countFromText(text, '评论') ?? countFromText(text, '回复');
                const saveText = clean(
                  container.querySelector('.collect-wrapper .count')?.innerText ||
                  container.querySelector('[class*="collect"] [class*="count"]')?.innerText ||
                  container.querySelector('[class*="save"] [class*="count"]')?.innerText ||
                  ''
                );
                const saves = parseCountText(saveText) ??
                  countFromText(text, '收藏') ??
                  countFromText(text, '收藏数');
                const userAnchor = container.querySelector('a[href*="/user/profile/"]');
                const account = clean(
                  container.querySelector('.name')?.innerText ||
                  userAnchor?.innerText ||
                  ''
                );
                if (!title) continue;

                const toolbarHeight = Math.max(0, window.outerHeight - window.innerHeight);
                const clickX = Math.round(window.screenX + rect.left + Math.min(Math.max(rect.width / 2, 16), Math.max(rect.width - 16, 16)));
                const clickY = Math.round(window.screenY + toolbarHeight + rect.top + Math.min(Math.max(rect.height / 2, 16), Math.max(rect.height - 16, 16)));
                cards.push({{
                  title,
                  note_url: href,
                  cover_text: img?.alt || title,
                  body_excerpt: lines.slice(0, 8).join(' / '),
                  account_name: account || 'unknown',
                  likes,
                  comments,
                  saves,
                  screen_x: clickX,
                  screen_y: clickY,
                  viewport_top: Math.round(rect.top),
                  observed_signals: [
                    `visible_search_card_title: ${{title}}`,
                    likes !== null ? `visible_likes: ${{likes}}` : '',
                    comments !== null ? `visible_comments: ${{comments}}` : '',
                    saves !== null ? `visible_saves: ${{saves}}` : '',
                    img?.alt ? `cover_alt: ${{img.alt}}` : '',
                  ].filter(Boolean),
                }});
                if (cards.length >= {limit}) break;
              }}
              return cards.sort((a, b) => a.viewport_top - b.viewport_top);
            }})())
            """
        )
    )


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


def _xhs_quality_score(card: dict[str, Any]) -> int:
    likes = card.get("likes")
    comments = card.get("comments")
    saves = card.get("saves")
    parsed_likes = _parse_count(likes) if isinstance(likes, str) else likes
    parsed_comments = _parse_count(comments) if isinstance(comments, str) else comments
    parsed_saves = _parse_count(saves) if isinstance(saves, str) else saves
    return max(
        parsed_likes if isinstance(parsed_likes, int) else 0,
        (parsed_comments if isinstance(parsed_comments, int) else 0) * 5,
        parsed_saves if isinstance(parsed_saves, int) else 0,
    )


def _extract_xhs_search_cards_by_selector(*, limit: int) -> list[dict[str, Any]]:
    return json.loads(
        execute_current_chrome_js(
            f"""
            JSON.stringify((() => {{
              const anchors = Array.from(document.querySelectorAll('a[href*="/explore/"]'));
              const seen = new Set();
              const cards = [];
              for (const anchor of anchors) {{
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
                cards.push({{
                  title,
                  note_url: href,
                  cover_text: img?.alt || title,
                  body_excerpt: lines.slice(0, 6).join(' / '),
                  account_name: account,
                  likes,
                  observed_signals: [
                    `search_card_title: ${{title}}`,
                    img?.alt ? `cover_alt: ${{img.alt}}` : '',
                  ].filter(Boolean),
                }});
                if (cards.length >= {limit}) break;
              }}
              return cards;
            }})())
            """
        )
    )


def _normalize_semantic_search_card(item: dict[str, Any]) -> dict[str, Any]:
    title = str(item.get("title") or "").strip()
    return {
        "title": title,
        "note_url": _clean_optional_text(item.get("note_url")),
        "cover_text": _clean_optional_text(item.get("cover_text")) or title,
        "body_excerpt": _clean_optional_text(item.get("body_excerpt")),
        "account_name": _clean_optional_text(item.get("account_name")) or "unknown",
        "likes": _clean_optional_text(item.get("likes")),
        "observed_signals": [
            "semantic_search_card",
            f"semantic_title: {title}" if title else "",
        ],
    }


def _merge_note_cards(
    primary_cards: list[dict[str, Any]],
    fallback_cards: list[dict[str, Any]],
    *,
    limit: int,
) -> list[dict[str, Any]]:
    merged = []
    seen = set()
    for card in [*primary_cards, *fallback_cards]:
        title = str(card.get("title") or "").strip()
        if not title:
            continue
        key = card.get("note_url") or title
        if key in seen:
            continue
        seen.add(key)
        merged.append(card)
        if len(merged) >= limit:
            break
    return merged


def _field_coverage(items: list[dict[str, Any]]) -> dict[str, int]:
    fields = [
        "account_name",
        "body_excerpt",
        "comments",
        "cover_text",
        "hashtags",
        "images",
        "likes",
        "note_url",
        "observed_signals",
        "author_url",
        "saves",
        "shares",
        "subtitle",
        "title",
        "visible_comments",
    ]
    return {
        field: sum(1 for item in items if item.get(field) not in (None, "", []))
        for field in fields
    }


def _rank_xhs_note_cards(cards: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return sorted(
        cards,
        key=lambda card: (
            _interaction_score(card),
            len(str(card.get("body_excerpt") or "")),
            len(str(card.get("title") or "")),
        ),
        reverse=True,
    )


def _interaction_score(card: dict[str, Any]) -> int:
    likes = card.get("likes")
    parsed_likes = _parse_count(likes) if isinstance(likes, str) else likes
    return parsed_likes if isinstance(parsed_likes, int) else 0


def _clean_optional_text(value: Any) -> str | None:
    if value is None:
        return None
    cleaned = str(value).strip()
    return cleaned or None


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


def _execute_chrome_js(script: str) -> str:
    return execute_current_chrome_js(script)


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
        "source": "xhs_current_chrome",
        "requirements": {
            "target_creators": target_creators,
            "notes_per_creator": notes_per_creator,
            "target_notes": target_creators * notes_per_creator,
            "target_creator_min_followers": XHS_STRATEGY_MIN_FOLLOWERS,
            "note_quality_threshold": {
                "min_likes": XHS_HIGH_LIKE_THRESHOLD,
                "min_comments": XHS_HIGH_COMMENT_THRESHOLD,
                "min_saves": XHS_HIGH_SAVE_THRESHOLD,
            },
        },
        "coverage": {
            "creator_count": len(accounts),
            "rejected_creator_count": len(rejected_creators),
            "note_count": note_count,
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
            "collection_note": (
                "Only visible page data from the user's logged-in Chrome was collected. "
                "The script does not bypass login, CAPTCHA, or platform protections."
            ),
        },
    }
    path.write_text(json.dumps(corpus, ensure_ascii=False, indent=2), encoding="utf-8")


def _collect_ranked_search_creator_candidates(
    keyword: str,
    *,
    limit: int,
    max_scroll_attempts: int = 10,
) -> list[dict[str, Any]]:
    search_url = f"{XHS_BASE_URL}/search_result?keyword={quote(keyword)}"
    open_current_chrome_url(search_url, wait_seconds=7)
    candidates: list[dict[str, Any]] = []
    target_pool_size = max(limit * 3, 12)
    for attempt in range(max_scroll_attempts + 1):
        candidates = _merge_creator_candidates(
            candidates,
            _extract_search_creator_candidates(limit=target_pool_size),
            limit=target_pool_size,
        )
        high_interaction_count = sum(1 for item in candidates if _is_high_quality_xhs_card(item))
        if len(candidates) >= target_pool_size and high_interaction_count >= limit:
            break
        if attempt >= 3 and len(candidates) >= limit and high_interaction_count >= max(1, limit // 2):
            break
        if attempt < max_scroll_attempts:
            scroll_current_chrome_wheel(
                clicks=XHS_SEARCH_SCROLL_CLICKS,
                direction="down",
                pause_seconds=XHS_SEARCH_SCROLL_PAUSE_SECONDS,
            )
    return sorted(
        candidates,
        key=_xhs_quality_score,
        reverse=True,
    )[:limit]


def _collect_account_sample_with_ranked_notes(
    *,
    fallback_name: str,
    fallback_url: str,
    notes_per_creator: int,
    max_scroll_attempts: int = 12,
) -> dict:
    open_current_chrome_url(fallback_url, wait_seconds=7)
    candidate_limit = max(notes_per_creator * 3, 20)
    account_sample = _extract_account_sample(
        fallback_name=fallback_name,
        fallback_url=fallback_url,
        notes_per_creator=candidate_limit,
    )
    _mark_strategy_creator_target_status(account_sample)
    if not account_sample.get("target_creator_qualified"):
        account_sample["notes"] = []
        return account_sample
    for attempt in range(max_scroll_attempts + 1):
        account_sample = _extract_account_sample(
            fallback_name=fallback_name,
            fallback_url=fallback_url,
            notes_per_creator=candidate_limit,
        )
        _mark_strategy_creator_target_status(account_sample)
        notes = account_sample.get("notes", [])
        high_interaction_count = sum(1 for note in notes if _is_high_quality_xhs_card(note))
        if len(notes) >= candidate_limit and high_interaction_count >= notes_per_creator:
            break
        if attempt >= 3 and len(notes) >= notes_per_creator and high_interaction_count >= max(1, notes_per_creator // 2):
            break
        if attempt < max_scroll_attempts:
            scroll_current_chrome_wheel(
                clicks=XHS_SEARCH_SCROLL_CLICKS,
                direction="down",
                pause_seconds=XHS_SEARCH_SCROLL_PAUSE_SECONDS,
            )

    high_quality_notes = [
        note for note in account_sample.get("notes", []) if _is_high_quality_xhs_card(note)
    ]
    account_sample["notes"] = sorted(
        high_quality_notes,
        key=_xhs_quality_score,
        reverse=True,
    )[:notes_per_creator]
    return account_sample


def _merge_creator_candidates(
    primary: list[dict[str, Any]],
    fallback: list[dict[str, Any]],
    *,
    limit: int,
) -> list[dict[str, Any]]:
    merged = []
    seen = set()
    for item in [*primary, *fallback]:
        key = item.get("account_url") or item.get("account_name")
        if not key or key in seen:
            continue
        seen.add(key)
        merged.append(item)
        if len(merged) >= limit:
            break
    return sorted(
        merged,
        key=_xhs_quality_score,
        reverse=True,
    )


def _mark_strategy_creator_target_status(account_sample: dict[str, Any]) -> None:
    follower_count = account_sample.get("follower_count")
    qualified = isinstance(follower_count, int) and follower_count > XHS_STRATEGY_MIN_FOLLOWERS
    account_sample["target_creator_min_followers"] = XHS_STRATEGY_MIN_FOLLOWERS
    account_sample["target_creator_qualified"] = qualified
    if not qualified:
        account_sample["target_creator_reject_reason"] = (
            f"follower_count_not_above_{XHS_STRATEGY_MIN_FOLLOWERS}: {follower_count}"
        )
    else:
        account_sample.pop("target_creator_reject_reason", None)


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
    for keyword in keywords:
        grouped[keyword] = sorted(
            grouped[keyword],
            key=_xhs_quality_score,
            reverse=True,
        )
    overflow = sorted(
        overflow,
        key=_xhs_quality_score,
        reverse=True,
    )

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
              const clean = (value) => String(value || '').replace(/\\s+/g, ' ').trim();
              const parseCountText = (value) => {{
                const cleaned = clean(value).replace('+', '');
                if (/^\\d+(\\.\\d+)?万$/.test(cleaned)) return Math.round(parseFloat(cleaned) * 10000);
                if (/^\\d+$/.test(cleaned)) return parseInt(cleaned, 10);
                return null;
              }};
              const countFromText = (text, label) => {{
                const compact = clean(text);
                const labeled = compact.match(new RegExp(label + '\\\\s*([0-9]+(?:\\\\.[0-9]+)?万?\\\\+?)'));
                if (labeled) return parseCountText(labeled[1]);
                return null;
              }};
              const anchors = Array.from(document.querySelectorAll('a[href*="/explore/"]'));
              const seen = new Set();
              const creators = [];
              for (const anchor of anchors) {{
                const container = anchor.closest('section, article, div') || anchor;
                const text = clean(container.innerText || anchor.innerText || '');
                const lines = text.split('\\n').map((line) => clean(line)).filter(Boolean);
                const title = lines.find((line) => line.length >= 4 && !/^\\d+(\\.\\d+)?万?$/.test(line)) || anchor.getAttribute('title') || '';
                const likes = lines.find((line) => /^\\d+(\\.\\d+)?万?\\+?$/.test(line)) || null;
                const comments = countFromText(text, '评论') ?? countFromText(text, '回复');
                const saves = countFromText(text, '收藏') ?? countFromText(text, '收藏数');
                const userAnchor = container.querySelector('a[href*="/user/profile/"]') ||
                  anchor.parentElement?.querySelector('a[href*="/user/profile/"]');
                const accountUrl = userAnchor ? userAnchor.href : null;
                const accountName = userAnchor ? (userAnchor.innerText || userAnchor.getAttribute('title') || '').trim() : '';
                if (!accountUrl || seen.has(accountUrl)) continue;
                seen.add(accountUrl);
                creators.push({{
                  account_name: accountName || 'unknown',
                  account_url: accountUrl,
                  likes: likes,
                  comments,
                  saves,
                  discovered_from_note: {{
                    title,
                    note_url: anchor.href,
                    likes,
                    comments,
                    saves,
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
              const parseCountText = (value) => {{
                if (!value) return null;
                const cleaned = String(value).trim().replace('+', '').replace(/,/g, '');
                if (/^\\d+(\\.\\d+)?万$/.test(cleaned)) return Math.round(parseFloat(cleaned) * 10000);
                if (/^\\d+$/.test(cleaned)) return parseInt(cleaned, 10);
                return null;
              }};
              const clean = (value) => String(value || '').replace(/\\s+/g, ' ').trim();
              const countNearLabel = (text, labels) => {{
                const compact = clean(text);
                for (const label of labels) {{
                  const before = compact.match(new RegExp('([0-9]+(?:\\\\.[0-9]+)?万?\\\\+?)\\\\s*' + label));
                  if (before) return parseCountText(before[1]);
                  const after = compact.match(new RegExp(label + '\\\\s*([0-9]+(?:\\\\.[0-9]+)?万?\\\\+?)'));
                  if (after) return parseCountText(after[1]);
                }}
                return null;
              }};
              const userBox = document.querySelector('.user-info') || document.querySelector('.user') || document.body;
              const descText = userBox.querySelector('.user-desc')?.innerText?.trim() || null;
              const tagText = userBox.querySelector('.user-tags')?.innerText?.trim() || null;
              const countTexts = Array.from(userBox.querySelectorAll('.data-info .count, .user-interactions .count')).map((el) => el.innerText.trim());
              const profileText = clean(userBox.innerText || document.body.innerText || '');
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
                const text = clean(container.innerText || anchor.innerText || '');
                const lines = text.split('\\n').map((line) => clean(line)).filter(Boolean);
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
                const comments = countNearLabel(text, ['评论', '回复']);
                const saves = countNearLabel(text, ['收藏', '收藏数']);
                if (!title) continue;
                notes.push({{
                  account_name: author,
                  title,
                  note_url: detailUrl,
                  cover_text: img?.alt || title,
                  body_excerpt: lines.slice(0, 8).join(' / '),
                  hashtags: [],
                  likes_text: likes,
                  comments,
                  saves,
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
                follower_count: countNearLabel(profileText, ['粉丝']) ?? parseCountText(countTexts[1]),
                following_count: countNearLabel(profileText, ['关注']) ?? parseCountText(countTexts[0]),
                liked_count: countNearLabel(profileText, ['获赞与收藏', '获赞', '赞和收藏']) ?? parseCountText(countTexts[2]),
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


def _extract_note_detail_by_click(card: dict[str, Any]) -> dict:
    """Open a note through the visible page card, read the modal, then close it."""
    note_url = card.get("note_url")
    if not note_url:
        return {
            "detail_collected": False,
            "detail_error": "missing note_url",
        }

    clicked = _click_visible_note_card(card)
    if not clicked.get("clicked"):
        return {
            "detail_collected": False,
            "detail_error": clicked.get("error") or "could not click note card",
        }

    detail: dict[str, Any] = {
        "detail_collected": False,
        "detail_error": "detail modal did not become readable",
    }
    try:
        for _ in range(10):
            time.sleep(0.8)
            detail = _read_current_note_detail()
            if not detail.get("detail_pending"):
                break
        if detail.get("detail_collected"):
            detail = _browse_and_collect_current_note_detail(detail)
    finally:
        _close_current_note_detail()

    detail.pop("detail_pending", None)
    if detail.get("detail_collected"):
        return _normalize_detail_payload(detail)
    return detail


def _browse_and_collect_current_note_detail(initial_detail: dict[str, Any]) -> dict[str, Any]:
    """Spend time in the opened note and merge information loaded while scrolling."""
    detail = dict(initial_detail)
    detail["detail_browse_rounds"] = 0
    detail["detail_completion_reason"] = "not_started"
    time.sleep(XHS_DETAIL_INITIAL_DWELL_SECONDS)
    _focus_xhs_detail_reading_area()
    detail = _browse_and_collect_xhs_detail_images(detail)

    stable_rounds = 0
    previous_signature = _detail_payload_signature(detail)
    previous_scroll_state = _read_xhs_detail_scroll_state()

    for _ in range(XHS_DETAIL_MAX_SCROLL_ROUNDS):
        scroll_current_chrome_wheel(
            clicks=XHS_DETAIL_SCROLL_CLICKS,
            direction="down",
            pause_seconds=XHS_DETAIL_SCROLL_PAUSE_SECONDS,
        )
        next_detail = _read_current_note_detail()
        detail = _merge_note_detail_payloads(detail, next_detail)
        detail["detail_browse_rounds"] = int(detail.get("detail_browse_rounds") or 0) + 1
        if not next_detail.get("detail_collected") and not next_detail.get("detail_pending"):
            detail["detail_completion_reason"] = "detail_became_unreadable"
            break
        current_signature = _detail_payload_signature(detail)
        current_scroll_state = _read_xhs_detail_scroll_state()
        if current_signature == previous_signature:
            stable_rounds += 1
        else:
            stable_rounds = 0
        if (
            current_scroll_state.get("at_bottom")
            and stable_rounds >= 1
        ):
            detail["detail_completion_reason"] = "reached_detail_bottom"
            break
        if (
            current_scroll_state.get("scroll_top") == previous_scroll_state.get("scroll_top")
            and stable_rounds >= XHS_DETAIL_STABLE_ROUNDS_TO_STOP
        ):
            detail["detail_completion_reason"] = "stable_no_new_detail"
            break
        previous_signature = current_signature
        previous_scroll_state = current_scroll_state
    else:
        detail["detail_completion_reason"] = "max_safety_rounds"

    return detail


def _detail_payload_signature(detail: dict[str, Any]) -> tuple[Any, ...]:
    return (
        len(str(detail.get("detail_title") or "")),
        len(str(detail.get("detail_subtitle") or "")),
        len(str(detail.get("detail_body") or "")),
        len(detail.get("detail_hashtags") or []),
        len(detail.get("detail_images") or []),
        len(detail.get("visible_comments") or []),
        detail.get("detail_like_text"),
        detail.get("detail_comment_text"),
        detail.get("detail_collect_text"),
        detail.get("detail_share_text"),
    )


def _browse_and_collect_xhs_detail_images(detail: dict[str, Any]) -> dict[str, Any]:
    merged = dict(detail)
    merged["detail_image_browse_steps"] = 0
    stable_steps = 0
    previous_image_count = len(merged.get("detail_images") or [])

    for _ in range(XHS_DETAIL_IMAGE_MAX_STEPS):
        next_point = _find_xhs_gallery_nav_point(direction="next")
        if not next_point:
            merged["detail_image_completion_reason"] = (
                "no_gallery_next_control" if previous_image_count <= 1 else "gallery_next_unavailable"
            )
            break
        try:
            click_screen_point(next_point["screen_x"], next_point["screen_y"], wait_seconds=0.1)
        except Exception as exc:
            merged["detail_image_completion_reason"] = f"gallery_next_click_failed: {exc}"
            break
        time.sleep(XHS_DETAIL_IMAGE_STEP_PAUSE_SECONDS)
        next_detail = _read_current_note_detail()
        merged = _merge_note_detail_payloads(merged, next_detail)
        merged["detail_image_browse_steps"] = int(merged.get("detail_image_browse_steps") or 0) + 1
        current_image_count = len(merged.get("detail_images") or [])
        if current_image_count <= previous_image_count:
            stable_steps += 1
        else:
            stable_steps = 0
        previous_image_count = current_image_count
        if stable_steps >= XHS_DETAIL_IMAGE_STABLE_STEPS_TO_STOP:
            merged["detail_image_completion_reason"] = "stable_no_new_images"
            break
    else:
        merged["detail_image_completion_reason"] = "max_image_safety_steps"

    return merged


def _find_xhs_gallery_nav_point(direction: str) -> dict[str, int] | None:
    if direction not in {"next", "prev"}:
        raise ValueError(f"Unsupported gallery direction: {direction}")
    point = json.loads(
        _execute_chrome_js(
            f"""
            JSON.stringify((() => {{
              const direction = {json.dumps(direction)};
              const visible = (el) => {{
                if (!el) return false;
                const rect = el.getBoundingClientRect();
                const style = window.getComputedStyle(el);
                return rect.width > 0 && rect.height > 0 &&
                  rect.bottom > 0 && rect.top < window.innerHeight &&
                  style.visibility !== 'hidden' && style.display !== 'none' &&
                  Number(style.opacity || 1) > 0.05;
              }};
              const clean = (value) => String(value || '').replace(/\\s+/g, ' ').trim().toLowerCase();
              const root = [
                '#noteContainer',
                '.note-detail-mask',
                '.note-detail-container',
                '.note-container',
                '[class*="note-detail"]',
                '[role="dialog"]'
              ].map((selector) => Array.from(document.querySelectorAll(selector)).find(visible)).find(Boolean) ||
                document.body;
              const rootRect = root.getBoundingClientRect();
              const toolbarHeight = Math.max(0, window.outerHeight - window.innerHeight);

              const controls = Array.from(root.querySelectorAll('button, [role="button"], [class*="arrow"], [class*="next"], [class*="prev"], [class*="swiper"]'))
                .filter(visible)
                .map((el) => {{
                  const rect = el.getBoundingClientRect();
                  const label = [
                    clean(el.getAttribute('aria-label')),
                    clean(el.getAttribute('title')),
                    clean(el.className),
                    clean(el.innerText),
                  ].join(' ');
                  return {{el, rect, label}};
                }})
                .filter((item) => {{
                  const inGallerySide = item.rect.left < rootRect.left + rootRect.width * 0.68;
                  if (!inGallerySide) return false;
                  if (direction === 'next') {{
                    return item.label.includes('next') ||
                      item.label.includes('right') ||
                      item.label.includes('arrow') ||
                      item.label.includes('下一') ||
                      item.rect.left > rootRect.left + rootRect.width * 0.35;
                  }}
                  return item.label.includes('prev') ||
                    item.label.includes('left') ||
                    item.label.includes('arrow') ||
                    item.label.includes('上一') ||
                    item.rect.left < rootRect.left + rootRect.width * 0.35;
                }})
                .sort((a, b) => {{
                  if (direction === 'next') return b.rect.left - a.rect.left;
                  return a.rect.left - b.rect.left;
                }});
              const control = controls[0];
              if (control) {{
                return {{
                  screen_x: Math.round(window.screenX + control.rect.left + control.rect.width / 2),
                  screen_y: Math.round(window.screenY + toolbarHeight + control.rect.top + control.rect.height / 2),
                }};
              }}

              const images = Array.from(root.querySelectorAll('img'))
                .filter(visible)
                .map((img) => {{
                  const rect = img.getBoundingClientRect();
                  const src = img.currentSrc || img.src || '';
                  const area = rect.width * rect.height;
                  return {{rect, src, area}};
                }})
                .filter((item) => item.src && !item.src.includes('avatar') && !item.src.includes('picasso-static'))
                .filter((item) => item.rect.left < rootRect.left + rootRect.width * 0.68)
                .sort((a, b) => b.area - a.area);
              const image = images[0];
              if (!image) return null;
              const xRatio = direction === 'next' ? 0.88 : 0.12;
              return {{
                screen_x: Math.round(window.screenX + image.rect.left + image.rect.width * xRatio),
                screen_y: Math.round(window.screenY + toolbarHeight + image.rect.top + image.rect.height * 0.5),
              }};
            }})())
            """
        )
    )
    if not point:
        return None
    return {
        "screen_x": int(point["screen_x"]),
        "screen_y": int(point["screen_y"]),
    }


def _read_xhs_detail_scroll_state() -> dict[str, Any]:
    try:
        return json.loads(
            _execute_chrome_js(
                """
                JSON.stringify((() => {
                  const visible = (el) => {
                    if (!el) return false;
                    const rect = el.getBoundingClientRect();
                    const style = window.getComputedStyle(el);
                    return rect.width > 0 && rect.height > 0 &&
                      style.visibility !== 'hidden' && style.display !== 'none';
                  };
                  const candidates = Array.from(document.querySelectorAll('*'))
                    .filter(visible)
                    .filter((el) => el.scrollHeight > el.clientHeight + 24)
                    .map((el) => ({
                      el,
                      score: (el.clientHeight || 0) * (el.clientWidth || 0),
                    }))
                    .sort((a, b) => b.score - a.score);
                  const target = candidates[0]?.el || document.scrollingElement || document.documentElement;
                  const scrollTop = Math.round(target.scrollTop || 0);
                  const clientHeight = Math.round(target.clientHeight || window.innerHeight || 0);
                  const scrollHeight = Math.round(target.scrollHeight || document.body.scrollHeight || 0);
                  return {
                    scroll_top: scrollTop,
                    client_height: clientHeight,
                    scroll_height: scrollHeight,
                    at_bottom: scrollTop + clientHeight >= scrollHeight - 24,
                  };
                })())
                """
            )
        )
    except Exception:
        return {
            "scroll_top": None,
            "client_height": None,
            "scroll_height": None,
            "at_bottom": False,
        }


def _focus_xhs_detail_reading_area() -> None:
    try:
        point = json.loads(
            _execute_chrome_js(
                """
                JSON.stringify((() => {
                  const visible = (el) => {
                    if (!el) return false;
                    const rect = el.getBoundingClientRect();
                    const style = window.getComputedStyle(el);
                    return rect.width > 0 && rect.height > 0 &&
                      style.visibility !== 'hidden' && style.display !== 'none';
                  };
                  const root = [
                    '#noteContainer',
                    '.note-detail-mask',
                    '.note-detail-container',
                    '.note-container',
                    '.note-content',
                    '[class*="note-detail"]',
                    '[class*="detail-container"]',
                    '[role="dialog"]'
                  ].map((selector) => Array.from(document.querySelectorAll(selector)).find(visible)).find(Boolean) ||
                    document.body;
                  const rect = root.getBoundingClientRect();
                  const toolbarHeight = Math.max(0, window.outerHeight - window.innerHeight);
                  return {
                    screen_x: Math.round(window.screenX + rect.left + rect.width * 0.72),
                    screen_y: Math.round(window.screenY + toolbarHeight + rect.top + rect.height * 0.56),
                  };
                })())
                """
            )
        )
        if point:
            click_screen_point(int(point["screen_x"]), int(point["screen_y"]), wait_seconds=0.1)
    except Exception:
        pass


def _merge_note_detail_payloads(
    primary: dict[str, Any],
    secondary: dict[str, Any],
) -> dict[str, Any]:
    if not secondary:
        return primary
    merged = dict(primary)
    for key, value in secondary.items():
        if value in (None, "", []):
            continue
        if key == "detail_body":
            if len(str(value)) > len(str(merged.get(key) or "")):
                merged[key] = value
        elif key in ("detail_hashtags", "visible_comments"):
            merged[key] = _merge_unique_strings(merged.get(key) or [], value or [])
        elif key == "detail_images":
            merged[key] = _merge_unique_images(merged.get(key) or [], value or [])
        else:
            merged[key] = value
    return merged


def _merge_unique_strings(primary: list[Any], secondary: list[Any]) -> list[str]:
    items: list[str] = []
    seen = set()
    for value in [*primary, *secondary]:
        text = str(value or "").strip()
        if not text or text in seen:
            continue
        seen.add(text)
        items.append(text)
    return items


def _merge_unique_images(primary: list[dict[str, Any]], secondary: list[dict[str, Any]]) -> list[dict[str, Any]]:
    images: list[dict[str, Any]] = []
    seen = set()
    for image in [*primary, *secondary]:
        src = image.get("src") if isinstance(image, dict) else None
        if not src or src in seen:
            continue
        seen.add(src)
        images.append(image)
    return images[:40]


def _click_visible_note_card(card: dict[str, Any]) -> dict[str, Any]:
    if card.get("screen_x") is not None and card.get("screen_y") is not None:
        try:
            click_screen_point(int(card["screen_x"]), int(card["screen_y"]))
            return {
                "clicked": True,
                "click_method": "visible_card_screen_point",
                "screen_x": int(card["screen_x"]),
                "screen_y": int(card["screen_y"]),
            }
        except Exception as exc:
            return {
                "clicked": False,
                "click_method": "visible_card_screen_point",
                "screen_x": card.get("screen_x"),
                "screen_y": card.get("screen_y"),
                "error": f"system click failed: {exc}",
            }

    note_url = str(card.get("note_url") or "")
    note_id = _note_id_from_url(note_url)
    title = str(card.get("title") or card.get("cover_text") or "")
    target = json.loads(
        _execute_chrome_js(
            f"""
            JSON.stringify((() => {{
              const noteId = {json.dumps(note_id)};
              const noteUrl = {json.dumps(note_url)};
              const title = {json.dumps(title)};
              const clean = (value) => String(value || '').replace(/\\s+/g, ' ').trim();
              const anchors = Array.from(document.querySelectorAll('a[href*="/explore/"]'));
              const anchor = anchors.find((item) => noteId && item.href.includes(noteId)) ||
                anchors.find((item) => noteUrl && item.href === noteUrl) ||
                anchors.find((item) => title && clean(item.innerText).includes(title.slice(0, 18))) ||
                anchors.find((item) => {{
                  const container = item.closest('section, article, div') || item;
                  return title && clean(container.innerText).includes(title.slice(0, 18));
                }});
              if (!anchor) {{
                return {{clicked: false, error: 'visible note card anchor not found'}};
              }}
              const target = anchor.closest('section, article, div') || anchor;
              target.scrollIntoView({{block: 'center', inline: 'center'}});
              const rect = target.getBoundingClientRect();
              const toolbarHeight = Math.max(0, window.outerHeight - window.innerHeight);
              const screenX = Math.round(window.screenX + rect.left + Math.min(Math.max(rect.width / 2, 12), Math.max(rect.width - 12, 12)));
              const screenY = Math.round(window.screenY + toolbarHeight + rect.top + Math.min(Math.max(rect.height / 2, 12), Math.max(rect.height - 12, 12)));
              return {{
                clicked: false,
                click_ready: true,
                note_id: noteId,
                href: anchor.href,
                title: title || clean(target.innerText).slice(0, 80),
                screen_x: screenX,
                screen_y: screenY,
              }};
            }})())
            """
        )
    )
    if not target.get("click_ready"):
        return target
    try:
        click_screen_point(int(target["screen_x"]), int(target["screen_y"]))
        target["clicked"] = True
        return target
    except Exception as exc:
        return {
            **target,
            "clicked": False,
            "error": f"system click failed: {exc}",
        }


def _read_current_note_detail() -> dict[str, Any]:
    try:
        return json.loads(
            _execute_chrome_js(
                """
                JSON.stringify((() => {
                  const clean = (value) => String(value || '').replace(/\\s+/g, ' ').trim();
                  const visible = (el) => {
                    if (!el) return false;
                    const rect = el.getBoundingClientRect();
                    const style = window.getComputedStyle(el);
                    return rect.width > 0 && rect.height > 0 &&
                      style.visibility !== 'hidden' && style.display !== 'none';
                  };
                  const pageText = clean(document.body ? document.body.innerText : '');
                  const unavailableText = [
                    '当前笔记暂时无法浏览',
                    '请打开小红书App扫码查看',
                    '你访问的页面不见了',
                    '页面不见了',
                    '404'
                  ].find((text) => pageText.includes(text));
                  if (location.pathname.startsWith('/404') || unavailableText) {
                    return {
                      detail_pending: false,
                      detail_collected: false,
                      resolved_url: location.href,
                      detail_error: unavailableText || 'xhs 404 page',
                    };
                  }

                  const isDetailUrl = location.pathname.includes('/explore/');
                  const detailRoot = [
                    '#noteContainer',
                    '.note-detail-mask',
                    '.note-detail-container',
                    '.note-container',
                    '.note-content',
                    '[class*="note-detail"]',
                    '[class*="detail-container"]',
                    '[role="dialog"]'
                  ].map((selector) => Array.from(document.querySelectorAll(selector)).find(visible)).find(Boolean);
                  if (!detailRoot && !isDetailUrl) {
                    return {
                      detail_pending: true,
                      detail_collected: false,
                      resolved_url: location.href,
                      detail_error: 'detail modal not visible yet',
                    };
                  }
                  const root = detailRoot || document.body;
                  const title = clean(
                    root.querySelector('#detail-title')?.innerText ||
                    root.querySelector('.note-content .title')?.innerText ||
                    root.querySelector('[class*="title"]')?.innerText ||
                    document.title.replace(' - 小红书', '')
                  );
                  const body = clean(
                    root.querySelector('#detail-desc')?.innerText ||
                    root.querySelector('.note-content .desc')?.innerText ||
                    root.querySelector('[class*="desc"]')?.innerText ||
                    ''
                  );
                  const subtitle = clean(
                    root.querySelector('.subtitle')?.innerText ||
                    root.querySelector('[class*="subtitle"]')?.innerText ||
                    root.querySelector('[class*="sub-title"]')?.innerText ||
                    ''
                  );
                  const hashtags = Array.from(root.querySelectorAll('#hash-tag, a.tag, [class*="tag"]'))
                    .map((el) => clean(el.innerText))
                    .filter((text) => text.startsWith('#'))
                    .slice(0, 20);
                  const author = clean(
                    root.querySelector('.author .username')?.innerText ||
                    root.querySelector('.author .name')?.innerText ||
                    root.querySelector('[class*="author"] [class*="name"]')?.innerText ||
                    ''
                  );
                  const likeText = clean(root.querySelector('.like-wrapper')?.innerText) || null;
                  const commentText = clean(root.querySelector('.chat-wrapper')?.innerText) || null;
                  const collectText = clean(root.querySelector('.collect-wrapper')?.innerText) || null;
                  const shareText = clean(root.querySelector('.share-wrapper')?.innerText) || null;
                  const authorLink = root.querySelector('a[href*="/user/profile/"]')?.href || null;
                  const publishTime = clean(
                    root.querySelector('.date')?.innerText ||
                    root.querySelector('[class*="date"]')?.innerText ||
                    root.querySelector('[class*="time"]')?.innerText ||
                    ''
                  ) || null;
                  const commentItems = Array.from(root.querySelectorAll('.comments-el .comment-item, .comments-el [class*="comment"]'))
                    .map((el) => clean(el.innerText))
                    .filter((text) => text.length >= 2 && !['评论', '回复'].includes(text));
                  const seenComments = new Set();
                  const uniqueComments = [];
                  for (const text of commentItems) {
                    if (seenComments.has(text)) continue;
                    seenComments.add(text);
                    uniqueComments.push(text);
                    if (uniqueComments.length >= 30) break;
                  }
                  const images = [];
                  const seenImages = new Set();
                  for (const img of Array.from(root.querySelectorAll('img'))) {
                    const rect = img.getBoundingClientRect();
                    const src = img.currentSrc || img.src || '';
                    if (!src || seenImages.has(src)) continue;
                    if (src.includes('avatar') || src.includes('picasso-static')) continue;
                    if ((img.naturalWidth || rect.width) < 240 || (img.naturalHeight || rect.height) < 240) continue;
                    seenImages.add(src);
                    images.push({
                      src,
                      alt: clean(img.alt),
                      title: clean(img.getAttribute('title')),
                      width: Math.round(img.naturalWidth || rect.width || 0),
                      height: Math.round(img.naturalHeight || rect.height || 0),
                    });
                    if (images.length >= 24) break;
                  }
                  const hasReadableDetail = Boolean(
                    body ||
                    hashtags.length ||
                    uniqueComments.length ||
                    images.length ||
                    likeText ||
                    commentText ||
                    collectText
                  );
                  if (!hasReadableDetail) {
                    return {
                      detail_pending: true,
                      detail_collected: false,
                      resolved_url: location.href,
                      detail_error: 'detail content not visible yet',
                    };
                  }
                  return {
                    detail_pending: false,
                    detail_collected: true,
                    resolved_url: location.href,
                    detail_title: title,
                    detail_subtitle: subtitle,
                    detail_body: body,
                    detail_hashtags: hashtags,
                    detail_author: author,
                    detail_author_url: authorLink,
                    detail_like_text: likeText,
                    detail_comment_text: commentText,
                    detail_collect_text: collectText,
                    detail_share_text: shareText,
                    detail_publish_time: publishTime,
                    detail_images: images,
                    visible_comments: uniqueComments,
                  };
                })())
                """
            )
        )
    except Exception as exc:
        return {
            "detail_pending": False,
            "detail_collected": False,
            "detail_error": str(exc),
        }


def _close_current_note_detail() -> None:
    try:
        close_point = _find_xhs_close_button_point()
        if close_point:
            click_screen_point(close_point["screen_x"], close_point["screen_y"])
        else:
            press_current_chrome_key("Escape")
        time.sleep(0.8)
        _execute_chrome_js(
            """
            (() => {
              if (location.pathname.includes('/explore/')) {
                history.back();
                return 'back';
              }
              return 'stay';
            })()
            """
        )
        time.sleep(0.8)
    except Exception:
        pass


def _find_xhs_close_button_point() -> dict[str, int] | None:
    point = json.loads(
        _execute_chrome_js(
            """
            JSON.stringify((() => {
              const visible = (el) => {
                if (!el) return false;
                const rect = el.getBoundingClientRect();
                const style = window.getComputedStyle(el);
                return rect.width > 0 && rect.height > 0 &&
                  style.visibility !== 'hidden' && style.display !== 'none';
              };
              const closeButton = [
                '.close-box',
                '.close-circle',
                '.note-detail-mask [class*="close"]',
                '[aria-label="关闭"]',
                '[class*="close"]'
              ].map((selector) => Array.from(document.querySelectorAll(selector)).find(visible)).find(Boolean);
              if (!closeButton) return null;
              const rect = closeButton.getBoundingClientRect();
              const toolbarHeight = Math.max(0, window.outerHeight - window.innerHeight);
              return {
                screen_x: Math.round(window.screenX + rect.left + rect.width / 2),
                screen_y: Math.round(window.screenY + toolbarHeight + rect.top + rect.height / 2),
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


def _normalize_detail_payload(detail: dict[str, Any]) -> dict[str, Any]:
    detail["hashtags"] = detail.get("detail_hashtags") or []
    if detail.get("detail_title"):
        detail["title"] = detail["detail_title"]
    if detail.get("detail_subtitle"):
        detail["subtitle"] = detail["detail_subtitle"]
    if detail.get("detail_body"):
        detail["body_excerpt"] = detail["detail_body"]
    if detail.get("detail_author_url"):
        detail["author_url"] = detail["detail_author_url"]
    if detail.get("detail_publish_time"):
        detail["publish_time"] = detail["detail_publish_time"]
    if detail.get("detail_images"):
        detail["images"] = detail["detail_images"]
    parsed_likes = _parse_count(detail.get("detail_like_text"))
    parsed_comments = _parse_count(detail.get("detail_comment_text"))
    parsed_collects = _parse_count(detail.get("detail_collect_text"))
    parsed_shares = _parse_count(detail.get("detail_share_text"))
    if parsed_likes is not None:
        detail["likes"] = parsed_likes
    if parsed_comments is not None:
        detail["comments"] = parsed_comments
    if parsed_collects is not None:
        detail["saves"] = parsed_collects
    if parsed_shares is not None:
        detail["shares"] = parsed_shares
    return detail


def _note_id_from_url(url: str | None) -> str | None:
    if not url:
        return None
    match = re.search(r"/explore/([A-Za-z0-9]+)", url)
    return match.group(1) if match else None
