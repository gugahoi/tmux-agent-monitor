"""Clickable notifications and headless focus callbacks; no macOS GUI required."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
TMUX_MOCK = """import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with (Path(os.environ['TEST_DIR']) / 'tmux-calls').open('a') as log:
    log.write(json.dumps(args) + '\\n')
if args[:1] == ['-S']:
    assert args[1] == os.environ['MOCK_SOCKET']
    args = args[2:]
if os.environ.get('MOCK_MISSING_SERVER') == '1':
    sys.exit(1)
if args[0] == 'display-message':
    if args[-1] == '#{socket_path}':
        print(os.environ['MOCK_SOCKET'])
    elif args[-1] == '#{pid}:#{pane_id}':
        print(os.environ.get('MOCK_IDENTITY', '12345:%7'))
elif args[0] == 'list-clients':
    print(os.environ.get('MOCK_CLIENTS', '100|/dev/ttys001|0|0'))
elif args[0] == 'switch-client':
    sys.exit(int(os.environ.get('MOCK_SWITCH_FAILURE', '0')))
"""
NOTIFIER_MOCK = """import json, os, sys
from pathlib import Path
(Path(os.environ['TEST_DIR']) / 'notification').write_text(json.dumps(sys.argv[1:]))
"""


class MacosNotifyTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)
        # All callbacks exercise quoting of paths, including quotes, dollars,
        # shell metacharacters and newlines; %q is not portable to /bin/sh.
        self.scripts = self.path / "plugin's $dir `name`\nwith spaces"
        self.scripts.mkdir()
        for name in ('tmux-agent-notify-macos.sh', 'tmux-agent-focus.sh'):
            shutil.copyfile(ROOT / 'scripts' / name, self.scripts / name)
        self.bin = self.path / "bin's $tools"
        self.bin.mkdir()
        self.mock('tmux', TMUX_MOCK)
        self.mock('terminal-notifier', NOTIFIER_MOCK)
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        TEST_DIR=str(self.path), TMUX='/tmp/custom,12345,0',
                        TMUX_PANE='%99',
                        MOCK_SOCKET="/tmp/server's $socket `name`\nwith spaces")

    def mock(self, name, body):
        path = self.bin / name
        path.write_text(f'#!{sys.executable}\n' + body)
        path.chmod(0o755)

    def send(self, image='/icons/badge-pi-done.png', app=None, pane='%7'):
        args = [pane, 'worktree "title"', 'pi is done; $(do-not-run)', image]
        if app is not None:
            args.append(app)
        return subprocess.run(['/bin/bash', str(self.scripts / 'tmux-agent-notify-macos.sh'),
                               *args], env=self.env, capture_output=True, text=True)

    def notification(self):
        return json.loads((self.path / 'notification').read_text())

    def click(self):
        args = self.notification()
        callback = args[args.index('-execute') + 1]
        # A GUI callback doesn't inherit the tmux client or Homebrew PATH.
        env = dict(self.env, PATH='/usr/bin:/bin')
        env.pop('TMUX', None)
        env.pop('TMUX_PANE', None)
        (self.path / 'tmux-calls').unlink(missing_ok=True)
        subprocess.run(['/bin/sh', '-c', callback], env=env, check=True,
                       capture_output=True, text=True)

    def calls(self):
        path = self.path / 'tmux-calls'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def switches(self):
        return [call[2:] for call in self.calls() if call[2:3] == ['switch-client']]

    def test_sends_badge_and_ghostty_activation_without_switching(self):
        self.assertEqual(self.send().returncode, 0)
        args = self.notification()
        self.assertEqual(args[:6], ['-title', 'worktree "title"', '-message',
                                   'pi is done; $(do-not-run)', '-activate',
                                   'com.mitchellh.ghostty'])
        self.assertEqual(args[-2:], ['-contentImage', '/icons/badge-pi-done.png'])
        self.assertFalse(any('switch-client' in call for call in self.calls()))

    def test_click_uses_captured_server_pane_and_tmux_executable(self):
        self.assertEqual(self.send().returncode, 0)
        self.click()
        self.assertEqual(self.switches(), [['switch-client', '-E', '-c', '/dev/ttys001', '-t', '%7']])
        for call in self.calls():
            self.assertEqual(call[:2], ['-S', self.env['MOCK_SOCKET']])
        self.assertEqual(self.calls()[0][-1], '#{pid}:#{pane_id}')

    def test_client_is_chosen_at_click_time_excluding_readonly_and_control(self):
        self.assertEqual(self.send().returncode, 0)
        self.env['MOCK_CLIENTS'] = '\n'.join([
            '400|control|0|1', '300|readonly|1|0',
            '100|/dev/ttys001|0|0', '200|/dev/ttys002|0|0',
        ])
        self.click()
        self.assertEqual(self.switches(), [['switch-client', '-E', '-c', '/dev/ttys002', '-t', '%7']])

    def test_closed_pane_or_restarted_server_does_not_switch(self):
        self.assertEqual(self.send().returncode, 0)
        for identity in ('12345:', '12345:%8', '67890:%7'):
            with self.subTest(identity=identity):
                self.env['MOCK_IDENTITY'] = identity
                self.click()
                self.assertEqual(len(self.calls()), 1)
                self.assertEqual(self.switches(), [])

    def test_missing_server_is_a_quiet_noop(self):
        self.assertEqual(self.send().returncode, 0)
        self.env['MOCK_MISSING_SERVER'] = '1'
        self.click()
        self.assertEqual(self.switches(), [])

    def test_no_eligible_client_does_not_attach_or_change_selection(self):
        self.assertEqual(self.send().returncode, 0)
        for clients in ('', '300|readonly|1|0\n400|control|0|1'):
            with self.subTest(clients=clients):
                self.env['MOCK_CLIENTS'] = clients
                self.click()
                self.assertEqual(len(self.calls()), 2)
                self.assertEqual(self.switches(), [])

    def test_client_disappearing_during_click_is_harmless(self):
        self.assertEqual(self.send().returncode, 0)
        self.env['MOCK_SWITCH_FAILURE'] = '1'
        self.click()  # still exits successfully

    def test_optional_image_and_terminal_override(self):
        self.assertEqual(self.send(image='', app='com.apple.Terminal').returncode, 0)
        args = self.notification()
        self.assertNotIn('-contentImage', args)
        self.assertEqual(args[args.index('-activate') + 1], 'com.apple.Terminal')

    def test_send_outside_tmux_is_a_noop(self):
        self.env.pop('TMUX')
        self.assertEqual(self.send().returncode, 0)
        self.assertFalse((self.path / 'notification').exists())
        self.assertEqual(self.calls(), [])

    def test_send_for_closed_pane_is_a_noop(self):
        self.env['MOCK_IDENTITY'] = '12345:'
        self.assertEqual(self.send().returncode, 0)
        self.assertFalse((self.path / 'notification').exists())

    def test_non_pane_targets_are_rejected(self):
        self.assertNotEqual(self.send(pane='some-session').returncode, 0)
        self.assertEqual(self.calls(), [])
        result = subprocess.run(['/bin/bash', str(self.scripts / 'tmux-agent-focus.sh'),
                                 self.env['MOCK_SOCKET'], 'some-session', '12345',
                                 str(self.bin / 'tmux')], env=self.env)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_missing_notifier_has_actionable_error(self):
        (self.bin / 'terminal-notifier').unlink()
        self.env['PATH'] = str(self.bin)
        result = self.send()
        self.assertEqual(result.returncode, 1)
        self.assertIn('brew install terminal-notifier', result.stderr)


if __name__ == '__main__':
    unittest.main()
