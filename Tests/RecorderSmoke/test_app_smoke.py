"""Exercise the smoke command with controlled app/inspector process boundaries."""
import contextlib
import io
import itertools
import json
import pathlib
import runpy
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

REPO = pathlib.Path(__file__).resolve().parents[2]


class SmokeCommandTests(unittest.TestCase):
    def run_smoke(self, inspector_code, completes=True):
        with tempfile.TemporaryDirectory() as folder:
            repo = pathlib.Path(folder)
            (repo / 'Scripts').mkdir()
            script = repo / 'Scripts/test-recorder-app.py'
            shutil.copyfile(REPO / 'Scripts/test-recorder-app.py', script)
            state = {'complete': False, 'stopped': False, 'inspected': False}

            class App:
                def __init__(self, command, **kwargs):
                    root = pathlib.Path(command[command.index('--app-data-folder') + 1])
                    choice = root / 'x-username-sharing-v1.json'
                    # The offline fixture must skip the sharing modal without
                    # creating any grant or withdrawal work.
                    saved = json.loads(choice.read_text())
                    if saved['choice'] != 'declined' or saved.get('grant') or saved['withdrawals']:
                        raise AssertionError('recording fixture enabled sharing')
                    if choice.stat().st_mode & 0o777 != 0o600:
                        raise AssertionError('recording fixture choice permissions')
                    self.run = root / 'runs/fixture'
                    self.run.mkdir(parents=True)
                    (self.run / 'demo.mp4').write_bytes(b'partial movie')
                    state['app'] = self

                def poll(self):
                    return None

                def terminate(self):
                    state['stopped'] = True

                def wait(self, **kwargs):
                    return 0

            def finish_writing(_):
                if not completes:
                    return
                run = state['app'].run
                (run / 'demo.mp4').write_bytes(b'finished movie')
                # The real pipeline opens post.log only after Recorder returns.
                (run / 'post.log').write_text('step: load compose\n')
                state['complete'] = True

            def inspect(command, **kwargs):
                if command[0] == 'ffprobe':
                    return subprocess.CompletedProcess(command, 0, '{"format":{"duration":"18.0"}}')
                self.assertTrue(state['complete'], 'inspected before writing finished')
                self.assertTrue(state['stopped'], 'inspected before app termination')
                self.assertEqual(command[2], 'inspect-animated')
                self.assertEqual(pathlib.Path(command[3]).read_bytes(), b'finished movie')
                state['inspected'] = True
                if inspector_code and kwargs.get('check'):
                    raise subprocess.CalledProcessError(inspector_code, command)
                return subprocess.CompletedProcess(command, inspector_code)

            output = io.StringIO()
            with patch('subprocess.Popen', App), patch('subprocess.run', inspect), \
                    patch('time.sleep', finish_writing), \
                    patch('time.monotonic', side_effect=itertools.count()), \
                    contextlib.redirect_stdout(output):
                try:
                    runpy.run_path(str(script), run_name='__main__')
                except subprocess.CalledProcessError as error:
                    return error.returncode, output.getvalue(), state
                except RuntimeError as error:
                    return 1, output.getvalue() + str(error), state
            return 0, output.getvalue(), state

    def test_rejects_failed_content_inspection(self):
        code, output, state = self.run_smoke(7)
        self.assertNotEqual(code, 0)
        self.assertNotIn('PASS built app', output)
        self.assertTrue(state['inspected'])

    def test_passes_after_completed_movie_passes_inspection(self):
        code, output, state = self.run_smoke(0)
        self.assertEqual(code, 0)
        self.assertTrue(state['inspected'])
        self.assertIn('PASS built app', output)

    def test_incomplete_movie_times_out_without_inspection(self):
        code, output, state = self.run_smoke(0, completes=False)
        self.assertNotEqual(code, 0)
        self.assertIn('no complete movie within 120s', output)
        self.assertFalse(state['inspected'])
        self.assertTrue(state['stopped'])
        self.assertNotIn('PASS built app', output)


if __name__ == '__main__':
    unittest.main()
