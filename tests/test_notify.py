"""Notification-hook substitution tests for tmux-agent-state.sh.

Drives the state script through a state transition with a mocked tmux/date and
asserts the on-wait/on-done command is fired with {agent} {pane} {branch}
{icon} {icon_path} substituted. Only Python's standard library is required.
"""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
NOW = 2_000_000_000

# A mocked tmux that answers the reads the state script makes and records the
# writes we assert on (run-shell = the fired hook; set-option = the stamps).
TMUX_MOCK = """#!/usr/bin/env bash
sub="$1"; shift
last=""; for a in "$@"; do last="$a"; done
case "$sub" in
  display-message)
    case "$last" in
      *pane_current_path*) printf '%s\\n' "${MOCK_BRANCH:-}" ;;
      *)                   printf '%s\\n' "${MOCK_ACTIVE:-0}" ;;
    esac ;;
  show-option)
    case "$last" in
      @agent_state)            printf '%s\\n' "${MOCK_PREV:-}" ;;
      @agent-monitor-on-wait)  printf '%s\\n' "${MOCK_ON_WAIT:-}" ;;
      @agent-monitor-on-done)  printf '%s\\n' "${MOCK_ON_DONE:-}" ;;
      @agent_icons)            printf '%s\\n' "${MOCK_ICONS:-}" ;;
    esac ;;
  run-shell)  printf '%s\\n' "$last" >> "$TEST_DIR/run-shell" ;;
  set-option) printf '%s\\n' "$*"    >> "$TEST_DIR/set-option" ;;
esac
"""


class NotifyTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)
        self.env = dict(
            os.environ,
            PATH=f"{self.path}:{os.environ['PATH']}",
            TEST_DIR=str(self.path),
            TMUX="/tmp/tmux-1/default,1,0",
            TMUX_PANE="%7",
            MOCK_ICONS="/opt/plugin/icons",
            MOCK_BRANCH="5966-new-recurring-payment-notification",
        )
        self.mock("date", f"printf '%s\\n' {NOW}\n")
        self.mock("tmux", TMUX_MOCK)

    def mock(self, name, body):
        path = self.path / name
        path.write_text("#!/usr/bin/env bash\n" + body)
        path.chmod(0o755)

    def run_state(self, event):
        subprocess.run(["bash", str(ROOT / "scripts/tmux-agent-state.sh"), "claude", event],
                       env=self.env, check=True, capture_output=True, text=True)

    def fired(self):
        path = self.path / "run-shell"
        return path.read_text().splitlines() if path.exists() else []

    def test_wait_hook_substitutes_every_placeholder(self):
        self.env["MOCK_ON_WAIT"] = (
            "notify {icon} {agent} on {branch} pane {pane} "
            "img {icon_path} logo {agent_icon_path} badge {badge_path}"
        )
        self.run_state("notify")  # Notification event -> wait
        self.assertEqual(self.fired(), [
            "notify \U0001F534 claude on 5966-new-recurring-payment-notification "
            "pane %7 img /opt/plugin/icons/agent-wait.png "
            "logo /opt/plugin/icons/logo-claude.png "
            "badge /opt/plugin/icons/badge-claude-wait.png",
        ])

    def test_done_hook_uses_done_icon_and_path(self):
        self.env["MOCK_ON_DONE"] = "notify {icon} {agent} done {branch} {icon_path} {badge_path}"
        self.env["MOCK_ACTIVE"] = "0"  # unwatched pane -> stop becomes done
        self.run_state("stop")
        self.assertEqual(self.fired(), [
            "notify \U0001F7E2 claude done 5966-new-recurring-payment-notification "
            "/opt/plugin/icons/agent-done.png /opt/plugin/icons/badge-claude-done.png",
        ])

    def test_icon_paths_are_empty_when_icons_dir_unset(self):
        self.env["MOCK_ON_WAIT"] = "notify [{icon_path}][{agent_icon_path}][{badge_path}]"
        self.env["MOCK_ICONS"] = ""
        self.run_state("notify")
        self.assertEqual(self.fired(), ["notify [][][]"])

    def test_focused_stop_is_idle_and_fires_nothing(self):
        self.env["MOCK_ON_DONE"] = "notify {agent} done"
        self.env["MOCK_ACTIVE"] = "1"  # you're watching -> idle, no done hook
        self.run_state("stop")
        self.assertEqual(self.fired(), [])

    def test_hook_does_not_refire_when_already_in_state(self):
        self.env["MOCK_ON_WAIT"] = "notify {agent}"
        self.env["MOCK_PREV"] = "wait"  # already waiting -> edge already passed
        self.run_state("notify")
        self.assertEqual(self.fired(), [])

    def test_no_hook_configured_fires_nothing(self):
        self.run_state("notify")  # @agent-monitor-on-wait unset
        self.assertEqual(self.fired(), [])


if __name__ == "__main__":
    unittest.main()
