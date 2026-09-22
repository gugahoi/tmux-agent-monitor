#!/usr/bin/env bash
# Clickable terminal-notifier notifications; Ghostty is the default terminal.
# Run from a tmux notification hook, with {pane} passed explicitly (run-shell's
# TMUX_PANE may belong to a different pane than the agent that fired the hook).
# Usage: tmux-agent-notify-macos.sh <pane> <title> <message> [image] [app-bundle-id]
set -u
if [ "$#" -lt 3 ] || [ "$#" -gt 5 ]; then
  echo 'Usage: tmux-agent-notify-macos.sh <pane> <title> <message> [image] [app-bundle-id]' >&2
  exit 1
fi
[ -n "${TMUX:-}" ] || exit 0
pane=$1; title=$2; message=$3; image=${4:-}; app=${5:-com.mitchellh.ghostty}
[[ "$pane" =~ ^%[0-9]+$ ]] || exit 1
tmux_bin=$(command -v tmux) || { echo 'tmux-agent-monitor: tmux not found' >&2; exit 1; }
command -v terminal-notifier >/dev/null 2>&1 || {
  echo 'tmux-agent-monitor: terminal-notifier not found (brew install terminal-notifier)' >&2
  exit 1
}
scripts_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# Capture server + executable at delivery time: Notification Center's callback
# may run with neither TMUX nor Homebrew on PATH, or after a server restart.
socket=$("$tmux_bin" display-message -p -t "$pane" '#{socket_path}' 2>/dev/null) || exit 0
identity=$("$tmux_bin" display-message -p -t "$pane" '#{pid}:#{pane_id}' 2>/dev/null) || exit 0
server_pid=${identity%%:*}
[[ -n "$socket" && "$server_pid" =~ ^[0-9]+$ && "$identity" = "$server_pid:$pane" ]] || exit 0

# terminal-notifier executes via /bin/sh. Use POSIX single-quote escaping,
# rather than printf %q (which can produce Bash-only $'...' strings).
quote() {
  local escaped="'\\''"
  printf "'%s'" "${1//\'/$escaped}"
}
callback="/bin/bash"
for arg in "$scripts_dir/tmux-agent-focus.sh" "$socket" "$pane" "$server_pid" "$tmux_bin"; do
  callback="$callback $(quote "$arg")"
done
args=(-title "$title" -message "$message" -activate "$app" -execute "$callback")
[ -z "$image" ] || args+=(-contentImage "$image")
exec terminal-notifier "${args[@]}"
