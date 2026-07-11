import json
from datetime import datetime
from pathlib import Path
from typing import Any, Literal, TypeVar
from zoneinfo import ZoneInfo

from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator

from src.base.json_utils import call_json_model
from src.base.run_log import log_event


class ImageSample(BaseModel):
    """One image resource made available by a collector."""

    model_config = ConfigDict(extra="allow")

    src: str | None = None
    srcset: str | None = None
    alt: str | None = None
    title: str | None = None
    width: int | None = Field(default=None, ge=0)
    height: int | None = Field(default=None, ge=0)
    index: int | None = Field(default=None, ge=1)


class CommentSample(BaseModel):
    """One visible comment or reply attached to a research note."""

    model_config = ConfigDict(extra="allow")

    author: str | None = None
    text: str = ""
    is_reply: bool = False
    parent_author: str | None = None
    parent_text: str | None = None
    reply_count: int | None = Field(default=None, ge=0)
    is_author_reply: bool = False
    raw_text: str | None = None
    likes: int | None = Field(default=None, ge=0)
    source_index: int | None = Field(default=None, ge=1)
    value_signals: list[str] = Field(default_factory=list)

    @field_validator("value_signals")
    @classmethod
    def clean_value_signals(cls, value: list[str]) -> list[str]:
        return [item.strip() for item in value if item.strip()]


class NoteSample(BaseModel):
    """Shared validated representation of one collected note."""

    model_config = ConfigDict(extra="forbid")

    note_id: str | None = None
    account_name: str = Field(min_length=1)
    author_url: str | None = None
    title: str = Field(min_length=1)
    subtitle: str | None = None
    note_url: str | None = None
    body: str | None = None
    # Compatibility fields for older research artifacts.
    cover_text: str | None = None
    body_excerpt: str | None = None
    hashtags: list[str] = Field(default_factory=list)
    likes: int | None = Field(default=None, ge=0)
    comments: int | None = Field(default=None, ge=0)
    saves: int | None = Field(default=None, ge=0)
    shares: int | None = Field(default=None, ge=0)
    publish_time: str | None = None
    location: str | None = None
    images: list[ImageSample] = Field(default_factory=list)
    video: dict[str, Any] | None = None
    comment_items: list[CommentSample] = Field(default_factory=list)
    collection_meta: dict[str, Any] = Field(default_factory=dict)
    # Compatibility fields for older research artifacts.
    visible_comments: list[str] = Field(default_factory=list)
    observed_signals: list[str] = Field(default_factory=list)

    @field_validator("hashtags", "visible_comments", "observed_signals")
    @classmethod
    def clean_list(cls, value: list[str]) -> list[str]:
        return [item.strip() for item in value if item.strip()]

    @property
    def full_body(self) -> str:
        return (self.body or self.body_excerpt or "").strip()


class AccountSample(BaseModel):
    """Shared validated representation of one collected account."""

    model_config = ConfigDict(extra="forbid")

    account_id: str | None = None
    account_name: str = Field(min_length=1)
    account_url: str | None = None
    avatar_url: str | None = None
    red_id: str | None = None
    ip_location: str | None = None
    bio: str | None = None
    follower_count: int | None = Field(default=None, ge=0)
    following_count: int | None = Field(default=None, ge=0)
    liked_count: int | None = Field(default=None, ge=0)
    positioning_notes: list[str] = Field(default_factory=list)
    seed_keyword: str | None = None
    discovered_from_note: dict[str, Any] = Field(default_factory=dict)
    collection_meta: dict[str, Any] = Field(default_factory=dict)
    notes: list[NoteSample] = Field(default_factory=list)

    @field_validator("positioning_notes")
    @classmethod
    def clean_positioning_notes(cls, value: list[str]) -> list[str]:
        return [item.strip() for item in value if item.strip()]


class ResearchInput(BaseModel):
    """Validated collector payload shared by research workflows."""

    model_config = ConfigDict(extra="forbid")

    platform: str = Field(default="xiaohongshu", min_length=2)
    research_goal: str = Field(min_length=4)
    source: str = Field(default="manual", min_length=2)
    accounts: list[AccountSample] = Field(default_factory=list)
    loose_notes: list[NoteSample] = Field(default_factory=list)
    collector_meta: dict[str, Any] = Field(default_factory=dict)

    @property
    def notes(self) -> list[NoteSample]:
        return [
            *self.loose_notes,
            *(note for account in self.accounts for note in account.notes),
        ]

    @property
    def note_count(self) -> int:
        return len(self.notes)


class ResearchDatasetStats(BaseModel):
    """Deterministic readiness statistics for a research dataset."""

    model_config = ConfigDict(extra="forbid")

    account_count: int = Field(ge=0)
    note_count: int = Field(ge=0)
    complete_note_count: int = Field(ge=0)
    notes_with_body: int = Field(ge=0)
    notes_with_engagement: int = Field(ge=0)
    image_count: int = Field(ge=0)
    comment_item_count: int = Field(ge=0)


class ResearchImageReference(BaseModel):
    """One labeled image passed to a multimodal research model."""

    model_config = ConfigDict(extra="forbid")

    label: str = Field(min_length=2)
    url: str = Field(min_length=4)
    detail: Literal["auto", "low", "high"] = "high"


StructuredModelT = TypeVar("StructuredModelT", bound=BaseModel)


def load_research_input(path: Path | str) -> ResearchInput:
    raw = json.loads(Path(path).read_text(encoding="utf-8"))
    return ResearchInput.model_validate(raw)


def summarize_research_input(research_input: ResearchInput) -> ResearchDatasetStats:
    notes = research_input.notes
    return ResearchDatasetStats(
        account_count=len(research_input.accounts),
        note_count=len(notes),
        complete_note_count=sum(
            1 for note in notes if note.collection_meta.get("complete") is True
        ),
        notes_with_body=sum(1 for note in notes if note.full_body),
        notes_with_engagement=sum(
            1
            for note in notes
            if any(
                value is not None
                for value in (note.likes, note.comments, note.saves, note.shares)
            )
        ),
        image_count=sum(len(note.images) for note in notes),
        comment_item_count=sum(len(note.comment_items) for note in notes),
    )


def load_research_prompt(path: Path | str) -> str:
    prompt_file = Path(path)
    if not prompt_file.exists():
        raise FileNotFoundError(f"Missing prompt file: {prompt_file}")
    prompt = prompt_file.read_text(encoding="utf-8").strip()
    if not prompt:
        raise ValueError(f"Prompt file is empty: {prompt_file}")
    return prompt


def build_multimodal_research_message(
    payload: dict[str, Any],
    image_references: list[ResearchImageReference],
) -> dict[str, Any]:
    """Build one labeled text-and-image user message for a vision-capable model."""
    content: list[dict[str, Any]] = [
        {
            "type": "text",
            "text": json.dumps(payload, ensure_ascii=False, indent=2),
        }
    ]
    for reference in image_references:
        content.extend(
            [
                {
                    "type": "text",
                    "text": f"Multimodal image label: {reference.label}",
                },
                {
                    "type": "image_url",
                    "image_url": {
                        "url": reference.url,
                        "detail": reference.detail,
                    },
                },
            ]
        )
    return {"role": "user", "content": content}


def call_structured_research_model(
    messages: list[dict[str, Any]],
    *,
    output_model: type[StructuredModelT],
    label: str,
    max_schema_attempts: int = 2,
) -> StructuredModelT:
    """Call a research model and retry JSON that fails its business schema."""
    if max_schema_attempts < 1:
        raise ValueError("max_schema_attempts must be >= 1")

    current_messages = list(messages)
    last_error: ValidationError | None = None
    for schema_attempt in range(1, max_schema_attempts + 1):
        parsed = call_json_model(current_messages, label)
        try:
            return output_model.model_validate(parsed)
        except ValidationError as exc:
            last_error = exc
            errors = exc.errors(include_url=False)
            log_event(
                "llm_schema_validation_failed",
                level="warning",
                label=label,
                schema=output_model.__name__,
                schema_attempt=schema_attempt,
                error_count=len(errors),
            )
            if schema_attempt >= max_schema_attempts:
                break
            current_messages = [
                *current_messages,
                {
                    "role": "assistant",
                    "content": json.dumps(parsed, ensure_ascii=False),
                },
                {
                    "role": "user",
                    "content": (
                        "The JSON is valid but does not match the required output schema. "
                        "Correct only the schema violations and return one JSON object. "
                        "Validation errors: "
                        f"{json.dumps(errors, ensure_ascii=False, default=str)}"
                    ),
                },
            ]

    raise ValueError(
        f"{label} output does not match {output_model.__name__}: {last_error}"
    ) from last_error


def save_debug_research_artifact(
    payload: dict[str, Any],
    *,
    output_dir: Path | str,
    filename_label: str,
) -> Path:
    """Persist a research result only when a caller explicitly enables debugging."""
    base_dir = Path(output_dir)
    base_dir.mkdir(parents=True, exist_ok=True)
    now = datetime.now(ZoneInfo("Asia/Shanghai"))
    path = base_dir / f"{now.strftime('%Y-%m-%d-%H%M%S')}-{filename_label}.json"
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return path
