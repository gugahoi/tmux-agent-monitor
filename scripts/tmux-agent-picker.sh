#!/usr/bin/env bash
# Alt+a: pick an AI-agent instance across ALL tmux sessions by status.
set -u

rows() {
  tmux list-panes -a -F '#{@agent}|#{@agent_state}|#{session_name}|#{b:pane_current_path}|#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null \
  | awk -F'|' '$1!=""' \
  | while IFS='|' read -r agent st sess dir target; do
      case "$st" in
        wait) b="🔴 waiting"; r=0 ;; done) b="🟢 done   "; r=1 ;;
        busy) b="🟡 busy   "; r=2 ;; idle) b="⚪ idle   "; r=3 ;;
        *)    b="   ${st:-?}"; r=9 ;;
      esac
      # leading rank field orders the list (wait first); cut drops it before fzf
      printf '%s\t%s\t%-8s\t%s\t%s\t%s\n' "$r" "$b" "$agent" "$dir" "$sess" "$target"
    done
}

sel=$(rows | sort -t"$(printf '\t')" -k1,1n | cut -f2- \
  | fzf --ansi --with-nth=1,2,3,4 --delimiter='\t' \
        --prompt='🤖 ' --header='status · agent · worktree · session' \
        --preview 'tmux capture-pane -pt "$(printf "%s" {} | cut -f5)" -S -40' \
        --preview-window 'down:60%:wrap')
[ -z "$sel" ] && exit 0
t=$(printf '%s' "$sel" | cut -f5)
tmux switch-client -t "${t%%:*}"
tmux select-window -t "$t"
tmux select-pane -t "$t"
