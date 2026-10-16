import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from check_handoff import check


class HandoffTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.input = self.root / 'script.md'
        self.input.write_text('reviewed script')
        self.manifest = self.root / 'handoff.json'
        self.manifest.write_text(json.dumps({'task':'sample','files':[{'path':'script.md','sha256':hashlib.sha256(self.input.read_bytes()).hexdigest()}]}))

    def test_reviewed_files_pass(self):
        self.assertTrue(check(self.manifest)['passed'])

    def test_input_revision_requires_review(self):
        self.input.write_text('new script')
        self.assertEqual(check(self.manifest)['errors'][0]['reason'], 'changed_since_review')

    def test_missing_file_fails(self):
        self.input.unlink()
        self.assertEqual(check(self.manifest)['errors'][0]['reason'], 'missing')

    def test_empty_manifest_cannot_claim_success(self):
        self.manifest.write_text('{"task":"sample","files":[]}')
        with self.assertRaises(ValueError):
            check(self.manifest)


if __name__ == '__main__':
    unittest.main()
