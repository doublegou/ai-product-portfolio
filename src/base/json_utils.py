import json
from typing import Any

from src.base.llm import call_llm
from src.base.run_log import log_event


def parse_json_object(raw_output: str, label: str) -> dict[str, Any]:
    """Parse a model response that must be a JSON object."""
    try:
        parsed = json.loads(raw_output)
    except json.JSONDecodeError as exc:
        raise ValueError(f"{label} output is not valid JSON. Raw output:\n{raw_output}") from exc

    if not isinstance(parsed, dict):
        raise ValueError(f"{label} output must be a JSON object.")

    return parsed


def call_json_model(
    messages: list[dict[str, str]],
    label: str,
    max_attempts: int = 2,
) -> dict[str, Any]:
    """Call the model and retry once if the response is not valid JSON."""
    current_messages = list(messages)
    last_error: ValueError | None = None

    for attempt in range(1, max_attempts + 1):
        raw_output = call_llm(current_messages, label=label, attempt=attempt)
        try:
            return parse_json_object(raw_output, label)
        except ValueError as exc:
            last_error = exc
            log_event(
                "llm_json_parse_failed",
                level="warning",
                label=label,
                attempt=attempt,
                response_chars=len(raw_output),
                error_type=type(exc).__name__,
            )
            current_messages = [
                *current_messages,
                {
                    "role": "assistant",
                    "content": raw_output,
                },
                {
                    "role": "user",
                    "content": (
                        "Your previous response was not valid JSON. "
                        "Return the same information as one valid JSON object only. "
                        "Do not add markdown, explanation, or code fences."
                    ),
                },
            ]

    raise last_error or ValueError(f"{label} output is not valid JSON.")
