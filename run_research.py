import argparse

from pydantic import ValidationError

from src.research import analyze_research, load_research_input, save_research_report


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Analyze Xiaohongshu account and note research samples."
    )
    parser.add_argument("input_json", help="Path to a research input JSON file.")
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="Validate the input JSON without calling the model.",
    )
    args = parser.parse_args()

    print("Research analyzer started.")

    try:
        research_input = load_research_input(args.input_json)
        print(f"accounts: {len(research_input.accounts)}")
        print(f"notes: {research_input.note_count}")

        if args.validate_only:
            print("Input JSON is valid.")
            print("Done.")
            return 0

        analysis = analyze_research(research_input)
        saved_path = save_research_report(analysis)
    except (FileNotFoundError, ValueError, ValidationError, RuntimeError) as exc:
        print(exc)
        return 1

    print(f"confidence: {analysis['confidence']}")
    print(f"summary: {analysis['summary']}")
    print(f"saved_path: {saved_path}")
    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
