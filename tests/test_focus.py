"""Optional real-tmux regression test using an isolated server and a PTY client."""

import os
from pathlib import Path
import pty
import shutil
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
TMUX = shutil.which('tmux')


@unittest.skipUnless(TMUX, 'tmux is not installed')
class FocusIntegrationTest(unittest.TestCase):
    def test_headless_callback_selects_moved_pane_and_unzooms_its_window(self):
        # Keep the Unix socket path short enough for macOS's sockaddr_un.
        with tempfile.TemporaryDirectory(prefix='tam-focus-', dir='/tmp') as tmp:
            socket = str(Path(tmp) / 'server')
            env = dict(os.environ, TERM='xterm-256color')
            env.pop('TMUX', None)
            env.pop('TMUX_PANE', None)

            def tmux(*args):
                return subprocess.run([TMUX, '-S', socket, '-f', '/dev/null', *args],
                                      env=env, check=True, capture_output=True,
                                      text=True, timeout=5).stdout.strip()

            client_pid = None
            master = None
            try:
                tmux('new-session', '-d', '-s', 'first', '/bin/sleep 60')
                tmux('new-session', '-d', '-s', 'agent', '/bin/sleep 60')
                pane = tmux('display-message', '-p', '-t', 'agent', '#{pane_id}')
                server_pid = tmux('display-message', '-p', '#{pid}')

                client_pid, master = pty.fork()
                if client_pid == 0:
                    os.execve(TMUX, [TMUX, '-S', socket, 'attach-session', '-t', 'first'], env)

                clients = ''
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    clients = tmux('list-clients', '-F', '#{client_name}')
                    if clients:
                        break
                    time.sleep(0.02)
                self.assertTrue(clients, 'PTY client did not attach')
                self.assertEqual(tmux('list-clients', '-F', '#{client_session}'), 'first')

                # Simulate changes between delivery and click: move the pane,
                # rename its session, and zoom a different pane in its window.
                tmux('new-window', '-d', '-t', 'agent', '-n', 'destination', '/bin/sleep 60')
                other = tmux('display-message', '-p', '-t', 'agent:destination', '#{pane_id}')
                tmux('join-pane', '-d', '-s', pane, '-t', other)
                tmux('rename-session', '-t', 'agent', 'renamed')
                tmux('select-pane', '-t', other)
                tmux('resize-pane', '-Z', '-t', other)
                self.assertEqual(tmux('display-message', '-p', '-t', pane,
                                      '#{window_zoomed_flag}'), '1')

                callback_env = dict(env, PATH='/usr/bin:/bin')
                callback = ['/bin/bash', str(ROOT / 'scripts/tmux-agent-focus.sh'),
                            socket, pane, server_pid, TMUX]
                subprocess.run(callback, env=callback_env, check=True,
                               capture_output=True, text=True, timeout=5)
                self.assertEqual(tmux('list-clients', '-F', '#{client_session}'), 'renamed')
                self.assertEqual(tmux('display-message', '-p', '-t', pane,
                                      '#{pane_active}:#{window_active}:#{window_zoomed_flag}'),
                                 '1:1:0')

                # With no eligible client, do not even alter the selected pane.
                tmux('detach-client', '-t', clients)
                tmux('select-pane', '-t', other)
                subprocess.run(callback, env=callback_env, check=True,
                               capture_output=True, text=True, timeout=5)
                self.assertEqual(tmux('display-message', '-p', '-t', pane, '#{pane_active}'), '0')
            finally:
                subprocess.run([TMUX, '-S', socket, 'kill-server'], env=env,
                               capture_output=True, timeout=5)
                if master is not None:
                    os.close(master)
                if client_pid:
                    os.waitpid(client_pid, 0)


if __name__ == '__main__':
    unittest.main()
