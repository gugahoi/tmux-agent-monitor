#!/usr/bin/env bash
# Stamp @agent / @agent_state on the calling agent's pane from a hook event.
# Usage: tmux-agent-state.sh <agent> <start|prompt|notify|stop|end>
# Generic CLI helper for any hook-driven agent (claude wires all five events).
set -u
[ -n "${TMUX:-}" ] || exit 0
pane="${TMUX_PANE:-}"; [ -n "$pane" ] || exit 0
agent="${1:-}"; event="${2:-}"
active=$(tmux display-message -t "$pane" -p '#{window_active}' 2>/dev/null)
case "$event" in
  start)  st=idle ;;                                   # SessionStart
  prompt) st=busy ;;                                   # UserPromptSubmit
  notify) st=wait ;;                                   # Notification
  stop)   [ "$active" = 1 ] && st=idle || st=done ;;   # Stop (focused = nothing to review)
  end)    tmux set-option -up -t "$pane" @agent; tmux set-option -up -t "$pane" @agent_state; exit 0 ;;
  *) exit 0 ;;
esac
tmux set-option -p -t "$pane" @agent "$agent"
tmux set-option -p -t "$pane" @agent_state "$st"
