#!/usr/bin/env bash
# Stamp @agent / @agent_state (+ @agent_state_ts) on the calling agent's pane
# from a hook event.
# Usage: tmux-agent-state.sh <agent> <start|prompt|notify|stop|end>
# Generic CLI helper for any hook-driven agent (claude wires all five events).
set -u
[ -n "${TMUX:-}" ] || exit 0
pane="${TMUX_PANE:-}"; [ -n "$pane" ] || exit 0
agent="${1:-}"; event="${2:-}"
# "focused" = active pane in the session's current window AND a client is
# actually attached to that session (window_active alone is true even for
# sessions nobody is looking at).
active=$(tmux display-message -t "$pane" -p '#{&&:#{&&:#{pane_active},#{window_active}},#{session_attached}}' 2>/dev/null)
case "$event" in
  start)  st="idle" ;;                                    # SessionStart
  prompt) st="busy" ;;                                    # UserPromptSubmit
  notify) st="wait" ;;                                    # Notification
  stop)   [ "$active" = 1 ] && st="idle" || st="done" ;;  # Stop (pane focused = nothing to review)
  end)    tmux set-option -up -t "$pane" @agent
          tmux set-option -up -t "$pane" @agent_state
          tmux set-option -up -t "$pane" @agent_state_ts
          exit 0 ;;
  *) exit 0 ;;
esac
prev=$(tmux show-option -qpv -t "$pane" @agent_state 2>/dev/null)
tmux set-option -p -t "$pane" @agent "$agent"
tmux set-option -p -t "$pane" @agent_state "$st"
tmux set-option -p -t "$pane" @agent_state_ts "$(date +%s)"
# Opt-in notification, fired on *entering* a state (edge-triggered, once).
# Set e.g.: set -g @agent-monitor-on-wait 'tmux-agent-notify.sh "{agent} needs input"'
#           set -g @agent-monitor-on-done 'tmux-agent-notify.sh "{agent} is done"'
# Placeholders {agent} and {pane} are substituted before the command runs.
fire_hook() { # <option>
  local cmd; cmd=$(tmux show-option -gqv "$1" 2>/dev/null)
  [ -n "$cmd" ] || return 0
  cmd=${cmd//\{agent\}/$agent}
  cmd=${cmd//\{pane\}/$pane}
  tmux run-shell -b "$cmd"
}
if [ "$st" = "wait" ] && [ "$prev" != "wait" ]; then fire_hook @agent-monitor-on-wait; fi
if [ "$st" = "done" ] && [ "$prev" != "done" ]; then fire_hook @agent-monitor-on-done; fi
