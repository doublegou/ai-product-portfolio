import argparse
from pathlib import Path
from tempfile import TemporaryDirectory

from src.base.file_store import save_draft
from src.create.runtime import create_approved_draft
from src.research.topic_research import (
    DAILY_PRODUCTS,
    collect_broad_hotspot_samples,
    discover_topic,
    get_daily_products,
)
from src.research.writing_research import run_writing_research


DEFAULT_DAILY_WRITING_GOAL = "自动为每个产品选择今天的小红书帖子选题"


def main() -> int:
    parser = argparse.ArgumentParser(description="Create one approved daily content draft.")
    parser.add_argument(
        "--writing-goal",
        default=DEFAULT_DAILY_WRITING_GOAL,
        help="Optional extra instruction used during automatic topic planning.",
    )
    parser.add_argument(
        "--product",
        choices=["all", *DAILY_PRODUCTS],
        default="all",
        help="Product to write for. Defaults to all daily products.",
    )
    parser.add_argument(
        "--research-query",
        default=None,
        help="Deprecated alias for --writing-goal.",
    )
    parser.add_argument(
        "--no-research",
        action="store_true",
        help="Skip fresh platform research before writing.",
    )
    parser.add_argument("--research-limit", type=int, default=10)
    parser.add_argument("--min-research-notes", type=int, default=10)
    parser.add_argument("--research-attempts", type=int, default=5)
    parser.add_argument("--broad-hotspot-limit", type=int, default=6)
    parser.add_argument("--broad-hotspot-queries", type=int, default=6)
    parser.add_argument(
        "--persist-research-artifacts",
        action="store_true",
        help="Persist topic discovery and writing research files for debugging.",
    )
    parser.add_argument(
        "--fallback-browser",
        action="store_true",
        help="If current Chrome collection fails, try the dedicated automation Chrome profile.",
    )
    args = parser.parse_args()

    print("Agent started.")

    saved_paths = []
    failures = []
    products = get_daily_products(args.product)

    if args.no_research:
        broad_hotspot_samples = None
        temp_context = None
    elif args.persist_research_artifacts:
        temp_context = None
        artifact_dir = Path("data/research/writing")
        artifact_dir.mkdir(parents=True, exist_ok=True)
        print("Topic discovery broad hotspot search started.")
        broad_hotspot_samples = collect_broad_hotspot_samples(
            output_dir=artifact_dir,
            limit=args.broad_hotspot_limit,
            query_limit=args.broad_hotspot_queries,
        )
        print(f"broad_hotspot_samples: {len(broad_hotspot_samples['notes'])}")
    else:
        temp_context = TemporaryDirectory(prefix="content-agent-broad-hotspots-")
        print("Topic discovery broad hotspot search started.")
        broad_hotspot_samples = collect_broad_hotspot_samples(
            output_dir=Path(temp_context.name),
            limit=args.broad_hotspot_limit,
            query_limit=args.broad_hotspot_queries,
        )
        print(f"broad_hotspot_samples: {len(broad_hotspot_samples['notes'])}")

    for product in products:
        try:
            print(f"Daily product started: {product}")
            research_brief = None
            user_topic = f"给 {product} 写一篇小红书产品推广帖"
            if not args.no_research:
                writing_goal = (
                    args.research_query
                    if args.research_query and args.research_query.strip()
                    else args.writing_goal
                )
                writing_goal = writing_goal.strip() or DEFAULT_DAILY_WRITING_GOAL
                discovery_dir = (
                    Path("data/research/writing")
                    if args.persist_research_artifacts
                    else Path(temp_context.name)
                )
                print(f"Topic discovery started: {product}")
                discovery_result = discover_topic(
                    writing_goal,
                    product=product,
                    output_dir=discovery_dir,
                    broad_hotspot_samples=broad_hotspot_samples,
                )
                topic_plan = discovery_result["topic_plan"]
                print(f"Writing research started: {product}")
                research_result = run_writing_research(
                    topic_plan,
                    limit=args.research_limit,
                    min_notes=args.min_research_notes,
                    max_attempts=args.research_attempts,
                    allow_dedicated_browser_fallback=args.fallback_browser,
                    persist_artifacts=args.persist_research_artifacts,
                    output_dir=discovery_dir,
                )
                research_brief = research_result["analysis"]
                user_topic = (
                    f"给 {product} 写一篇小红书帖子。"
                    f"今天主题：{topic_plan['planned_topic']}。"
                    f"角度：{topic_plan['hot_angle_hypothesis']}。"
                    f"目标读者：{topic_plan['audience_hypothesis']}。"
                )
                print(f"planned_product: {topic_plan['product']}")
                print(f"planned_topic: {topic_plan['planned_topic']}")
                print(f"research_used_query: {research_result['used_query']}")
                print(f"research_sample_count: {research_result['sample_count']}")
                if research_result.get("input_path"):
                    print(f"research_input: {research_result['input_path']}")
                if research_result.get("report_path"):
                    print(f"research_report: {research_result['report_path']}")

            result = create_approved_draft(
                user_topic=user_topic,
                research_brief=research_brief,
            )
            validated_draft = result["draft"]
            saved_path = save_draft(
                validated_draft,
                status="approved",
                metadata={
                    "final_score": result["final_score"],
                },
            )
            saved_paths.append(saved_path)
            print(f"topic: {validated_draft['topic']}")
            print(f"title: {validated_draft['title']}")
            print(f"cover_text: {validated_draft['cover_text']}")
            print(f"final_score: {result['final_score']}")
            print(f"iterations: {result['iterations']}")
            print(f"saved_path: {saved_path}")
        except (FileNotFoundError, RuntimeError, ValueError) as exc:
            failures.append((product, str(exc)))
            print(f"product_failed: {product}")
            print(exc)
            continue

    print(f"saved_count: {len(saved_paths)}")
    if failures:
        print(f"failed_count: {len(failures)}")
        for product, message in failures:
            print(f"failed_product: {product} | {message}")
    if not saved_paths:
        if temp_context:
            temp_context.cleanup()
        return 1
    if temp_context:
        temp_context.cleanup()
    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
