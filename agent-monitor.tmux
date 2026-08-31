#!/usr/bin/env bash
# TPM entry: wires the focus-downgrade hook, the Alt+a picker, and exposes the
# scripts dir. Resolves its own location so nothing is hardcoded to ~/.claude.
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmux set-option -g @agent_scripts "$CURRENT_DIR/scripts"

# Focusing a wait/done pane means I've seen it -> downgrade to idle.
tmux set-hook -g pane-focus-in \
  'run-shell -b "case $(tmux show-option -qpv @agent_state) in wait|done) tmux set-option -p @agent_state idle;; esac"'

# Alt+a: pick an agent instance across all sessions.
tmux bind-key -n M-a display-popup -w 80% -h 70% -E "$CURRENT_DIR/scripts/tmux-agent-picker.sh"
