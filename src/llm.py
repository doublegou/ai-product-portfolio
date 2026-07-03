import os
import json
import subprocess
from pathlib import Path
from urllib import error, request

from dotenv import load_dotenv
from openai import OpenAI, OpenAIError


DEFAULT_MODEL = "deepseek-v4-flash"


def call_llm(messages: list[dict[str, str]]) -> str:
    """Call OpenAI and return the assistant text."""
    load_dotenv(dotenv_path=Path(".env"))

    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("Missing OPENAI_API_KEY. Please set it in .env.")

    model = os.getenv("MODEL", DEFAULT_MODEL).strip() or DEFAULT_MODEL
    base_url = os.getenv("OPENAI_BASE_URL", "").strip()
    client_kwargs = {"api_key": api_key}
    if base_url:
        client_kwargs["base_url"] = base_url

    client = OpenAI(**client_kwargs)

    try:
        response = client.chat.completions.create(
            model=model,
            messages=messages,
            response_format={"type": "json_object"},
            temperature=0.7,
        )
    except OpenAIError as exc:
        if not base_url:
            raise RuntimeError(f"LLM request failed: {exc}") from exc
        return _call_openai_compatible_http(
            base_url=base_url,
            api_key=api_key,
            model=model,
            messages=messages,
        )

    content = response.choices[0].message.content
    if not content:
        raise RuntimeError("LLM returned empty content.")

    return content


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
