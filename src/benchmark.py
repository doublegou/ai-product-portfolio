import json
from datetime import datetime
from pathlib import Path
from typing import Any, Literal
from zoneinfo import ZoneInfo

from pydantic import BaseModel, ConfigDict, Field, field_validator

from src.json_utils import call_json_model
from src.memory import load_memory


class BenchmarkAnalysis(BaseModel):
    model_config = ConfigDict(extra="forbid")

    platform: Literal["xiaohongshu"]
    corpus_size: dict[str, int]
    ready_for_persona: bool
    confidence: Literal["low", "medium", "high"]
    summary: str = Field(min_length=6)
    account_archetypes: list[str] = Field(default_factory=list)
    winning_persona_patterns: list[str] = Field(default_factory=list)
    note_level_patterns: list[str] = Field(default_factory=list)
    title_methods: list[str] = Field(default_factory=list)
    hook_methods: list[str] = Field(default_factory=list)
    body_structures: list[str] = Field(default_factory=list)
    cover_methods: list[str] = Field(default_factory=list)
    comment_triggers: list[str] = Field(default_factory=list)
    final_persona: str = Field(min_length=6)
    writing_rules: list[str] = Field(default_factory=list)
    acceptance_standards: list[str] = Field(default_factory=list)
    rejection_rules: list[str] = Field(default_factory=list)
    product_mapping: list[str] = Field(default_factory=list)
    open_questions: list[str] = Field(default_factory=list)

    @field_validator(
        "account_archetypes",
        "winning_persona_patterns",
        "note_level_patterns",
        "title_methods",
        "hook_methods",
        "body_structures",
        "cover_methods",
        "comment_triggers",
        "writing_rules",
        "acceptance_standards",
        "rejection_rules",
        "product_mapping",
        "open_questions",
    )
    @classmethod
    def clean_items(cls, value: list[str]) -> list[str]:
        return [item.strip() for item in value if item.strip()]


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

    review_type: Literal["weekly_benchmark_strategy_review"]
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
    benchmark_analysis_path: str | None = None
    corpus_path: str | None = None
    generated_at: str
    status: Literal["pending_human_decision", "approved", "rejected"] = "pending_human_decision"
    summary: str = Field(min_length=6)
    evidence: list[StrategyEvidence] = Field(default_factory=list)
    recommendations: list[StrategyRecommendation] = Field(default_factory=list)
    proposed_memory_changes: list[ProposedMemoryChange] = Field(default_factory=list)
    do_not_change: list[str] = Field(default_factory=list)
    human_decision_notes: str = ""

    @field_validator("do_not_change")
    @classmethod
    def clean_do_not_change(cls, value: list[str]) -> list[str]:
        return [item.strip() for item in value if item.strip()]


def load_benchmark_corpus(path: Path | str) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def validate_benchmark_threshold(
    corpus: dict[str, Any],
    *,
    min_creators: int = 100,
    min_notes_per_creator: int = 10,
) -> dict[str, int]:
    accounts = corpus.get("accounts", [])
    creator_count = len(accounts)
    note_count = sum(len(account.get("notes", [])) for account in accounts)
    qualified_creator_count = sum(
        1 for account in accounts if len(account.get("notes", [])) >= min_notes_per_creator
    )
    target_note_count = min_creators * min_notes_per_creator
    return {
        "creator_count": creator_count,
        "note_count": note_count,
        "qualified_creator_count": qualified_creator_count,
        "target_creators": min_creators,
        "target_notes": target_note_count,
    }


def analyze_benchmark_corpus(
    corpus: dict[str, Any],
    *,
    min_creators: int = 100,
    min_notes_per_creator: int = 10,
    allow_partial: bool = False,
    batch_size: int = 5,
    prompt_path: Path | str = "prompts/benchmark_analyzer.md",
) -> dict[str, Any]:
    threshold = validate_benchmark_threshold(
        corpus,
        min_creators=min_creators,
        min_notes_per_creator=min_notes_per_creator,
    )
    if not allow_partial and (
        threshold["creator_count"] < threshold["target_creators"]
        or threshold["qualified_creator_count"] < threshold["target_creators"]
    ):
        raise RuntimeError(
            "Benchmark corpus is not large enough for final persona/rules. "
            f"Creators: {threshold['creator_count']}/{threshold['target_creators']}; "
            f"qualified creators with >= {min_notes_per_creator} notes: "
            f"{threshold['qualified_creator_count']}/{threshold['target_creators']}; "
            f"notes: {threshold['note_count']}/{threshold['target_notes']}."
        )

    prompt_file = Path(prompt_path)
    if not prompt_file.exists():
        raise FileNotFoundError(f"Missing prompt file: {prompt_file}")
    prompt = prompt_file.read_text(encoding="utf-8").strip()
    if not prompt:
        raise ValueError(f"Prompt file is empty: {prompt_file}")

    accounts = corpus.get("accounts", [])
    if len(accounts) > batch_size:
        batch_analyses = []
        for start in range(0, len(accounts), batch_size):
            batch_accounts = accounts[start : start + batch_size]
            batch_corpus = {
                **corpus,
                "accounts": batch_accounts,
                "coverage": {
                    **corpus.get("coverage", {}),
                    "creator_count": len(batch_accounts),
                    "note_count": sum(len(account.get("notes", [])) for account in batch_accounts),
                    "batch_index": len(batch_analyses) + 1,
                },
            }
            batch_analyses.append(
                _call_benchmark_model(
                    prompt=prompt,
                    payload={
                        "mode": "batch_analysis",
                        "threshold": threshold,
                        "corpus": _compact_corpus(batch_corpus),
                    },
                )
            )

        final_analysis = _call_benchmark_model(
            prompt=prompt,
            payload={
                "mode": "final_synthesis_from_batches",
                "threshold": threshold,
                "batch_analyses": batch_analyses,
                "product_memory": load_memory(),
            },
        )
        final_analysis["batch_reports"] = batch_analyses
        final_analysis["corpus_size"] = {
            "creators": threshold["creator_count"],
            "qualified_creators": threshold["qualified_creator_count"],
            "notes": threshold["note_count"],
        }
        return final_analysis

    analysis = _call_benchmark_model(
        prompt=prompt,
        payload={
            "mode": "single_pass_analysis",
            "threshold": threshold,
            "corpus": _compact_corpus(corpus),
            "product_memory": load_memory(),
        },
    )
    analysis["corpus_size"] = {
        "creators": threshold["creator_count"],
        "qualified_creators": threshold["qualified_creator_count"],
        "notes": threshold["note_count"],
    }
    return analysis


def _call_benchmark_model(*, prompt: str, payload: dict[str, Any]) -> dict[str, Any]:
    memory = load_memory()
    memory_block = "\n\n".join(
        f"## {filename}\n{content}" for filename, content in memory.items()
    )

    messages = [
        {
            "role": "system",
            "content": (
                "You are a strict Chinese social content strategist. "
                "Infer account positioning and writing rules only from the provided corpus. "
                "Return valid JSON only."
            ),
        },
        {
            "role": "user",
            "content": (
                f"{prompt}\n\n"
                "# Current Product Memory\n"
                f"{memory_block}\n\n"
                "# Analysis Payload\n"
                f"{json.dumps(payload, ensure_ascii=False, indent=2)}"
            ),
        },
    ]
    parsed = call_json_model(messages, "Benchmark analyzer")
    return BenchmarkAnalysis.model_validate(parsed).model_dump()


def _compact_corpus(corpus: dict[str, Any]) -> dict[str, Any]:
    compact_accounts = []
    for account in corpus.get("accounts", []):
        compact_notes = []
        for note in account.get("notes", []):
            body = note.get("detail_body") or note.get("body_excerpt") or ""
            compact_notes.append(
                {
                    "title": note.get("title"),
                    "body_excerpt": body[:700],
                    "hashtags": note.get("hashtags") or note.get("detail_hashtags") or [],
                    "likes": note.get("likes"),
                    "comments": note.get("comments"),
                    "saves": note.get("saves"),
                    "cover_text": note.get("cover_text"),
                    "visible_comments": note.get("visible_comments", [])[:3],
                }
            )
        compact_accounts.append(
            {
                "account_name": account.get("account_name"),
                "bio": account.get("bio"),
                "follower_count": account.get("follower_count"),
                "liked_count": account.get("liked_count"),
                "seed_keyword": account.get("seed_keyword"),
                "notes": compact_notes,
            }
        )
    return {
        "platform": corpus.get("platform"),
        "corpus_type": corpus.get("corpus_type"),
        "research_goal": corpus.get("research_goal"),
        "coverage": corpus.get("coverage"),
        "accounts": compact_accounts,
    }


def save_benchmark_analysis(
    analysis: dict[str, Any],
    output_dir: Path | str = "data/research/benchmark",
) -> Path:
    base_dir = Path(output_dir)
    base_dir.mkdir(parents=True, exist_ok=True)
    now = datetime.now(ZoneInfo("Asia/Shanghai"))
    path = base_dir / f"{now.strftime('%Y-%m-%d-%H%M%S')}-benchmark-analysis.json"
    path.write_text(json.dumps(analysis, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


def generate_strategy_review(
    analysis: dict[str, Any],
    *,
    corpus_path: str | None = None,
    analysis_path: str | None = None,
    trigger: str = "weekly",
    trigger_reason: str = "Weekly benchmark review.",
    prompt_path: Path | str = "prompts/strategy_reviewer.md",
) -> dict[str, Any]:
    prompt_file = Path(prompt_path)
    if not prompt_file.exists():
        raise FileNotFoundError(f"Missing prompt file: {prompt_file}")
    prompt = prompt_file.read_text(encoding="utf-8").strip()
    if not prompt:
        raise ValueError(f"Prompt file is empty: {prompt_file}")

    memory = load_memory()
    messages = [
        {
            "role": "system",
            "content": (
                "You are a strict content strategy reviewer. "
                "Create a human-reviewable strategy change proposal. "
                "Do not directly rewrite memory files. Return valid JSON only."
            ),
        },
        {
            "role": "user",
            "content": (
                f"{prompt}\n\n"
                "# Current Memory\n"
                f"{json.dumps(memory, ensure_ascii=False, indent=2)}\n\n"
                "# Benchmark Analysis\n"
                f"{json.dumps(analysis, ensure_ascii=False, indent=2)}\n\n"
                "# Trigger\n"
                f"trigger: {trigger}\n"
                f"trigger_reason: {trigger_reason}\n\n"
                "# Paths\n"
                f"corpus_path: {corpus_path or ''}\n"
                f"analysis_path: {analysis_path or ''}"
            ),
        },
    ]
    parsed = call_json_model(messages, "Strategy reviewer")
    parsed["generated_at"] = datetime.now(ZoneInfo("Asia/Shanghai")).isoformat()
    parsed["benchmark_analysis_path"] = analysis_path
    parsed["corpus_path"] = corpus_path
    parsed["trigger"] = trigger
    parsed["trigger_reason"] = trigger_reason
    parsed["status"] = "pending_human_decision"
    return StrategyReview.model_validate(parsed).model_dump()


def save_strategy_review(
    review: dict[str, Any],
    output_dir: Path | str = "data/strategy_reviews",
) -> Path:
    base_dir = Path(output_dir)
    base_dir.mkdir(parents=True, exist_ok=True)
    now = datetime.now(ZoneInfo("Asia/Shanghai"))
    path = base_dir / f"{now.strftime('%Y-%m-%d-%H%M%S')}-strategy-review.json"
    path.write_text(json.dumps(review, ensure_ascii=False, indent=2), encoding="utf-8")
    return path
