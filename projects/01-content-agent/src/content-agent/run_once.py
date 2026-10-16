import argparse
import time
from pathlib import Path
from tempfile import TemporaryDirectory

from src.base.file_store import save_draft
from src.base.run_log import log_event, log_exception, set_run_context
from src.create.runtime import create_approved_draft
from src.publish.xhs import publish_draft_to_xhs
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
        "--no-publish",
        action="store_true",
        help="Generate and save the approved draft, but do not publish it.",
    )
    parser.add_argument(
        "--publish-dry-run",
        action="store_true",
        help="Prepare the publish page but do not click the final publish button.",
    )
    args = parser.parse_args()

    user_topic = " ".join(args.topic).strip()
    if not user_topic:
        print('Usage: python run_once.py "你想写的主题或要求"')
        return 1

    started_at = time.perf_counter()
    set_run_context(
        "once",
        args={
            "no_research": args.no_research,
            "research_limit": args.research_limit,
            "min_research_notes": args.min_research_notes,
            "research_attempts": args.research_attempts,
            "persist_research_artifacts": args.persist_research_artifacts,
            "publish": not args.no_publish,
            "publish_dry_run": args.publish_dry_run,
        },
    )
    log_event("run_start")
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
        publish_result = None
        if not args.no_publish:
            publish_result = publish_draft_to_xhs(
                saved_path,
                dry_run=args.publish_dry_run,
            )
    except (FileNotFoundError, RuntimeError, ValueError) as exc:
        log_exception("exception", exc, phase="run_once")
        log_event(
            "run_end",
            level="error",
            status="failed",
            duration_ms=int((time.perf_counter() - started_at) * 1000),
            error_type=type(exc).__name__,
            error_message=str(exc),
        )
        print(exc)
        return 1

    log_event(
        "run_end",
        status="success",
        duration_ms=int((time.perf_counter() - started_at) * 1000),
        saved_path=saved_path,
        final_score=result["final_score"],
        iterations=result["iterations"],
        publish_status=publish_result.status if publish_result else "skipped",
    )
    print(f"topic: {validated_draft['topic']}")
    print(f"title: {validated_draft['title']}")
    print(f"cover_text: {validated_draft['cover_text']}")
    print(f"final_score: {result['final_score']}")
    print(f"iterations: {result['iterations']}")
    print(f"saved_path: {saved_path}")
    if publish_result:
        print(f"publish_status: {publish_result.status}")
        print(f"publish_page_url: {publish_result.page_url}")
    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
