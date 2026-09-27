from pathlib import Path


REQUIRED_MEMORY_FILES = (
    "account/persona.md",
    "account/editorial_rules.md",
    "account/acceptance_standards.md",
    "platforms/xiaohongshu.md",
)

OPTIONAL_MEMORY_DIRS = (
    "products",
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

    for optional_dir_name in OPTIONAL_MEMORY_DIRS:
        optional_dir = base_dir / optional_dir_name
        if not optional_dir.exists():
            continue

        for path in sorted(optional_dir.glob("*.md")):
            content = path.read_text(encoding="utf-8").strip()
            if content:
                memory[f"{optional_dir_name}/{path.name}"] = content

    return memory


def load_banned_phrases(memory_dir: Path | str = "memory") -> list[str]:
    """Extract banned phrases from memory/account/editorial_rules.md."""
    path = Path(memory_dir) / "account" / "editorial_rules.md"
    if not path.exists():
        raise FileNotFoundError(f"Missing memory file: {path}")

    phrases: list[str] = []
    in_banned_section = False
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped.startswith("## "):
            in_banned_section = stripped == "## Banned Phrases"
            continue
        if not in_banned_section:
            continue
        if stripped.startswith("- "):
            phrase = stripped[2:].strip()
            if phrase:
                phrases.append(phrase)

    return phrases
