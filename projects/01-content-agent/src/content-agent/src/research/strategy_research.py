import json
from datetime import datetime
from pathlib import Path
from typing import Any, Literal
from zoneinfo import ZoneInfo

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from src.base.memory import load_memory
from src.research.research_infra import (
    AccountSample,
    ResearchImageReference,
    build_multimodal_research_message,
    call_structured_research_model,
    load_research_prompt,
)


MAX_STRATEGY_BODY_CHARS = 8000
MAX_STRATEGY_COMMENTS_PER_NOTE = 24
MAX_STRATEGY_IMAGES_PER_NOTE = 16
STRATEGY_PRODUCTS = {
    "ISS Tracker",
    "BirdTracker",
    "Math Puzzle",
    "Soulnio",
}


class CreatorStrategyInsight(BaseModel):
    """Ephemeral analysis of one creator and the creator's detailed notes."""

    model_config = ConfigDict(extra="forbid")

    creator_index: int = Field(ge=1)
    account_archetype: str = Field(min_length=4)
    positioning: str = Field(min_length=6)
    trust_source: str = Field(min_length=6)
    target_audience: str = Field(min_length=4)
    content_pillars: list[str] = Field(min_length=2, max_length=8)
    recurring_formats: list[str] = Field(min_length=2, max_length=8)
    title_patterns: list[str] = Field(min_length=2, max_length=8)
    cover_patterns: list[str] = Field(min_length=2, max_length=8)
    visual_storytelling_patterns: list[str] = Field(min_length=2, max_length=8)
    hook_patterns: list[str] = Field(min_length=2, max_length=8)
    body_patterns: list[str] = Field(min_length=2, max_length=8)
    interaction_patterns: list[str] = Field(min_length=2, max_length=8)
    strengths_to_transfer: list[str] = Field(min_length=2, max_length=8)
    risks_to_avoid: list[str] = Field(min_length=1, max_length=8)

    @field_validator(
        "content_pillars",
        "recurring_formats",
        "title_patterns",
        "cover_patterns",
        "visual_storytelling_patterns",
        "hook_patterns",
        "body_patterns",
        "interaction_patterns",
        "strengths_to_transfer",
        "risks_to_avoid",
        mode="before",
    )
    @classmethod
    def clean_items(cls, value: list[str]) -> list[str]:
        return _clean_string_list(value)


class CreatorStrategyInsightBatch(BaseModel):
    model_config = ConfigDict(extra="forbid")

    insights: list[CreatorStrategyInsight] = Field(min_length=1)

    @model_validator(mode="after")
    def creator_indices_must_be_unique(self) -> "CreatorStrategyInsightBatch":
        indices = [item.creator_index for item in self.insights]
        if len(indices) != len(set(indices)):
            raise ValueError("creator insight indices must be unique")
        return self


class StrategyCorpusSize(BaseModel):
    model_config = ConfigDict(extra="forbid")

    creators: int = Field(ge=0)
    qualified_creators: int = Field(ge=0)
    notes: int = Field(ge=0)


class ContentPillarGuidance(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=2)
    strategic_role: str = Field(min_length=6)
    audience_value: str = Field(min_length=6)
    suitable_products: list[str] = Field(min_length=1, max_length=4)

    @field_validator("suitable_products", mode="before")
    @classmethod
    def clean_products(cls, value: list[str]) -> list[str]:
        return _clean_string_list(value)


class ProductStrategyMapping(BaseModel):
    model_config = ConfigDict(extra="forbid")

    product: str = Field(min_length=2)
    content_role: str = Field(min_length=6)
    recommended_angles: list[str] = Field(min_length=2, max_length=6)
    avoid: list[str] = Field(min_length=1, max_length=5)

    @field_validator("recommended_angles", "avoid", mode="before")
    @classmethod
    def clean_items(cls, value: list[str]) -> list[str]:
        return _clean_string_list(value)


class StrategyGuidance(BaseModel):
    """Long-term strategy research output for the product account."""

    model_config = ConfigDict(extra="forbid")

    platform: Literal["xiaohongshu"] = "xiaohongshu"
    corpus_size: StrategyCorpusSize
    ready_for_persona: bool
    confidence: Literal["low", "medium", "high"]
    summary: str = Field(min_length=8)
    strategy_thesis: str = Field(min_length=10)
    final_persona: str = Field(min_length=8)
    account_promise: str = Field(min_length=8)
    target_audience: str = Field(min_length=6)
    content_pillars: list[ContentPillarGuidance] = Field(min_length=3, max_length=8)
    persona_rules: list[str] = Field(min_length=3, max_length=10)
    title_rules: list[str] = Field(min_length=3, max_length=10)
    cover_rules: list[str] = Field(min_length=3, max_length=10)
    visual_rules: list[str] = Field(min_length=3, max_length=10)
    hook_rules: list[str] = Field(min_length=3, max_length=10)
    body_rules: list[str] = Field(min_length=3, max_length=10)
    interaction_rules: list[str] = Field(min_length=3, max_length=10)
    product_mapping: list[ProductStrategyMapping] = Field(min_length=4, max_length=4)
    acceptance_standards: list[str] = Field(min_length=4, max_length=12)
    rejection_rules: list[str] = Field(min_length=4, max_length=12)
    open_questions: list[str] = Field(default_factory=list, max_length=10)

    @field_validator(
        "persona_rules",
        "title_rules",
        "cover_rules",
        "visual_rules",
        "hook_rules",
        "body_rules",
        "interaction_rules",
        "acceptance_standards",
        "rejection_rules",
        "open_questions",
        mode="before",
    )
    @classmethod
    def clean_items(cls, value: list[str]) -> list[str]:
        return _clean_string_list(value)

    @model_validator(mode="after")
    def product_mapping_must_cover_product_matrix(self) -> "StrategyGuidance":
        products = [item.product for item in self.product_mapping]
        if len(products) != len(set(products)) or set(products) != STRATEGY_PRODUCTS:
            raise ValueError(
                "product_mapping must contain each strategy product exactly once"
            )
        return self


class StrategyEvidence(BaseModel):
    model_config = ConfigDict(extra="forbid")

    finding: str = Field(min_length=2)
    evidence: str = Field(min_length=2)
    confidence: Literal["low", "medium", "high"]


class StrategyRecommendation(BaseModel):
    model_config = ConfigDict(extra="forbid")

    recommendation: str = Field(min_length=2)
    reason: str = Field(min_length=2)
    expected_impact: str = Field(min_length=2)
    risk: str = Field(min_length=2)


class ProposedMemoryChange(BaseModel):
    model_config = ConfigDict(extra="forbid")

    target_file: str = Field(min_length=2)
    change_summary: str = Field(min_length=2)
    reason: str = Field(min_length=2)


class StrategyReview(BaseModel):
    model_config = ConfigDict(extra="forbid")

    review_type: Literal["weekly_strategy_research_review"]
    trigger: Literal[
        "weekly",
        "account_data_change",
        "new_product",
        "platform_style_change",
        "content_underperformance",
        "strategy_hypothesis",
        "manual",
    ] = "weekly"
    trigger_reason: str = Field(min_length=2)
    corpus_path: str | None = None
    generated_at: str
    status: Literal["pending_human_decision", "approved", "rejected"] = (
        "pending_human_decision"
    )
    summary: str = Field(min_length=6)
    evidence: list[StrategyEvidence] = Field(default_factory=list)
    recommendations: list[StrategyRecommendation] = Field(default_factory=list)
    proposed_memory_changes: list[ProposedMemoryChange] = Field(default_factory=list)
    do_not_change: list[str] = Field(default_factory=list)
    human_decision_notes: str = ""

    @field_validator("do_not_change", mode="before")
    @classmethod
    def clean_do_not_change(cls, value: list[str]) -> list[str]:
        return _clean_string_list(value)


def load_strategy_corpus(path: Path | str) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def validate_strategy_corpus_threshold(
    corpus: dict[str, Any],
    *,
    min_creators: int = 50,
    min_notes_per_creator: int = 10,
) -> dict[str, int]:
    accounts = corpus.get("accounts", [])
    creator_count = len(accounts)
    note_count = sum(len(account.get("notes", [])) for account in accounts)
    qualified_creator_count = sum(
        1 for account in accounts if len(account.get("notes", [])) >= min_notes_per_creator
    )
    return {
        "creator_count": creator_count,
        "note_count": note_count,
        "qualified_creator_count": qualified_creator_count,
        "target_creators": min_creators,
        "target_notes": min_creators * min_notes_per_creator,
    }


def analyze_strategy_corpus(
    corpus: dict[str, Any],
    *,
    min_creators: int = 50,
    min_notes_per_creator: int = 10,
    allow_partial: bool = False,
    batch_size: int = 1,
    prompt_path: Path | str = "skills/strategy_researcher.md",
) -> dict[str, Any]:
    """Turn creator-level multimodal research data into StrategyGuidance."""
    if min_creators < 1 or min_notes_per_creator < 1:
        raise ValueError("strategy research thresholds must be >= 1")
    if batch_size < 1:
        raise ValueError("batch_size must be >= 1")

    threshold = validate_strategy_corpus_threshold(
        corpus,
        min_creators=min_creators,
        min_notes_per_creator=min_notes_per_creator,
    )
    threshold_met = (
        threshold["creator_count"] >= threshold["target_creators"]
        and threshold["qualified_creator_count"] >= threshold["target_creators"]
    )
    if not allow_partial and not threshold_met:
        raise RuntimeError(
            "Strategy corpus is not large enough for final persona/rules. "
            f"Creators: {threshold['creator_count']}/{threshold['target_creators']}; "
            f"qualified creators with >= {min_notes_per_creator} notes: "
            f"{threshold['qualified_creator_count']}/{threshold['target_creators']}; "
            f"notes: {threshold['note_count']}/{threshold['target_notes']}."
        )

    all_accounts = [
        AccountSample.model_validate(account) for account in corpus.get("accounts", [])
    ]
    qualified_accounts = [
        account for account in all_accounts if len(account.notes) >= min_notes_per_creator
    ]
    analysis_accounts = qualified_accounts
    if allow_partial and not threshold_met:
        analysis_accounts = [account for account in all_accounts if account.notes]
    if not analysis_accounts:
        raise RuntimeError("Strategy corpus has no creator with analyzable detailed notes.")

    prompt = load_research_prompt(prompt_path)
    analysis_as_of = datetime.now(ZoneInfo("Asia/Shanghai")).isoformat()
    indexed_accounts = list(enumerate(analysis_accounts, start=1))
    creator_insights: list[CreatorStrategyInsight] = []

    for start in range(0, len(indexed_accounts), batch_size):
        batch = indexed_accounts[start : start + batch_size]
        account_payloads = [
            _compact_strategy_account(account, creator_index=creator_index)
            for creator_index, account in batch
        ]
        payload = {
            "mode": "creator_analysis",
            "analysis_as_of": analysis_as_of,
            "corpus_context": {
                "platform": corpus.get("platform"),
                "research_goal": corpus.get("research_goal"),
                "source": corpus.get("source"),
            },
            "threshold": threshold,
            "accounts": account_payloads,
        }
        result = call_structured_research_model(
            [
                {"role": "system", "content": prompt},
                build_multimodal_research_message(
                    payload,
                    _strategy_image_references(account_payloads),
                ),
            ],
            output_model=CreatorStrategyInsightBatch,
            label=f"Strategy creator researcher batch {start // batch_size + 1}",
        )
        _validate_creator_insight_coverage(account_payloads, result.insights)
        creator_insights.extend(result.insights)

    corpus_size = StrategyCorpusSize(
        creators=threshold["creator_count"],
        qualified_creators=threshold["qualified_creator_count"],
        notes=threshold["note_count"],
    )
    synthesis_payload = {
        "mode": "strategy_synthesis",
        "analysis_as_of": analysis_as_of,
        "threshold": threshold,
        "threshold_met": threshold_met,
        "corpus_size": corpus_size.model_dump(),
        "creator_insights": [item.model_dump() for item in creator_insights],
        "local_memory": load_memory(),
    }
    guidance = call_structured_research_model(
        [
            {"role": "system", "content": prompt},
            {
                "role": "user",
                "content": json.dumps(synthesis_payload, ensure_ascii=False, indent=2),
            },
        ],
        output_model=StrategyGuidance,
        label="Strategy guidance synthesizer",
    )
    guidance_payload = guidance.model_dump()
    guidance_payload["corpus_size"] = corpus_size.model_dump()
    if not threshold_met:
        guidance_payload["ready_for_persona"] = False
        guidance_payload["confidence"] = "low"
    return StrategyGuidance.model_validate(guidance_payload).model_dump()


def _compact_strategy_account(
    account: AccountSample,
    *,
    creator_index: int,
) -> dict[str, Any]:
    notes = []
    for note_index, note in enumerate(account.notes, start=1):
        notes.append(
            {
                "note_index": note_index,
                "title": note.title,
                "subtitle": note.subtitle,
                "body": note.full_body[:MAX_STRATEGY_BODY_CHARS],
                "hashtags": note.hashtags,
                "engagement": {
                    "likes": note.likes,
                    "comments": note.comments,
                    "saves": note.saves,
                    "shares": note.shares,
                },
                "publish_time": note.publish_time,
                "images": [
                    {
                        **image.model_dump(exclude_none=True),
                        "multimodal_label": _strategy_image_label(
                            creator_index,
                            note_index,
                            image_position,
                        ),
                    }
                    for image_position, image in enumerate(
                        note.images[:MAX_STRATEGY_IMAGES_PER_NOTE],
                        start=1,
                    )
                ],
                "video": note.video,
                "comments": [
                    comment.model_dump(exclude_none=True)
                    for comment in note.comment_items[:MAX_STRATEGY_COMMENTS_PER_NOTE]
                ],
            }
        )
    return {
        "creator_index": creator_index,
        "account": {
            "account_name": account.account_name,
            "bio": account.bio,
            "follower_count": account.follower_count,
            "following_count": account.following_count,
            "liked_count": account.liked_count,
            "positioning_notes": account.positioning_notes,
            "seed_keyword": account.seed_keyword,
            "profile_image": (
                {
                    "src": account.avatar_url,
                    "multimodal_label": f"creator_{creator_index}_profile_image",
                }
                if account.avatar_url
                else None
            ),
        },
        "notes": notes,
    }


def _strategy_image_references(
    account_payloads: list[dict[str, Any]],
) -> list[ResearchImageReference]:
    references: list[ResearchImageReference] = []
    for account in account_payloads:
        profile_image = account.get("account", {}).get("profile_image") or {}
        profile_url = str(profile_image.get("src") or "").strip()
        profile_label = str(profile_image.get("multimodal_label") or "").strip()
        if profile_url and profile_label:
            references.append(
                ResearchImageReference(
                    label=profile_label,
                    url=profile_url,
                    detail="high",
                )
            )
        for note in account.get("notes", []):
            for image in note.get("images", []):
                url = str(image.get("src") or "").strip()
                label = str(image.get("multimodal_label") or "").strip()
                if url and label:
                    references.append(
                        ResearchImageReference(label=label, url=url, detail="high")
                    )
    return references


def _strategy_image_label(
    creator_index: int,
    note_index: int,
    image_position: int,
) -> str:
    return f"creator_{creator_index}_note_{note_index}_image_{image_position}"


def _validate_creator_insight_coverage(
    account_payloads: list[dict[str, Any]],
    insights: list[CreatorStrategyInsight],
) -> None:
    expected = {int(item["creator_index"]) for item in account_payloads}
    actual = {item.creator_index for item in insights}
    if actual != expected:
        raise ValueError(
            "Strategy creator analysis did not cover the requested creators. "
            f"Expected indices: {sorted(expected)}; got: {sorted(actual)}."
        )


def generate_strategy_review(
    analysis: dict[str, Any],
    *,
    corpus_path: str | None = None,
    trigger: str = "weekly",
    trigger_reason: str = "Weekly strategy research review.",
    prompt_path: Path | str = "skills/strategy_researcher.md",
) -> dict[str, Any]:
    prompt = load_research_prompt(prompt_path)
    payload = {
        "mode": "strategy_review",
        "current_memory": load_memory(),
        "strategy_guidance": StrategyGuidance.model_validate(analysis).model_dump(),
        "trigger": trigger,
        "trigger_reason": trigger_reason,
        "corpus_path": corpus_path,
    }
    review = call_structured_research_model(
        [
            {"role": "system", "content": prompt},
            {
                "role": "user",
                "content": json.dumps(payload, ensure_ascii=False, indent=2),
            },
        ],
        output_model=StrategyReview,
        label="Strategy reviewer",
    )
    review_payload = review.model_dump()
    review_payload.update(
        {
            "generated_at": datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(),
            "corpus_path": corpus_path,
            "trigger": trigger,
            "trigger_reason": trigger_reason,
            "status": "pending_human_decision",
        }
    )
    return StrategyReview.model_validate(review_payload).model_dump()


def save_strategy_result(
    *,
    analysis: dict[str, Any],
    review: dict[str, Any] | None,
    corpus_path: str | None = None,
    trigger: str = "weekly",
    trigger_reason: str = "Weekly strategy research review.",
    output_dir: Path | str = "data/strategy_results",
) -> Path:
    base_dir = Path(output_dir)
    base_dir.mkdir(parents=True, exist_ok=True)
    now = datetime.now(ZoneInfo("Asia/Shanghai"))
    result = {
        "result_type": "strategy_research_result",
        "generated_at": now.isoformat(),
        "trigger": trigger,
        "trigger_reason": trigger_reason,
        "corpus_path": corpus_path,
        "analysis": StrategyGuidance.model_validate(analysis).model_dump(),
        "review": review,
    }
    path = base_dir / f"{now.strftime('%Y-%m-%d-%H%M%S')}-strategy-result.json"
    path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


def _clean_string_list(value: list[str]) -> list[str]:
    cleaned: list[str] = []
    for item in value:
        item = item.strip()
        if item and item not in cleaned:
            cleaned.append(item)
    return cleaned
