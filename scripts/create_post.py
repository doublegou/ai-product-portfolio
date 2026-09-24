#!/usr/bin/env python3
"""Allocate the next episode directory and save a final UTF-8 post, without overwriting."""
import argparse
import json
import re
from pathlib import Path

from check_post import format_post, inspect_post


def next_number(root, start_at=4):
    if start_at < 1:
        raise ValueError('start_at must be positive')
    occupied = [int(p.name) for p in Path(root).iterdir() if re.fullmatch(r'[0-9]+', p.name)] if Path(root).exists() else []
    return max([start_at - 1, *occupied]) + 1


def create_post(root, title, description, start_at=4, dry_run=False):
    text = format_post(title, description)
    root = Path(root).expanduser().resolve()
    number = next_number(root, start_at)
    if dry_run:
        directory = root / f'{number:03d}'
    else:
        root.mkdir(parents=True, exist_ok=True)
        while True:
            directory = root / f'{number:03d}'
            try:
                directory.mkdir()
                break
            except FileExistsError:
                number = max(number + 1, next_number(root, start_at))
        try:
            with (directory / 'post.txt').open('x', encoding='utf-8', newline='\n') as stream:
                stream.write(text)
        except OSError as exc:
            raise RuntimeError(f'Write failed in reserved directory {directory}; inspect it before retrying') from exc
    return {'created': not dry_run, 'number': f'{number:03d}', 'directory': str(directory),
            'post': str(directory / 'post.txt'), 'checks': inspect_post(text)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--post-root', type=Path, required=True)
    parser.add_argument('--title-file', type=Path, required=True)
    parser.add_argument('--description-file', type=Path, required=True)
    parser.add_argument('--start-at', type=int, default=4, help='Default first episode is 004')
    parser.add_argument('--dry-run', action='store_true', help='Preview; does not reserve or create anything')
    args = parser.parse_args()
    try:
        result = create_post(args.post_root, args.title_file.read_text(encoding='utf-8'),
                             args.description_file.read_text(encoding='utf-8'), args.start_at, args.dry_run)
    except (OSError, ValueError, RuntimeError, UnicodeError) as exc:
        parser.exit(1, f'{exc}\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
