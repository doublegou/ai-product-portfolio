import argparse

from src.file_store import save_draft
from src.pipeline import create_approved_draft
from src.prewrite_research import run_prewrite_research


def main() -> int:
    parser = argparse.ArgumentParser(description="Create one approved content draft.")
    parser.add_argument("topic", nargs="+", help="Topic or writing request.")
    parser.add_argument(
        "--no-research",
        action="store_true",
        help="Skip fresh platform research before writing.",
    )
    parser.add_argument("--research-limit", type=int, default=10)
    parser.add_argument("--min-research-notes", type=int, default=5)
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
            print("Prewrite research started.")
            research_result = run_prewrite_research(
                user_topic,
                limit=args.research_limit,
                min_notes=args.min_research_notes,
                allow_dedicated_browser_fallback=args.fallback_browser,
            )
            research_brief = research_result["analysis"]
            print(f"research_input: {research_result['input_path']}")
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
                "iterations": result["iterations"],
                "review_rounds": result["review_rounds"],
                "research_brief": research_brief,
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
