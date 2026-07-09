from __future__ import annotations

import ctypes
import json
import subprocess
import tempfile
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

from src.base.json_utils import call_json_model


class _CGPoint(ctypes.Structure):
    _fields_ = [
        ("x", ctypes.c_double),
        ("y", ctypes.c_double),
    ]


@dataclass
class PageSnapshot:
    """A platform-neutral view of the currently visible browser page."""

    title: str | None
    url: str | None
    visible_text: str
    links: list[dict[str, str | None]] = field(default_factory=list)
    images: list[dict[str, str | None]] = field(default_factory=list)
    text_blocks: list[str] = field(default_factory=list)

    def model_dump(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class ExtractionResult:
    """Generic extraction output plus platform-neutral quality signals."""

    items: list[dict[str, Any]]
    method: str
    confidence: float
    field_coverage: dict[str, int]
    warnings: list[str] = field(default_factory=list)
    page: PageSnapshot | None = None

    def model_dump(self) -> dict[str, Any]:
        data = asdict(self)
        if self.page is None:
            data["page"] = None
        return data


def run_chrome_applescript(script: str) -> str:
    """Run AppleScript against the user's current Chrome."""
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
                "Current Chrome collection can use your existing browser session, "
                "but DOM extraction needs one Chrome setting: "
                "View > Developer > Allow JavaScript from Apple Events. "
                "Turn it on once, keep your logged-in tab available, then rerun."
            )
        raise RuntimeError(message)
    return result.stdout.strip()


def execute_current_chrome_js(script: str) -> str:
    """Execute JavaScript in the active tab of the front Chrome window."""
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8") as tmp:
        tmp.write(script)
        tmp_path = Path(tmp.name)

    try:
        return run_chrome_applescript(
            f'set jsSource to read POSIX file "{tmp_path}"\n'
            'tell application "Google Chrome" to execute active tab of front window javascript jsSource'
        )
    finally:
        tmp_path.unlink(missing_ok=True)


def open_current_chrome_url(url: str, *, wait_seconds: float = 0) -> None:
    """Navigate the current active Chrome tab to a URL."""
    run_chrome_applescript(
        f"""
        tell application "Google Chrome"
          activate
          if (count of windows) = 0 then
            make new window
          end if
          set URL of active tab of front window to "{url}"
        end tell
        """
    )
    if wait_seconds > 0:
        time.sleep(wait_seconds)


def activate_current_chrome(*, wait_seconds: float = 0.2) -> None:
    """Bring the user's current Chrome window to the front."""
    run_chrome_applescript('tell application "Google Chrome" to activate')
    if wait_seconds > 0:
        time.sleep(wait_seconds)


def click_screen_point(x: int, y: int, *, wait_seconds: float = 0.2) -> None:
    """Click an absolute screen coordinate using a real macOS mouse event."""
    x = int(x)
    y = int(y)
    if x < 0 or y < 0:
        raise RuntimeError(f"invalid screen coordinate: {x}, {y}")
    try:
        activate_current_chrome(wait_seconds=wait_seconds)
        _post_mouse_click(x, y)
    except RuntimeError as exc:
        message = str(exc)
        if "not allowed assistive access" in message or "-25211" in message:
            message = (
                "macOS blocked human-like system clicking. Enable Accessibility permission "
                "for the app running this command in System Settings > Privacy & Security > Accessibility, "
                "then rerun the collector."
            )
        raise RuntimeError(message) from exc


def _post_mouse_click(x: int, y: int) -> None:
    app_services = ctypes.CDLL(
        "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
    )
    core_foundation = ctypes.CDLL(
        "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
    )
    app_services.CGEventCreateMouseEvent.restype = ctypes.c_void_p
    app_services.CGEventCreateMouseEvent.argtypes = [
        ctypes.c_void_p,
        ctypes.c_uint32,
        _CGPoint,
        ctypes.c_uint32,
    ]
    app_services.CGEventPost.argtypes = [ctypes.c_uint32, ctypes.c_void_p]
    core_foundation.CFRelease.argtypes = [ctypes.c_void_p]

    point = _CGPoint(float(x), float(y))
    down = app_services.CGEventCreateMouseEvent(None, 1, point, 0)
    up = app_services.CGEventCreateMouseEvent(None, 2, point, 0)
    if not down or not up:
        if down:
            core_foundation.CFRelease(down)
        if up:
            core_foundation.CFRelease(up)
        raise RuntimeError("Could not create macOS mouse click event.")
    try:
        app_services.CGEventPost(0, down)
        time.sleep(0.05)
        app_services.CGEventPost(0, up)
    finally:
        core_foundation.CFRelease(down)
        core_foundation.CFRelease(up)


def press_current_chrome_key(key: str, *, wait_seconds: float = 0.2) -> None:
    """Send a simple key press to the current Chrome window."""
    activate_current_chrome(wait_seconds=wait_seconds)
    run_chrome_applescript(
        f'tell application "System Events" to key code {_key_code_for(key)}'
    )


def scroll_current_chrome(*, rounds: int, pause_seconds: float = 1.2) -> None:
    """Scroll the active Chrome tab like a human reading down a feed."""
    for _ in range(rounds):
        scroll_current_chrome_wheel()
        if pause_seconds > 0:
            time.sleep(pause_seconds)


def scroll_current_chrome_wheel(
    *,
    clicks: int = 6,
    direction: str = "down",
    pause_seconds: float = 0,
) -> None:
    """Scroll the current Chrome window using a real macOS wheel event."""
    activate_current_chrome(wait_seconds=0.1)
    delta = abs(clicks)
    if direction.lower() == "down":
        delta = -delta
    elif direction.lower() != "up":
        raise ValueError(f"Unsupported scroll direction: {direction}")

    app_services = ctypes.CDLL(
        "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
    )
    core_foundation = ctypes.CDLL(
        "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
    )
    app_services.CGEventCreateScrollWheelEvent.restype = ctypes.c_void_p
    app_services.CGEventPost.argtypes = [ctypes.c_uint32, ctypes.c_void_p]
    core_foundation.CFRelease.argtypes = [ctypes.c_void_p]

    event = app_services.CGEventCreateScrollWheelEvent(
        None,
        0,
        1,
        ctypes.c_int32(delta),
    )
    if not event:
        raise RuntimeError("Could not create macOS scroll wheel event.")
    try:
        app_services.CGEventPost(0, event)
    finally:
        core_foundation.CFRelease(event)
    if pause_seconds > 0:
        time.sleep(pause_seconds)


def snapshot_current_chrome(
    *,
    text_limit: int = 4000,
    link_limit: int = 120,
    image_limit: int = 80,
    block_limit: int = 80,
) -> PageSnapshot:
    """Capture a compact semantic snapshot of the active Chrome page."""
    raw = execute_current_chrome_js(
        f"""
        JSON.stringify((() => {{
          const clean = (value) => String(value || '').replace(/\\s+/g, ' ').trim();
          const visible = (el) => {{
            if (!el) return false;
            const rect = el.getBoundingClientRect();
            const style = window.getComputedStyle(el);
            return rect.width > 0 && rect.height > 0 &&
              style.visibility !== 'hidden' && style.display !== 'none';
          }};
          const links = Array.from(document.querySelectorAll('a[href]'))
            .filter(visible)
            .map((a) => ({{
              text: clean(a.innerText || a.getAttribute('title') || a.getAttribute('aria-label')),
              href: a.href,
              title: clean(a.getAttribute('title')),
              aria_label: clean(a.getAttribute('aria-label')),
            }}))
            .filter((item) => item.href || item.text)
            .slice(0, {link_limit});
          const images = Array.from(document.querySelectorAll('img'))
            .filter(visible)
            .map((img) => ({{
              alt: clean(img.alt),
              src: img.currentSrc || img.src || null,
              title: clean(img.getAttribute('title')),
            }}))
            .filter((item) => item.alt || item.src)
            .slice(0, {image_limit});
          const textBlocks = Array.from(document.querySelectorAll('section, article, main, div, li'))
            .filter(visible)
            .map((el) => clean(el.innerText))
            .filter((text) => text.length >= 12 && text.length <= 500)
            .slice(0, {block_limit});
          return {{
            title: document.title || null,
            url: location.href || null,
            visible_text: document.body ? clean(document.body.innerText).slice(0, {text_limit}) : '',
            links,
            images,
            text_blocks: textBlocks,
          }};
        }})())
        """
    )
    data = json.loads(raw)
    return PageSnapshot(
        title=data.get("title"),
        url=data.get("url"),
        visible_text=data.get("visible_text") or "",
        links=data.get("links") or [],
        images=data.get("images") or [],
        text_blocks=data.get("text_blocks") or [],
    )


def build_extraction_result(
    items: list[dict[str, Any]],
    *,
    method: str,
    confidence: float,
    page: PageSnapshot | None = None,
    warnings: list[str] | None = None,
) -> ExtractionResult:
    """Build a generic result with field coverage counts."""
    return ExtractionResult(
        items=items,
        method=method,
        confidence=max(0.0, min(1.0, confidence)),
        field_coverage=_field_coverage(items),
        warnings=warnings or [],
        page=page,
    )


def semantic_extract_items_from_snapshot(
    snapshot: PageSnapshot,
    *,
    item_description: str,
    required_fields: list[str],
    optional_fields: list[str] | None = None,
    max_items: int = 10,
    label: str = "Semantic page extractor",
) -> ExtractionResult:
    """Use an LLM to extract structured items from a page snapshot."""
    optional_fields = optional_fields or []
    fields = [*required_fields, *optional_fields]
    messages = [
        {
            "role": "system",
            "content": (
                "You are a careful web page information extractor. "
                "Use only the provided page snapshot. Return valid JSON only."
            ),
        },
        {
            "role": "user",
            "content": (
                "# Task\n"
                f"Extract up to {max_items} items that match this description:\n"
                f"{item_description}\n\n"
                "# Fields\n"
                f"Required fields: {required_fields}\n"
                f"Optional fields: {optional_fields}\n\n"
                "# Rules\n"
                "- Do not invent missing values\n"
                "- Use null when a field is not visible\n"
                "- Prefer visible links and nearby visible text\n"
                "- Only include items that look like real page content, not navigation controls\n"
                "- confidence must be a number from 0 to 1\n\n"
                "# Output JSON Schema\n"
                "{\n"
                '  "items": [\n'
                f"    {{{', '.join(json.dumps(field) + ': null' for field in fields)}}}\n"
                "  ],\n"
                '  "confidence": 0.7,\n'
                '  "warnings": ["..."]\n'
                "}\n\n"
                "# Page Snapshot\n"
                f"{json.dumps(snapshot.model_dump(), ensure_ascii=False, indent=2)}"
            ),
        },
    ]
    parsed = call_json_model(messages, label)
    raw_items = parsed.get("items") or []
    if not isinstance(raw_items, list):
        raw_items = []
    items = [
        {field: item.get(field) for field in fields}
        for item in raw_items[:max_items]
        if isinstance(item, dict)
    ]
    confidence = parsed.get("confidence", 0.45)
    if not isinstance(confidence, (int, float)):
        confidence = 0.45
    warnings = parsed.get("warnings") or []
    if not isinstance(warnings, list):
        warnings = [str(warnings)]
    missing_required = [
        field
        for field in required_fields
        if sum(1 for item in items if item.get(field)) == 0
    ]
    if missing_required:
        warnings = [*warnings, f"missing_required_fields: {', '.join(missing_required)}"]
        confidence = min(float(confidence), 0.5)

    return build_extraction_result(
        items=items,
        method="semantic",
        confidence=float(confidence),
        page=snapshot,
        warnings=[str(item) for item in warnings if str(item).strip()],
    )


def _field_coverage(items: list[dict[str, Any]]) -> dict[str, int]:
    fields = sorted({field for item in items for field in item})
    return {
        field: sum(1 for item in items if item.get(field) not in (None, "", [], {}))
        for field in fields
    }


def _key_code_for(key: str) -> int:
    codes = {
        "escape": 53,
        "esc": 53,
        "return": 36,
        "enter": 36,
        "tab": 48,
        "space": 49,
        "delete": 51,
        "backspace": 51,
    }
    normalized = key.strip().lower()
    if normalized not in codes:
        raise ValueError(f"Unsupported key for System Events key code: {key}")
    return codes[normalized]
