import argparse
import contextlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch, Mock
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Scripts'))
import prepare_card


class PrepareCardTests(unittest.TestCase):
    def test_only_https_origins(self):
        self.assertEqual(prepare_card.https_origin('https://backend.example/'), 'https://backend.example')
        for value in ['http://backend.example', 'https://user:pass@backend.example',
                      'https://backend.example/path', 'https://backend.example?token=x',
                      'https://backend.example#fragment', 'https://backend.example:444', '//backend.example']:
            with self.subTest(value=value), self.assertRaises(argparse.ArgumentTypeError):
                prepare_card.https_origin(value)

    def test_saves_scoped_url_privately_without_printing_token(self):
        prepared = {'ok': True, 'sessionId': 'test-session', 'token': 'synthetic-secret-token',
                    'tokenExpiresAt': '2030-01-01T00:00:00Z'}
        response = io.BytesIO(json.dumps(prepared).encode())
        opener = Mock()
        opener.open.return_value = contextlib.closing(response)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'card.txt'
            args = ['prepare_card.py', '--base-url', 'https://backend.example', '--output', str(output)]
            stdout = io.StringIO()
            with patch.object(sys, 'argv', args), patch.dict(os.environ, {'APP_TRANSFER_SECRET': 'x' * 32}), \
                 patch('urllib.request.build_opener', return_value=opener), contextlib.redirect_stdout(stdout):
                prepare_card.main()
            query = parse_qs(urlsplit(output.read_text().strip()).query)
            self.assertEqual(query['view'], ['web'])
            self.assertEqual(query['bbSession'], ['test-session'])
            self.assertEqual(query['bbToken'], ['synthetic-secret-token'])
            self.assertEqual(query['target'], ['https://news.ycombinator.com/login'])
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            self.assertNotIn('synthetic-secret-token', stdout.getvalue())
            self.assertEqual(opener.open.call_args.args[0].full_url, 'https://backend.example/api/transfers/prepare')

    def test_existing_output_stops_before_creating_a_session(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'card.txt'
            output.write_text('existing')
            with patch.object(sys, 'argv', ['prepare_card.py', '--base-url', 'https://backend.example', '--output', str(output)]), \
                 patch('urllib.request.build_opener') as build, contextlib.redirect_stderr(io.StringIO()), \
                 self.assertRaises(SystemExit):
                prepare_card.main()
            build.assert_not_called()
            self.assertEqual(output.read_text(), 'existing')


if __name__ == '__main__':
    unittest.main()
