from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator

from src.json_utils import call_json_model
from src.memory import load_memory


class Review(BaseModel):
    model_config = ConfigDict(extra="forbid")

    overall_score: float = Field(ge=0, le=10)
    passed: bool
    summary: str = Field(min_length=6)
    strengths: list[str] = Field(min_length=1)
    issues: list[str] = Field(default_factory=list)
    blocking_issues: list[str] = Field(default_factory=list)
    revision_brief: str = Field(min_length=6)

    @field_validator("strengths", "issues", "blocking_issues")
    @classmethod
    def clean_items(cls, value: list[str]) -> list[str]:
        return [item.strip() for item in value if item.strip()]


def review_draft(draft: dict[str, Any], user_topic: str | None = None) -> dict[str, Any]:
    """Ask the model to review the draft against publishing standards."""
    topic_line = user_topic.strip() if user_topic else "No explicit user topic."
    memory = load_memory()
    memory_block = "\n\n".join(
        f"## {filename}\n{content}" for filename, content in memory.items()
    )
    messages = [
        {
            "role": "system",
            "content": (
                "You are a strict senior Chinese content editor. "
                "Review Xiaohongshu drafts for usefulness, specificity, voice, and publishability. "
                "Return valid JSON only."
            ),
        },
        {
            "role": "user",
            "content": (
                "# User Topic\n"
                f"{topic_line}\n\n"
                "# Review Rubric\n"
                "- Title is specific and clickable without being exaggerated\n"
                "- Hook names a real problem or sharp observation\n"
                "- Body has concrete context, clear logic, and actionable steps\n"
                "- Voice sounds like a thoughtful creator, not generic AI copy\n"
                "- Voice matches account/persona.md: independent product creator, not a tool curator or AI workflow blogger\n"
                "- The post promotes a real product or product scene from memory/products when the user topic implies one\n"
                "- Claims are grounded and do not invent facts or results\n"
                "- Facts must be consistent with Local Memory, especially account/persona.md, account/editorial_rules.md, and memory/products\n"
                "- Unsupported first-person past events, specific species, cities, dates, user stories, or unlisted product controls are blocking issues\n"
                "- Scenario writing is acceptable only when framed as hypothetical or instructional, such as 比如, 想象一个场景, or 你可以这样用\n"
                "- App Store, downloads, ratings, user reviews, revenue, official partnerships, and guaranteed outcomes are blocking issues unless Local Memory confirms them\n"
                "- Do not ask the editor to add specific dates, durations, metrics, or personal history unless Local Memory provides them\n"
                "- The post is useful enough to save as an approved draft\n\n"
                "# Passing Standard\n"
                "Pass only when overall_score >= 8.2 and blocking_issues is empty. "
                "Any factual mismatch with Local Memory is a blocking issue.\n\n"
                "# Output JSON Schema\n"
                "{\n"
                '  "overall_score": 8.4,\n'
                '  "passed": true,\n'
                '  "summary": "one sentence review summary",\n'
                '  "strengths": ["..."],\n'
                '  "issues": ["..."],\n'
                '  "blocking_issues": [],\n'
                '  "revision_brief": "specific instructions for the editor"\n'
                "}\n\n"
                "# Local Memory\n"
                f"{memory_block}\n\n"
                "# Draft\n"
                f"{draft}"
            ),
        },
    ]
    parsed = call_json_model(messages, "Reviewer")
    return Review.model_validate(parsed).model_dump()
