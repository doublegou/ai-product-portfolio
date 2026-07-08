import time
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any

from src.collect.xhs import collect_xhs_current_chrome, collect_xhs_search
from src.research.research_infra import analyze_research, load_research_input, save_research_report


def run_writing_research(
    topic_plan: dict[str, Any],
    *,
    platform: str = "xhs",
    limit: int = 10,
    min_notes: int = 10,
    max_attempts: int = 5,
    allow_dedicated_browser_fallback: bool = False,
    persist_artifacts: bool = False,
    artifact_dir: Path | str = "data/research/writing",
    output_dir: Path | None = None,
) -> dict[str, Any]:
    """Collect and analyze focused samples for one planned writing topic."""
    if platform != "xhs":
        raise ValueError(f"Unsupported research platform: {platform}")

    if persist_artifacts:
        research_dir = Path(output_dir or artifact_dir)
        research_dir.mkdir(parents=True, exist_ok=True)
        return _collect_and_analyze(
            queries=_queries_from_topic_plan(topic_plan),
            topic_plan=topic_plan,
            limit=limit,
            min_notes=min_notes,
            max_attempts=max_attempts,
            allow_dedicated_browser_fallback=allow_dedicated_browser_fallback,
            output_dir=research_dir,
            persist_artifacts=True,
        )

    if output_dir is not None:
        return _collect_and_analyze(
            queries=_queries_from_topic_plan(topic_plan),
            topic_plan=topic_plan,
            limit=limit,
            min_notes=min_notes,
            max_attempts=max_attempts,
            allow_dedicated_browser_fallback=allow_dedicated_browser_fallback,
            output_dir=output_dir,
            persist_artifacts=False,
        )

    with TemporaryDirectory(prefix="content-agent-writing-research-") as tmp_dir:
        return _collect_and_analyze(
            queries=_queries_from_topic_plan(topic_plan),
            topic_plan=topic_plan,
            limit=limit,
            min_notes=min_notes,
            max_attempts=max_attempts,
            allow_dedicated_browser_fallback=allow_dedicated_browser_fallback,
            output_dir=Path(tmp_dir),
            persist_artifacts=False,
        )


def _queries_from_topic_plan(topic_plan: dict[str, Any]) -> list[str]:
    return [
        topic_plan["primary_query"],
        *topic_plan.get("supporting_queries", []),
    ]


def _collect_and_analyze(
    *,
    queries: list[str],
    topic_plan: dict[str, Any],
    limit: int,
    min_notes: int,
    max_attempts: int,
    allow_dedicated_browser_fallback: bool,
    output_dir: Path,
    persist_artifacts: bool,
) -> dict[str, Any]:
    current_chrome_error = None
    research_input = None
    input_path = None
    max_attempts = max(1, max_attempts)
    attempted_queries: list[str] = []

    for query in queries:
        query = query.strip()
        if not query or query in attempted_queries:
            continue
        attempted_queries.append(query)
        for attempt in range(1, max_attempts + 1):
            try:
                input_path = collect_xhs_current_chrome(
                    query,
                    limit=limit,
                    output_dir=output_dir,
                )
                research_input = load_research_input(input_path)
                if research_input.note_count >= min_notes:
                    break
                current_chrome_error = (
                    f"Query '{query}' collected {research_input.note_count}, need at least {min_notes}."
                )
            except RuntimeError as exc:
                current_chrome_error = f"Query '{query}' failed: {exc}"
            if attempt < max_attempts:
                time.sleep(min(3 * attempt, 12))
        if research_input is not None and research_input.note_count >= min_notes:
            break

    if (
        (research_input is None or research_input.note_count < min_notes)
        and allow_dedicated_browser_fallback
    ):
        fallback_query = attempted_queries[0] if attempted_queries else topic_plan["primary_query"]
        input_path = collect_xhs_search(
            fallback_query,
            limit=limit,
            output_dir=output_dir,
        )
        research_input = load_research_input(input_path)

    if research_input is None or input_path is None:
        raise RuntimeError(
            "Could not collect from your logged-in Chrome. "
            f"{current_chrome_error or 'unknown error'}"
        )

    if research_input.note_count < min_notes:
        raise RuntimeError(
            "Writing research did not collect enough Xiaohongshu notes. "
            f"Collected {research_input.note_count}, need at least {min_notes}. "
            f"Tried {len(attempted_queries)} queries and current Chrome {max_attempts} times per query. "
            "Your logged-in Chrome may not be showing search results, or the collector selector needs updating. "
            f"Current Chrome attempt: {current_chrome_error or 'not used'}"
        )

    analysis = analyze_research(research_input)
    report_path = save_research_report(analysis, output_dir=output_dir) if persist_artifacts else None
    return {
        "input_path": str(input_path) if persist_artifacts else None,
        "report_path": str(report_path) if report_path else None,
        "sample_count": research_input.note_count,
        "topic_plan": topic_plan,
        "used_query": research_input.collector_meta.get("keyword"),
        "attempted_queries": attempted_queries,
        "analysis": {
            "topic_plan": topic_plan,
            "sample_analysis": analysis,
        },
    }
