# tmux-agent-monitor

Know which AI-agent instance across many worktrees needs you, and jump straight
to it. Covers **claude, opencode, pi**. One tmux session per worktree, one agent
per session.

Each agent stamps two per-pane tmux options from its own hooks:

- `@agent` — agent name (`claude`/`opencode`/`pi`). Its presence = a tracked instance.
- `@agent_state` — `idle` ⚪ · `busy` 🟡 · `wait` 🔴 (needs input) · `done` 🟢 (finished, unreviewed).

Focusing a `wait`/`done` pane downgrades it to `idle` — you've seen it.

## Install

**tmux side (TPM):**

```tmux
set -g @plugin 'gugahoi/tmux-agent-monitor'
```

`prefix + I` to install. Wires the `Alt+a` picker and the focus-downgrade hook.

**agent side (ad-hoc):**

```sh
./install.sh
```

Symlinks the adapters into each agent's config dir and merges the claude hooks
into `~/.claude/settings.json` (backup at `settings.json.bak`). Existing hooks are preserved, not replaced. Restart running
agents to load their adapter.

| agent    | mechanism                        | states                    |
|----------|----------------------------------|---------------------------|
| claude   | hooks → `settings.json`          | idle · busy · wait · done |
| opencode | plugin → `~/.config/opencode/plugin/` | idle · busy · wait · done |
| pi       | extension → `~/.config/pi/extensions/` | idle · busy · done (no mid-turn `wait`) |

## Use

- **`Alt+a`** — picker across all sessions, `wait` floats to top, live preview, Enter jumps.
- **status-right roll-up** (optional, manual): add `#(~/path/to/scripts/tmux-agent-summary.sh)`
  to your `status-right`. Prints e.g. `🔴2 🟢1`. Left manual so re-sourcing your
  config doesn't append it repeatedly.

## Layout

```
agent-monitor.tmux        TPM entry: focus hook + Alt+a binding + @agent_scripts
scripts/
  tmux-agent-state.sh     state stamp (claude hooks + generic CLI helper)
  tmux-agent-picker.sh    Alt+a picker (needs fzf)
  tmux-agent-summary.sh   status-right roll-up
adapters/{pi,opencode,claude}/   per-agent adapters, installed by install.sh
```
