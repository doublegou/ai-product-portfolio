import os
import json
import subprocess
import time
from pathlib import Path
from urllib.parse import urlparse
from urllib import error, request

from dotenv import load_dotenv
from openai import OpenAI, OpenAIError

from src.base.run_log import log_event


DEFAULT_MODEL = "deepseek-v4-flash"


def call_llm(
    messages: list[dict[str, str]],
    *,
    label: str | None = None,
    attempt: int | None = None,
) -> str:
    """Call OpenAI and return the assistant text."""
    started_at = time.perf_counter()
    prompt_chars = sum(len(message.get("content", "")) for message in messages)
    load_dotenv(dotenv_path=Path(".env"))

    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        _log_llm_call(
            started_at=started_at,
            label=label,
            attempt=attempt,
            success=False,
            prompt_chars=prompt_chars,
            error_type="RuntimeError",
            error_message="Missing OPENAI_API_KEY. Please set it in .env.",
        )
        raise RuntimeError("Missing OPENAI_API_KEY. Please set it in .env.")

    model = os.getenv("MODEL", DEFAULT_MODEL).strip() or DEFAULT_MODEL
    base_url = os.getenv("OPENAI_BASE_URL", "").strip()
    client_kwargs = {"api_key": api_key}
    if base_url:
        client_kwargs["base_url"] = base_url

    client = OpenAI(**client_kwargs)

    try:
        usage_data: dict[str, int | None] = {}
        try:
            response = client.chat.completions.create(
                model=model,
                messages=messages,
                response_format={"type": "json_object"},
                temperature=0.7,
            )
            content = response.choices[0].message.content
            usage = getattr(response, "usage", None)
            if usage is not None:
                usage_data = {
                    "prompt_tokens": getattr(usage, "prompt_tokens", None),
                    "completion_tokens": getattr(usage, "completion_tokens", None),
                    "total_tokens": getattr(usage, "total_tokens", None),
                }
        except OpenAIError as exc:
            if not base_url:
                raise RuntimeError(f"LLM request failed: {exc}") from exc
            content = _call_openai_compatible_http(
                base_url=base_url,
                api_key=api_key,
                model=model,
                messages=messages,
            )

        if not content:
            raise RuntimeError("LLM returned empty content.")

        _log_llm_call(
            started_at=started_at,
            label=label,
            attempt=attempt,
            success=True,
            prompt_chars=prompt_chars,
            response_chars=len(content),
            model=model,
            base_url=base_url,
            **usage_data,
        )
        return content
    except Exception as exc:
        _log_llm_call(
            started_at=started_at,
            label=label,
            attempt=attempt,
            success=False,
            prompt_chars=prompt_chars,
            model=model,
            base_url=base_url,
            error_type=type(exc).__name__,
            error_message=str(exc),
        )
        raise


def _log_llm_call(
    *,
    started_at: float,
    label: str | None,
    attempt: int | None,
    success: bool,
    prompt_chars: int,
    response_chars: int | None = None,
    model: str | None = None,
    base_url: str | None = None,
    error_type: str | None = None,
    error_message: str | None = None,
    prompt_tokens: int | None = None,
    completion_tokens: int | None = None,
    total_tokens: int | None = None,
) -> None:
    host = urlparse(base_url).netloc if base_url else None
    log_event(
        "llm_call",
        level="info" if success else "error",
        label=label,
        model=model,
        base_url_host=host,
        duration_ms=int((time.perf_counter() - started_at) * 1000),
        attempt=attempt,
        success=success,
        prompt_chars=prompt_chars,
        response_chars=response_chars,
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
        total_tokens=total_tokens,
        error_type=error_type,
        error_message=error_message,
    )


def _call_openai_compatible_http(
    *,
    base_url: str,
    api_key: str,
    model: str,
    messages: list[dict[str, str]],
) -> str:
    """Fallback for OpenAI-compatible providers when the SDK transport fails."""
    url = f"{base_url.rstrip('/')}/chat/completions"
    payload = json.dumps(
        {
            "model": model,
            "messages": messages,
            "response_format": {"type": "json_object"},
            "temperature": 0.7,
        },
        ensure_ascii=False,
    ).encode("utf-8")
    req = request.Request(
        url,
        data=payload,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with request.urlopen(req, timeout=60) as response:
            data = json.loads(response.read().decode("utf-8"))
    except error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"LLM HTTP request failed: HTTP {exc.code}. {body[:500]}"
        ) from exc
    except (error.URLError, TimeoutError) as exc:
        return _call_openai_compatible_curl(
            url=url,
            api_key=api_key,
            payload=payload,
            original_error=exc,
        )
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"LLM HTTP request failed: {exc}") from exc

    try:
        content = data["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError) as exc:
        raise RuntimeError(f"LLM returned unexpected response: {data}") from exc

    if not content:
        raise RuntimeError("LLM returned empty content.")

    return content


def _call_openai_compatible_curl(
    *,
    url: str,
    api_key: str,
    payload: bytes,
    original_error: Exception,
) -> str:
    """Last-resort fallback for providers that work with curl but not Python SSL."""
    command = [
        "curl",
        "-sS",
        "--max-time",
        "60",
        url,
        "-H",
        f"Authorization: Bearer {api_key}",
        "-H",
        "Content-Type: application/json",
        "-d",
        payload.decode("utf-8"),
    ]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(
            "LLM HTTP request failed: "
            f"{original_error}. curl fallback failed: {result.stderr[:500]}"
        )

    try:
        data = json.loads(result.stdout)
        content = data["choices"][0]["message"]["content"]
    except (json.JSONDecodeError, KeyError, IndexError, TypeError) as exc:
        raise RuntimeError(
            f"LLM curl fallback returned unexpected response: {result.stdout[:500]}"
        ) from exc

    if not content:
        raise RuntimeError("LLM returned empty content.")

    return content
