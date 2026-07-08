import json
from pathlib import Path
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from src.collect.xhs import collect_xhs_current_chrome
from src.base.json_utils import call_json_model
from src.base.memory import load_memory
from src.research.research_infra import load_research_input


DAILY_PRODUCTS = (
    "ISS Tracker",
    "BirdTracker",
    "Math Puzzle",
    "Soulnio",
)

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
    "今日热点",
    "最近很火",
    "生活方式 热点",
    "AI 科技 热点",
    "户外 自然 热门",
    "情绪 关系 热门",
)


class TopicPlan(BaseModel):
    model_config = ConfigDict(extra="forbid")

    product: str = Field(min_length=2)
    topic_source: Literal["broad_hotspot", "related_field"]
    planned_topic: str = Field(min_length=4)
    primary_query: str = Field(min_length=2)
    supporting_queries: list[str] = Field(min_length=2, max_length=5)
    broad_hotspot_signal: str = Field(min_length=6)
    hotspot_fit_score: float = Field(ge=0, le=10)
    hot_angle_hypothesis: str = Field(min_length=6)
    audience_hypothesis: str = Field(min_length=6)
    trend_opportunity: str = Field(min_length=6)
    related_field_signal: str = Field(min_length=6)
    risk: str = Field(min_length=4)
    reason: str = Field(min_length=6)

    @field_validator("supporting_queries")
    @classmethod
    def clean_queries(cls, value: list[str]) -> list[str]:
        cleaned = []
        for item in value:
            item = item.strip()
            if item and item not in cleaned:
                cleaned.append(item)
        if len(cleaned) < 2:
            raise ValueError("supporting_queries must include at least 2 useful queries")
        return cleaned


def get_daily_products(product: str | None = None) -> list[str]:
    if not product or product == "all":
        return list(DAILY_PRODUCTS)
    if product not in DAILY_PRODUCTS:
        raise ValueError(f"Unknown product: {product}")
    return [product]


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
    broad_samples = broad_hotspot_samples or collect_broad_hotspot_samples(
        output_dir=output_dir,
        limit=broad_hotspot_limit,
        query_limit=broad_hotspot_queries,
    )
    related_samples = collect_related_field_samples(
        product=product,
        output_dir=output_dir,
        limit=related_field_limit,
        query_limit=related_field_queries,
    )
    topic_plan = plan_topic(
        writing_goal,
        product=product,
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
) -> dict[str, Any]:
    """Select today's product topic and plan the final writing research search."""
    if product and product not in DAILY_PRODUCTS:
        raise ValueError(f"Unknown product: {product}")
    goal = (
        writing_goal.strip()
        if writing_goal and writing_goal.strip()
        else "自动选择今天的小红书产品帖选题"
    )
    memory = load_memory()
    memory_block = "\n\n".join(
        f"## {filename}\n{content}" for filename, content in memory.items()
    )

    messages = [
        {
            "role": "system",
            "content": (
                "You are a sharp Chinese content strategist for Xiaohongshu. "
                "Select today's post topic for one product, then plan the focused writing research. "
                "Return valid JSON only."
            ),
        },
        {
            "role": "user",
            "content": (
                "# Writing Goal\n"
                f"{goal}\n\n"
                "# Product Constraint\n"
                f"{product or 'Choose the best matching product from Local Memory.'}\n\n"
                "# Broad Hotspot Samples\n"
                f"{json.dumps(broad_hotspot_samples or {}, ensure_ascii=False, indent=2)}\n\n"
                "# Related Field Samples\n"
                f"{json.dumps(related_field_samples or {}, ensure_ascii=False, indent=2)}\n\n"
                "# Planning Rules\n"
                "- If Product Constraint names a product, you must plan for that product only\n"
                "- There are two topic layers: broad_hotspot means connecting the product upward to a broad current hotspot; related_field means writing directly from product-adjacent field signals\n"
                "- First inspect Broad Hotspot Samples for a timely trend the product can naturally connect to\n"
                "- Then inspect Related Field Samples for product-adjacent signals, user language, content formats, and field heat\n"
                "- If a broad hotspot has hotspot_fit_score >= 8 and low risk, choose topic_source=broad_hotspot\n"
                "- Otherwise choose topic_source=related_field and write from the strongest product-adjacent signal\n"
                "- Do not force a broad hotspot if the connection is weak, sensational, or unsupported by product memory\n"
                "- primary_query should search the final planned topic, not just the product name\n"
                "- supporting_queries should help inspect adjacent formats, user language, and competing angles\n"
                "- Keep the plan grounded in Local Memory and do not invent product facts\n\n"
                "# Output JSON Schema\n"
                "{\n"
                '  "product": "Math Puzzle",\n'
                '  "topic_source": "related_field",\n'
                '  "planned_topic": "睡前轻量数字谜题",\n'
                '  "primary_query": "睡前 数字谜题",\n'
                '  "supporting_queries": ["数学游戏", "睡前放松", "逻辑谜题"],\n'
                '  "broad_hotspot_signal": "没有发现足够自然的大热点连接",\n'
                '  "hotspot_fit_score": 5.8,\n'
                '  "hot_angle_hypothesis": "用睡前放松和轻量脑力题连接产品，而不是写成数学训练",\n'
                '  "audience_hypothesis": "喜欢轻量游戏但不想有考试压力的用户",\n'
                '  "trend_opportunity": "睡前放松和轻量游戏内容适合转化成收藏型帖子",\n'
                '  "related_field_signal": "数字谜题、逻辑题和睡前放松内容都在争夺短休场景",\n'
                '  "risk": "避免承诺提升智力或数学成绩",\n'
                '  "reason": "这个搜索计划能同时观察同类内容、场景语言和用户保存理由"\n'
                "}\n\n"
                "# Local Memory\n"
                f"{memory_block}"
            ),
        },
    ]
    parsed = call_json_model(messages, "Topic discovery planner")
    return TopicPlan.model_validate(parsed).model_dump()


def collect_broad_hotspot_samples(
    *,
    output_dir: Path,
    limit: int,
    query_limit: int,
) -> dict[str, Any]:
    notes: list[dict[str, Any]] = []
    errors: list[str] = []
    queries = get_broad_hotspot_queries(limit=query_limit)
    for query in queries:
        try:
            input_path = collect_xhs_current_chrome(
                query,
                limit=limit,
                output_dir=output_dir,
            )
            research_input = load_research_input(input_path)
            for note in research_input.loose_notes[:limit]:
                notes.append(_compact_discovery_note(query, note))
        except RuntimeError as exc:
            errors.append(f"{query}: {exc}")
    return {
        "mode": "broad_hotspot_discovery",
        "source": "current_chrome_xiaohongshu_broad_search",
        "queries": queries,
        "notes": notes,
        "errors": errors,
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
    errors: list[str] = []
    queries = get_product_discovery_queries(product, limit=query_limit)
    for query in queries:
        try:
            input_path = collect_xhs_current_chrome(
                query,
                limit=limit,
                output_dir=output_dir,
            )
            research_input = load_research_input(input_path)
            for note in research_input.loose_notes[:limit]:
                notes.append(_compact_discovery_note(query, note))
        except RuntimeError as exc:
            errors.append(f"{query}: {exc}")
    return {
        "mode": "related_field_topic_discovery",
        "product": product,
        "queries": queries,
        "notes": notes,
        "errors": errors,
    }


def _compact_discovery_note(query: str, note: Any) -> dict[str, Any]:
    return {
        "query": query,
        "title": note.title,
        "account_name": note.account_name,
        "cover_text": note.cover_text,
        "body_excerpt": note.body_excerpt,
        "likes": note.likes,
        "observed_signals": note.observed_signals,
    }
