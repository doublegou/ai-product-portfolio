#!/usr/bin/env python3
"""Create a self-contained draft; never overwrite an existing file."""
import argparse
import html
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def scaffold(title):
    css = (ROOT / 'assets/base.css').read_text() + '\n' + (ROOT / 'assets/liquid-controls.css').read_text()
    js = (ROOT / 'assets/state.js').read_text() + '\n' + (ROOT / 'assets/player.js').read_text() + '\n' + (ROOT / 'assets/liquid-controls.js').read_text()
    controls = (ROOT / 'assets/liquid-controls.html').read_text()
    return f'''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{html.escape(title)}</title>
<style>{css}
/* Add this deck's typography, palette and layouts here. */
</style></head><body>
<div class="deck-viewport"><main class="deck-stage" aria-label="演示画布">
<section class="slide" data-placeholder="replace-me"><h1>替换为演示内容</h1></section>
</main></div>
{controls}
<aside class="deck-help" hidden>点击画面 / 空格 / →：下一步<br>←：上一步<br>PageUp / PageDown：翻页<br>R：重播 · V：纯画面 · F：全屏<br>Esc：恢复控件 · 横向滑动：前后推进<br>鼠标移入底部中央：显示控制栏；移出：隐藏</aside>
<script>{js}</script></body></html>'''

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--title', required=True)
    args = parser.parse_args()
    if args.output.suffix.lower() != '.html':
        parser.error('--output must end in .html')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    try:
        with args.output.open('x', encoding='utf-8') as stream:
            stream.write(scaffold(args.title))
    except FileExistsError:
        parser.exit(1, f'Refusing to overwrite: {args.output}\n')
    print(args.output.resolve())

if __name__ == '__main__':
    main()
