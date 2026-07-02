import json
from pathlib import Path
from typing import Any

from src.llm import call_llm
from src.memory import load_memory


def generate_draft(
    memory_dir: Path | str = "memory",
    prompt_path: Path | str = "prompts/daily_writer.md",
) -> dict[str, Any]:
    """Generate one draft by combining memory, prompt, and the LLM."""
    memory = load_memory(memory_dir)
    prompt_file = Path(prompt_path)
    if not prompt_file.exists():
        raise FileNotFoundError(f"Missing prompt file: {prompt_file}")

    prompt = prompt_file.read_text(encoding="utf-8").strip()
    if not prompt:
        raise ValueError(f"Prompt file is empty: {prompt_file}")

    memory_block = "\n\n".join(
        f"## {filename}\n{content}" for filename, content in memory.items()
    )
    messages = [
        {
            "role": "system",
            "content": "You are a careful Chinese content writing agent. Return valid JSON only.",
        },
        {
            "role": "user",
            "content": f"{prompt}\n\n# Local Memory\n\n{memory_block}",
        },
    ]

    raw_output = call_llm(messages)
    try:
        parsed = json.loads(raw_output)
    except json.JSONDecodeError as exc:
        raise ValueError(
            "LLM output is not valid JSON. Raw output:\n" + raw_output
        ) from exc

    if not isinstance(parsed, dict):
        raise ValueError("LLM output must be a JSON object.")

    return parsed
