import json
from datetime import datetime
from pathlib import Path
from typing import Any, Literal
from zoneinfo import ZoneInfo

from pydantic import BaseModel, ConfigDict, Field, field_validator

from src.base.json_utils import call_json_model
from src.base.memory import load_memory


class NoteSample(BaseModel):
    model_config = ConfigDict(extra="forbid")

    account_name: str = Field(min_length=1)
    title: str = Field(min_length=1)
    note_url: str | None = None
    cover_text: str | None = None
    body_excerpt: str | None = None
    hashtags: list[str] = Field(default_factory=list)
    likes: int | None = Field(default=None, ge=0)
    comments: int | None = Field(default=None, ge=0)
    saves: int | None = Field(default=None, ge=0)
    publish_time: str | None = None
    visible_comments: list[str] = Field(default_factory=list)
    observed_signals: list[str] = Field(default_factory=list)

    @field_validator("hashtags", "visible_comments", "observed_signals")
    @classmethod
    def clean_list(cls, value: list[str]) -> list[str]:
        return [item.strip() for item in value if item.strip()]


class AccountSample(BaseModel):
    model_config = ConfigDict(extra="forbid")

    account_name: str = Field(min_length=1)
    account_url: str | None = None
    bio: str | None = None
    follower_count: int | None = Field(default=None, ge=0)
    following_count: int | None = Field(default=None, ge=0)
    liked_count: int | None = Field(default=None, ge=0)
    positioning_notes: list[str] = Field(default_factory=list)
    notes: list[NoteSample] = Field(default_factory=list)

    @field_validator("positioning_notes")
    @classmethod
    def clean_positioning_notes(cls, value: list[str]) -> list[str]:
        return [item.strip() for item in value if item.strip()]


class ResearchInput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    platform: Literal["xiaohongshu"] = "xiaohongshu"
    research_goal: str = Field(min_length=4)
    source: str = Field(default="manual")
    accounts: list[AccountSample] = Field(default_factory=list)
    loose_notes: list[NoteSample] = Field(default_factory=list)
    collector_meta: dict[str, Any] = Field(default_factory=dict)

    @property
    def note_count(self) -> int:
        return len(self.loose_notes) + sum(len(account.notes) for account in self.accounts)


class PatternItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    pattern: str = Field(min_length=2)
    evidence: str = Field(min_length=2)
    why_it_works: str = Field(min_length=2)


class NotePatternItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    pattern: str = Field(min_length=2)
    title_mechanism: str = Field(min_length=2)
    hook_mechanism: str = Field(min_length=2)
    body_structure: str = Field(min_length=2)
    visual_or_cover_signal: str = Field(min_length=2)
    evidence: str = Field(min_length=2)


class ProductOpportunity(BaseModel):
    model_config = ConfigDict(extra="forbid")

    product: str = Field(min_length=1)
    opportunity: str = Field(min_length=2)
    example_topic: str = Field(min_length=2)
    risk: str = Field(min_length=2)


class RecommendedTest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    test_name: str = Field(min_length=2)
    hypothesis: str = Field(min_length=2)
    product: str = Field(min_length=1)
    post_angle: str = Field(min_length=2)
    success_signal: str = Field(min_length=2)


class ResearchAnalysis(BaseModel):
    model_config = ConfigDict(extra="forbid")

    platform: Literal["xiaohongshu"]
    research_goal: str = Field(min_length=4)
    sample_size: dict[str, int]
    confidence: Literal["low", "medium", "high"]
    summary: str = Field(min_length=6)
    account_patterns: list[PatternItem] = Field(default_factory=list)
    note_patterns: list[NotePatternItem] = Field(default_factory=list)
    persona_findings: list[str] = Field(default_factory=list)
    traffic_hooks: list[str] = Field(default_factory=list)
    content_formats: list[str] = Field(default_factory=list)
    visual_patterns: list[str] = Field(default_factory=list)
    audience_questions: list[str] = Field(default_factory=list)
    opportunities_for_our_products: list[ProductOpportunity] = Field(default_factory=list)
    recommended_tests: list[RecommendedTest] = Field(default_factory=list)
    do: list[str] = Field(default_factory=list)
    avoid: list[str] = Field(default_factory=list)
    next_research_targets: list[str] = Field(default_factory=list)

    @field_validator(
        "persona_findings",
        "traffic_hooks",
        "content_formats",
        "visual_patterns",
        "audience_questions",
        "do",
        "avoid",
        "next_research_targets",
    )
    @classmethod
    def clean_text_items(cls, value: list[str]) -> list[str]:
        return [item.strip() for item in value if item.strip()]


def load_research_input(path: Path | str) -> ResearchInput:
    raw = json.loads(Path(path).read_text(encoding="utf-8"))
    return ResearchInput.model_validate(raw)


def analyze_research(
    research_input: ResearchInput,
    prompt_path: Path | str = "skills/research_analyzer.md",
) -> dict[str, Any]:
    prompt_file = Path(prompt_path)
    if not prompt_file.exists():
        raise FileNotFoundError(f"Missing prompt file: {prompt_file}")

    prompt = prompt_file.read_text(encoding="utf-8").strip()
    if not prompt:
        raise ValueError(f"Prompt file is empty: {prompt_file}")

    memory = load_memory()
    memory_block = "\n\n".join(
        f"## {filename}\n{content}" for filename, content in memory.items()
    )
    sample_block = json.dumps(
        research_input.model_dump(),
        ensure_ascii=False,
        indent=2,
    )

    messages = [
        {
            "role": "system",
            "content": (
                "You are a strict Xiaohongshu content strategy analyst. "
                "Analyze only the provided samples and return valid JSON only."
            ),
        },
        {
            "role": "user",
            "content": (
                f"{prompt}\n\n"
                "# Our Account And Product Memory\n"
                f"{memory_block}\n\n"
                "# Research Samples\n"
                f"{sample_block}"
            ),
        },
    ]
    parsed = call_json_model(messages, "Research analyzer")
    analysis = ResearchAnalysis.model_validate(parsed).model_dump()
    analysis["sample_size"] = {
        "accounts": len(research_input.accounts),
        "notes": research_input.note_count,
    }
    return analysis


def save_research_report(
    analysis: dict[str, Any],
    output_dir: Path | str = "data/research/reports",
) -> Path:
    base_dir = Path(output_dir)
    base_dir.mkdir(parents=True, exist_ok=True)
    now = datetime.now(ZoneInfo("Asia/Shanghai"))
    path = base_dir / f"{now.strftime('%Y-%m-%d-%H%M%S')}-xiaohongshu-research.json"
    path.write_text(
        json.dumps(analysis, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return path
