#!/usr/bin/env python3
"""Static preflight, not a rendering, semantic or offline-execution proof."""
import argparse
import json
import re
from html.parser import HTMLParser
from pathlib import Path

class Preflight(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.errors, self.warnings, self.ids, self.css = [], [], set(), []
        self.slides = self.stages = 0
        self.in_style = False

    def error(self, message):
        self.errors.append(message)

    def resource(self, value, context):
        if value and not value.startswith(('data:', '#')):
            self.error(f'Non-embedded resource: {context}')

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        classes = attrs.get('class', '').split()
        self.slides += 'slide' in classes
        self.stages += 'deck-stage' in classes
        if 'data-placeholder' in attrs:
            self.error('Unreplaced scaffold placeholder')
        if 'id' in attrs:
            if attrs['id'] in self.ids:
                self.error(f'Duplicate id: {attrs["id"]}')
            self.ids.add(attrs['id'])
        if 'data-step' in attrs and not re.fullmatch(r'\d+', attrs['data-step'] or ''):
            self.error('data-step must be a non-negative integer')
        for key in ('src', 'poster'):
            if key in attrs:
                self.resource(attrs[key], f'{tag}[{key}]')
        if 'srcset' in attrs:
            self.error('srcset needs manual conversion to a single embedded src')
        if tag in ('image', 'use', 'link'):
            self.resource(attrs.get('href') or attrs.get('xlink:href'), f'{tag}[href]')
        if tag == 'object':
            self.resource(attrs.get('data'), 'object[data]')
        if tag in ('iframe', 'object', 'embed'):
            self.warnings.append(f'Embedded {tag}: inspect nested content and resource loading manually')
        if 'style' in attrs:
            self.css.append(attrs['style'])
        if tag == 'style':
            self.in_style = True

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        self.handle_endtag(tag)

    def handle_endtag(self, tag):
        if tag == 'style':
            self.in_style = False

    def handle_data(self, data):
        if self.in_style:
            self.css.append(data)

    def result(self):
        if self.stages != 1:
            self.error(f'Expected one deck-stage, found {self.stages}')
        if not self.slides:
            self.error('No slides found')
        for css in self.css:
            css = re.sub(r'/\*.*?\*/', '', css, flags=re.S)
            if re.search(r'@import\b', css, re.I):
                self.error('CSS @import must be inlined')
            for match in re.finditer(r'url\(\s*(?:"([^"]*)"|\x27([^\x27]*)\x27|([^)]*))\s*\)', css, re.I):
                value = next(x for x in match.groups() if x is not None).strip()
                self.resource(value, 'CSS url()')
        return {
            'passed': not self.errors, 'slides': self.slides,
            'errors': list(dict.fromkeys(self.errors)),
            'warnings': list(dict.fromkeys(self.warnings)),
            'scope': 'Static resource/structure preflight only. Browser rendering, dynamic network activity, content accuracy and design require separate review.'
        }

def check(text):
    parser = Preflight()
    parser.feed(text)
    parser.close()
    return parser.result()

def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('html', type=Path)
    cli.add_argument('--require-numbered', action='store_true')
    args = cli.parse_args()
    report = check(args.html.read_text(encoding='utf-8'))
    if args.require_numbered and not re.fullmatch(r'\d{3,}\.html', args.html.name):
        report['errors'].append('Final filename must contain at least three digits and .html')
        report['passed'] = False
    print(json.dumps(report, ensure_ascii=False, indent=2))
    raise SystemExit(0 if report['passed'] else 1)

if __name__ == '__main__':
    main()
