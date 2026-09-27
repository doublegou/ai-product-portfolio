import json
from datetime import datetime
from pathlib import Path
from typing import Any, Literal
from zoneinfo import ZoneInfo

from pydantic import BaseModel, ConfigDict, Field, field_validator

from src.base.memory import load_memory
from src.collect.topic import collect_external_hotspots
from src.research.research_infra import (
    call_structured_research_model,
    load_research_prompt,
)


DAILY_PRODUCTS = (
    "ISS Tracker",
    "BirdTracker",
    "Math Puzzle",
    "Soulnio",
)

PRODUCT_ALIASES = {
    "ISS Tracker": (
        "ISS Tracker",
        "ISS-Tracker",
        "ISS",
        "国际空间站",
        "空间站",
    ),
    "BirdTracker": (
        "BirdTracker",
        "Bird Tracker",
        "观鸟",
        "鸟类",
    ),
    "Math Puzzle": (
        "Math Puzzle",
        "MathPuzzle",
        "Math-Puzzle",
        "数字谜题",
        "数学谜题",
        "交叉算式",
    ),
    "Soulnio": (
        "Soulnio",
        "塔罗",
        "自我探索",
        "时间罗盘",
        "关系星网",
    ),
}

PRODUCT_DISCOVERY_QUERIES = {
    "ISS Tracker": (
        "国际空间站",
        "天文 科普",
        "卫星 夜空",
        "NASA 直播",
        "太空 小众App",
    ),
    "BirdTracker": (
        "观鸟",
        "自然观察",
        "户外散步",
        "鸟类摄影",
        "小众App 自然",
    ),
    "Math Puzzle": (
        "数字谜题",
        "逻辑谜题",
        "益智游戏",
        "睡前放松",
        "小众游戏",
    ),
    "Soulnio": (
        "塔罗 自我探索",
        "情绪整理",
        "关系困惑",
        "自我觉察",
        "疗愈感 产品",
    ),
}

BROAD_HOTSPOT_QUERIES = (
    "生活方式 热点",
    "AI 科技 热点",
    "户外 自然",
    "情绪 关系",
    "天文 国际空间站",
)


class TopicPlan(BaseModel):
    model_config = ConfigDict(extra="forbid")

    product: str = Field(min_length=2)
    topic_source: Literal["broad_hotspot", "related_field"]
    planned_topic: str = Field(min_length=4)
    primary_query: str = Field(min_length=2)
    supporting_queries: list[str] = Field(default_factory=list, max_length=3)
    broad_hotspot_signal: str = Field(min_length=6)
    hotspot_fit_score: float = Field(ge=0, le=10)
    hot_angle_hypothesis: str = Field(min_length=6)
    audience_hypothesis: str = Field(min_length=6)
    trend_opportunity: str = Field(min_length=6)
    related_field_signal: str = Field(min_length=6)
    risk: str = Field(min_length=4)
    reason: str = Field(min_length=6)

    @field_validator("supporting_queries", mode="before")
    @classmethod
    def clean_queries(cls, value: list[str]) -> list[str]:
        cleaned = []
        for item in value:
            item = item.strip()
            if item and item not in cleaned:
                cleaned.append(item)
        return cleaned


def get_daily_products(product: str | None = None) -> list[str]:
    if not product or product == "all":
        return list(DAILY_PRODUCTS)
    if product not in DAILY_PRODUCTS:
        raise ValueError(f"Unknown product: {product}")
    return [product]


def infer_product_from_writing_goal(writing_goal: str | None) -> str | None:
    """Infer an explicitly named product from a writing goal."""
    if not writing_goal:
        return None

    normalized_goal = writing_goal.lower()
    matches = []
    for product, aliases in PRODUCT_ALIASES.items():
        for alias in aliases:
            if alias.lower() in normalized_goal:
                matches.append((product, len(alias)))
                break

    if not matches:
        return None

    matches.sort(key=lambda item: item[1], reverse=True)
    return matches[0][0]


def get_product_discovery_queries(product: str, *, limit: int = 4) -> list[str]:
    queries = PRODUCT_DISCOVERY_QUERIES.get(product)
    if not queries:
        raise ValueError(f"Missing discovery queries for product: {product}")
    return list(queries[:limit])


def get_broad_hotspot_queries(*, limit: int = 6) -> list[str]:
    return list(BROAD_HOTSPOT_QUERIES[:limit])


def discover_topic(
    writing_goal: str | None = None,
    *,
    product: str | None = None,
    output_dir: Path,
    broad_hotspot_samples: dict[str, Any] | None = None,
    broad_hotspot_limit: int = 6,
    broad_hotspot_queries: int = 6,
    related_field_limit: int = 6,
    related_field_queries: int = 4,
) -> dict[str, Any]:
    """Run broad and related-field discovery, then choose today's topic."""
    resolved_product = product or infer_product_from_writing_goal(writing_goal)
    broad_samples = broad_hotspot_samples or collect_broad_hotspot_samples(
        output_dir=output_dir,
        limit=broad_hotspot_limit,
        query_limit=broad_hotspot_queries,
    )
    related_samples = collect_related_field_samples(
        product=resolved_product,
        output_dir=output_dir,
        limit=related_field_limit,
        query_limit=related_field_queries,
    )
    topic_plan = plan_topic(
        writing_goal,
        product=resolved_product,
        broad_hotspot_samples=broad_samples,
        related_field_samples=related_samples,
    )
    return {
        "topic_plan": topic_plan,
        "broad_hotspot_samples": broad_samples,
        "related_field_samples": related_samples,
    }


def plan_topic(
    writing_goal: str | None = None,
    *,
    product: str | None = None,
    broad_hotspot_samples: dict[str, Any] | None = None,
    related_field_samples: dict[str, Any] | None = None,
    prompt_path: Path | str = "skills/topic_researcher.md",
) -> dict[str, Any]:
    """Select today's product topic and plan the final writing research search."""
    if product and product not in DAILY_PRODUCTS:
        raise ValueError(f"Unknown product: {product}")
    goal = (
        writing_goal.strip()
        if writing_goal and writing_goal.strip()
        else "自动选择今天的小红书产品帖选题"
    )
    prompt = load_research_prompt(prompt_path)
    research_payload = {
        "analysis_as_of": datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(),
        "writing_goal": goal,
        "product_constraint": product,
        "broad_hotspot_samples": broad_hotspot_samples or {},
        "related_field_samples": related_field_samples or {},
        "local_memory": load_memory(),
    }

    messages = [
        {
            "role": "system",
            "content": prompt,
        },
        {
            "role": "user",
            "content": json.dumps(research_payload, ensure_ascii=False, indent=2),
        },
    ]
    return call_structured_research_model(
        messages,
        output_model=TopicPlan,
        label="Topic researcher",
    ).model_dump()


def collect_broad_hotspot_samples(
    *,
    output_dir: Path,
    limit: int,
    query_limit: int,
) -> dict[str, Any]:
    queries = get_broad_hotspot_queries(limit=query_limit)
    hotspot_result = collect_external_hotspots(
        limit_per_source=limit,
        google_news_queries=queries,
    )
    return {
        "mode": "broad_hotspot_discovery",
        "source": "external_cross_platform_hotspot_sources",
        "queries": queries,
        "sources": hotspot_result["source_results"],
        "notes": _compact_external_hotspot_items(hotspot_result["items"]),
        "errors": _external_source_errors(hotspot_result["source_results"]),
        "collected_at": hotspot_result["collected_at"],
    }


def collect_related_field_samples(
    *,
    product: str | None,
    output_dir: Path,
    limit: int,
    query_limit: int,
) -> dict[str, Any]:
    if not product:
        return {
            "mode": "manual_or_unspecified_product",
            "notes": [],
            "queries": [],
            "errors": [],
        }

    notes: list[dict[str, Any]] = []
    queries = get_product_discovery_queries(product, limit=query_limit)
    field_result = collect_external_hotspots(
        limit_per_source=limit,
        sources=("google_news_rss",),
        google_news_queries=queries,
    )
    notes.extend(_compact_external_hotspot_items(field_result["items"]))
    return {
        "mode": "related_field_topic_discovery",
        "product": product,
        "source": "external_product_adjacent_field_sources",
        "queries": queries,
        "sources": field_result["source_results"],
        "notes": notes,
        "errors": _external_source_errors(field_result["source_results"]),
        "collected_at": field_result["collected_at"],
    }


def _compact_external_hotspot_items(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {
            "source": item.get("source"),
            "query": item.get("query"),
            "geo": item.get("geo"),
            "title": item.get("title"),
            "summary": item.get("summary"),
            "url": item.get("url"),
            "channel": item.get("channel"),
            "published_at": item.get("published_at"),
            "views": item.get("views"),
        }
        for item in items
        if item.get("title")
    ]


def _external_source_errors(source_results: list[dict[str, Any]]) -> list[str]:
    errors: list[str] = []
    for result in source_results:
        source = result.get("source", "unknown")
        if result.get("status") == "error":
            errors.append(f"{source}: {result.get('error')}")
        for error in result.get("errors", []):
            errors.append(f"{source}: {error}")
        if result.get("status") == "skipped":
            errors.append(f"{source}: skipped - {result.get('reason')}")
    return errors
