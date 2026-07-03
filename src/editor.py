from typing import Any

from src.json_utils import call_json_model
from src.memory import load_memory


def revise_draft(
    draft: dict[str, Any],
    review: dict[str, Any],
    user_topic: str | None = None,
) -> dict[str, Any]:
    """Revise a draft according to reviewer feedback."""
    topic_line = user_topic.strip() if user_topic else "No explicit user topic."
    memory = load_memory()
    memory_block = "\n\n".join(
        f"## {filename}\n{content}" for filename, content in memory.items()
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
                "topic, audience, title, hook, body, takeaways, hashtags, cover_text, reason\n\n"
                "# Revision Goals\n"
                "- Fix every concrete issue from the review\n"
                "- Remove or rewrite every blocking issue\n"
                "- Keep all factual claims consistent with Local Memory\n"
                "- Match account/persona.md: independent product creator, not a tool curator or AI workflow blogger\n"
                "- Promote the product through a real user scene, not through hype or fake metrics\n"
                "- Convert unsupported first-person past events into hypothetical or instructional scenarios\n"
                "- Remove specific species, cities, dates, user stories, or product controls unless Local Memory confirms them\n"
                "- Make the body more specific and less generic\n"
                "- Keep the style suitable for Xiaohongshu without hype\n"
                "- Do not add id, created_at, status, review fields, or markdown fences\n\n"
                "# Local Memory\n"
                f"{memory_block}\n\n"
                "# Current Draft\n"
                f"{draft}\n\n"
                "# Review\n"
                f"{review}"
            ),
        },
    ]
    return call_json_model(messages, "Editor")
