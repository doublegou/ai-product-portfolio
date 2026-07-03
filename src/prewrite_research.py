from typing import Any

from src.collectors.xhs_browser import collect_xhs_search
from src.collectors.xhs_current_chrome import collect_xhs_current_chrome
from src.research import analyze_research, load_research_input, save_research_report


def run_prewrite_research(
    topic: str,
    *,
    platform: str = "xhs",
    limit: int = 10,
    min_notes: int = 5,
    allow_dedicated_browser_fallback: bool = False,
) -> dict[str, Any]:
    """Collect and analyze fresh platform samples for one writing task."""
    if platform != "xhs":
        raise ValueError(f"Unsupported research platform: {platform}")

    current_chrome_error = None
    try:
        input_path = collect_xhs_current_chrome(topic, limit=limit)
    except RuntimeError as exc:
        current_chrome_error = str(exc)
        if not allow_dedicated_browser_fallback:
            raise RuntimeError(
                "Could not collect from your logged-in Chrome. "
                f"{current_chrome_error}"
            ) from exc
        input_path = collect_xhs_search(topic, limit=limit)
    research_input = load_research_input(input_path)
    if research_input.note_count < min_notes:
        raise RuntimeError(
            "Prewrite research did not collect enough Xiaohongshu notes. "
            f"Collected {research_input.note_count}, need at least {min_notes}. "
            "Your logged-in Chrome may not be showing search results, or the collector selector needs updating. "
            f"Current Chrome attempt: {current_chrome_error or 'not used'}"
        )

    analysis = analyze_research(research_input)
    report_path = save_research_report(analysis)
    return {
        "input_path": str(input_path),
        "report_path": str(report_path),
        "analysis": analysis,
    }
