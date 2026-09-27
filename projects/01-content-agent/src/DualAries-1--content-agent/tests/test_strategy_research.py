import json
import unittest
from unittest.mock import patch

from src.research.strategy_research import (
    CreatorStrategyInsight,
    CreatorStrategyInsightBatch,
    StrategyGuidance,
    StrategyReview,
    analyze_strategy_corpus,
    generate_strategy_review,
)


def _corpus(creator_count: int = 2, notes_per_creator: int = 2) -> dict:
    return {
        "platform": "xiaohongshu",
        "corpus_type": "creator_strategy_research",
        "research_goal": "研究成熟创作者的长期内容策略",
        "source": "test_collector",
        "requirements": {},
        "coverage": {},
        "accounts": [
            {
                "account_id": f"creator-{creator_index}",
                "account_name": f"创作者{creator_index}",
                "bio": "长期分享自然观察和产品方法",
                "follower_count": 10000 + creator_index,
                "positioning_notes": ["自然观察", "实用方法"],
                "notes": [
                    {
                        "note_id": f"creator-{creator_index}-note-{note_index}",
                        "account_name": f"创作者{creator_index}",
                        "title": f"自然观察方法{note_index}",
                        "body": "从具体场景进入，再给出一套可以复用的方法。" * 4,
                        "hashtags": ["#自然观察", "#方法"],
                        "likes": 1000 + note_index,
                        "comments": 100 + note_index,
                        "saves": 1200 + note_index,
                        "publish_time": "2026-07-01",
                        "images": [
                            {
                                "src": (
                                    "https://example.com/"
                                    f"{creator_index}-{note_index}.jpg"
                                ),
                                "width": 1080,
                                "height": 1440,
                                "index": 1,
                            }
                        ],
                        "comment_items": [
                            {
                                "author": "读者",
                                "text": "这个方法适合新手吗？",
                                "value_signals": ["question"],
                            }
                        ],
                        "collection_meta": {"complete": True},
                    }
                    for note_index in range(1, notes_per_creator + 1)
                ],
            }
            for creator_index in range(1, creator_count + 1)
        ],
        "rejected_creators": [],
        "collector_meta": {},
    }


def _creator_insight(creator_index: int) -> CreatorStrategyInsight:
    return CreatorStrategyInsight.model_validate(
        {
            "creator_index": creator_index,
            "account_archetype": "垂直兴趣方法型创作者",
            "positioning": "用具体自然观察场景持续提供可执行的方法",
            "trust_source": "长期稳定输出真实场景、方法和边界",
            "target_audience": "希望低门槛开始自然观察的新手",
            "content_pillars": ["场景观察", "入门方法"],
            "recurring_formats": ["场景指南", "步骤清单"],
            "title_patterns": ["具体场景", "明确问题"],
            "cover_patterns": ["场景主体明确", "短文字说明任务"],
            "visual_storytelling_patterns": ["首图建立场景", "后续图片分步说明"],
            "hook_patterns": ["从读者瞬间进入", "先问题后答案"],
            "body_patterns": ["场景到方法", "步骤到边界"],
            "interaction_patterns": ["新手提问", "经验补充"],
            "strengths_to_transfer": ["稳定场景", "可复用方法"],
            "risks_to_avoid": ["不能复制创作者个人经历"],
        }
    )


def _strategy_guidance() -> StrategyGuidance:
    pillar = lambda name, products: {
        "name": name,
        "strategic_role": "建立账号长期稳定且可识别的内容方向",
        "audience_value": "为读者持续提供具体场景和可复用方法",
        "suitable_products": products,
    }
    mapping = lambda product: {
        "product": product,
        "content_role": "用真实使用场景承接账号长期内容承诺",
        "recommended_angles": ["具体使用场景", "轻量入门方法"],
        "avoid": ["避免夸大结果"],
    }
    return StrategyGuidance.model_validate(
        {
            "platform": "xiaohongshu",
            "corpus_size": {"creators": 2, "qualified_creators": 2, "notes": 4},
            "ready_for_persona": True,
            "confidence": "high",
            "summary": "账号应通过具体场景和可复用方法建立长期信任",
            "strategy_thesis": "把好奇心和轻量观察转化成可执行的小产品使用场景",
            "final_persona": "持续把好奇心做成小产品的独立产品创作者",
            "account_promise": "持续提供具体、有边界并且可以立刻尝试的小产品场景",
            "target_audience": "喜欢观察、轻量思考和自我探索的普通用户",
            "content_pillars": [
                pillar("观察世界", ["ISS Tracker", "BirdTracker"]),
                pillar("轻量思考", ["Math Puzzle"]),
                pillar("自我探索", ["Soulnio"]),
            ],
            "persona_rules": ["产品场景优先", "创作者判断适度出现", "不做工具合集"],
            "title_rules": ["使用具体场景", "提供点击理由", "避免夸张承诺"],
            "cover_rules": ["主体单一", "文字简短", "与标题分工"],
            "visual_rules": ["首图建立任务", "图片顺序推进", "保持信息密度"],
            "hook_rules": ["从读者瞬间进入", "先问题后功能", "快速建立相关性"],
            "body_rules": ["一个核心角度", "包含动作步骤", "说明产品边界"],
            "interaction_rules": ["使用自然选择题", "鼓励经验补充", "不乞求互动"],
            "product_mapping": [
                mapping("ISS Tracker"),
                mapping("BirdTracker"),
                mapping("Math Puzzle"),
                mapping("Soulnio"),
            ],
            "acceptance_standards": ["产品准确", "场景具体", "方法可执行", "视觉有分工"],
            "rejection_rules": ["拒绝工具合集", "拒绝虚构经历", "拒绝夸张结果", "拒绝功能堆砌"],
            "open_questions": ["不同内容支柱的发布比例仍需验证"],
        }
    )


class StrategyResearchTests(unittest.TestCase):
    @patch("src.research.strategy_research.load_memory", return_value={})
    @patch("src.research.strategy_research.load_research_prompt", return_value="review skill")
    @patch("src.research.strategy_research.call_structured_research_model")
    def test_strategy_review_uses_skill_and_authoritative_trigger_fields(
        self,
        call_model,
        _load_prompt,
        _load_memory,
    ) -> None:
        call_model.return_value = StrategyReview.model_validate(
            {
                "review_type": "weekly_strategy_research_review",
                "trigger": "weekly",
                "trigger_reason": "placeholder",
                "corpus_path": None,
                "generated_at": "placeholder",
                "status": "pending_human_decision",
                "summary": "策略方向可以进入人工审批",
                "evidence": [],
                "recommendations": [],
                "proposed_memory_changes": [],
                "do_not_change": ["产品事实边界"],
                "human_decision_notes": "",
            }
        )

        result = generate_strategy_review(
            _strategy_guidance().model_dump(),
            corpus_path="corpus.json",
            trigger="manual",
            trigger_reason="Manual strategy check",
        )

        self.assertEqual(result["trigger"], "manual")
        self.assertEqual(result["trigger_reason"], "Manual strategy check")
        self.assertEqual(result["corpus_path"], "corpus.json")
        _load_prompt.assert_called_once_with("skills/strategy_researcher.md")

    @patch("src.research.strategy_research.load_memory")
    @patch("src.research.strategy_research.load_research_prompt")
    @patch("src.research.strategy_research.call_structured_research_model")
    def test_creator_insights_are_ephemeral_and_images_are_multimodal(
        self,
        call_model,
        load_prompt,
        load_memory,
    ) -> None:
        load_prompt.return_value = "strategy skill"
        load_memory.return_value = {"account/persona.md": "current persona"}

        def fake_call(messages, *, output_model, label, max_schema_attempts=2):
            user_content = messages[-1]["content"]
            payload_text = (
                user_content[0]["text"]
                if isinstance(user_content, list)
                else user_content
            )
            payload = json.loads(payload_text)
            if output_model is CreatorStrategyInsightBatch:
                self.assertTrue(
                    any(block.get("type") == "image_url" for block in user_content)
                )
                return CreatorStrategyInsightBatch(
                    insights=[
                        _creator_insight(account["creator_index"])
                        for account in payload["accounts"]
                    ]
                )
            self.assertIs(output_model, StrategyGuidance)
            return _strategy_guidance()

        call_model.side_effect = fake_call

        result = analyze_strategy_corpus(
            _corpus(),
            min_creators=2,
            min_notes_per_creator=2,
            batch_size=1,
        )

        self.assertTrue(result["ready_for_persona"])
        self.assertEqual(result["corpus_size"]["notes"], 4)
        self.assertNotIn("creator_insights", result)
        self.assertEqual(call_model.call_count, 3)

    @patch("src.research.strategy_research.load_memory", return_value={})
    @patch("src.research.strategy_research.load_research_prompt", return_value="skill")
    @patch("src.research.strategy_research.call_structured_research_model")
    def test_partial_corpus_is_forced_to_low_confidence(
        self,
        call_model,
        _load_prompt,
        _load_memory,
    ) -> None:
        call_model.side_effect = [
            CreatorStrategyInsightBatch(insights=[_creator_insight(1)]),
            _strategy_guidance(),
        ]

        result = analyze_strategy_corpus(
            _corpus(creator_count=1, notes_per_creator=2),
            min_creators=2,
            min_notes_per_creator=2,
            allow_partial=True,
            batch_size=1,
        )

        self.assertFalse(result["ready_for_persona"])
        self.assertEqual(result["confidence"], "low")
        self.assertEqual(result["corpus_size"]["creators"], 1)


if __name__ == "__main__":
    unittest.main()
