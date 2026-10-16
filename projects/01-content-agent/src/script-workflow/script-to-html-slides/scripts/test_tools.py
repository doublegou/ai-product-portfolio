#!/usr/bin/env python3
"""Regression checks for scaffold/preflight behavior; no design-quality claims."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from check_html import check
from scaffold import scaffold

def ready():
    return scaffold('测试 <script> & 标题').replace('<section class="slide" data-placeholder="replace-me"><h1>替换为演示内容</h1></section>', '<section class="slide"><h1>演示</h1><p data-step="1">核心观点</p></section>')

class ToolsTest(unittest.TestCase):
    def test_inlined_deck(self):
        self.assertTrue(check(ready())['passed'])
        self.assertIn('&lt;script&gt; &amp;', ready())

    def test_unfinished_scaffold_rejected(self):
        self.assertFalse(check(scaffold('测试'))['passed'])

    def test_resource_detection(self):
        for resource in ['<img src="https://example.org/p.png">', '<script src="local.js"></script>', '<style>.x{background:url(../x.png)}</style>', '<style>@import "https://example.org/font.css";</style>', '<svg><image href="x.png"/></svg>']:
            self.assertFalse(check(ready().replace('</main>',resource+'</main>'))['passed'])

    def test_data_and_fragment_resources_allowed(self):
        resource='<img src="data:image/png;base64,AA=="><svg><use href="#symbol"/></svg><style>.x{filter:url(#filter)}</style>'
        self.assertTrue(check(ready().replace('</main>',resource+'</main>'))['passed'])

    def test_bad_step_and_duplicate_id(self):
        self.assertFalse(check(ready().replace('data-step="1"','data-step="oops"'))['passed'])
        self.assertFalse(check(ready().replace('</main>','<i id="x"></i><b id="x"></b></main>'))['passed'])

    def test_existing_file_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            target=Path(directory)/'001.html'
            target.write_text('keep me')
            result=subprocess.run([sys.executable,str(Path(__file__).with_name('scaffold.py')),'--output',str(target),'--title','测试'],capture_output=True)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual(target.read_text(),'keep me')

if __name__=='__main__':
    unittest.main()
