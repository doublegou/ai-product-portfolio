import json
from pathlib import Path
from typing import Any

from src.base.json_utils import call_json_model
from src.base.memory import load_memory


def generate_draft(
    user_topic: str | None = None,
    research_brief: dict[str, Any] | None = None,
    memory_dir: Path | str = "memory",
    prompt_path: Path | str = "skills/daily_writer.md",
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
        research_block = (
            "\n\n# Fresh Platform Research Brief\n\n"
            f"{json.dumps(research_brief, ensure_ascii=False, indent=2)}"
        )

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


def revise_draft(
    draft: dict[str, Any],
    review: dict[str, Any],
    user_topic: str | None = None,
    research_brief: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Revise a draft according to reviewer feedback."""
    topic_line = user_topic.strip() if user_topic else "No explicit user topic."
    memory = load_memory()
    memory_block = "\n\n".join(
        f"## {filename}\n{content}" for filename, content in memory.items()
    )
    research_block = ""
    if research_brief:
        research_block = (
            "# Fresh Platform Research Brief\n"
            f"{json.dumps(research_brief, ensure_ascii=False, indent=2)}\n\n"
        )
    messages = [
        {
            "role": "system",
            "content": (
                "You are an excellent Chinese content editor. "
                "Revise the draft according to the review while preserving the required JSON schema. "
                "Return valid JSON only."
            ),
        },
        {
            "role": "user",
            "content": (
                "# User Topic\n"
                f"{topic_line}\n\n"
                "# Required JSON Fields\n"
                "product, post_archetype, target_scene, traffic_hook, topic, audience, "
                "title, hook, body, takeaways, hashtags, cover_text, reason\n\n"
                "# Revision Goals\n"
                "- Fix every concrete issue from the review\n"
                "- Remove or rewrite every blocking issue\n"
                "- Improve virality_score and publishability_score without weakening safety_score\n"
                "- Strengthen title_score, cover_score, hook_score, save_value_score, comment_potential_score, and differentiation_score\n"
                "- Make the title more clickable through a concrete scene, problem, contrast, or curiosity gap without exaggeration\n"
                "- Make cover_text shorter and more visual than the title\n"
                "- Make the opening hook name a reader moment instead of announcing the product too early\n"
                "- Add save value through a small checklist, steps, boundary, or reusable product judgment\n"
                "- Add natural comment potential without begging for comments\n"
                "- Keep product, post_archetype, target_scene, and traffic_hook accurate and specific\n"
                "- Keep all factual claims consistent with Local Memory\n"
                "- Match account/persona.md: independent product creator, not a tool curator or AI workflow blogger\n"
                "- Promote the product through a real user scene, not through hype or fake metrics\n"
                "- Convert unsupported first-person past events into hypothetical or instructional scenarios\n"
                "- Remove specific species, cities, dates, user stories, or product controls unless Local Memory confirms them\n"
                "- Preserve and strengthen useful mechanisms from Fresh Platform Research Brief without copying sampled posts\n"
                "- Make the body more specific, more memorable, and less generic\n"
                "- Keep the style suitable for Xiaohongshu without hype\n"
                "- Do not add id, created_at, status, review fields, or markdown fences\n\n"
                "# Local Memory\n"
                f"{memory_block}\n\n"
                f"{research_block}"
                "# Current Draft\n"
                f"{draft}\n\n"
                "# Review\n"
                f"{review}"
            ),
        },
    ]
    return call_json_model(messages, "Editor")
