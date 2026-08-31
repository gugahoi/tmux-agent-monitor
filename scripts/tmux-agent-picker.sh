#!/usr/bin/env bash
# Alt+a: pick an AI-agent instance across ALL tmux sessions by status.
set -u

note() { tmux display-message "tmux-agent-monitor: $1" 2>/dev/null || true; exit 0; }

command -v fzf >/dev/null 2>&1 || note "fzf not found (e.g. brew install fzf)"

now=$(date +%s)

# seconds -> compact age ("45s", "4m", "2h", "3d"); empty input -> empty
age() {
  [ -n "$1" ] || return 0
  local s=$(( now - $1 ))
  if   (( s < 60 ));    then printf '%ds' "$s"
  elif (( s < 3600 ));  then printf '%dm' $(( s / 60 ))
  elif (( s < 86400 )); then printf '%dh' $(( s / 3600 ))
  else printf '%dd' $(( s / 86400 )); fi
}

rows() {
  tmux list-panes -a -F '#{@agent}|#{@agent_state}|#{@agent_state_ts}|#{session_name}|#{b:pane_current_path}|#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null \
  | awk -F'|' '$1!=""' \
  | while IFS='|' read -r agent st ts sess dir target; do
      case "$st" in
        # badge padded by hand: printf %Ns counts emoji bytes, not columns
        wait) b="🔴 waiting"; r=0; a=$(age "$ts") ;;
        done) b="🟢 done   "; r=1; a=$(age "$ts") ;;
        busy) b="🟡 busy   "; r=2; a="" ;;
        idle) b="⚪ idle   "; r=3; a="" ;;
        *)    b="   ${st:-?}"; r=9; a="" ;;
      esac
      # hidden rank + epoch fields order the list: state rank, then oldest
      # (longest in that state) first; cut drops them before fzf
      printf '%s\t%s\t%s\t%3s\t%-8s\t%s\t%s\t%s\n' "$r" "${ts:-$now}" "$b" "$a" "$agent" "$dir" "$sess" "$target"
    done
}

list=$(rows | sort -t"$(printf '\t')" -k1,1n -k2,2n | cut -f3-)
[ -n "$list" ] || note "no agents tracked yet — start claude, opencode or pi in a tmux pane"

# shellcheck disable=SC2016  # single quotes on purpose: fzf runs the preview per row
sel=$(printf '%s\n' "$list" \
  | fzf --ansi --with-nth=1,2,3,4,5 --delimiter='\t' \
        --prompt='🤖 ' --header='status · age · agent · worktree · session' \
        --preview 'tmux capture-pane -pt "$(printf "%s" {} | cut -f6)" -S -40' \
        --preview-window 'down:60%:wrap')
[ -z "$sel" ] && exit 0
t=$(printf '%s' "$sel" | cut -f6)
tmux switch-client -t "${t%%:*}"
tmux select-window -t "$t"
tmux select-pane -t "$t"
