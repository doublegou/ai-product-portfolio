from typing import Any

from src.create.review import find_quality_guard_issues, review_draft, validate_draft
from src.create.write import generate_draft, revise_draft
from src.base.memory import load_banned_phrases


def create_approved_draft(
    user_topic: str | None = None,
    research_brief: dict[str, Any] | None = None,
    max_rounds: int = 5,
    passing_score: float = 8.6,
) -> dict[str, Any]:
    """Generate, review, revise, and return an approved draft package."""
    banned_phrases = load_banned_phrases()
    draft = validate_draft(
        generate_draft(user_topic=user_topic, research_brief=research_brief),
        banned_phrases,
    )
    review_rounds: list[dict[str, Any]] = []

    for round_index in range(1, max_rounds + 1):
        guard_issues = find_quality_guard_issues(draft)
        if guard_issues:
            review = {
                "overall_score": 6.0,
                "safety_score": 5.0,
                "publishability_score": 6.0,
                "virality_score": 5.8,
                "specificity_score": 6.0,
                "persona_score": 6.5,
                "title_score": 6.0,
                "cover_score": 6.0,
                "hook_score": 6.0,
                "save_value_score": 5.5,
                "comment_potential_score": 5.5,
                "differentiation_score": 5.5,
                "passed": False,
                "summary": "Local quality guard found unsupported factual claims.",
                "strengths": [],
                "issues": guard_issues,
                "improvement_issues": [
                    "Fix factual grounding before optimizing title, hook, or spreadability."
                ],
                "blocking_issues": guard_issues,
                "revision_brief": (
                    "Remove unsupported time, usage, offline, privacy, or capability claims. "
                    "Do not say this project is fully offline or independent of online services. "
                    "Use this grounded replacement when needed: "
                    "'项目代码、记忆文件和草稿文件在本地管理，模型推理调用在线 API。' "
                    "Rewrite with grounded statements based on Local Memory and the user topic."
                ),
            }
        else:
            review = review_draft(
                draft,
                user_topic=user_topic,
                research_brief=research_brief,
            )
        review["round"] = round_index
        review_rounds.append(review)

        blocking_issues = review.get("blocking_issues", [])
        if (
            review["passed"]
            and review["overall_score"] >= max(passing_score, 8.6)
            and review.get("safety_score", 0) >= 9.2
            and review.get("publishability_score", 0) >= 8.4
            and review.get("virality_score", 0) >= 8.2
            and review.get("title_score", 0) >= 8.0
            and review.get("hook_score", 0) >= 8.0
            and review.get("save_value_score", 0) >= 7.8
            and review.get("differentiation_score", 0) >= 7.8
            and not blocking_issues
        ):
            return {
                "draft": draft,
                "review_rounds": review_rounds,
                "final_score": review["overall_score"],
                "iterations": round_index,
            }

        if round_index < max_rounds:
            draft = validate_draft(
                revise_draft(
                    draft,
                    review,
                    user_topic=user_topic,
                    research_brief=research_brief,
                ),
                banned_phrases,
            )

    final_review = review_rounds[-1]
    raise RuntimeError(
        "Draft did not pass review after "
        f"{max_rounds} rounds. Final score: {final_review['overall_score']}. "
        f"Issues: {'; '.join(final_review.get('issues', []))}"
    )
