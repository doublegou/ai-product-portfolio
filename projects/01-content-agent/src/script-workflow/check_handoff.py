#!/usr/bin/env python3
"""Verify reviewed task file fingerprints; this does not judge content quality."""
import argparse
import hashlib
import json
from pathlib import Path


def check(manifest_path):
    manifest_path = Path(manifest_path)
    manifest = json.loads(manifest_path.read_text())
    if not isinstance(manifest.get('task'), str) or not manifest['task'].strip():
        raise ValueError('task must be a nonempty string')
    if not isinstance(manifest.get('files'), list) or not manifest['files']:
        raise ValueError('files must be a nonempty list')
    errors = []
    for item in manifest['files']:
        if not isinstance(item, dict) or not isinstance(item.get('path'), str) or not item['path'] or not isinstance(item.get('sha256'), str) or len(item['sha256']) != 64:
            raise ValueError('each file must provide a path and SHA-256')
        path = manifest_path.parent / item['path']
        if not path.is_file():
            errors.append({'path': item['path'], 'reason': 'missing'})
        elif hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
            errors.append({'path': item['path'], 'reason': 'changed_since_review'})
    return {'task': manifest['task'], 'passed': not errors, 'checked_files': len(manifest['files']),
            'errors': errors, 'scope': 'fingerprints only; content review is recorded separately'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest')
    args = parser.parse_args()
    try:
        result = check(args.manifest)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        result = {'passed': False, 'errors': [{'reason': str(exc)}]}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result['passed'] else 1)
