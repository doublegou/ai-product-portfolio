"""Offline regressions for review feedback and bounded acceptance decisions."""
import copy
import unittest
from unittest.mock import patch

from src.create import runtime


def draft():
    return {
        "product": "BirdTracker", "post_archetype": "场景介绍",
        "target_scene": "散步时想了解看到的鸟", "traffic_hook": "从一次观察开始认识鸟类",
        "topic": "观鸟记录", "audience": "刚开始观鸟的人",
        "title": "把一次观察记下来", "hook": "散步时看到一只鸟，可以查资料，也可以整理观察记录。",
        "body": "图鉴提供鸟类资料，地图提供地点线索，相机流程支持保存观察记录。" * 15,
        "takeaways": ["查阅鸟类资料", "寻找观察地点", "保存观察记录"],
        "hashtags": ["#观鸟", "#记录", "#自然", "#散步"],
        "cover_text": "把观察记下来", "reason": "介绍资料中列出的产品能力",
    }


def review(**changes):
    result = {
        "passed": True, "overall_score": 8.6, "safety_score": 9.2,
        "publishability_score": 8.4, "virality_score": 8.2,
        "title_score": 8.0, "hook_score": 8.0,
        "save_value_score": 7.8, "differentiation_score": 7.8,
        "blocking_issues": [], "issues": [],
    }
    result.update(changes)
    return result


class ReviewRuntimeTests(unittest.TestCase):
    def setUp(self):
        # No model or log writes; schema validation and local guards remain real.
        self.generate = self.enterContext(patch.object(runtime, 'generate_draft', return_value=draft()))
        self.revise = self.enterContext(patch.object(runtime, 'revise_draft', return_value=draft()))
        self.review = self.enterContext(patch.object(runtime, 'review_draft', return_value=review()))
        self.enterContext(patch.object(runtime, 'log_event'))

    def test_guard_feedback_preserves_product_topic(self):
        invalid = draft()
        invalid['body'] += '完全离线。'
        self.generate.return_value = invalid
        result = runtime.create_approved_draft(user_topic='BirdTracker 观鸟记录')
        rejected, feedback = self.revise.call_args.args
        self.assertEqual(rejected['product'], 'BirdTracker')
        self.assertTrue(any('完全离线' in x for x in feedback['blocking_issues']))
        self.assertIn("that product's Local Memory", feedback['revision_brief'])
        self.assertNotIn('项目代码、记忆文件和草稿文件在本地管理', feedback['revision_brief'])
        self.assertIn('Do not insert content-agent implementation details', feedback['revision_brief'])
        self.assertEqual(self.revise.call_args.kwargs['user_topic'], 'BirdTracker 观鸟记录')
        self.assertEqual(self.review.call_count, 1)  # Invalid draft skipped model review.
        self.assertEqual(result['iterations'], 2)

    def test_model_pass_cannot_override_minimum_score(self):
        self.review.side_effect = [review(overall_score=8.5), review()]
        result = runtime.create_approved_draft(passing_score=8.2)
        self.assertEqual(result['iterations'], 2)
        self.assertEqual(result['final_score'], 8.6)
        self.revise.assert_called_once()

    def test_blocking_fact_overrides_high_scores(self):
        self.review.return_value = review(overall_score=9.9, blocking_issues=['Unsupported feature'])
        with self.assertRaisesRegex(RuntimeError, 'after 1 rounds'):
            runtime.create_approved_draft(max_rounds=1)
        self.revise.assert_not_called()

    def test_repeated_failures_stop_at_round_limit(self):
        self.review.side_effect = lambda *a, **k: copy.deepcopy(review(passed=False, overall_score=8.0))
        with self.assertRaisesRegex(RuntimeError, 'after 2 rounds'):
            runtime.create_approved_draft(max_rounds=2)
        self.assertEqual(self.review.call_count, 2)
        self.assertEqual(self.revise.call_count, 1)


if __name__ == '__main__':
    unittest.main()
