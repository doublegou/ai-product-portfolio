from pathlib import Path
from typing import Any

from src.json_utils import call_json_model
from src.memory import load_memory


def generate_draft(
    user_topic: str | None = None,
    research_brief: dict[str, Any] | None = None,
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
    user_topic_block = ""
    if user_topic and user_topic.strip():
        user_topic_block = f"\n\n# User Topic\n\n{user_topic.strip()}"
    research_block = ""
    if research_brief:
        research_block = f"\n\n# Fresh Platform Research Brief\n\n{research_brief}"

    messages = [
        {
            "role": "system",
            "content": (
                "You are a careful Chinese content editor for Xiaohongshu. "
                "Write practical, specific posts and return valid JSON only."
            ),
        },
        {
            "role": "user",
            "content": (
                f"{prompt}{user_topic_block}{research_block}\n\n"
                f"# Local Memory\n\n{memory_block}"
            ),
        },
    ]

    return call_json_model(messages, "Writer")
