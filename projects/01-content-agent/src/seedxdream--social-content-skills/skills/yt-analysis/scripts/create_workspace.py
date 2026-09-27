#!/usr/bin/env python3
"""Create a timestamp-topic task directory with an analysis.md skeleton."""

from __future__ import annotations

import argparse
from datetime import datetime
import json
from pathlib import Path
import re
import sys


def configure_console() -> None:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")


def sanitize_topic(topic: str) -> str:
    topic = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", topic)
    topic = re.sub(r"\s+", "", topic).strip(" ._-")
    topic = topic[:60].rstrip(" ._-")
    if not topic:
        raise ValueError("Topic is empty after filename sanitization")
    return topic


def parse_timestamp(value: str | None) -> datetime:
    if value is None:
        return datetime.now().astimezone()
    parsed = datetime.fromisoformat(value)
    return parsed.astimezone() if parsed.tzinfo else parsed


def create_workspace(root: Path, topic: str, timestamp: datetime) -> tuple[Path, Path]:
    root = root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    base_name = f"{timestamp:%Y-%m-%d_%H%M}_{sanitize_topic(topic)}"
    workspace = root / base_name
    suffix = 2
    while workspace.exists():
        workspace = root / f"{base_name}_{suffix:02d}"
        suffix += 1
    workspace.mkdir()
    analysis_path = workspace / "analysis.md"
    analysis_path.write_text(
        f"# {topic.strip()}\n\n"
        "## 一、概述\n\n"
        "<!-- 写入视频标题、链接、中文完整摘要、核心观点及必要背景；完成后删除本注释。 -->\n\n"
        "## 二、内容\n\n"
        "<!-- 写入带 [HH:MM:SS] 时间戳的完整中文转译；完成后删除本注释。 -->\n\n"
        "## 三、二创\n\n"
        "<!-- 写入原创二创方向；不要以原视频、原作者或原材料为叙述依托；完成后删除本注释。 -->\n",
        encoding="utf-8",
    )
    return workspace, analysis_path


def main() -> int:
    configure_console()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("topic", help="Short Chinese topic used in the folder name")
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="Posts root; defaults to current directory")
    parser.add_argument("--timestamp", help="Optional ISO timestamp, used for deterministic tests")
    args = parser.parse_args()
    workspace, analysis_path = create_workspace(args.root, args.topic, parse_timestamp(args.timestamp))
    print(
        json.dumps(
            {"workspace_path": str(workspace), "analysis_path": str(analysis_path)},
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
