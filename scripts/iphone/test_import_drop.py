import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('import_drop.py')


class ImportTests(unittest.TestCase):
    def test_import_dedupe_reject_and_no_network(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            drop = root / 'drop'; drop.mkdir()
            workspace = root / 'brain'; workspace.mkdir()
            row = {'version': 1, 'kind': 'clipboard', 'title': 'Hello', 'text': 'A thought',
                   'captured_at': '2026-09-28T12:00:00Z', 'explicit_capture': True}
            (drop / 'one.json').write_text(json.dumps(row))
            cmd = [sys.executable, str(SCRIPT), '--drop', str(drop), '--workspace', str(workspace)]
            first = subprocess.run(cmd, capture_output=True, text=True)
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertIn('imported=1', first.stdout)
            note = next((workspace / 'Oracle Inbox').glob('*.md'))
            self.assertIn('reviewStatus: new', note.read_text())
            self.assertIn('A thought', note.read_text())
            self.assertIn('duplicates=1', subprocess.run(cmd, capture_output=True, text=True).stdout)
            row['text'] = 'password=topsecret'
            (drop / 'two.json').write_text(json.dumps(row))
            result = subprocess.run(cmd, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertNotIn('topsecret', result.stderr)
            self.assertEqual(len(list((workspace / 'Oracle Inbox').glob('*.md'))), 1)

    def test_clipboard_requires_consent(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); (root / 'drop').mkdir(); (root / 'brain').mkdir()
            row = {'version': 1, 'kind': 'clipboard', 'title': 'x', 'text': 'y', 'captured_at': '2026-01-01T00:00:00Z'}
            (root / 'drop' / 'x.jsonl').write_text(json.dumps(row) + '\n')
            result = subprocess.run([sys.executable, str(SCRIPT), '--drop', str(root / 'drop'), '--workspace', str(root / 'brain')], capture_output=True)
            self.assertEqual(result.returncode, 1)
            self.assertFalse(list((root / 'brain' / 'Oracle Inbox').glob('*.md')))


if __name__ == '__main__':
    unittest.main()
