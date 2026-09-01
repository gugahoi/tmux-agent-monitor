#!/usr/bin/env bash
# Prep an isolated tmux server (socket "tam-demo") for the demo recording:
# one session per agent, plugin + adapters wired, no pre-stamped state —
# we're using real CLIs on-camera so their own hooks write state.
# Usage: docs/demo-setup.sh   (then use docs/demo-record.sh or asciinema)
set -u
SOCK="${1:-tam-demo}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmux -L "$SOCK" kill-server 2>/dev/null || true

# shell session to record from (driven by camera)
tmux -L "$SOCK" new-session -d -s demo -x 120 -y 32

# bind picker to plain 'A' for one-confined demo; plugin loads after
tmux -L "$SOCK" set-option -g @agent-monitor-key 'A'
TMUX="$(tmux -L "$SOCK" display-message -p '#{socket_path}'),0,0" \
  bash "$REPO/agent-monitor.tmux"

# state helper must be reachable for hooks straight from this repo
tmux -L "$SOCK" set-option -g @agent_scripts "$REPO/scripts"

# one session per real agent, launched interactively (they stamp state on-cam)
for pair in claude:claude opencode:opencode pi:pi; do
  s="${pair%%:*}"; a="${pair##*:}"
  tmux -L "$SOCK" new-session -d -s "$s" -x 120 -y 32 "$a"
done

echo "demo sessions: demo, claude, opencode, pi"
echo "attach: tmux -L $SOCK attach -t demo"
