#!/usr/bin/env bash
# Flash a message on every attached tmux client. Ready-made target for
# @agent-monitor-on-wait / @agent-monitor-on-done. Placeholders {agent},
# {pane}, {branch} and {icon} are substituted by the adapter before this runs:
#   set -g @agent-monitor-on-wait '$HOME/.tmux/plugins/tmux-agent-monitor/scripts/tmux-agent-notify.sh "{icon} {agent} needs input on {branch}"'
#   set -g @agent-monitor-on-done '$HOME/.tmux/plugins/tmux-agent-monitor/scripts/tmux-agent-notify.sh "{icon} {agent} is done on {branch}"'
# Usage: tmux-agent-notify.sh [message...]
set -u
msg="${*:-"an agent needs input"}"
# display-message format-expands its argument (a pane id like %0 would be
# eaten) — escape % as %% so the message renders literally.
tmux list-clients -F '#{client_name}' 2>/dev/null | while IFS= read -r c; do
  tmux display-message -c "$c" "${msg//%/%%}" 2>/dev/null
done
exit 0
