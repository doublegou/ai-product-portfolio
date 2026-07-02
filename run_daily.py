from src.file_store import save_draft
from src.memory import load_banned_phrases
from src.validator import validate_draft
from src.writer import generate_draft


def main() -> int:
    print("Agent started.")

    try:
        draft = generate_draft()
        banned_phrases = load_banned_phrases()
        validated_draft = validate_draft(draft, banned_phrases)
        saved_path = save_draft(validated_draft)
    except (FileNotFoundError, RuntimeError, ValueError) as exc:
        print(exc)
        return 1

    print(f"topic: {validated_draft['topic']}")
    print(f"title: {validated_draft['title']}")
    print(f"saved_path: {saved_path}")
    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
