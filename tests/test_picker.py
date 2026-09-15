"""Picker regression tests; only Python's standard library is required."""

import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unicodedata
import unittest


ROOT = Path(__file__).resolve().parents[1]
NOW = 2_000_000_000
FZF = shutil.which("fzf")


def columns(text):
    """Terminal width of the ASCII text and status emoji in these fixtures."""
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in text)


class PickerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)
        self.env = dict(os.environ, PATH=f"{self.path}:{os.environ['PATH']}",
                        TEST_DIR=str(self.path), PICK_TARGET="done-session:2.3")
        self.mock("date", f"printf '%s\\n' {NOW}\n")
        self.mock("tmux", """case "$1" in
  list-panes) cat "$TEST_DIR/panes" ;;
  *) printf '%s\\n' "$*" >> "$TEST_DIR/commands" ;;
esac
""")
        self.mock("fzf", """printf '%s\\n' "$@" > "$TEST_DIR/fzf-args"
cat > "$TEST_DIR/fzf-input"
[ "${CANCEL:-0}" = 1 ] && exit 1
awk -F '\\t' 'NR > 1 && $6 == ENVIRON["PICK_TARGET"] { print; exit }' "$TEST_DIR/fzf-input"
""")
        self.panes = [
            "pi|idle||idle-session|short|idle-session:0.0",
            f"custom-long-agent|busy|{NOW}|busy-session|worktree with spaces|busy-session:1.0",
            f"claude|done|{NOW - 45}|done-session|5966-new-recurring-payment-notification|done-session:2.3",
            f"opencode|wait|{NOW - 4000}|older-wait|tiny|older-wait:3.0",
            f"pi|wait|{NOW - 120}|newer-wait|another-worktree|newer-wait:4.0",
            "|||untracked|ignored|untracked:0.0",
        ]

    def mock(self, name, body):
        path = self.path / name
        path.write_text("#!/usr/bin/env bash\n" + body)
        path.chmod(0o755)

    def run_picker(self):
        (self.path / "panes").write_text("\n".join(self.panes) + "\n")
        subprocess.run(["bash", str(ROOT / "scripts/tmux-agent-picker.sh")],
                       env=self.env, check=True, capture_output=True, text=True)

    def records(self):
        return [line.split("\t") for line in
                (self.path / "fzf-input").read_text().splitlines()]

    def test_header_and_rows_share_column_boundaries(self):
        self.run_picker()
        args = (self.path / "fzf-args").read_text().splitlines()
        self.assertIn("--header-lines=1", args)
        self.assertIn("--tabstop=1", args)
        self.assertIn("--with-nth=1,2,3,4,5", args)
        records = self.records()
        self.assertEqual([field.strip() for field in records[0][:5]],
                         ["status", "age", "agent", "worktree", "session"])
        # With tabstop=1 each delimiter occupies one column. Equal field
        # widths mean all following columns start at the same screen position.
        widths = [columns(field) for field in records[0][:4]]
        for record in records[1:]:
            self.assertEqual(len(record), 6)
            self.assertEqual([columns(field) for field in record[:4]], widths)
        self.assertEqual(records[-1][1].strip(), "")  # idle has no age
        self.assertEqual(records[-2][1].strip(), "")  # busy has no age
        self.assertEqual(records[-2][3].strip(), "worktree with spaces")

    def test_sort_order_and_target_are_preserved(self):
        self.run_picker()
        self.assertEqual([record[5] for record in self.records()[1:]], [
            "older-wait:3.0", "newer-wait:4.0", "done-session:2.3",
            "busy-session:1.0", "idle-session:0.0",
        ])
        self.assertEqual((self.path / "commands").read_text().splitlines(), [
            "switch-client -t done-session",
            "select-window -t done-session:2.3",
            "select-pane -t done-session:2.3",
        ])
        args = (self.path / "fzf-args").read_text().splitlines()
        preview = args[args.index("--preview") + 1]
        selected = "\t".join(self.records()[3])
        subprocess.run(["bash", "-c", preview.replace("{}", shlex.quote(selected))],
                       env=self.env, check=True)
        self.assertEqual((self.path / "commands").read_text().splitlines()[-1],
                         "capture-pane -pt done-session:2.3 -S -40")

    @unittest.skipUnless(FZF, "fzf is not installed")
    def test_real_fzf_excludes_header_and_returns_original_target(self):
        self.run_picker()
        args = (self.path / "fzf-args").read_text().splitlines()
        data = (self.path / "fzf-input").read_text()
        env = dict(os.environ, FZF_DEFAULT_OPTS="", FZF_DEFAULT_OPTS_FILE="/dev/null")
        result = subprocess.run([FZF, *args, "--filter=claude"], input=data,
                                text=True, capture_output=True, env=env, check=True)
        self.assertEqual(result.stdout.rstrip("\n").split("\t")[5], "done-session:2.3")
        result = subprocess.run([FZF, *args, "--filter='status"], input=data,
                                text=True, capture_output=True, env=env)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")

    def test_age_column_expands_for_long_ages(self):
        self.panes.append("pi|wait|1|ancient|old|ancient:0.0")
        self.run_picker()
        records = self.records()
        self.assertEqual(records[1][1].strip(), "23148d")
        self.assertEqual(len(records[0][1]), len(records[1][1]))

    def test_cancel_does_not_switch_panes(self):
        self.env["CANCEL"] = "1"
        self.run_picker()
        self.assertFalse((self.path / "commands").exists())

    def test_no_agents_does_not_open_fzf(self):
        self.panes = ["|||untracked|ignored|untracked:0.0"]
        self.run_picker()
        self.assertFalse((self.path / "fzf-input").exists())
        self.assertIn("no agents tracked yet", (self.path / "commands").read_text())


if __name__ == "__main__":
    unittest.main()
