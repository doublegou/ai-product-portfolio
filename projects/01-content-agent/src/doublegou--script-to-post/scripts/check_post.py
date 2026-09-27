#!/usr/bin/env python3
"""Check post.txt structure; editorial signals are advisory, not semantic verdicts."""
import argparse
import json
import re
from pathlib import Path


def format_post(title, description):
    title, description = title.strip(), description.strip()
    if not title or '\n' in title or '\r' in title:
        raise ValueError('Title must be one nonempty line')
    if not description:
        raise ValueError('Description must not be empty')
    if '\x00' in title + description:
        raise ValueError('NUL characters are not allowed')
    return f'标题：\n{title}\n\n正文：\n{description}\n'


def inspect_post(text):
    result = {'structure_passed': False, 'errors': [], 'review': []}
    match = re.fullmatch(r'标题：\n([^\n]+)\n\n正文：\n(.+?)\n?', text, re.S)
    if not match:
        result['errors'].append('Expected exactly 标题：, a title, blank line, 正文： and a description')
        return result
    title, description = (v.strip() for v in match.groups())
    try:
        format_post(title, description)
    except ValueError as exc:
        result['errors'].append(str(exc))
        return result
    count = len(re.sub(r'\s', '', description))
    sentences = len([part for part in re.split(r'[。！？!?]+|(?<!\d)\.(?!\d)', description)
                     if re.search(r'[\w\u4e00-\u9fff]', part)])
    result.update(structure_passed=True, title=title, description=description,
                  description_characters=count, approximate_sentences=sentences)
    if not 80 <= count <= 150:
        result['review'].append('Default description length is 80–150 visible non-whitespace characters')
    if not 2 <= sentences <= 3:
        result['review'].append('Default description length is 2–3 sentences; sentence parsing is approximate')
    if title in description:
        result['review'].append('Description repeats the full title; check whether it adds information')
    for phrase in ('史上最强', '颠覆', '革命', '炸裂', '爆火', '实测', '免费', '零成本'):
        if phrase in title + description:
            result['review'].append(f'Check script/evidence for: {phrase}')
    if description.startswith(('近年来', '随着', '在这个时代')):
        result['review'].append('Opening may be background padding; lead with the episode topic')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('post', type=Path)
    args = parser.parse_args()
    try:
        result = inspect_post(args.post.read_text(encoding='utf-8'))
    except (OSError, UnicodeError) as exc:
        result = {'structure_passed': False, 'errors': [str(exc)], 'review': []}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result['structure_passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
