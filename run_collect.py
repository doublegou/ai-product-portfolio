import argparse

from src.collectors.xhs_browser import collect_xhs_search
from src.collectors.xhs_current_chrome import collect_xhs_current_chrome


def main() -> int:
    parser = argparse.ArgumentParser(description="Collect platform research samples.")
    subparsers = parser.add_subparsers(dest="platform", required=True)

    xhs_parser = subparsers.add_parser("xhs", help="Collect Xiaohongshu search notes.")
    xhs_parser.add_argument("keyword", help="Search keyword.")
    xhs_parser.add_argument("--limit", type=int, default=10)
    xhs_parser.add_argument("--headless", action="store_true")

    xhs_current_parser = subparsers.add_parser(
        "xhs-current",
        help="Collect Xiaohongshu search notes from current logged-in Chrome.",
    )
    xhs_current_parser.add_argument("keyword", help="Search keyword.")
    xhs_current_parser.add_argument("--limit", type=int, default=10)

    args = parser.parse_args()

    print("Collector started.")
    try:
        if args.platform == "xhs":
            path = collect_xhs_search(
                args.keyword,
                limit=args.limit,
                headless=args.headless,
            )
        elif args.platform == "xhs-current":
            path = collect_xhs_current_chrome(
                args.keyword,
                limit=args.limit,
            )
        else:
            raise ValueError(f"Unsupported platform: {args.platform}")
    except (RuntimeError, ValueError) as exc:
        print(exc)
        return 1

    print(f"saved_path: {path}")
    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
