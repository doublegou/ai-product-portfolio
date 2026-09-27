import argparse
import time

from pydantic import ValidationError

from src.base.run_log import log_event, log_exception, set_run_context
from src.research.strategy_research import (
    analyze_strategy_corpus,
    generate_strategy_review,
    load_strategy_corpus,
    save_strategy_result,
    validate_strategy_corpus_threshold,
)
from src.collect.xhs import (
    DEFAULT_STRATEGY_RESEARCH_KEYWORDS,
    collect_xhs_strategy_corpus_current_chrome,
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Collect and analyze Xiaohongshu creators for long-term strategy research."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    collect_parser = subparsers.add_parser("collect")
    collect_parser.add_argument("--target-creators", type=int, default=50)
    collect_parser.add_argument("--notes-per-creator", type=int, default=10)
    collect_parser.add_argument("--creators-per-keyword", type=int, default=8)
    collect_parser.add_argument("--account-pause-seconds", type=float, default=10)
    collect_parser.add_argument("--note-pause-seconds", type=float, default=1.5)
    collect_parser.add_argument(
        "--keywords",
        nargs="*",
        default=list(DEFAULT_STRATEGY_RESEARCH_KEYWORDS),
        help="Seed search keywords. Defaults cover startup, AI, product, app, and related niches.",
    )

    analyze_parser = subparsers.add_parser("analyze")
    analyze_parser.add_argument("corpus_json")
    analyze_parser.add_argument("--min-creators", type=int, default=50)
    analyze_parser.add_argument("--min-notes-per-creator", type=int, default=10)
    analyze_parser.add_argument(
        "--batch-size",
        type=int,
        default=1,
        help="Creators per multimodal analysis call. Defaults to one creator per call.",
    )
    analyze_parser.add_argument(
        "--skip-strategy-review",
        action="store_true",
        help="Save one analysis-only result, without producing a human-review proposal.",
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
        help="Why this strategy research was triggered.",
    )
    analyze_parser.add_argument(
        "--trigger-reason",
        default="Weekly strategy research review.",
        help="Human-readable reason for this strategy research run.",
    )
    analyze_parser.add_argument(
        "--allow-partial",
        action="store_true",
        help="Allow model analysis before the corpus reaches the final threshold.",
    )

    args = parser.parse_args()

    started_at = time.perf_counter()
    command_name = f"strategy_{args.command}"
    safe_args = {
        key: value
        for key, value in vars(args).items()
        if key not in {"trigger_reason", "corpus_json"}
    }
    set_run_context(command_name, args=safe_args)
    log_event("run_start")

    try:
        if args.command == "collect":
            print("Strategy research collection started.")
            path = collect_xhs_strategy_corpus_current_chrome(
                keywords=args.keywords,
                target_creators=args.target_creators,
                notes_per_creator=args.notes_per_creator,
                creators_per_keyword=args.creators_per_keyword,
                progress=True,
                account_pause_seconds=args.account_pause_seconds,
                note_pause_seconds=args.note_pause_seconds,
            )
            print(f"corpus_path: {path}")
            log_event(
                "run_end",
                status="success",
                duration_ms=int((time.perf_counter() - started_at) * 1000),
                corpus_path=path,
            )
            print("Done.")
            return 0

        if args.command == "analyze":
            print("Strategy research analysis started.")
            corpus = load_strategy_corpus(args.corpus_json)
            threshold = validate_strategy_corpus_threshold(
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
            analysis = analyze_strategy_corpus(
                corpus,
                min_creators=args.min_creators,
                min_notes_per_creator=args.min_notes_per_creator,
                allow_partial=args.allow_partial,
                batch_size=args.batch_size,
            )
            print(f"ready_for_persona: {analysis['ready_for_persona']}")
            print(f"confidence: {analysis['confidence']}")
            review = None
            if not args.skip_strategy_review:
                review = generate_strategy_review(
                    analysis,
                    corpus_path=args.corpus_json,
                    trigger=args.trigger,
                    trigger_reason=args.trigger_reason,
                )
            path = save_strategy_result(
                analysis=analysis,
                review=review,
                corpus_path=args.corpus_json,
                trigger=args.trigger,
                trigger_reason=args.trigger_reason,
            )
            print(f"saved_path: {path}")
            log_event(
                "run_end",
                status="success",
                duration_ms=int((time.perf_counter() - started_at) * 1000),
                saved_path=path,
                ready_for_persona=analysis["ready_for_persona"],
                confidence=analysis["confidence"],
            )
            print("Done.")
            return 0

        raise ValueError(f"Unsupported command: {args.command}")
    except (FileNotFoundError, RuntimeError, ValueError, ValidationError) as exc:
        log_exception("exception", exc, phase=command_name)
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


if __name__ == "__main__":
    raise SystemExit(main())
