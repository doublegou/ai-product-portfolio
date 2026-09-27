"""Synthetic fixtures only; no user image is created, edited or overwritten."""
import hashlib
import tempfile
import unittest
from pathlib import Path

from PIL import Image
from check_covers import check_set


class CoverChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        (self.folder / 'post.txt').write_text('标题：\n测试标题\n\n正文：\n用于测试的描述。\n')
        for name, size in {"3-4": (96, 128), "4-3": (128, 96), "16-9": (160, 90)}.items():
            Image.new('RGB', size, '#303036').save(self.folder / f'{name}.png')

    def run_check(self):
        return check_set(self.folder, min_short=64)

    def test_valid_exact_set_and_no_file_changes(self):
        def hashes():
            return {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in self.folder.iterdir()}
        before = hashes()
        self.assertTrue(self.run_check()['passed'])
        self.assertEqual(before, hashes())

    def test_nearly_16x9_rejected(self):
        Image.new('RGB', (1672, 941)).save(self.folder / '16-9.png')
        report = self.run_check()
        self.assertFalse(report['passed'])
        self.assertTrue(any('NOT exact 16:9' in error for error in report['errors']))

    def test_missing_or_duplicate_ratio_rejected(self):
        p = self.folder / '16-9.png'
        p.unlink()
        self.assertFalse(self.run_check()['passed'])
        Image.new('RGB', (128, 96)).save(self.folder / '4-3.jpg')
        self.assertFalse(self.run_check()['passed'])

    def test_corrupt_image_rejected(self):
        (self.folder / '3-4.png').write_bytes(b'not an image')
        self.assertFalse(self.run_check()['passed'])

    def test_mislabeled_format_rejected(self):
        Image.new('RGB', (96, 128)).save(self.folder / '3-4.png', format='JPEG')
        self.assertFalse(self.run_check()['passed'])

    def test_exif_rotation_rejected(self):
        (self.folder / '3-4.png').unlink()
        exif = Image.Exif()
        exif[274] = 6
        Image.new('RGB', (96, 128)).save(self.folder / '3-4.jpg', exif=exif)
        self.assertFalse(self.run_check()['passed'])

    def test_extra_process_artifact_rejected(self):
        (self.folder / 'script.md').write_text('working notes')
        self.assertFalse(self.run_check()['passed'])

    def test_resolution_and_absent_directory(self):
        self.assertFalse(check_set(self.folder)['passed'])
        self.assertFalse(check_set(self.folder / 'absent')['passed'])

    def test_post_required_and_not_modified(self):
        (self.folder / 'post.txt').unlink()
        self.assertFalse(self.run_check()['passed'])

    def test_animated_output_rejected(self):
        Image.new('RGB', (160, 90), 'black').save(
            self.folder / '16-9.png', save_all=True,
            append_images=[Image.new('RGB', (160, 90), 'white')], duration=100, loop=0)
        self.assertFalse(self.run_check()['passed'])


if __name__ == '__main__':
    unittest.main()
