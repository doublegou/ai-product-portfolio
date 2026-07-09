from __future__ import annotations

import re
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from PIL import Image, ImageDraw, ImageFont


CARD_SIZE = (1080, 1440)
FONT_CANDIDATES = (
    "/System/Library/Fonts/STHeiti Medium.ttc",
    "/System/Library/Fonts/PingFang.ttc",
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    "/System/Library/Fonts/Supplemental/Songti.ttc",
)

PRODUCT_THEMES = {
    "ISS Tracker": {
        "background": "#071722",
        "panel": "#0e2a35",
        "primary": "#7ee7ff",
        "text": "#eefbff",
        "muted": "#a6c7d0",
    },
    "BirdTracker": {
        "background": "#eef8ef",
        "panel": "#ffffff",
        "primary": "#2d8f6f",
        "text": "#18352c",
        "muted": "#5f776e",
    },
    "Math Puzzle": {
        "background": "#fff4df",
        "panel": "#ffffff",
        "primary": "#9b5a24",
        "text": "#362212",
        "muted": "#7b6046",
    },
    "Soulnio": {
        "background": "#f9eef9",
        "panel": "#ffffff",
        "primary": "#9a5bb7",
        "text": "#37213f",
        "muted": "#765f7c",
    },
    "Product Universe": {
        "background": "#f2f4f7",
        "panel": "#ffffff",
        "primary": "#3f6f8f",
        "text": "#17212b",
        "muted": "#627283",
    },
}


def ensure_publish_assets(draft: dict, *, output_dir: Path | str = "data/publish_assets") -> list[Path]:
    """Return publish assets, generating a fallback text-card image if needed."""
    target_dir = Path(output_dir) / datetime.now(ZoneInfo("Asia/Shanghai")).strftime("%Y-%m-%d")
    target_dir.mkdir(parents=True, exist_ok=True)
    path = target_dir / f"{_safe_slug(draft.get('product', 'post'))}-{_safe_slug(draft.get('topic', 'draft'))}.png"
    if not path.exists():
        create_text_card(draft, path)
    return [path]


def create_text_card(draft: dict, output_path: Path) -> Path:
    """Render a simple Xiaohongshu-friendly text card as a fallback image."""
    product = str(draft.get("product") or "Product Universe")
    theme = PRODUCT_THEMES.get(product, PRODUCT_THEMES["Product Universe"])
    image = Image.new("RGB", CARD_SIZE, theme["background"])
    draw = ImageDraw.Draw(image)

    title_font = _font(76)
    subtitle_font = _font(42)
    body_font = _font(34)
    small_font = _font(30)

    margin = 86
    panel = (margin, 118, CARD_SIZE[0] - margin, CARD_SIZE[1] - 128)
    draw.rounded_rectangle(panel, radius=42, fill=theme["panel"])

    x = panel[0] + 62
    y = panel[1] + 62
    max_width = panel[2] - panel[0] - 124

    cover_text = str(draft.get("cover_text") or draft.get("title") or "").strip()
    title = str(draft.get("title") or "").strip()
    hook = str(draft.get("hook") or "").strip()
    takeaways = [str(item).strip() for item in draft.get("takeaways", []) if str(item).strip()]

    draw.text((x, y), product, font=small_font, fill=theme["primary"])
    y += 72

    y = _draw_wrapped(draw, cover_text or title, x, y, max_width, title_font, theme["text"], line_gap=16, max_lines=3)
    y += 42

    if title and title != cover_text:
        y = _draw_wrapped(draw, title, x, y, max_width, subtitle_font, theme["primary"], line_gap=12, max_lines=2)
        y += 44

    if hook:
        y = _draw_wrapped(draw, hook, x, y, max_width, body_font, theme["text"], line_gap=14, max_lines=4)
        y += 42

    for item in takeaways[:4]:
        bullet = f"- {item}"
        y = _draw_wrapped(draw, bullet, x, y, max_width, body_font, theme["muted"], line_gap=12, max_lines=2)
        y += 22

    footer = "一个小产品宇宙里的今日笔记"
    footer_bbox = draw.textbbox((0, 0), footer, font=small_font)
    draw.text(
        (x, panel[3] - 72),
        footer,
        font=small_font,
        fill=theme["muted"],
    )
    draw.line(
        (x, panel[3] - 104, x + max(220, footer_bbox[2] - footer_bbox[0]), panel[3] - 104),
        fill=theme["primary"],
        width=4,
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    image.save(output_path)
    return output_path


def _draw_wrapped(
    draw: ImageDraw.ImageDraw,
    text: str,
    x: int,
    y: int,
    max_width: int,
    font: ImageFont.ImageFont,
    fill: str,
    *,
    line_gap: int,
    max_lines: int,
) -> int:
    lines = _wrap_text(draw, text, max_width, font, max_lines=max_lines)
    for line in lines:
        draw.text((x, y), line, font=font, fill=fill)
        bbox = draw.textbbox((x, y), line, font=font)
        y += bbox[3] - bbox[1] + line_gap
    return y


def _wrap_text(
    draw: ImageDraw.ImageDraw,
    text: str,
    max_width: int,
    font: ImageFont.ImageFont,
    *,
    max_lines: int,
) -> list[str]:
    cleaned = re.sub(r"\s+", " ", text).strip()
    if not cleaned:
        return []
    lines: list[str] = []
    current = ""
    for char in cleaned:
        candidate = f"{current}{char}"
        width = draw.textbbox((0, 0), candidate, font=font)[2]
        if width <= max_width or not current:
            current = candidate
            continue
        lines.append(current)
        current = char
        if len(lines) >= max_lines:
            break
    if current and len(lines) < max_lines:
        lines.append(current)
    if len(lines) == max_lines and len("".join(lines)) < len(cleaned):
        lines[-1] = lines[-1].rstrip("，。,. ") + "..."
    return lines


def _font(size: int) -> ImageFont.ImageFont:
    for path in FONT_CANDIDATES:
        font_path = Path(path)
        if font_path.exists():
            return ImageFont.truetype(str(font_path), size=size)
    return ImageFont.load_default()


def _safe_slug(value: object) -> str:
    slug = re.sub(r"[^\w\u4e00-\u9fff]+", "-", str(value or "draft"), flags=re.UNICODE)
    slug = re.sub(r"-+", "-", slug).strip("-_")
    return (slug[:36].strip("-_") or "draft")
