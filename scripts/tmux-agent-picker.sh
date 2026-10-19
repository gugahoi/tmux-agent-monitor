#!/usr/bin/env bash
# Alt+a: pick an AI-agent instance across ALL tmux sessions by status.
set -u

note() { tmux display-message "tmux-agent-monitor: $1" 2>/dev/null || true; exit 0; }

command -v fzf >/dev/null 2>&1 || note "fzf not found (e.g. brew install fzf)"

now=$(date +%s)
# In a popup, tmux resolves this against the client that opened it.
current_pane=$(tmux display-message -p '#{pane_id}' 2>/dev/null)

# seconds -> compact age ("45s", "4m", "2h", "3d"); empty input -> empty
age() {
  [ -n "$1" ] || return 0
  local s=$(( now - $1 ))
  if   (( s < 60 ));    then printf '%ds' "$s"
  elif (( s < 3600 ));  then printf '%dm' $(( s / 60 ))
  elif (( s < 86400 )); then printf '%dh' $(( s / 3600 ))
  else printf '%dd' $(( s / 86400 )); fi
}

# title last: it may contain '|' (read leaves the rest of the line in it).
# tmux defaults pane_title to the hostname; blank that for agents that never set one.
rows() {
  tmux list-panes -a -F '#{@agent}|#{@agent_state}|#{@agent_state_ts}|#{session_name}|#{pane_current_path}|#{session_name}:#{window_index}.#{pane_index}|#{pane_id}|#{?#{==:#{pane_title},#{host}},,#{pane_title}}' 2>/dev/null \
  | awk -F'|' '$1!=""' \
  | while IFS='|' read -r agent st ts sess cwd target pane_id title; do
      [ -n "$current_pane" ] && [ "$pane_id" = "$current_pane" ] && continue
      # repo is named after the git dir all its worktrees share: repo/.git,
      # repo/.bare and repo.git all give "repo". Detached HEAD shows as HEAD.
      { read -r common; read -r branch; } < <(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir --abbrev-ref HEAD 2>/dev/null)
      case ${common##*/} in .*) common=${common%/*} ;; esac
      repo=${common##*/}; repo=${repo%.git}
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
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$r" "${ts:-$now}" "$b" "$a" "$agent" "$repo" "$branch" "$sess" "$title" "$target"
    done
}

list=$(rows | sort -t"$(printf '\t')" -k1,1n -k2,2n | cut -f3-)
[ -n "$list" ] || note "no other agents to show"

# Measure once, then use the same format for the header and every row.
# Status badges already occupy 10 terminal columns (including the wide emoji).
# Keep tabs as field delimiters for preview/selection, but render each as one
# space in fzf so tab stops cannot change the explicit column padding.
# Long agent/repo/branch/session names are clipped to max_width so the title
# stays on screen; ASCII ".." because mawk counts bytes, not columns.
table() {
  awk -F '\t' '
    BEGIN {
      OFS = "\t"; max_width = 24
      age_width = 3; agent_width = 8; repo_width = 4; branch_width = 6; sess_width = 7
      fmt = "%s \t%*s \t%-*s \t%-*s \t%-*s \t%-*s \t%s\t%s\n"
    }
    {
      for (i = 3; i <= 6; i++)
        if (length($i) > max_width) $i = substr($i, 1, max_width - 2) ".."
      lines[NR] = $0
      if (length($2) > age_width) age_width = length($2)
      if (length($3) > agent_width) agent_width = length($3)
      if (length($4) > repo_width) repo_width = length($4)
      if (length($5) > branch_width) branch_width = length($5)
      if (length($6) > sess_width) sess_width = length($6)
    }
    END {
      printf fmt, "status    ", age_width, "age", agent_width, "agent", repo_width, "repo", branch_width, "branch", sess_width, "session", "title", ""
      for (row = 1; row <= NR; row++) {
        split(lines[row], fields, "\t")
        printf fmt, fields[1], age_width, fields[2], agent_width, fields[3], repo_width, fields[4], branch_width, fields[5], sess_width, fields[6], fields[7], fields[8]
      }
    }
  '
}

# shellcheck disable=SC2016  # single quotes on purpose: fzf runs the preview per row
sel=$(printf '%s\n' "$list" | table \
  | fzf --ansi --with-nth=1,2,3,4,5,6,7 --delimiter='\t' --tabstop=1 \
        --prompt='🤖 ' --header-lines=1 \
        --preview 'tmux capture-pane -pt "$(printf "%s" {} | cut -f8)" -S -40' \
        --preview-window 'down:60%:wrap')
[ -z "$sel" ] && exit 0
t=$(printf '%s' "$sel" | cut -f8)
tmux switch-client -t "${t%%:*}"
tmux select-window -t "$t"
tmux select-pane -t "$t"
