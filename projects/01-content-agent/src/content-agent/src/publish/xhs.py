from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

from src.base.run_log import log_event, log_exception
from src.publish.assets import ensure_publish_assets
from src.publish.publish_infra import (
    PublishPayload,
    PublishResult,
    click_text,
    current_page_url,
    fill_body,
    fill_title,
    open_publish_page,
    upload_file_via_dialog,
    wait_for_any_text,
)


XHS_PUBLISH_URL = "https://creator.xiaohongshu.com/publish/publish?source=official"


def publish_draft_to_xhs(
    draft_path: Path | str,
    *,
    dry_run: bool = False,
    allow_unapproved: bool = False,
) -> PublishResult:
    """Publish an approved draft to Xiaohongshu through the current Chrome session."""
    draft_path = Path(draft_path)
    draft = _load_draft(draft_path)
    if not allow_unapproved and draft.get("status") != "approved":
        raise ValueError(
            f"Draft is not approved: {draft_path}. "
            "Pass --allow-unapproved if you intentionally want to publish it."
        )

    payload = _build_payload(draft, draft_path)
    log_event(
        "publish_attempt",
        platform="xhs",
        draft_path=draft_path,
        title_chars=len(payload.title),
        body_chars=len(payload.body),
        asset_count=len(payload.asset_paths),
        dry_run=dry_run,
    )

    try:
        _publish_payload(payload, dry_run=dry_run)
    except Exception as exc:
        log_exception("exception", exc, phase="publish_xhs", draft_path=draft_path)
        result = PublishResult(
            platform="xhs",
            status="failed",
            draft_path=str(draft_path),
            asset_paths=[str(path) for path in payload.asset_paths],
            page_url=current_page_url(),
            error_message=str(exc),
        )
        save_publish_result(result)
        log_event(
            "publish_result",
            level="error",
            platform="xhs",
            status=result.status,
            draft_path=draft_path,
            page_url=result.page_url,
            error_message=result.error_message,
        )
        raise

    result = PublishResult(
        platform="xhs",
        status="dry_run" if dry_run else "published",
        draft_path=str(draft_path),
        asset_paths=[str(path) for path in payload.asset_paths],
        page_url=current_page_url(),
    )
    save_publish_result(result)
    log_event(
        "publish_result",
        platform="xhs",
        status=result.status,
        draft_path=draft_path,
        page_url=result.page_url,
        asset_count=len(result.asset_paths),
    )
    return result


def save_publish_result(
    result: PublishResult,
    *,
    output_dir: Path | str = "data/publish_results",
) -> Path:
    target_dir = Path(output_dir)
    target_dir.mkdir(parents=True, exist_ok=True)
    now = datetime.now(ZoneInfo("Asia/Shanghai"))
    path = target_dir / f"{now.strftime('%Y-%m-%d-%H%M%S')}-{result.platform}-{result.status}.json"
    path.write_text(json.dumps(result.model_dump(), ensure_ascii=False, indent=2), encoding="utf-8")
    return path


def _publish_payload(payload: PublishPayload, *, dry_run: bool) -> None:
    open_publish_page(XHS_PUBLISH_URL, wait_seconds=8)
    log_event("publish_step", platform="xhs", step="open_publish_page", page_url=current_page_url())

    click_text(["发布图文", "上传图文", "图文", "上传笔记"], timeout_seconds=4)
    for path in payload.asset_paths:
        upload_file_via_dialog(path)
        log_event("publish_step", platform="xhs", step="upload_asset", asset_path=path)

    if not fill_title(payload.title):
        raise RuntimeError("Could not fill Xiaohongshu title field.")
    log_event("publish_step", platform="xhs", step="fill_title", title_chars=len(payload.title))

    if not fill_body(payload.body):
        raise RuntimeError("Could not fill Xiaohongshu body field.")
    log_event("publish_step", platform="xhs", step="fill_body", body_chars=len(payload.body))

    if dry_run:
        return

    if not click_text(["立即发布", "发布"], timeout_seconds=8, exact=True):
        raise RuntimeError("Could not find Xiaohongshu publish button.")
    log_event("publish_step", platform="xhs", step="click_publish")

    success_signal = wait_for_any_text(
        ["发布成功", "已发布", "审核中", "发布笔记成功"],
        timeout_seconds=35,
    )
    if not success_signal:
        raise RuntimeError("Clicked publish, but did not observe a success signal.")
    log_event("publish_step", platform="xhs", step="observe_success", success_signal=success_signal)


def _load_draft(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise FileNotFoundError(f"Missing draft file: {path}")
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"Draft file must contain one JSON object: {path}")
    return data


def _build_payload(draft: dict[str, Any], draft_path: Path) -> PublishPayload:
    title = str(draft.get("title") or "").strip()
    body = _build_post_body(draft)
    if not title:
        raise ValueError("Draft is missing title.")
    if not body:
        raise ValueError("Draft is missing body.")

    asset_paths = _asset_paths_from_draft(draft)
    if not asset_paths:
        asset_paths = ensure_publish_assets(draft)

    return PublishPayload(
        title=title,
        body=body,
        hashtags=[str(tag).strip() for tag in draft.get("hashtags", []) if str(tag).strip()],
        asset_paths=asset_paths,
        source_draft_path=str(draft_path),
    )


def _build_post_body(draft: dict[str, Any]) -> str:
    hook = str(draft.get("hook") or "").strip()
    body = str(draft.get("body") or "").strip()
    hashtags = [str(tag).strip() for tag in draft.get("hashtags", []) if str(tag).strip()]
    parts = []
    if hook and hook not in body:
        parts.append(hook)
    parts.append(body)
    if hashtags:
        parts.append(" ".join(hashtags))
    return "\n\n".join(part for part in parts if part).strip()


def _asset_paths_from_draft(draft: dict[str, Any]) -> list[Path]:
    raw_paths = draft.get("asset_paths") or draft.get("assets") or []
    if not isinstance(raw_paths, list):
        return []
    paths = [Path(str(path)).expanduser() for path in raw_paths if str(path).strip()]
    return [path for path in paths if path.exists()]
