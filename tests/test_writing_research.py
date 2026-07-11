import json
import unittest
from unittest.mock import patch

from src.research.research_infra import ResearchInput
from src.research.writing_research import (
    NoteInsight,
    NoteInsightBatch,
    WritingGuidance,
    analyze_writing_research,
)


def _topic_plan() -> dict:
    return {
        "product": "BirdTracker",
        "topic_source": "related_field",
        "planned_topic": "周末散步观鸟记录",
        "primary_query": "散步 观鸟记录",
        "supporting_queries": [],
        "broad_hotspot_signal": "没有自然且及时的广泛热点连接",
        "hotspot_fit_score": 4.0,
        "hot_angle_hypothesis": "把普通散步转化成一次轻量观察记录",
        "audience_hypothesis": "周末散步时愿意观察自然的新手",
        "trend_opportunity": "户外散步和自然观察适合形成具体场景",
        "related_field_signal": "观鸟入门和自然记录内容提供了相关表达",
        "risk": "避免承诺专业识别结果",
        "reason": "选题和产品能力可以自然连接",
    }


def _research_input(note_count: int = 10) -> ResearchInput:
    return ResearchInput.model_validate(
        {
            "platform": "xiaohongshu",
            "research_goal": "分析周末散步观鸟记录",
            "source": "test_collector",
            "accounts": [],
            "loose_notes": [
                {
                    "note_id": f"note-{index}",
                    "account_name": f"作者{index}",
                    "title": f"观鸟记录方法{index}",
                    "body": "从散步场景进入，给出观察步骤和记录方法。" * 4,
                    "hashtags": ["#观鸟", "#户外散步"],
                    "likes": 500 + index,
                    "comments": 20 + index,
                    "saves": 600 + index,
                    "publish_time": "2026-07-01",
                    "images": [
                        {
                            "src": f"https://example.com/{index}.jpg",
                            "width": 1080,
                            "height": 1440,
                            "index": 1,
                        }
                    ],
                    "comment_items": [
                        {
                            "author": "读者",
                            "text": "新手应该先记什么？",
                            "value_signals": ["question"],
                        }
                    ],
                    "collection_meta": {"complete": True},
                }
                for index in range(1, note_count + 1)
            ],
            "collector_meta": {},
        }
    )


def _guidance() -> WritingGuidance:
    return WritingGuidance.model_validate(
        {
            "platform": "xiaohongshu",
            "product": "BirdTracker",
            "planned_topic": "周末散步观鸟记录",
            "traffic_thesis": "用具体散步瞬间吸引新手，再用可执行记录步骤制造收藏价值",
            "traffic_strategy": {
                "click_driver": "让散步时突然注意到鸟的人立刻认出自己的场景",
                "reading_driver": "按照一次散步的顺序逐步展开，不堆砌产品功能",
                "save_driver": "提供下次散步可以直接使用的观察和记录步骤",
                "comment_driver": "用新手最容易忽略的观察点引出经验交流",
                "share_driver": "适合转给刚开始户外散步或自然观察的朋友",
            },
            "target_audience": "刚开始留意身边鸟类的散步爱好者",
            "target_scene": "周末散步时看到鸟却不知道该如何开始记录",
            "recommended_content_archetype": "场景化新手指南",
            "core_angle": "把一次普通散步变成低门槛的观鸟记录",
            "title_brief": "用周末散步和不知道怎么记录的具体瞬间建立点击理由",
            "cover_brief": "用散步环境和清晰短句让读者一眼看懂观鸟记录任务",
            "visual_brief": "首图建立场景，后续图片依次展示观察动作、记录步骤和产品承接",
            "opening_brief": "从散步时突然注意到一只鸟却不知道记什么的瞬间进入",
            "body_outline": [
                {"order": 1, "purpose": "建立场景", "guidance": "写出散步中注意到鸟的具体瞬间"},
                {"order": 2, "purpose": "提供方法", "guidance": "给出新手可以执行的观察记录步骤"},
                {"order": 3, "purpose": "连接产品", "guidance": "自然说明 BirdTracker 如何承接记录动作"},
            ],
            "product_bridge": "在记录步骤出现后连接 BirdTracker 的真实记录能力",
            "value_to_deliver": ["一套低门槛观察顺序", "下次散步可复用的记录动作"],
            "interaction_brief": "邀请读者比较自己散步时最先注意到的是声音还是动作",
            "keyword_strategy": ["观鸟入门", "户外散步", "自然观察"],
            "style_rules": ["先写用户场景再写产品", "保持新手友好"],
            "avoid": ["不承诺专业识别", "不编造具体鸟种和用户故事"],
        }
    )


class WritingResearchTests(unittest.TestCase):
    @patch("src.research.writing_research._load_relevant_memory")
    @patch("src.research.writing_research.load_research_prompt")
    @patch("src.research.writing_research.call_structured_research_model")
    def test_generates_only_final_guidance_from_ephemeral_note_insights(
        self,
        call_model,
        load_prompt,
        load_memory,
    ) -> None:
        load_prompt.return_value = "writing skill"
        load_memory.return_value = {"products/birdtracker.md": "product facts"}

        def fake_call(messages, *, output_model, label, max_schema_attempts=2):
            user_content = messages[-1]["content"]
            payload_text = (
                user_content[0]["text"]
                if isinstance(user_content, list)
                else user_content
            )
            payload = json.loads(payload_text)
            if output_model is NoteInsightBatch:
                self.assertTrue(
                    any(block.get("type") == "image_url" for block in user_content)
                )
                return NoteInsightBatch(
                    insights=[
                        NoteInsight(
                            sample_index=note["sample_index"],
                            content_archetype="场景化指南",
                            performance_profile="save_led",
                            information_promise="提供新手可以复用的观察步骤",
                            title_mechanism="用具体散步场景和新手问题建立点击理由",
                            cover_mechanism="用自然场景和短标题建立轻量入门预期",
                            visual_sequence_mechanism="按场景、步骤和记录结果依次推进",
                            opening_mechanism="从看到鸟却不知道如何记录的瞬间进入",
                            body_structure=["建立场景", "给出步骤", "形成行动"],
                            audience_value="降低第一次观鸟记录的行动门槛",
                            interaction_mechanism="用新手问题引出经验讨论",
                            likely_success_drivers=["具体场景", "可收藏步骤"],
                            transferable_mechanisms=["先场景后方法"],
                            risks=["不能复制未证实功能"],
                        )
                        for note in payload["notes"]
                    ]
                )
            self.assertIs(output_model, WritingGuidance)
            return _guidance()

        call_model.side_effect = fake_call

        result = analyze_writing_research(
            _topic_plan(),
            _research_input(),
            min_notes=10,
        )

        self.assertEqual(result["product"], "BirdTracker")
        self.assertEqual(result["planned_topic"], "周末散步观鸟记录")
        self.assertNotIn("note_insights", result)
        self.assertEqual(call_model.call_count, 11)

    def test_rejects_samples_without_enough_complete_notes(self) -> None:
        research_input = _research_input(note_count=2)
        research_input.loose_notes[1].collection_meta["complete"] = False

        with self.assertRaisesRegex(RuntimeError, "Ready detailed notes: 1/2"):
            analyze_writing_research(
                _topic_plan(),
                research_input,
                min_notes=2,
            )


if __name__ == "__main__":
    unittest.main()
