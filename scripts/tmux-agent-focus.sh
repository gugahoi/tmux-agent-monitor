#!/usr/bin/env bash
# Notification click callback. No terminal or inherited TMUX/PATH is required.
# Usage: tmux-agent-focus.sh <socket> <pane> <server-pid> [absolute-tmux-path]
# Switch the most recently active writable, non-control client. Never attach a
# new client: the callback has no TTY. Stale notifications quietly do nothing.
set -u
[ "$#" -ge 3 ] && [ "$#" -le 4 ] || exit 1
socket=$1; pane=$2; server_pid=$3; tmux_bin=${4:-tmux}
[[ "$pane" =~ ^%[0-9]+$ && "$server_pid" =~ ^[0-9]+$ ]] || exit 1
tmux_cmd=("$tmux_bin" -S "$socket")

# A pane id is stable across renames/moves, but can be reused after a server
# restart. Check both identities before changing any client's selection.
identity=$("${tmux_cmd[@]}" display-message -p -t "$pane" '#{pid}:#{pane_id}' 2>/dev/null) || exit 0
[ "$identity" = "$server_pid:$pane" ] || exit 0

client=""; newest=-1
while IFS='|' read -r activity name readonly control; do
  [[ "$activity" =~ ^[0-9]+$ ]] || continue
  if [ "$readonly" = 0 ] && [ "$control" = 0 ] && (( activity > newest )); then
    client=$name; newest=$activity
  fi
done < <("${tmux_cmd[@]}" list-clients -F '#{client_activity}|#{client_name}|#{client_readonly}|#{client_control_mode}' 2>/dev/null)
[ -n "$client" ] || exit 0

# A pane target makes switch-client select its session, window AND pane, and
# reveal it even if another pane in the window was zoomed. -E keeps the GUI
# callback's environment from replacing the session's update-environment vars.
"${tmux_cmd[@]}" switch-client -E -c "$client" -t "$pane" 2>/dev/null || true
