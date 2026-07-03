import argparse

from pydantic import ValidationError

from src.benchmark import (
    analyze_benchmark_corpus,
    generate_strategy_review,
    load_benchmark_corpus,
    save_benchmark_analysis,
    save_strategy_review,
    validate_benchmark_threshold,
)
from src.collectors.xhs_benchmark import (
    DEFAULT_BENCHMARK_KEYWORDS,
    collect_xhs_benchmark_current_chrome,
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Collect and analyze Xiaohongshu benchmark creators."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    collect_parser = subparsers.add_parser("collect")
    collect_parser.add_argument("--target-creators", type=int, default=50)
    collect_parser.add_argument("--notes-per-creator", type=int, default=10)
    collect_parser.add_argument("--creators-per-keyword", type=int, default=8)
    collect_parser.add_argument("--account-pause-seconds", type=float, default=10)
    collect_parser.add_argument("--note-pause-seconds", type=float, default=1.5)
    collect_parser.add_argument(
        "--skip-note-details",
        action="store_true",
        help="Only collect profile note cards, without opening each note detail page.",
    )
    collect_parser.add_argument(
        "--keywords",
        nargs="*",
        default=list(DEFAULT_BENCHMARK_KEYWORDS),
        help="Seed search keywords. Defaults cover startup, AI, product, app, and related niches.",
    )

    analyze_parser = subparsers.add_parser("analyze")
    analyze_parser.add_argument("corpus_json")
    analyze_parser.add_argument("--min-creators", type=int, default=50)
    analyze_parser.add_argument("--min-notes-per-creator", type=int, default=10)
    analyze_parser.add_argument("--batch-size", type=int, default=5)
    analyze_parser.add_argument(
        "--skip-strategy-review",
        action="store_true",
        help="Only save benchmark analysis, without producing a human-review proposal.",
    )
    analyze_parser.add_argument(
        "--trigger",
        choices=[
            "weekly",
            "account_data_change",
            "new_product",
            "platform_style_change",
            "content_underperformance",
            "strategy_hypothesis",
            "manual",
        ],
        default="weekly",
        help="Why this benchmark analysis was triggered.",
    )
    analyze_parser.add_argument(
        "--trigger-reason",
        default="Weekly benchmark review.",
        help="Human-readable reason for this benchmark run.",
    )
    analyze_parser.add_argument(
        "--allow-partial",
        action="store_true",
        help="Allow model analysis before the corpus reaches the final threshold.",
    )

    args = parser.parse_args()

    try:
        if args.command == "collect":
            print("Benchmark collection started.")
            path = collect_xhs_benchmark_current_chrome(
                keywords=args.keywords,
                target_creators=args.target_creators,
                notes_per_creator=args.notes_per_creator,
                creators_per_keyword=args.creators_per_keyword,
                collect_note_details=not args.skip_note_details,
                progress=True,
                account_pause_seconds=args.account_pause_seconds,
                note_pause_seconds=args.note_pause_seconds,
            )
            print(f"corpus_path: {path}")
            print("Done.")
            return 0

        if args.command == "analyze":
            print("Benchmark analysis started.")
            corpus = load_benchmark_corpus(args.corpus_json)
            threshold = validate_benchmark_threshold(
                corpus,
                min_creators=args.min_creators,
                min_notes_per_creator=args.min_notes_per_creator,
            )
            print(f"creators: {threshold['creator_count']}/{threshold['target_creators']}")
            print(
                "qualified_creators: "
                f"{threshold['qualified_creator_count']}/{threshold['target_creators']}"
            )
            print(f"notes: {threshold['note_count']}/{threshold['target_notes']}")
            analysis = analyze_benchmark_corpus(
                corpus,
                min_creators=args.min_creators,
                min_notes_per_creator=args.min_notes_per_creator,
                allow_partial=args.allow_partial,
                batch_size=args.batch_size,
            )
            path = save_benchmark_analysis(analysis)
            print(f"ready_for_persona: {analysis['ready_for_persona']}")
            print(f"confidence: {analysis['confidence']}")
            print(f"saved_path: {path}")
            if not args.skip_strategy_review:
                review = generate_strategy_review(
                    analysis,
                    corpus_path=args.corpus_json,
                    analysis_path=str(path),
                    trigger=args.trigger,
                    trigger_reason=args.trigger_reason,
                )
                review_path = save_strategy_review(review)
                print(f"strategy_review_path: {review_path}")
            print("Done.")
            return 0

        raise ValueError(f"Unsupported command: {args.command}")
    except (FileNotFoundError, RuntimeError, ValueError, ValidationError) as exc:
        print(exc)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
