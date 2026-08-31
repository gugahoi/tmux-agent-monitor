#!/usr/bin/env bash
# status-right roll-up: count agent panes by state across all sessions.
# Prints e.g. "🔴2 🟢1". Empty when nothing is pending.
set -u
tmux list-panes -a -F '#{@agent}|#{@agent_state}' 2>/dev/null \
| awk -F'|' '
  $1!="" {
    if      ($2=="wait") w++
    else if ($2=="done") d++
    else if ($2=="busy") b++
    else if ($2=="idle") i++
  }
  END {
    out=""
    if (w) out=out "🔴" w " "
    if (d) out=out "🟢" d " "
    if (b) out=out "🟡" b " "
    if (i) out=out "⚪" i " "
    sub(/ $/, "", out)
    print out
  }'
