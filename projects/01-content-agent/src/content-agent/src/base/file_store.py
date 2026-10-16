from __future__ import annotations

import json
import re
from datetime import datetime
from pathlib import Path
from uuid import uuid4


PRODUCT_ALIASES = {
    "ISS-Tracker": (
        "ISS Tracker",
        "ISS",
        "国际空间站",
        "空间站",
    ),
    "BirdTracker": (
        "BirdTracker",
        "观鸟",
        "鸟类",
    ),
    "Math-Puzzle": (
        "Math Puzzle",
        "数字谜题",
        "数学谜题",
        "交叉算式",
    ),
    "Soulnio": (
        "Soulnio",
        "塔罗",
        "自我探索",
        "时间罗盘",
        "关系星网",
    ),
}


def save_draft(
    draft: dict,
    output_dir: Path | str = "data/drafts",
    status: str = "draft",
    metadata: dict | None = None,
) -> Path:
    """Add local state fields and persist the draft as JSON."""
    target_dir = Path(output_dir)
    target_dir.mkdir(parents=True, exist_ok=True)

    now = datetime.now().astimezone()
    metadata = metadata or {}
    complete_draft = {
        "id": str(uuid4()),
        "created_at": now.isoformat(timespec="seconds"),
        **draft,
        **metadata,
        "status": status,
    }

    filename = _build_draft_filename(now, complete_draft, target_dir)
    path = target_dir / filename
    path.write_text(
        json.dumps(complete_draft, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return path


def _build_draft_filename(now: datetime, draft: dict, target_dir: Path) -> str:
    date_part = now.strftime("%Y-%m-%d")
    product_part = _infer_product_name(draft)
    topic_part = _slugify(
        _topic_for_filename(draft, product_part),
        max_length=36,
    )
    base_name = f"{date_part}-{product_part}-{topic_part}"
    filename = f"{base_name}.json"
    index = 2
    while (target_dir / filename).exists():
        filename = f"{base_name}-{index}.json"
        index += 1
    return filename


def _infer_product_name(draft: dict) -> str:
    product = draft.get("product")
    product_to_filename = {
        "ISS Tracker": "ISS-Tracker",
        "BirdTracker": "BirdTracker",
        "Math Puzzle": "Math-Puzzle",
        "Soulnio": "Soulnio",
        "Product Universe": "Product-Universe",
    }
    if isinstance(product, str) and product.strip() in product_to_filename:
        return product_to_filename[product.strip()]

    searchable_text = "\n".join(
        str(value)
        for key, value in draft.items()
        if key
        in {
            "topic",
            "audience",
            "title",
            "hook",
            "body",
            "takeaways",
            "hashtags",
            "cover_text",
            "reason",
        }
    )
    for product_name, aliases in PRODUCT_ALIASES.items():
        if any(alias in searchable_text for alias in aliases):
            return product_name
    return "Product-Universe"


def _topic_for_filename(draft: dict, product_name: str) -> str:
    topic = str(draft.get("topic") or draft.get("title") or "untitled").strip()
    aliases = PRODUCT_ALIASES.get(product_name, ())
    for alias in aliases:
        topic = re.sub(
            rf"^\s*{re.escape(alias)}[\s:：_-]*",
            "",
            topic,
            flags=re.IGNORECASE,
        ).strip()
    return topic or str(draft.get("title") or "untitled").strip()


def _slugify(value: str, *, max_length: int) -> str:
    value = re.sub(r"[^\w\u4e00-\u9fff]+", "-", value, flags=re.UNICODE)
    value = re.sub(r"-+", "-", value).strip("-_")
    if not value:
        return "untitled"
    return value[:max_length].strip("-_") or "untitled"
