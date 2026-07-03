import json
from datetime import datetime
from pathlib import Path
from uuid import uuid4


def save_draft(
    draft: dict,
    output_dir: Path | str = "data/drafts",
    status: str = "draft",
    metadata: dict | None = None,
) -> Path:
    """Add local state fields and persist the draft as JSON."""
    target_dir = Path(output_dir)
    target_dir.mkdir(parents=True, exist_ok=True)

    now = datetime.now().astimezone()
    metadata = metadata or {}
    complete_draft = {
        "id": str(uuid4()),
        "created_at": now.isoformat(timespec="seconds"),
        **draft,
        **metadata,
        "status": status,
    }

    filename = now.strftime("%Y-%m-%d-%H%M%S-local-content-agent.json")
    path = target_dir / filename
    path.write_text(
        json.dumps(complete_draft, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return path
