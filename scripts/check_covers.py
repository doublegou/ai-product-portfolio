#!/usr/bin/env python3
"""Read-only delivery checks. Does not assess faces, text, truthfulness or design."""
import argparse
import json
from pathlib import Path

from PIL import Image, UnidentifiedImageError

RATIOS = {"3-4": (3, 4), "4-3": (4, 3), "16-9": (16, 9)}
FORMATS = {".png": "PNG", ".jpg": "JPEG", ".jpeg": "JPEG", ".webp": "WEBP"}


def check_set(directory, min_short=1024):
    if min_short < 1:
        raise ValueError("min_short must be positive")
    directory = Path(directory)
    result = {"passed": False, "directory": str(directory), "files": [], "errors": [],
              "scope": "File checks only; visual and factual review still required."}
    errors = result["errors"]
    if not directory.is_dir():
        errors.append("Output directory does not exist")
        return result
    entries = sorted(p for p in directory.iterdir() if not p.name.startswith('.'))
    if len(entries) != 4:
        errors.append(f"Expected post.txt and exactly 3 images, found {len(entries)} entries")
    post = directory / 'post.txt'
    try:
        text = post.read_text(encoding='utf-8')
        parts = text.split('\n\n正文：\n')
        if len(parts) != 2 or not parts[0].startswith('标题：\n') or not parts[0][4:].strip() or not parts[1].strip():
            errors.append('post.txt must contain a nonempty title and description')
    except (OSError, UnicodeError):
        errors.append('Missing or unreadable UTF-8 post.txt')
    for stem, (a, b) in RATIOS.items():
        matches = [p for p in entries if p.is_file() and p.stem == stem and p.suffix.lower() in FORMATS]
        if len(matches) != 1:
            errors.append(f"{stem}: expected one image, found {len(matches)}")
            continue
        path = matches[0]
        info = {"name": path.name, "target_ratio": f"{a}:{b}"}
        result["files"].append(info)
        try:
            with Image.open(path) as im:
                im.verify()
            with Image.open(path) as im:
                im.load()
                w, h = im.size
                orientation = im.getexif().get(274, 1)
                info.update(width=w, height=h, format=im.format, bytes=path.stat().st_size,
                            exif_orientation=orientation)
                if im.format != FORMATS[path.suffix.lower()]:
                    errors.append(f"{path.name}: extension does not match encoded format {im.format}")
                if orientation != 1:
                    errors.append(f"{path.name}: EXIF orientation {orientation} is not normalized")
                if getattr(im, 'n_frames', 1) != 1:
                    errors.append(f"{path.name}: expected a single still image")
                if w * b != h * a:
                    errors.append(f"{path.name}: {w}x{h} is NOT exact {a}:{b}")
                if min(w, h) < min_short:
                    errors.append(f"{path.name}: short edge {min(w, h)} is below {min_short}px")
        except (OSError, ValueError, SyntaxError, UnidentifiedImageError, Image.DecompressionBombError) as exc:
            errors.append(f"{path.name}: cannot decode ({type(exc).__name__})")
    for path in entries:
        if path.name == 'post.txt' and path.is_file():
            continue
        if not path.is_file() or path.stem not in RATIOS or path.suffix.lower() not in FORMATS:
            errors.append(f"Unexpected deliverable: {path.name}")
    result["passed"] = not errors
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--min-short-edge", type=int, default=1024,
                        help="Override only when a different delivery resolution was chosen")
    args = parser.parse_args()
    if args.min_short_edge < 1:
        parser.error("--min-short-edge must be positive")
    result = check_set(args.directory, args.min_short_edge)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
