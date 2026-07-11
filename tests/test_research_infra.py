import unittest
from typing import Literal
from unittest.mock import patch

from pydantic import BaseModel, ConfigDict

from src.research.research_infra import (
    ResearchImageReference,
    ResearchInput,
    build_multimodal_research_message,
    call_structured_research_model,
    summarize_research_input,
)


class _SchemaResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: Literal["ok"]


class ResearchInfraTests(unittest.TestCase):
    def test_builds_labeled_multimodal_message(self) -> None:
        message = build_multimodal_research_message(
            {"mode": "note_analysis"},
            [
                ResearchImageReference(
                    label="sample_1_image_1",
                    url="https://example.com/image.jpg",
                )
            ],
        )

        self.assertEqual(message["role"], "user")
        self.assertEqual(message["content"][0]["type"], "text")
        self.assertEqual(message["content"][1]["text"], "Multimodal image label: sample_1_image_1")
        self.assertEqual(message["content"][2]["type"], "image_url")

    def test_validates_rich_collector_payload_and_summarizes_it(self) -> None:
        research_input = ResearchInput.model_validate(
            {
                "platform": "xiaohongshu",
                "research_goal": "研究观鸟内容",
                "source": "test_collector",
                "accounts": [],
                "loose_notes": [
                    {
                        "note_id": "note-1",
                        "account_name": "作者",
                        "title": "观鸟入门",
                        "body": "这是完整正文",
                        "likes": 800,
                        "images": [
                            {
                                "src": "https://example.com/cover.jpg",
                                "width": 1080,
                                "height": 1440,
                                "index": 1,
                            }
                        ],
                        "comment_items": [
                            {
                                "author": "读者",
                                "text": "适合新手吗？",
                                "value_signals": ["question"],
                            }
                        ],
                        "collection_meta": {"complete": True},
                    }
                ],
                "collector_meta": {},
            }
        )

        stats = summarize_research_input(research_input)

        self.assertEqual(research_input.note_count, 1)
        self.assertEqual(stats.note_count, 1)
        self.assertEqual(stats.complete_note_count, 1)
        self.assertEqual(stats.notes_with_body, 1)
        self.assertEqual(stats.notes_with_engagement, 1)
        self.assertEqual(stats.image_count, 1)
        self.assertEqual(stats.comment_item_count, 1)

    @patch("src.research.research_infra.log_event")
    @patch("src.research.research_infra.call_json_model")
    def test_structured_call_retries_schema_errors(
        self,
        call_json_model,
        _log_event,
    ) -> None:
        call_json_model.side_effect = [
            {"status": "wrong"},
            {"status": "ok"},
        ]

        result = call_structured_research_model(
            [{"role": "system", "content": "test"}],
            output_model=_SchemaResult,
            label="test researcher",
        )

        self.assertEqual(result.status, "ok")
        self.assertEqual(call_json_model.call_count, 2)


if __name__ == "__main__":
    unittest.main()
