from __future__ import annotations

import ctypes
import json
import subprocess
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import TypedDict


class _CGPoint(ctypes.Structure):
    _fields_ = [
        ("x", ctypes.c_double),
        ("y", ctypes.c_double),
    ]


class ChromeContentBounds(TypedDict):
    left: int
    top: int
    right: int
    bottom: int
    url: str


@dataclass(frozen=True)
class ChromeTabState:
    window_id: int
    tab_id: int
    url: str


@dataclass(frozen=True)
class ChromeSessionSnapshot:
    window_ids: frozenset[int]
    tabs: dict[int, ChromeTabState]
    active_window_id: int | None
    active_tab_id: int | None
    active_tab_url: str | None


class ChromeSessionCleanup(TypedDict):
    closed_window_ids: list[int]
    closed_tab_ids: list[int]
    restored_initial_tab: bool
    errors: list[str]


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


def capture_chrome_session() -> ChromeSessionSnapshot:
    """Capture existing Chrome resources without launching Chrome."""
    raw = run_chrome_applescript(
        """
        tell application "System Events"
          set chromeRunning to exists process "Google Chrome"
        end tell
        if chromeRunning is false then return ""

        set fieldSeparator to ASCII character 9
        set rowSeparator to ASCII character 10
        set output to ""
        tell application "Google Chrome"
          repeat with chromeWindow in windows
            set windowId to id of chromeWindow
            set output to output & "W" & fieldSeparator & windowId & rowSeparator
            repeat with chromeTab in tabs of chromeWindow
              set tabUrl to ""
              try
                set tabUrl to URL of chromeTab
              end try
              set output to output & "T" & fieldSeparator & windowId & fieldSeparator & ¬
                (id of chromeTab) & fieldSeparator & tabUrl & rowSeparator
            end repeat
          end repeat
          if (count of windows) > 0 then
            set activeWindow to front window
            set activeChromeTab to active tab of activeWindow
            set output to output & "A" & fieldSeparator & (id of activeWindow) & ¬
              fieldSeparator & (id of activeChromeTab) & fieldSeparator & ¬
              (URL of activeChromeTab) & rowSeparator
          end if
        end tell
        return output
        """
    )
    window_ids: set[int] = set()
    tabs: dict[int, ChromeTabState] = {}
    active_window_id = None
    active_tab_id = None
    active_tab_url = None
    for row in raw.splitlines():
        parts = row.split("\t")
        if not parts:
            continue
        if parts[0] == "W" and len(parts) >= 2:
            window_ids.add(int(parts[1]))
        elif parts[0] == "T" and len(parts) >= 4:
            window_id = int(parts[1])
            tab_id = int(parts[2])
            tabs[tab_id] = ChromeTabState(
                window_id=window_id,
                tab_id=tab_id,
                url="\t".join(parts[3:]),
            )
        elif parts[0] == "A" and len(parts) >= 4:
            active_window_id = int(parts[1])
            active_tab_id = int(parts[2])
            active_tab_url = "\t".join(parts[3:])
    return ChromeSessionSnapshot(
        window_ids=frozenset(window_ids),
        tabs=tabs,
        active_window_id=active_window_id,
        active_tab_id=active_tab_id,
        active_tab_url=active_tab_url,
    )


def cleanup_chrome_session(
    initial: ChromeSessionSnapshot,
) -> ChromeSessionCleanup:
    """Close collector-created XHS resources and restore the original active tab."""
    result: ChromeSessionCleanup = {
        "closed_window_ids": [],
        "closed_tab_ids": [],
        "restored_initial_tab": False,
        "errors": [],
    }
    try:
        current = capture_chrome_session()
    except Exception as exc:
        result["errors"].append(f"session capture failed: {exc}")
        return result

    new_window_ids = current.window_ids - initial.window_ids
    close_window_ids: list[int] = []
    for window_id in new_window_ids:
        window_tabs = [
            tab for tab in current.tabs.values() if tab.window_id == window_id
        ]
        if window_tabs and all(_is_collector_chrome_url(tab.url) for tab in window_tabs):
            close_window_ids.append(window_id)

    close_tab_states = [
        tab
        for tab_id, tab in current.tabs.items()
        if tab_id not in initial.tabs
        and tab.window_id not in close_window_ids
        and _is_collector_chrome_url(tab.url)
    ]
    original_tab = (
        initial.tabs.get(initial.active_tab_id)
        if initial.active_tab_id is not None
        else None
    )
    current_original_tab = (
        current.tabs.get(initial.active_tab_id)
        if initial.active_tab_id is not None
        else None
    )
    restore_original = bool(
        original_tab
        and current_original_tab
        and original_tab.url
        and original_tab.url != current_original_tab.url
    )

    script_lines = ['tell application "Google Chrome"']
    for window_id in close_window_ids:
        script_lines.extend(
            [
                "  try",
                f"    close (first window whose id is {window_id})",
                "  end try",
            ]
        )
    for tab in close_tab_states:
        script_lines.extend(
            [
                "  try",
                f"    set targetWindow to first window whose id is {tab.window_id}",
                f"    close (first tab of targetWindow whose id is {tab.tab_id})",
                "  end try",
            ]
        )
    if restore_original and original_tab:
        escaped_url = _escape_applescript_string(original_tab.url)
        script_lines.extend(
            [
                "  try",
                f"    set targetWindow to first window whose id is {original_tab.window_id}",
                "    repeat with tabIndex from 1 to count of tabs of targetWindow",
                f'      if (id of tab tabIndex of targetWindow as text) is "{original_tab.tab_id}" then',
                f'        set URL of tab tabIndex of targetWindow to "{escaped_url}"',
                "        set active tab index of targetWindow to tabIndex",
                "        exit repeat",
                "      end if",
                "    end repeat",
                "    set index of targetWindow to 1",
                "    activate",
                "  end try",
            ]
        )
    script_lines.append("end tell")

    if len(script_lines) > 2:
        try:
            run_chrome_applescript("\n".join(script_lines))
            time.sleep(0.3)
            verified = capture_chrome_session()
            result["closed_window_ids"] = sorted(
                window_id
                for window_id in close_window_ids
                if window_id not in verified.window_ids
            )
            result["closed_tab_ids"] = sorted(
                tab.tab_id
                for tab in close_tab_states
                if tab.tab_id not in verified.tabs
            )
            verified_original = (
                verified.tabs.get(original_tab.tab_id)
                if original_tab
                else None
            )
            result["restored_initial_tab"] = bool(
                restore_original
                and verified_original
                and verified_original.url == original_tab.url
            )
            unclosed_windows = set(close_window_ids) - set(
                result["closed_window_ids"]
            )
            unclosed_tabs = {tab.tab_id for tab in close_tab_states} - set(
                result["closed_tab_ids"]
            )
            if unclosed_windows:
                result["errors"].append(
                    f"windows not closed: {sorted(unclosed_windows)}"
                )
            if unclosed_tabs:
                result["errors"].append(
                    f"tabs not closed: {sorted(unclosed_tabs)}"
                )
            if restore_original and not result["restored_initial_tab"]:
                result["errors"].append("initial active tab was not restored")
        except Exception as exc:
            result["errors"].append(f"session cleanup failed: {exc}")
    return result


def _is_collector_chrome_url(url: str) -> bool:
    normalized = str(url or "").strip().lower()
    return (
        not normalized
        or "xiaohongshu.com" in normalized
        or normalized.startswith("about:blank")
        or normalized.startswith("chrome://newtab")
    )


def _escape_applescript_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def execute_current_chrome_js(script: str) -> str:
    """Execute JavaScript in the active tab of the front Chrome window."""
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8") as tmp:
        tmp.write(script)
        tmp_path = Path(tmp.name)

    try:
        last_error: RuntimeError | None = None
        for _ in range(3):
            ensure_current_chrome_window()
            try:
                return run_chrome_applescript(
                    f'set jsSource to read POSIX file "{tmp_path}" as «class utf8»\n'
                    'tell application "Google Chrome" to execute active tab of front window javascript jsSource'
                )
            except RuntimeError as exc:
                last_error = exc
                if "Invalid index" not in str(exc) and "-1719" not in str(exc):
                    raise
                time.sleep(0.35)
        raise last_error or RuntimeError("Chrome did not expose an active tab.")
    finally:
        tmp_path.unlink(missing_ok=True)


def ensure_current_chrome_window(*, timeout_seconds: float = 5.0) -> None:
    """Ensure Chrome has a front window and active tab before browser work."""
    deadline = time.monotonic() + timeout_seconds
    last_error: RuntimeError | None = None
    while time.monotonic() < deadline:
        try:
            count = run_chrome_applescript(
                f"""
                tell application "Google Chrome"
                  activate
                  if (count of windows) = 0 then
                    make new window
                  end if
                  return count of windows
                end tell
                """
            )
            if int(count or "0") > 0:
                return
        except (RuntimeError, ValueError) as exc:
            last_error = RuntimeError(str(exc))
        time.sleep(0.25)
    raise last_error or RuntimeError("Chrome did not provide a usable window.")


def open_current_chrome_url(url: str, *, wait_seconds: float = 0) -> None:
    """Navigate the current active Chrome tab to a URL."""
    escaped_url = _escape_applescript_string(url)
    last_error: RuntimeError | None = None
    for _ in range(3):
        ensure_current_chrome_window()
        try:
            run_chrome_applescript(
                f"""
                tell application "Google Chrome"
                  activate
                  set URL of active tab of front window to "{escaped_url}"
                end tell
                """
            )
            last_error = None
            break
        except RuntimeError as exc:
            last_error = exc
            if "Invalid index" not in str(exc) and "-1719" not in str(exc):
                raise
            time.sleep(0.35)
    if last_error:
        raise last_error
    if wait_seconds > 0:
        time.sleep(wait_seconds)


def activate_current_chrome(*, wait_seconds: float = 0.2) -> None:
    """Bring the user's current Chrome window to the front."""
    ensure_current_chrome_window()
    run_chrome_applescript('tell application "Google Chrome" to activate')
    if wait_seconds > 0:
        time.sleep(wait_seconds)


def current_chrome_content_bounds() -> ChromeContentBounds:
    """Return absolute screen bounds for the active Chrome tab's content."""
    bounds = json.loads(
        execute_current_chrome_js(
            """
            JSON.stringify((() => {
              const toolbarHeight = Math.max(
                0,
                window.outerHeight - window.innerHeight
              );
              const left = Math.round(window.screenX);
              const top = Math.round(window.screenY + toolbarHeight);
              return {
                left,
                top,
                right: Math.round(left + window.innerWidth),
                bottom: Math.round(top + window.innerHeight),
                url: location.href || '',
              };
            })())
            """
        )
    )
    return {
        "left": int(bounds["left"]),
        "top": int(bounds["top"]),
        "right": int(bounds["right"]),
        "bottom": int(bounds["bottom"]),
        "url": str(bounds.get("url") or ""),
    }


def _require_current_chrome_content_point(
    x: int,
    y: int,
    *,
    action: str,
) -> None:
    bounds = current_chrome_content_bounds()
    if (
        bounds["left"] <= x <= bounds["right"]
        and bounds["top"] <= y <= bounds["bottom"]
    ):
        return
    raise RuntimeError(
        f"Blocked {action}: screen point ({x}, {y}) is outside "
        f"the current Chrome content bounds {bounds}."
    )


def click_screen_point(x: int, y: int, *, wait_seconds: float = 0.2) -> None:
    """Click an absolute screen coordinate using a real macOS mouse event."""
    x = int(x)
    y = int(y)
    try:
        activate_current_chrome(wait_seconds=wait_seconds)
        _require_current_chrome_content_point(x, y, action="mouse click")
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


def move_mouse_screen_point(x: int, y: int, *, wait_seconds: float = 0.1) -> None:
    """Move the real macOS pointer without clicking."""
    x = int(x)
    y = int(y)
    activate_current_chrome(wait_seconds=wait_seconds)
    _require_current_chrome_content_point(x, y, action="mouse move")
    _post_mouse_move(x, y)


def drag_screen_points(
    start_x: int,
    start_y: int,
    end_x: int,
    end_y: int,
    *,
    duration_seconds: float = 0.35,
) -> None:
    """Drag the real macOS pointer between two absolute screen points."""
    activate_current_chrome(wait_seconds=0.1)
    _require_current_chrome_content_point(
        int(start_x),
        int(start_y),
        action="drag start",
    )
    _require_current_chrome_content_point(
        int(end_x),
        int(end_y),
        action="drag end",
    )
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

    steps = 12
    delay = max(duration_seconds, 0.12) / steps
    events: list[int] = []
    mouse_down_posted = False
    mouse_up_posted = False
    try:
        down = app_services.CGEventCreateMouseEvent(
            None,
            1,
            _CGPoint(float(start_x), float(start_y)),
            0,
        )
        if not down:
            raise RuntimeError("Could not create macOS drag start event.")
        events.append(down)
        app_services.CGEventPost(0, down)
        mouse_down_posted = True
        for step in range(1, steps + 1):
            ratio = step / steps
            point = _CGPoint(
                float(start_x + (end_x - start_x) * ratio),
                float(start_y + (end_y - start_y) * ratio),
            )
            dragged = app_services.CGEventCreateMouseEvent(None, 6, point, 0)
            if not dragged:
                raise RuntimeError("Could not create macOS drag movement event.")
            events.append(dragged)
            app_services.CGEventPost(0, dragged)
            time.sleep(delay)
        up = app_services.CGEventCreateMouseEvent(
            None,
            2,
            _CGPoint(float(end_x), float(end_y)),
            0,
        )
        if not up:
            raise RuntimeError("Could not create macOS drag end event.")
        events.append(up)
        app_services.CGEventPost(0, up)
        mouse_up_posted = True
    finally:
        if mouse_down_posted and not mouse_up_posted:
            emergency_up = app_services.CGEventCreateMouseEvent(
                None,
                2,
                _CGPoint(float(end_x), float(end_y)),
                0,
            )
            if emergency_up:
                app_services.CGEventPost(0, emergency_up)
                core_foundation.CFRelease(emergency_up)
        for event in events:
            core_foundation.CFRelease(event)


def _post_mouse_move(x: int, y: int) -> None:
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

    event = app_services.CGEventCreateMouseEvent(
        None,
        5,
        _CGPoint(float(x), float(y)),
        0,
    )
    if not event:
        raise RuntimeError("Could not create macOS mouse move event.")
    try:
        app_services.CGEventPost(0, event)
    finally:
        core_foundation.CFRelease(event)


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


def navigate_current_chrome_back(*, wait_seconds: float = 1.5) -> None:
    """Navigate back with the same Command-Left shortcut a person would use."""
    activate_current_chrome(wait_seconds=0.1)
    run_chrome_applescript(
        'tell application "System Events" to key code 123 using {command down}'
    )
    if wait_seconds > 0:
        time.sleep(wait_seconds)


def navigate_current_chrome_top(*, wait_seconds: float = 0.6) -> None:
    """Move to the top with the same Command-Up shortcut a person would use."""
    activate_current_chrome(wait_seconds=0.1)
    run_chrome_applescript(
        'tell application "System Events" to key code 126 using {command down}'
    )
    if wait_seconds > 0:
        time.sleep(wait_seconds)


def close_current_chrome_tab(*, wait_seconds: float = 1.0) -> None:
    """Close the active tab with the same Command-W shortcut a person would use."""
    activate_current_chrome(wait_seconds=0.1)
    run_chrome_applescript(
        'tell application "System Events" to key code 13 using {command down}'
    )
    if wait_seconds > 0:
        time.sleep(wait_seconds)


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
