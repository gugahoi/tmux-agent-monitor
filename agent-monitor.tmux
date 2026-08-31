#!/usr/bin/env bash
# TPM entry: wires the focus-downgrade hook, the Alt+a picker, and exposes the
# scripts dir. Resolves its own location so nothing is hardcoded to ~/.claude.
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmux set-option -g @agent_scripts "$CURRENT_DIR/scripts"

# Focusing a wait/done pane means I've seen it -> downgrade to idle.
# Appended (-a) so existing pane-focus-in hooks survive; guarded so
# re-sourcing never stacks duplicates.
# shellcheck disable=SC2016  # single-quoted on purpose: the shell runs this when the hook fires
tmux show-hooks -g pane-focus-in 2>/dev/null | grep -qF 'set-option -p @agent_state idle' \
  || tmux set-hook -ga pane-focus-in \
  'run-shell -b "case $(tmux show-option -qpv @agent_state) in wait|done) tmux set-option -p @agent_state idle; tmux set-option -p @agent_state_ts $(date +%s);; esac"'

# Picker key (default M-a). Override: set -g @agent-monitor-key 'M-g'
key="$(tmux show-option -gqv @agent-monitor-key)"; key="${key:-M-a}"
tmux bind-key -n "$key" display-popup -w 80% -h 70% -E "$CURRENT_DIR/scripts/tmux-agent-picker.sh"

# Opt-in status-right roll-up: set -g @agent-monitor-status 'on'
# Idempotent — the marker check means re-sourcing never appends twice.
if [ "$(tmux show-option -gqv @agent-monitor-status)" = on ]; then
  sr="$(tmux show-option -gqv status-right)"
  case "$sr" in
    *tmux-agent-summary*) ;;  # already wired
    *) tmux set-option -g status-right "#($CURRENT_DIR/scripts/tmux-agent-summary.sh) $sr" ;;
  esac
fi
