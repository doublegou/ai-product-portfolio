import contextlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import run_daily


class DailyPersistenceTest(unittest.TestCase):
    def test_publish_failure_retains_saved_draft_count(self):
        """A downstream exception must not erase an already saved draft."""
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'draft.json'
            def save(*args, **kwargs):
                target.write_text('{"status":"approved"}')
                return target
            with patch('sys.argv', ['run_daily.py', '--product', 'BirdTracker', '--no-research']), \
                 patch.object(run_daily, 'set_run_context'), \
                 patch.object(run_daily, 'log_exception'), \
                 patch.object(run_daily, 'log_event') as events, \
                 patch.object(run_daily, 'create_approved_draft', return_value={'draft':{}, 'final_score':8.6, 'iterations':2}), \
                 patch.object(run_daily, 'save_draft', side_effect=save), \
                 patch.object(run_daily, 'publish_draft_to_xhs', side_effect=RuntimeError('upload control unavailable')), \
                 contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(run_daily.main(), 0)
            self.assertTrue(target.exists())
            end = [call for call in events.call_args_list if call.args[0] == 'run_end'][-1].kwargs
            self.assertEqual(end['saved_count'], 1)
            self.assertEqual(end['failed_count'], 1)
            self.assertEqual(end['status'], 'partial_success')
