from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator


class Draft(BaseModel):
    model_config = ConfigDict(extra="forbid")

    topic: str = Field(min_length=2)
    audience: str = Field(min_length=4)
    title: str = Field(min_length=4)
    hook: str = Field(min_length=12)
    body: str = Field(min_length=300)
    takeaways: list[str] = Field(min_length=3, max_length=5)
    hashtags: list[str] = Field(min_length=4)
    cover_text: str = Field(min_length=2, max_length=16)
    reason: str = Field(min_length=5)

    @field_validator("topic", "audience", "title", "hook", "body", "cover_text", "reason")
    @classmethod
    def text_must_not_be_blank(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("field cannot be blank")
        return cleaned

    @field_validator("takeaways")
    @classmethod
    def takeaways_must_be_useful(cls, value: list[str]) -> list[str]:
        cleaned = [item.strip() for item in value if item.strip()]
        if len(cleaned) < 3:
            raise ValueError("takeaways must include at least 3 items")
        too_short = [item for item in cleaned if len(item) < 4]
        if too_short:
            raise ValueError(f"takeaways are too short: {too_short}")
        return cleaned

    @field_validator("hashtags")
    @classmethod
    def hashtags_must_be_valid(cls, value: list[str]) -> list[str]:
        cleaned = [tag.strip() for tag in value if tag.strip()]
        if len(cleaned) < 4:
            raise ValueError("hashtags must include at least 4 items")
        invalid = [tag for tag in cleaned if not tag.startswith("#")]
        if invalid:
            raise ValueError(f"hashtags must start with #: {invalid}")
        return cleaned


def validate_draft(raw_draft: dict[str, Any], banned_phrases: list[str]) -> dict[str, Any]:
    """Validate structure and banned phrases, then return a clean dict."""
    draft = Draft.model_validate(raw_draft)
    searchable_text = "\n".join(
        [
            draft.topic,
            draft.audience,
            draft.title,
            draft.hook,
            draft.body,
            " ".join(draft.takeaways),
            " ".join(draft.hashtags),
            draft.cover_text,
            draft.reason,
        ]
    )

    found = [phrase for phrase in banned_phrases if phrase and phrase in searchable_text]
    if found:
        raise ValueError(f"Draft contains banned phrases: {', '.join(found)}")

    return draft.model_dump()
