import unittest

from src.research.topic_research import TopicPlan


class TopicResearchTests(unittest.TestCase):
    def test_supporting_queries_are_optional_and_deduplicated(self) -> None:
        plan = TopicPlan.model_validate(
            {
                "product": "BirdTracker",
                "topic_source": "related_field",
                "planned_topic": "周末散步观鸟记录",
                "primary_query": "散步 观鸟记录",
                "supporting_queries": ["观鸟入门", "观鸟入门", "  "],
                "broad_hotspot_signal": "没有自然且及时的广泛热点连接",
                "hotspot_fit_score": 4.0,
                "hot_angle_hypothesis": "把普通散步转化成一次轻量观察记录",
                "audience_hypothesis": "周末散步时愿意观察自然的新手",
                "trend_opportunity": "户外散步和自然观察适合形成具体场景",
                "related_field_signal": "观鸟入门和自然记录内容提供了相关表达",
                "risk": "避免承诺专业识别结果",
                "reason": "选题和产品能力可以自然连接",
            }
        )

        self.assertEqual(plan.supporting_queries, ["观鸟入门"])

    def test_supporting_queries_can_be_empty(self) -> None:
        payload = {
            "product": "Math Puzzle",
            "topic_source": "related_field",
            "planned_topic": "睡前轻量数字谜题",
            "primary_query": "睡前 数字谜题",
            "broad_hotspot_signal": "没有自然且及时的广泛热点连接",
            "hotspot_fit_score": 3.0,
            "hot_angle_hypothesis": "用短时轻量挑战进入睡前放松场景",
            "audience_hypothesis": "喜欢轻量思考但不想有考试压力的人",
            "trend_opportunity": "轻量游戏适合形成可收藏的睡前内容",
            "related_field_signal": "数字谜题与睡前放松内容存在场景交集",
            "risk": "避免承诺提升智力或成绩",
            "reason": "相关领域信号比广泛热点更自然",
        }

        plan = TopicPlan.model_validate(payload)

        self.assertEqual(plan.supporting_queries, [])


if __name__ == "__main__":
    unittest.main()
