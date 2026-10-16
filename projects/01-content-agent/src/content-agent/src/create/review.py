import json
import re
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator

from src.base.json_utils import call_json_model
from src.base.memory import load_memory


PRODUCT_NAMES = {
    "ISS Tracker",
    "BirdTracker",
    "Math Puzzle",
    "Soulnio",
    "Product Universe",
}

UNSUPPORTED_TIME_CLAIMS = (
    "上周",
    "去年",
    "上个月",
    "年初",
    "前几天",
    "某天",
    "那天",
    "三个月前",
    "两周",
    "每天早上",
    "每天运行",
    "已经稳定",
    "10分钟",
    "10 分钟",
    "十分钟",
)

UNSUPPORTED_CAPABILITY_CLAIMS = (
    "不联网",
    "不需要联网",
    "不依赖任何一个在线服务",
    "不依赖在线服务",
    "不依赖云端",
    "不想依赖云端",
    "不依赖任何平台",
    "所有操作都在本机完成",
    "完全离线",
    "离线可读",
    "离线模型",
    "本地模型",
    "没有第三方平台",
    "不看任何人",
    "数据安全性",
    "数据安全",
)

UNSUPPORTED_WORKFLOW_CLAIMS = (
    "人工审查",
    "人工审核",
    "人工审校",
    "人工判断",
    "人工过一遍",
    "人来审核",
)

UNSUPPORTED_PERSONAL_CLAIMS = (
    "我不是技术背景",
    "试过几个大厂",
    "试过很多",
    "我出门",
    "我打开了手机",
    "我打开了",
    "我确认",
    "回家后",
    "回来后",
)

UNSUPPORTED_PRODUCT_CLAIMS = (
    "已上架",
    "App Store 下载",
    "下载量",
    "评分",
    "用户评价",
    "官方合作",
    "NASA 官方",
    "NASA官方",
    "官方认证",
    "一定能看到",
    "保证看到",
    "裸眼可见",
    "按颜色",
    "按大小",
    "颜色筛选",
    "大小筛选",
)

UNSUPPORTED_NUMERIC_CLAIM_PATTERNS = (
    (re.compile(r"\d+\s*(秒|分钟|小时|天|周|个月|年)"), "Unsupported concrete time claim"),
    (re.compile(r"\d+\s*圈"), "Unsupported concrete orbit/count claim"),
)


class Draft(BaseModel):
    model_config = ConfigDict(extra="forbid")

    product: str = Field(min_length=2)
    post_archetype: str = Field(min_length=2)
    target_scene: str = Field(min_length=6)
    traffic_hook: str = Field(min_length=6)
    topic: str = Field(min_length=2)
    audience: str = Field(min_length=4)
    title: str = Field(min_length=4)
    hook: str = Field(min_length=12)
    body: str = Field(min_length=300)
    takeaways: list[str] = Field(min_length=3, max_length=5)
    hashtags: list[str] = Field(min_length=4)
    cover_text: str = Field(min_length=2, max_length=16)
    reason: str = Field(min_length=5)

    @field_validator(
        "product",
        "post_archetype",
        "target_scene",
        "traffic_hook",
        "topic",
        "audience",
        "title",
        "hook",
        "body",
        "cover_text",
        "reason",
    )
    @classmethod
    def text_must_not_be_blank(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("field cannot be blank")
        return cleaned

    @field_validator("product")
    @classmethod
    def product_must_be_known(cls, value: str) -> str:
        aliases = {
            "ISS": "ISS Tracker",
            "ISS-Tracker": "ISS Tracker",
            "Bird Tracker": "BirdTracker",
            "MathPuzzle": "Math Puzzle",
            "Product-Universe": "Product Universe",
        }
        normalized = aliases.get(value.strip(), value.strip())
        if normalized not in PRODUCT_NAMES:
            raise ValueError(f"product must be one of: {', '.join(sorted(PRODUCT_NAMES))}")
        return normalized

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


class Review(BaseModel):
    model_config = ConfigDict(extra="forbid")

    overall_score: float = Field(ge=0, le=10)
    safety_score: float = Field(ge=0, le=10)
    publishability_score: float = Field(ge=0, le=10)
    virality_score: float = Field(ge=0, le=10)
    specificity_score: float = Field(ge=0, le=10)
    persona_score: float = Field(ge=0, le=10)
    title_score: float = Field(ge=0, le=10)
    cover_score: float = Field(ge=0, le=10)
    hook_score: float = Field(ge=0, le=10)
    save_value_score: float = Field(ge=0, le=10)
    comment_potential_score: float = Field(ge=0, le=10)
    differentiation_score: float = Field(ge=0, le=10)
    passed: bool
    summary: str = Field(min_length=6)
    strengths: list[str] = Field(min_length=1)
    issues: list[str] = Field(default_factory=list)
    improvement_issues: list[str] = Field(default_factory=list)
    blocking_issues: list[str] = Field(default_factory=list)
    revision_brief: str = Field(min_length=6)

    @field_validator("strengths", "issues", "improvement_issues", "blocking_issues")
    @classmethod
    def clean_items(cls, value: list[str]) -> list[str]:
        return [item.strip() for item in value if item.strip()]


def validate_draft(raw_draft: dict[str, Any], banned_phrases: list[str]) -> dict[str, Any]:
    """Validate draft structure and banned phrases, then return a clean dict."""
    draft = Draft.model_validate(raw_draft)
    searchable_text = "\n".join(
        [
            draft.product,
            draft.post_archetype,
            draft.target_scene,
            draft.traffic_hook,
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


def find_quality_guard_issues(draft: dict[str, Any]) -> list[str]:
    """Find unsupported factual claims before model review."""
    searchable_text = "\n".join(
        str(value) for value in draft.values() if isinstance(value, (str, list))
    )
    issues: list[str] = []

    for phrase in UNSUPPORTED_TIME_CLAIMS:
        if phrase in searchable_text:
            issues.append(f"Unsupported time or usage claim: {phrase}")

    for phrase in UNSUPPORTED_CAPABILITY_CLAIMS:
        if phrase in searchable_text:
            issues.append(f"Unsupported capability or privacy claim: {phrase}")

    for phrase in UNSUPPORTED_WORKFLOW_CLAIMS:
        if phrase in searchable_text:
            issues.append(f"Unsupported workflow claim: {phrase}")

    for phrase in UNSUPPORTED_PERSONAL_CLAIMS:
        if phrase in searchable_text:
            issues.append(f"Unsupported personal claim: {phrase}")

    for phrase in UNSUPPORTED_PRODUCT_CLAIMS:
        if phrase in searchable_text:
            issues.append(f"Unsupported product marketing claim: {phrase}")

    for pattern, label in UNSUPPORTED_NUMERIC_CLAIM_PATTERNS:
        for match in pattern.finditer(searchable_text):
            issues.append(f"{label}: {match.group(0)}")

    return issues


def review_draft(
    draft: dict[str, Any],
    user_topic: str | None = None,
    research_brief: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Ask the model to review the draft against publishing standards."""
    topic_line = user_topic.strip() if user_topic else "No explicit user topic."
    memory = load_memory()
    memory_block = "\n\n".join(
        f"## {filename}\n{content}" for filename, content in memory.items()
    )
    research_block = ""
    if research_brief:
        research_block = (
            "# Fresh Platform Research Brief\n"
            f"{json.dumps(research_brief, ensure_ascii=False, indent=2)}\n\n"
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
                "- Treat safety, persona, specificity, publishability, and virality as parts of one unified review\n"
                "- product must match one product in Local Memory, unless the post intentionally covers the whole product universe\n"
                "- post_archetype, target_scene, and traffic_hook must be specific and useful for later performance review\n"
                "- Title must create a concrete reason to click through scene, person, problem, contrast, or curiosity; avoid generic product names\n"
                "- Cover text must be short, visual, and understandable in one glance; it should not merely repeat the title\n"
                "- Hook must name a real reader moment, sharp observation, contradiction, or curiosity gap in the first 1-2 sentences\n"
                "- Body must have concrete context, clear logic, actionable steps, a boundary, and a reason to save or discuss\n"
                "- The draft must have natural comment potential: a question, contrast, choice, relatable scene, or series continuation without begging for engagement\n"
                "- The draft must be differentiated from generic app recommendation posts and from obvious AI copy\n"
                "- Voice sounds like a thoughtful creator, not generic AI copy\n"
                "- Voice matches account/persona.md: independent product creator, not a tool curator or AI workflow blogger\n"
                "- The post promotes a real product or product scene from memory/products when the user topic implies one\n"
                "- When Fresh Platform Research Brief is provided, the draft should use its transferable mechanisms without copying sampled posts\n"
                "- Claims are grounded and do not invent facts or results\n"
                "- Facts must be consistent with Local Memory, especially account/persona.md, account/editorial_rules.md, and memory/products\n"
                "- Unsupported first-person past events, specific species, cities, dates, user stories, or unlisted product controls are blocking issues\n"
                "- Scenario writing is acceptable only when framed as hypothetical or instructional, such as 比如, 想象一个场景, or 你可以这样用\n"
                "- App Store, downloads, ratings, user reviews, revenue, official partnerships, and guaranteed outcomes are blocking issues unless Local Memory confirms them\n"
                "- Do not ask the editor to add specific dates, durations, metrics, or personal history unless Local Memory provides them\n"
                "- The post is useful enough to save as an approved draft\n\n"
                "# Passing Standard\n"
                "Pass only when overall_score >= 8.6, virality_score >= 8.2, "
                "publishability_score >= 8.4, safety_score >= 9.2, "
                "title_score >= 8.0, hook_score >= 8.0, save_value_score >= 7.8, "
                "differentiation_score >= 7.8, and blocking_issues is empty. "
                "Any factual mismatch with Local Memory is a blocking issue. "
                "Safety is a gate; use improvement_issues and revision_brief mostly to improve spreadability, "
                "clickability, save value, specificity, and comment potential.\n\n"
                "# Output JSON Schema\n"
                "{\n"
                '  "overall_score": 8.4,\n'
                '  "safety_score": 9.4,\n'
                '  "publishability_score": 8.4,\n'
                '  "virality_score": 8.0,\n'
                '  "specificity_score": 8.6,\n'
                '  "persona_score": 8.8,\n'
                '  "title_score": 8.2,\n'
                '  "cover_score": 8.0,\n'
                '  "hook_score": 8.3,\n'
                '  "save_value_score": 8.1,\n'
                '  "comment_potential_score": 7.9,\n'
                '  "differentiation_score": 8.0,\n'
                '  "passed": true,\n'
                '  "summary": "one sentence review summary",\n'
                '  "strengths": ["..."],\n'
                '  "issues": ["..."],\n'
                '  "improvement_issues": ["..."],\n'
                '  "blocking_issues": [],\n'
                '  "revision_brief": "specific instructions for the editor, prioritizing spreadability after safety"\n'
                "}\n\n"
                "# Local Memory\n"
                f"{memory_block}\n\n"
                f"{research_block}"
                "# Draft\n"
                f"{draft}"
            ),
        },
    ]
    parsed = call_json_model(messages, "Reviewer")
    return Review.model_validate(parsed).model_dump()
