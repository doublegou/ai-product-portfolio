from pathlib import Path


REQUIRED_MEMORY_FILES = (
    "profile.md",
    "voice.md",
    "topics.md",
    "banned_phrases.md",
    "examples.md",
)


def load_memory(memory_dir: Path | str = "memory") -> dict[str, str]:
    """Load required Markdown memory files."""
    base_dir = Path(memory_dir)
    memory: dict[str, str] = {}

    for filename in REQUIRED_MEMORY_FILES:
        path = base_dir / filename
        if not path.exists():
            raise FileNotFoundError(f"Missing memory file: {path}")
        if not path.is_file():
            raise FileNotFoundError(f"Memory path is not a file: {path}")

        content = path.read_text(encoding="utf-8").strip()
        if not content:
            raise ValueError(f"Memory file is empty: {path}")
        memory[filename] = content

    return memory


def load_banned_phrases(memory_dir: Path | str = "memory") -> list[str]:
    """Extract banned phrases from memory/banned_phrases.md."""
    path = Path(memory_dir) / "banned_phrases.md"
    if not path.exists():
        raise FileNotFoundError(f"Missing memory file: {path}")

    phrases: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped.startswith("- "):
            phrase = stripped[2:].strip()
            if phrase:
                phrases.append(phrase)

    return phrases
