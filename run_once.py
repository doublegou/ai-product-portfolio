import argparse
from pathlib import Path
from tempfile import TemporaryDirectory

from src.base.file_store import save_draft
from src.create.runtime import create_approved_draft
from src.research.topic_research import discover_topic
from src.research.writing_research import run_writing_research


def main() -> int:
    parser = argparse.ArgumentParser(description="Create one approved content draft.")
    parser.add_argument("topic", nargs="+", help="Topic or writing request.")
    parser.add_argument(
        "--no-research",
        action="store_true",
        help="Skip fresh platform research before writing.",
    )
    parser.add_argument("--research-limit", type=int, default=10)
    parser.add_argument("--min-research-notes", type=int, default=10)
    parser.add_argument("--research-attempts", type=int, default=5)
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

    user_topic = " ".join(args.topic).strip()
    if not user_topic:
        print('Usage: python run_once.py "你想写的主题或要求"')
        return 1

    print("Agent started.")

    try:
        research_brief = None
        if not args.no_research:
            if args.persist_research_artifacts:
                output_dir = Path("data/research/writing")
                output_dir.mkdir(parents=True, exist_ok=True)
                temp_context = None
            else:
                temp_context = TemporaryDirectory(prefix="content-agent-once-research-")
                output_dir = Path(temp_context.name)

            print("Topic discovery started.")
            discovery_result = discover_topic(
                user_topic,
                output_dir=output_dir,
            )
            topic_plan = discovery_result["topic_plan"]
            print("Writing research started.")
            research_result = run_writing_research(
                topic_plan,
                limit=args.research_limit,
                min_notes=args.min_research_notes,
                max_attempts=args.research_attempts,
                allow_dedicated_browser_fallback=args.fallback_browser,
                persist_artifacts=args.persist_research_artifacts,
                output_dir=output_dir,
            )
            if temp_context:
                temp_context.cleanup()
            research_brief = research_result["analysis"]
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
    except (FileNotFoundError, RuntimeError, ValueError) as exc:
        print(exc)
        return 1

    print(f"topic: {validated_draft['topic']}")
    print(f"title: {validated_draft['title']}")
    print(f"cover_text: {validated_draft['cover_text']}")
    print(f"final_score: {result['final_score']}")
    print(f"iterations: {result['iterations']}")
    print(f"saved_path: {saved_path}")
    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
