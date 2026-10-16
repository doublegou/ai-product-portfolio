import json
import time
from datetime import datetime
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any, Literal
from zoneinfo import ZoneInfo

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from src.base.memory import load_memory
from src.base.run_log import log_event
from src.collect.xhs import collect_xhs_deep_search_current_chrome
from src.research.research_infra import (
    NoteSample,
    ResearchImageReference,
    ResearchInput,
    build_multimodal_research_message,
    call_structured_research_model,
    load_research_input,
    load_research_prompt,
    save_debug_research_artifact,
    summarize_research_input,
)
from src.research.topic_research import TopicPlan


NOTE_ANALYSIS_BATCH_SIZE = 1
MAX_BODY_CHARS = 8000
MAX_COMMENTS_PER_NOTE = 24
MAX_IMAGES_PER_NOTE = 16

PRODUCT_MEMORY_FILES = {
    "ISS Tracker": "products/isstracker.md",
    "BirdTracker": "products/birdtracker.md",
    "Math Puzzle": "products/mathpuzzle.md",
    "Soulnio": "products/soulnio.md",
}


class NoteInsight(BaseModel):
    """Ephemeral business analysis of one high-performing note."""

    model_config = ConfigDict(extra="forbid")

    sample_index: int = Field(ge=1)
    content_archetype: str = Field(min_length=2)
    performance_profile: Literal[
        "like_led",
        "save_led",
        "comment_led",
        "share_led",
        "mixed",
        "unknown",
    ]
    information_promise: str = Field(min_length=4)
    title_mechanism: str = Field(min_length=4)
    cover_mechanism: str = Field(min_length=4)
    visual_sequence_mechanism: str = Field(min_length=4)
    opening_mechanism: str = Field(min_length=4)
    body_structure: list[str] = Field(min_length=2, max_length=8)
    audience_value: str = Field(min_length=4)
    interaction_mechanism: str = Field(min_length=4)
    likely_success_drivers: list[str] = Field(min_length=1, max_length=6)
    transferable_mechanisms: list[str] = Field(min_length=1, max_length=6)
    risks: list[str] = Field(default_factory=list, max_length=6)

    @field_validator(
        "body_structure",
        "likely_success_drivers",
        "transferable_mechanisms",
        "risks",
        mode="before",
    )
    @classmethod
    def clean_items(cls, value: list[str]) -> list[str]:
        return _clean_string_list(value)


class NoteInsightBatch(BaseModel):
    model_config = ConfigDict(extra="forbid")

    insights: list[NoteInsight] = Field(min_length=1)

    @model_validator(mode="after")
    def sample_indices_must_be_unique(self) -> "NoteInsightBatch":
        indices = [item.sample_index for item in self.insights]
        if len(indices) != len(set(indices)):
            raise ValueError("note insight sample_index values must be unique")
        return self


class TrafficStrategy(BaseModel):
    model_config = ConfigDict(extra="forbid")

    click_driver: str = Field(min_length=4)
    reading_driver: str = Field(min_length=4)
    save_driver: str = Field(min_length=4)
    comment_driver: str = Field(min_length=4)
    share_driver: str = Field(min_length=4)


class BodySectionGuidance(BaseModel):
    model_config = ConfigDict(extra="forbid")

    order: int = Field(ge=1)
    purpose: str = Field(min_length=4)
    guidance: str = Field(min_length=6)


class WritingGuidance(BaseModel):
    """The writing-research business output for one planned post."""

    model_config = ConfigDict(extra="forbid")

    platform: Literal["xiaohongshu"] = "xiaohongshu"
    product: str = Field(min_length=2)
    planned_topic: str = Field(min_length=4)
    traffic_thesis: str = Field(min_length=8)
    traffic_strategy: TrafficStrategy
    target_audience: str = Field(min_length=4)
    target_scene: str = Field(min_length=6)
    recommended_content_archetype: str = Field(min_length=2)
    core_angle: str = Field(min_length=6)
    title_brief: str = Field(min_length=8)
    cover_brief: str = Field(min_length=8)
    visual_brief: str = Field(min_length=8)
    opening_brief: str = Field(min_length=8)
    body_outline: list[BodySectionGuidance] = Field(min_length=3, max_length=7)
    product_bridge: str = Field(min_length=8)
    value_to_deliver: list[str] = Field(min_length=2, max_length=6)
    interaction_brief: str = Field(min_length=6)
    keyword_strategy: list[str] = Field(min_length=3, max_length=10)
    style_rules: list[str] = Field(min_length=2, max_length=8)
    avoid: list[str] = Field(min_length=2, max_length=8)

    @field_validator(
        "value_to_deliver",
        "keyword_strategy",
        "style_rules",
        "avoid",
        mode="before",
    )
    @classmethod
    def clean_items(cls, value: list[str]) -> list[str]:
        return _clean_string_list(value)

    @model_validator(mode="after")
    def body_orders_must_be_unique(self) -> "WritingGuidance":
        orders = [item.order for item in self.body_outline]
        if len(orders) != len(set(orders)):
            raise ValueError("body outline order values must be unique")
        return self


def run_writing_research(
    topic_plan: dict[str, Any],
    *,
    platform: str = "xhs",
    limit: int = 10,
    min_notes: int = 10,
    max_attempts: int = 5,
    persist_artifacts: bool = False,
    artifact_dir: Path | str = "data/research/writing",
    output_dir: Path | None = None,
) -> dict[str, Any]:
    """Collect samples, then run the writing-specific research workflow."""
    if platform != "xhs":
        raise ValueError(f"Unsupported research platform: {platform}")

    validated_plan = TopicPlan.model_validate(topic_plan).model_dump()
    if persist_artifacts:
        research_dir = Path(output_dir or artifact_dir)
        research_dir.mkdir(parents=True, exist_ok=True)
        return _collect_and_analyze(
            queries=_queries_from_topic_plan(validated_plan),
            topic_plan=validated_plan,
            limit=limit,
            min_notes=min_notes,
            max_attempts=max_attempts,
            output_dir=research_dir,
            persist_artifacts=True,
        )

    if output_dir is not None:
        return _collect_and_analyze(
            queries=_queries_from_topic_plan(validated_plan),
            topic_plan=validated_plan,
            limit=limit,
            min_notes=min_notes,
            max_attempts=max_attempts,
            output_dir=output_dir,
            persist_artifacts=False,
        )

    with TemporaryDirectory(prefix="content-agent-writing-research-") as tmp_dir:
        return _collect_and_analyze(
            queries=_queries_from_topic_plan(validated_plan),
            topic_plan=validated_plan,
            limit=limit,
            min_notes=min_notes,
            max_attempts=max_attempts,
            output_dir=Path(tmp_dir),
            persist_artifacts=False,
        )


def analyze_writing_research(
    topic_plan: dict[str, Any] | TopicPlan,
    research_input: ResearchInput,
    *,
    min_notes: int = 10,
    prompt_path: Path | str = "skills/writing_researcher.md",
) -> dict[str, Any]:
    """Return the final writing guidance for one topic and its detailed samples."""
    return _analyze_writing_research_details(
        topic_plan,
        research_input,
        min_notes=min_notes,
        prompt_path=prompt_path,
    )["writing_guidance"]


def _analyze_writing_research_details(
    topic_plan: dict[str, Any] | TopicPlan,
    research_input: ResearchInput,
    *,
    min_notes: int,
    prompt_path: Path | str,
) -> dict[str, Any]:
    """Run ephemeral note analysis and return guidance plus optional debug details."""
    if min_notes < 1:
        raise ValueError("min_notes must be >= 1")

    plan = (
        topic_plan
        if isinstance(topic_plan, TopicPlan)
        else TopicPlan.model_validate(topic_plan)
    )
    eligible_notes = [
        note for note in research_input.notes if _is_writing_note_ready(note)
    ]
    if len(eligible_notes) < min_notes:
        raise RuntimeError(
            "Writing research samples are not analysis-ready. "
            f"Ready detailed notes: {len(eligible_notes)}/{min_notes}; "
            f"collected notes: {research_input.note_count}."
        )

    prompt = load_research_prompt(prompt_path)
    dataset_stats = summarize_research_input(research_input).model_dump()
    research_context = {
        "research_goal": research_input.research_goal,
        "source": research_input.source,
        "collected_query": research_input.collector_meta.get("keyword"),
        "field_coverage": research_input.collector_meta.get("field_coverage", {}),
    }
    analysis_as_of = datetime.now(ZoneInfo("Asia/Shanghai")).isoformat()
    note_payloads = [
        _compact_writing_note(note, sample_index=index)
        for index, note in enumerate(eligible_notes, start=1)
    ]

    insights: list[NoteInsight] = []
    for start in range(0, len(note_payloads), NOTE_ANALYSIS_BATCH_SIZE):
        batch = note_payloads[start : start + NOTE_ANALYSIS_BATCH_SIZE]
        payload = {
            "mode": "note_analysis",
            "analysis_as_of": analysis_as_of,
            "topic_plan": plan.model_dump(),
            "research_context": research_context,
            "dataset_stats": dataset_stats,
            "notes": batch,
        }
        result = call_structured_research_model(
            [
                {"role": "system", "content": prompt},
                build_multimodal_research_message(
                    payload,
                    _image_references_from_note_payloads(batch),
                ),
            ],
            output_model=NoteInsightBatch,
            label=f"Writing note researcher batch {start // NOTE_ANALYSIS_BATCH_SIZE + 1}",
        )
        _validate_note_insight_coverage(batch, result.insights)
        insights.extend(result.insights)

    synthesis_payload = {
        "mode": "guidance_synthesis",
        "analysis_as_of": analysis_as_of,
        "topic_plan": plan.model_dump(),
        "research_context": research_context,
        "dataset_stats": dataset_stats,
        "note_insights": [item.model_dump() for item in insights],
        "local_memory": _load_relevant_memory(plan.product),
    }
    guidance = call_structured_research_model(
        [
            {"role": "system", "content": prompt},
            {
                "role": "user",
                "content": json.dumps(synthesis_payload, ensure_ascii=False, indent=2),
            },
        ],
        output_model=WritingGuidance,
        label="Writing guidance synthesizer",
    )
    guidance_payload = guidance.model_dump()
    # Topic research is authoritative for these two identity fields.
    guidance_payload["product"] = plan.product
    guidance_payload["planned_topic"] = plan.planned_topic
    guidance = WritingGuidance.model_validate(guidance_payload)

    return {
        "writing_guidance": guidance.model_dump(),
        "dataset_stats": dataset_stats,
        "analyzed_note_count": len(eligible_notes),
        "note_insights": [item.model_dump() for item in insights],
    }


def _queries_from_topic_plan(topic_plan: dict[str, Any]) -> list[str]:
    return [
        topic_plan["primary_query"],
        *topic_plan.get("supporting_queries", []),
    ]


def _collect_and_analyze(
    *,
    queries: list[str],
    topic_plan: dict[str, Any],
    limit: int,
    min_notes: int,
    max_attempts: int,
    output_dir: Path,
    persist_artifacts: bool,
) -> dict[str, Any]:
    current_chrome_error = None
    research_input = None
    input_path = None
    ready_note_count = 0
    max_attempts = max(1, max_attempts)
    attempted_queries: list[str] = []

    for query in queries:
        query = query.strip()
        if not query or query in attempted_queries:
            continue
        attempted_queries.append(query)
        for attempt in range(1, max_attempts + 1):
            try:
                input_path = collect_xhs_deep_search_current_chrome(
                    query,
                    limit=limit,
                    output_dir=output_dir,
                )
                research_input = load_research_input(input_path)
                ready_note_count = sum(
                    1 for note in research_input.notes if _is_writing_note_ready(note)
                )
                log_event(
                    "collect_attempt",
                    level="info" if ready_note_count >= min_notes else "warning",
                    phase="writing_research",
                    platform="xhs",
                    collector="current_chrome_deep",
                    query=query,
                    attempt=attempt,
                    requested_limit=limit,
                    min_notes=min_notes,
                    collected_count=research_input.note_count,
                    analysis_ready_count=ready_note_count,
                    enough_samples=ready_note_count >= min_notes,
                    input_path=input_path,
                )
                if ready_note_count >= min_notes:
                    break
                current_chrome_error = (
                    f"Query '{query}' produced {ready_note_count} analysis-ready "
                    f"notes from {research_input.note_count} collected notes; "
                    f"need at least {min_notes}."
                )
            except RuntimeError as exc:
                current_chrome_error = f"Query '{query}' failed: {exc}"
                log_event(
                    "collect_attempt",
                    level="error",
                    phase="writing_research",
                    platform="xhs",
                    collector="current_chrome",
                    query=query,
                    attempt=attempt,
                    requested_limit=limit,
                    min_notes=min_notes,
                    success=False,
                    error_type=type(exc).__name__,
                    error_message=str(exc),
                )
            if attempt < max_attempts:
                time.sleep(min(3 * attempt, 12))
        if research_input is not None and ready_note_count >= min_notes:
            break

    if research_input is None or input_path is None:
        raise RuntimeError(
            "Could not collect from your logged-in Chrome. "
            f"{current_chrome_error or 'unknown error'}"
        )

    if ready_note_count < min_notes:
        raise RuntimeError(
            "Writing research did not collect enough Xiaohongshu notes. "
            f"Analysis-ready notes: {ready_note_count}/{min_notes}; "
            f"collected notes: {research_input.note_count}. "
            f"Tried {len(attempted_queries)} queries and current Chrome "
            f"{max_attempts} times per query. "
            "Your logged-in Chrome may not be showing search results, or the "
            "collector selector needs updating. "
            f"Current Chrome attempt: {current_chrome_error or 'not used'}"
        )

    research = _analyze_writing_research_details(
        topic_plan,
        research_input,
        min_notes=min_notes,
        prompt_path="skills/writing_researcher.md",
    )
    guidance = research["writing_guidance"]
    debug_payload = {
        "topic_plan": topic_plan,
        "dataset_stats": research["dataset_stats"],
        "note_insights": research["note_insights"],
        "writing_guidance": guidance,
    }
    report_path = (
        save_debug_research_artifact(
            debug_payload,
            output_dir=output_dir,
            filename_label="xiaohongshu-writing-guidance",
        )
        if persist_artifacts
        else None
    )
    return {
        "input_path": str(input_path) if persist_artifacts else None,
        "report_path": str(report_path) if report_path else None,
        "sample_count": research_input.note_count,
        "topic_plan": topic_plan,
        "used_query": research_input.collector_meta.get("keyword"),
        "attempted_queries": attempted_queries,
        "writing_guidance": guidance,
        "analysis": {
            "topic_plan": topic_plan,
            "writing_guidance": guidance,
        },
    }


def _is_writing_note_ready(note: NoteSample) -> bool:
    if note.collection_meta.get("complete") is False:
        return False
    if not note.full_body:
        return False
    return any(
        value is not None
        for value in (note.likes, note.comments, note.saves, note.shares)
    )


def _compact_writing_note(note: NoteSample, *, sample_index: int) -> dict[str, Any]:
    return {
        "sample_index": sample_index,
        "title": note.title,
        "subtitle": note.subtitle,
        "body": note.full_body[:MAX_BODY_CHARS],
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
                "multimodal_label": _image_label(sample_index, image_position),
            }
            for image_position, image in enumerate(
                note.images[:MAX_IMAGES_PER_NOTE],
                start=1,
            )
        ],
        "video": note.video,
        "comments": [
            comment.model_dump(exclude_none=True)
            for comment in note.comment_items[:MAX_COMMENTS_PER_NOTE]
        ],
    }


def _image_references_from_note_payloads(
    note_payloads: list[dict[str, Any]],
) -> list[ResearchImageReference]:
    references: list[ResearchImageReference] = []
    for note in note_payloads:
        for image in note.get("images", []):
            url = str(image.get("src") or "").strip()
            label = str(image.get("multimodal_label") or "").strip()
            if url and label:
                references.append(
                    ResearchImageReference(label=label, url=url, detail="high")
                )
    return references


def _image_label(sample_index: int, image_position: int) -> str:
    return f"sample_{sample_index}_image_{image_position}"


def _validate_note_insight_coverage(
    note_payloads: list[dict[str, Any]],
    insights: list[NoteInsight],
) -> None:
    expected = {int(item["sample_index"]) for item in note_payloads}
    actual = {item.sample_index for item in insights}
    if actual != expected:
        raise ValueError(
            "Writing note analysis did not cover the requested samples. "
            f"Expected indices: {sorted(expected)}; got: {sorted(actual)}."
        )


def _load_relevant_memory(product: str) -> dict[str, str]:
    memory = load_memory()
    product_file = PRODUCT_MEMORY_FILES.get(product)
    return {
        filename: content
        for filename, content in memory.items()
        if filename.startswith("account/")
        or filename.startswith("platforms/")
        or filename == product_file
    }


def _clean_string_list(value: list[str]) -> list[str]:
    cleaned: list[str] = []
    for item in value:
        item = item.strip()
        if item and item not in cleaned:
            cleaned.append(item)
    return cleaned
