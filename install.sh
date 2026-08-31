#!/usr/bin/env bash
# Ad-hoc installer for the agent-side adapters. The tmux side installs via TPM;
# this handles what a tmux plugin can't reach: each agent's own config dir.
# Symlinks (not copies) so edits in this repo reflect live. Idempotent.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

link() { mkdir -p "$(dirname "$2")"; ln -sfn "$1" "$2"; echo "  linked $2"; }

# runtime dep for the Alt+a picker (not needed for this script, checked for DX)
command -v fzf >/dev/null 2>&1 || echo "note: fzf not found — the Alt+a picker needs it (e.g. brew install fzf)"

echo "claude:"
if [ -d "$HOME/.claude" ]; then
  link "$REPO/scripts/tmux-agent-state.sh" "$HOME/.claude/tmux-agent-state.sh"
  SETTINGS="$HOME/.claude/settings.json"
  if command -v jq >/dev/null 2>&1; then
    [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
    cp "$SETTINGS" "$SETTINGS.bak"
    # Concat, not replace: append our hook to each event's existing array so
    # other hooks (e.g. notify.sh) survive. Idempotent — strips any prior
    # tmux-agent-state.sh entry first, so re-running doesn't duplicate.
    jq -s '.[0] as $cur | .[1] as $new
      | reduce ($new.hooks | keys[]) as $ev ($cur;
          .hooks[$ev] =
            (((.hooks[$ev] // [])
              | map(select((.hooks | any(.command | test("tmux-agent-state.sh"))) | not)))
             + $new.hooks[$ev]))' \
      "$SETTINGS.bak" "$REPO/adapters/claude/hooks.json" > "$SETTINGS"
    echo "  merged hooks into $SETTINGS (backup: $SETTINGS.bak)"
  else
    echo "  jq not found — merge $REPO/adapters/claude/hooks.json into $SETTINGS by hand"
  fi
else
  echo "  skipped — ~/.claude not found (install Claude Code, then re-run)"
fi

echo "pi:"
if [ -d "$HOME/.config/pi" ]; then
  link "$REPO/adapters/pi/tmux-status" "$HOME/.config/pi/extensions/tmux-status"
else
  echo "  skipped — ~/.config/pi not found (install pi, then re-run)"
fi

echo "opencode:"
if [ -d "$HOME/.config/opencode" ]; then
  link "$REPO/adapters/opencode/tmux-status.ts" "$HOME/.config/opencode/plugin/tmux-status.ts"
else
  echo "  skipped — ~/.config/opencode not found (install opencode, then re-run)"
fi

echo "done. restart running agents to load their adapter."
