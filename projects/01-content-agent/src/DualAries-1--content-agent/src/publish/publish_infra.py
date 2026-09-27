from __future__ import annotations

import json
import subprocess
import tempfile
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class PublishPayload:
    title: str
    body: str
    hashtags: list[str] = field(default_factory=list)
    asset_paths: list[Path] = field(default_factory=list)
    source_draft_path: str | None = None


@dataclass
class PublishResult:
    platform: str
    status: str
    draft_path: str | None = None
    asset_paths: list[str] = field(default_factory=list)
    page_url: str | None = None
    warnings: list[str] = field(default_factory=list)
    error_message: str | None = None

    def model_dump(self) -> dict[str, Any]:
        return asdict(self)


def open_publish_page(url: str, *, wait_seconds: float = 8) -> None:
    open_current_chrome_url(url, wait_seconds=wait_seconds)


def current_page_url() -> str | None:
    try:
        data = json.loads(
            execute_current_chrome_js(
                "JSON.stringify({title: document.title || null, url: location.href || null})"
            )
        )
    except (RuntimeError, json.JSONDecodeError):
        return None
    return data.get("url")


def visible_page_text(limit: int = 3000) -> str:
    return execute_current_chrome_js(
        f"document.body ? document.body.innerText.slice(0, {int(limit)}) : ''"
    )


def click_text(candidates: list[str], *, timeout_seconds: float = 8, exact: bool = False) -> bool:
    """Click the first visible element whose text contains one candidate."""
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        clicked = json.loads(
            execute_current_chrome_js(
                f"""
                JSON.stringify((() => {{
                  const candidates = {json.dumps(candidates, ensure_ascii=False)};
                  const visible = (el) => {{
                    const rect = el.getBoundingClientRect();
                    const style = getComputedStyle(el);
                    return rect.width > 0 && rect.height > 0 &&
                      style.visibility !== 'hidden' && style.display !== 'none';
                  }};
                  const elements = Array.from(document.querySelectorAll(
                    'button, [role="button"], a, div, span'
                  )).filter(visible);
                  const matches = (actual, expected) => {{
                    const cleaned = String(actual || '').replace(/\\s+/g, ' ').trim();
                    return {json.dumps(exact)} ? cleaned === expected : cleaned.includes(expected);
                  }};
                  for (const text of candidates) {{
                    const target = elements.find((el) => matches(el.innerText || el.textContent, text));
                    if (target) {{
                      target.scrollIntoView({{block: 'center', inline: 'center'}});
                      target.click();
                      return true;
                    }}
                  }}
                  return false;
                }})())
                """
            )
        )
        if clicked:
            time.sleep(1)
            return True
        time.sleep(0.5)
    return False


def fill_title(title: str) -> bool:
    return _fill_field(
        title,
        selectors=[
            'input[placeholder*="标题"]',
            'textarea[placeholder*="标题"]',
            '[contenteditable="true"][placeholder*="标题"]',
            'input',
        ],
        max_candidates=8,
    )


def fill_body(body: str) -> bool:
    return _fill_field(
        body,
        selectors=[
            'textarea[placeholder*="正文"]',
            'textarea[placeholder*="内容"]',
            'textarea[placeholder*="描述"]',
            '[contenteditable="true"][placeholder*="正文"]',
            '[contenteditable="true"][placeholder*="内容"]',
            '[contenteditable="true"]',
            'textarea',
        ],
        max_candidates=12,
    )


def upload_file_via_dialog(path: Path, *, open_dialog: bool = True) -> None:
    """Upload a file through the current Chrome file dialog using macOS UI scripting."""
    absolute_path = str(path.expanduser().resolve())
    if open_dialog:
        if not click_file_input_or_upload_button():
            raise RuntimeError("Could not find an upload control on the current page.")
        time.sleep(1.5)
    _choose_file_in_system_dialog(absolute_path)
    time.sleep(5)


def click_file_input_or_upload_button() -> bool:
    clicked_input = json.loads(
        execute_current_chrome_js(
            """
            JSON.stringify((() => {
              const visible = (el) => {
                const rect = el.getBoundingClientRect();
                const style = getComputedStyle(el);
                return rect.width > 0 && rect.height > 0 &&
                  style.visibility !== 'hidden' && style.display !== 'none';
              };
              const input = Array.from(document.querySelectorAll('input[type="file"]')).find(visible);
              if (input) {
                input.scrollIntoView({block: 'center', inline: 'center'});
                input.click();
                return true;
              }
              return false;
            })())
            """
        )
    )
    if clicked_input:
        return True
    return click_text(["上传", "选择图片", "上传图片", "发布图文", "图文"], timeout_seconds=4)


def wait_for_any_text(candidates: list[str], *, timeout_seconds: float = 20) -> str | None:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        text = visible_page_text(limit=3000)
        for candidate in candidates:
            if candidate in text:
                return candidate
        time.sleep(1)
    return None


def _fill_field(value: str, *, selectors: list[str], max_candidates: int) -> bool:
    return json.loads(
        execute_current_chrome_js(
            f"""
            JSON.stringify((() => {{
              const value = {json.dumps(value, ensure_ascii=False)};
              const selectors = {json.dumps(selectors, ensure_ascii=False)};
              const visible = (el) => {{
                const rect = el.getBoundingClientRect();
                const style = getComputedStyle(el);
                return rect.width > 0 && rect.height > 0 &&
                  style.visibility !== 'hidden' && style.display !== 'none';
              }};
              const setInputValue = (el, nextValue) => {{
                el.focus();
                const tag = el.tagName.toLowerCase();
                if (el.isContentEditable) {{
                  el.innerText = nextValue;
                }} else if (tag === 'textarea') {{
                  const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')?.set;
                  setter ? setter.call(el, nextValue) : el.value = nextValue;
                }} else {{
                  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
                  setter ? setter.call(el, nextValue) : el.value = nextValue;
                }}
                el.dispatchEvent(new InputEvent('input', {{inputType: 'insertText', data: nextValue, bubbles: true}}));
                el.dispatchEvent(new Event('change', {{bubbles: true}}));
                return true;
              }};
              for (const selector of selectors) {{
                const elements = Array.from(document.querySelectorAll(selector)).filter(visible).slice(0, {max_candidates});
                for (const el of elements) {{
                  if (setInputValue(el, value)) return true;
                }}
              }}
              return false;
            }})())
            """
        )
    )


def _choose_file_in_system_dialog(absolute_path: str) -> None:
    script = f'''
    tell application "System Events"
      keystroke "g" using {{command down, shift down}}
      delay 0.5
      keystroke {json.dumps(absolute_path)}
      delay 0.2
      key code 36
      delay 0.5
      key code 36
    end tell
    '''
    result = subprocess.run(
        ["osascript", "-e", script],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        message = result.stderr.strip() or result.stdout.strip()
        if "not allowed assistive access" in message.lower() or "not authorized" in message.lower():
            raise RuntimeError(
                "macOS blocked System Events file upload. Grant Accessibility permission "
                "to the terminal/Codex app, then rerun."
            )
        raise RuntimeError(message)


def open_current_chrome_url(url: str, *, wait_seconds: float = 0) -> None:
    run_chrome_applescript(
        f'tell application "Google Chrome" to set URL of active tab of front window to "{url}"'
    )
    if wait_seconds > 0:
        time.sleep(wait_seconds)


def execute_current_chrome_js(script: str) -> str:
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


def run_chrome_applescript(script: str) -> str:
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
                "Current Chrome publishing needs Chrome permission: "
                "View > Developer > Allow JavaScript from Apple Events."
            )
        raise RuntimeError(message)
    return result.stdout.strip()
