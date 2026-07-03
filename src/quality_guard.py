import re
from typing import Any


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
