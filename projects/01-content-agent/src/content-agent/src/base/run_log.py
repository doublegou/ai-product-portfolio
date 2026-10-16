from __future__ import annotations

import json
import os
import traceback as traceback_module
from datetime import datetime
from pathlib import Path
from uuid import uuid4
from zoneinfo import ZoneInfo


LOG_TIMEZONE = ZoneInfo("Asia/Shanghai")
DEFAULT_LOG_DIR = Path("data/logs")
MAX_STRING_LENGTH = 4000
MAX_TRACEBACK_LENGTH = 12000

_run_context: dict[str, object] = {
    "run_id": None,
    "command": None,
}


def set_run_context(
    command: str,
    *,
    run_id: str | None = None,
    args: dict | None = None,
) -> str:
    """Set lightweight process-wide context for structured run logs."""
    generated_run_id = run_id or _generate_run_id()
    _run_context["run_id"] = generated_run_id
    _run_context["command"] = command
    if args is not None:
        _run_context["args"] = _sanitize(args)
    return generated_run_id


def get_run_id() -> str:
    """Return the current run id, creating one if needed."""
    existing = _run_context.get("run_id")
    if isinstance(existing, str) and existing:
        return existing
    return set_run_context("unknown")


def log_event(event: str, *, level: str = "info", **fields: object) -> None:
    """Append one structured JSON event. Logging failures never stop the agent."""
    try:
        now = _now()
        payload = {
            "ts": now.isoformat(timespec="seconds"),
            "run_id": get_run_id(),
            "level": level,
            "event": event,
            "pid": os.getpid(),
        }
        command = _run_context.get("command")
        if command:
            payload["command"] = command
        if event == "run_start" and "args" in _run_context:
            payload["args"] = _run_context["args"]
        payload.update({key: _sanitize(value) for key, value in fields.items()})
        _log_path(now).parent.mkdir(parents=True, exist_ok=True)
        with _log_path(now).open("a", encoding="utf-8") as file:
            file.write(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n")
    except Exception:
        return


def log_exception(event: str, exc: Exception, *, level: str = "error", **fields: object) -> None:
    """Log an exception with type, message, and traceback."""
    tb = "".join(traceback_module.format_exception(type(exc), exc, exc.__traceback__))
    log_event(
        event,
        level=level,
        error_type=type(exc).__name__,
        error_message=str(exc),
        traceback=tb[:MAX_TRACEBACK_LENGTH],
        **fields,
    )


def _generate_run_id() -> str:
    now = _now()
    return f"{now.strftime('%Y%m%d-%H%M%S')}-{uuid4().hex[:6]}"


def _now() -> datetime:
    return datetime.now(LOG_TIMEZONE)


def _log_path(now: datetime) -> Path:
    log_dir = Path(os.getenv("CONTENT_AGENT_LOG_DIR", str(DEFAULT_LOG_DIR)))
    return log_dir / f"{now.strftime('%Y-%m-%d')}.jsonl"


def _sanitize(value: object) -> object:
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, dict):
        return {str(key): _sanitize(item) for key, item in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [_sanitize(item) for item in value]
    if isinstance(value, BaseException):
        return str(value)
    if isinstance(value, str):
        return value[:MAX_STRING_LENGTH]
    if value is None or isinstance(value, (bool, int, float)):
        return value
    return str(value)[:MAX_STRING_LENGTH]
