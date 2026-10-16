import concurrent.futures
import tempfile
import unittest
from pathlib import Path

from create_post import create_post, next_number
from check_post import format_post, inspect_post

TITLE = 'Jev 不生成内容，怎么给邮件分类？'
DESCRIPTION = ('Jev 把分类、评分和是否需要处理，变成程序可以直接使用的判断结果。'
               '这期用客户邮件讲清它如何工作、为什么适合高频判断，以及怎么接入自己的流程。'
               '还会演示从准备授权到批量处理邮件的过程，帮助你把概念变成一个能运行的小工具。')


class PostTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'post'

    def test_first_and_next_and_roundtrip(self):
        first = create_post(self.root, TITLE, DESCRIPTION)
        second = create_post(self.root, '第二期标题', DESCRIPTION)
        self.assertEqual((first['number'], second['number']), ('004', '005'))
        self.assertEqual(Path(first['post']).read_text(), format_post(TITLE, DESCRIPTION))
        report = inspect_post(Path(first['post']).read_text())
        self.assertTrue(report['structure_passed'])
        self.assertEqual(report['review'], [])
        self.assertEqual(list(Path(first['directory']).iterdir()), [Path(first['post'])])

    def test_gaps_numeric_files_and_skill_directories(self):
        self.root.mkdir()
        for name in ('004', '008', 'script-to-post', '004-not-number', '.cache'):
            (self.root / name).mkdir()
        (self.root / '009').write_text('existing file')
        self.assertEqual(create_post(self.root, TITLE, DESCRIPTION)['number'], '010')
        self.assertEqual((self.root / '009').read_text(), 'existing file')

    def test_dry_run_writes_nothing(self):
        result = create_post(self.root, TITLE, DESCRIPTION, dry_run=True)
        self.assertEqual(result['number'], '004')
        self.assertFalse(result['created'])
        self.assertFalse(self.root.exists())

    def test_large_numbers(self):
        self.root.mkdir()
        (self.root / '999').mkdir()
        self.assertEqual(create_post(self.root, TITLE, DESCRIPTION)['number'], '1000')

    def test_concurrent_allocation_never_overwrites(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(lambda n: create_post(self.root, str(n), DESCRIPTION), range(12)))
        self.assertEqual(len({r['number'] for r in results}), 12)
        for n, result in enumerate(results):
            self.assertEqual(inspect_post(Path(result['post']).read_text())['title'], str(n))

    def test_invalid_input_does_not_allocate(self):
        for title, description in [('', DESCRIPTION), ('two\nlines', DESCRIPTION), (TITLE, ''), ('bad\x00', DESCRIPTION)]:
            with self.assertRaises(ValueError):
                create_post(self.root, title, description)
        self.assertFalse(self.root.exists())

    def test_existing_episode_is_unchanged(self):
        r = create_post(self.root, TITLE, DESCRIPTION)
        before = Path(r['post']).read_bytes()
        create_post(self.root, TITLE, '新的正文。')
        self.assertEqual(Path(r['post']).read_bytes(), before)

    def test_length_is_review_not_structure_failure(self):
        result = inspect_post(format_post('测试标题', '这是短正文。'))
        self.assertTrue(result['structure_passed'])
        self.assertTrue(result['review'])

    def test_malformed_post_rejected(self):
        self.assertFalse(inspect_post('标题：\n正文：\n')['structure_passed'])
        self.assertFalse(inspect_post('随便一段文字')['structure_passed'])


if __name__ == '__main__':
    unittest.main()
