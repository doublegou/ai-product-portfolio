from src.file_store import save_draft
from src.pipeline import create_approved_draft


def main() -> int:
    print("Agent started.")

    try:
        result = create_approved_draft()
        validated_draft = result["draft"]
        saved_path = save_draft(
            validated_draft,
            status="approved",
            metadata={
                "final_score": result["final_score"],
                "iterations": result["iterations"],
                "review_rounds": result["review_rounds"],
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
