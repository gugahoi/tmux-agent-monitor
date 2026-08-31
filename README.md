# tmux-agent-monitor

**🚦 Air-traffic control for parallel AI coding agents — see which tmux session needs you, jump to it in one keystroke.**

[![CI](https://github.com/gugahoi/tmux-agent-monitor/actions/workflows/ci.yml/badge.svg)](https://github.com/gugahoi/tmux-agent-monitor/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![tmux ≥ 3.2](https://img.shields.io/badge/tmux-%E2%89%A5%203.2-green.svg)](https://github.com/tmux/tmux)

## The problem

You run Claude Code, opencode, pi — several at once, one git worktree per task,
one tmux session per worktree. Right now one of them is blocked on a permission
prompt, another finished ten minutes ago, and a third is mid-refactor. tmux is
holding all of them — but nothing tells you *which one needs a decision*.

So you cycle through sessions reading spinners, or you forget one entirely and
it sits blocked for an hour.

## The fix

Every agent gets a traffic light — ⚪ idle · 🟡 busy · 🔴 waiting for you ·
🟢 done (unreviewed) — and `Alt+a` opens a picker with the ones that need you
on top, how long they've been waiting, and a live preview:

```
🤖 status · age · agent · worktree · session
╭────────────────────────────────────────────╮
│ 🔴 waiting   4m  claude    flux/api       │
│ 🔴 waiting  12s  opencode  flux/web       │
│ 🟢 done      9m  pi        dotfiles       │
│ 🟡 busy          claude    sandbox        │
╰────────────────────────────────────────────╯
╎ Enter jumps to the session · preview below ╎
```

<!-- TODO(demo): replace this ASCII mock with a real recording of the picker
     (e.g. vhs or asciinema + agg), committed as docs/demo.gif and embedded here. -->

No daemon. No database. No background process. Agents stamp their own state
into tmux pane options through their **native hook systems** — tmux itself is
the state store.

## Install

Requirements: **tmux ≥ 3.2** · **fzf** (for the picker) · **jq** (optional —
auto-merges the Claude hooks for you)

**1. tmux side (TPM)** — add to `~/.tmux.conf`:

```tmux
set -g @plugin 'gugahoi/tmux-agent-monitor'
```

`prefix + I` to install. That wires the picker key and the focus-acknowledge hook.

**2. agent side** — each agent needs its tiny adapter linked into its own
config dir:

```sh
~/.tmux/plugins/tmux-agent-monitor/install.sh
```

(Or clone the repo anywhere and run `./install.sh`.) Claude's hooks are merged
into `~/.claude/settings.json` — existing hooks are preserved, backup written
to `settings.json.bak`. Adapters for agents you don't have installed are
skipped. **Restart running agents once** so they pick up the adapter.

| agent    | mechanism                           | states                              |
|----------|-------------------------------------|-------------------------------------|
| claude   | hooks → `settings.json`             | idle · busy · wait · done           |
| opencode | plugin → `~/.config/opencode/plugin/` | idle · busy · wait · done         |
| pi       | extension → `~/.config/pi/extensions/` | idle · busy · done (no mid-turn wait) |

## Use

- **`Alt+a`** — picker across *all* sessions: waiting-first (longest wait
  first), live pane preview, Enter jumps there. Rebind with
  `set -g @agent-monitor-key 'M-g'` (before the plugin loads).
- **Focus = acknowledged** — land on a 🔴/🟢 pane and it quietly flips to ⚪.
- **Status-bar roll-up** — a live `🔴2 🟢1` count in your `status-right`,
  refreshed on tmux's normal `status-interval`. Opt in (off by default so it
  never touches a bar you compose):

  ```tmux
  set -g @agent-monitor-status 'on'   # before the plugin loads
  ```

  Prefer to place it yourself? Leave it off and put
  `#(~/.tmux/plugins/tmux-agent-monitor/scripts/tmux-agent-summary.sh)`
  wherever you want in your own `status-right`.

- **Notifications (opt-in)** — run any command when an agent *enters* the
  waiting state (edge-triggered, fires once per wait). `{agent}` and `{pane}`
  are substituted:

  ```tmux
  # flash a message on every attached client (helper ships with the plugin)
  set -g @agent-monitor-on-wait '$HOME/.tmux/plugins/tmux-agent-monitor/scripts/tmux-agent-notify.sh "{agent} needs input"'

  # macOS Notification Center
  set -g @agent-monitor-on-wait 'osascript -e "display notification \"{agent} needs input\" with title \"tmux-agent-monitor\""'

  # Linux
  set -g @agent-monitor-on-wait 'notify-send tmux-agent-monitor "{agent} needs input"'
  ```

## How it works

1. **Agents report their own state.** Claude Code hooks, an opencode plugin and
   a pi extension stamp two per-pane tmux options on lifecycle events:
   `@agent` (which agent) and `@agent_state`, plus a timestamp. Prompt
   submitted → 🟡 busy · permission needed → 🔴 waiting · turn finished →
   🟢 done (⚪ if you're already watching) · session ended → untracked. Because
   state comes from the agents' own events — not from scraping pane output —
   spinners, TUI repaints and locales can't fool it.
2. **tmux is the database.** The picker and roll-up are one `tmux list-panes`
   over those options — run when you press the key, or when tmux refreshes your
   status bar anyway. Nothing polls in the background; there is no server but
   tmux itself.
3. **Focusing acknowledges.** A `pane-focus-in` hook downgrades 🔴/🟢 to ⚪ —
   if you're looking at it, it's not pending any more.

## Add your own agent

No plugin API needed — any agent that can run a shell command on lifecycle
events can join. `scripts/tmux-agent-state.sh` is the whole contract (it
no-ops outside tmux):

```sh
tmux-agent-state.sh <name> start    # session began       → tracked, idle
tmux-agent-state.sh <name> prompt   # user submitted work → busy
tmux-agent-state.sh <name> notify   # needs input         → waiting
tmux-agent-state.sh <name> stop     # turn ended          → done (idle if watched)
tmux-agent-state.sh <name> end      # session over        → untracked
```

Wire those to your agent's hook system (or a wrapper alias) and it shows up in
the picker. PRs for new adapters are welcome — see `adapters/` for examples
(~20 lines each).

## Why not …?

| alternative | how this differs |
|---|---|
| **Agent orchestrators** (claude-squad, Vibe Kanban, Conductor…) | They *launch and manage* agents inside their own UI and process model. This doesn't run agents — it watches the ones you already run, in the terminal you already use. Different weight class; they can even coexist. |
| **Screen-scraping notifiers** | Parsing pane text for “Do you want to…” breaks on repaints, spinners and locales. Here the agent reports state through native hooks — exact by construction. |
| **Per-session status lines** (ccstatusline & co.) | They describe the agent in the session you're *already looking at*. This is cross-session triage: *which of the N sessions needs me right now?* |
| **tmux `monitor-activity` / bells** | “something moved in window 3” ≠ “an agent needs a decision” — and there's no queue of pending agents. |
| **Your own pile of shell scripts** | That's all this is — ~250 lines with the sharp edges (hook merging, idempotency, focus semantics) already sanded down. |

## Configuration

| option | default | purpose |
|---|---|---|
| `@agent-monitor-key` | `M-a` | picker key binding |
| `@agent-monitor-status` | off | `on` prepends the roll-up to your `status-right` |
| `@agent-monitor-on-wait` | *(empty)* | shell command run when an agent enters waiting |

## Troubleshooting

- **Nothing shows up in the picker** — adapters load when an agent starts:
  restart the agent. Check a pane is tracked with
  `tmux display-message -p '#{@agent} #{@agent_state}'` inside it.
- **Picker complains about fzf** — install it (`brew install fzf`).
- **`Alt+a` does nothing** — on macOS Terminal enable “Use Option as Meta key”;
  in iTerm2 set the Option key to “Esc+”. Or rebind via `@agent-monitor-key`.
- **install.sh said “skipped”** — it only links adapters for agents whose
  config dir exists; install the agent and re-run.
- **Claude hooks weren't merged** — `jq` is missing; merge
  `adapters/claude/hooks.json` into `~/.claude/settings.json` by hand.
- **Status bar shows nothing** — the roll-up is opt-in, and empty by design
  when nothing is pending.

## Layout

```
agent-monitor.tmux          TPM entry: focus-acknowledge hook + picker binding
install.sh                  links agent adapters into their config dirs (idempotent)
scripts/
  tmux-agent-state.sh       state stamp — used by claude, generic CLI for any agent
  tmux-agent-picker.sh      the Alt+a picker (needs fzf)
  tmux-agent-summary.sh     status-bar roll-up
  tmux-agent-notify.sh      optional on-wait notifier (messages all attached clients)
adapters/{claude,opencode,pi}/
```

## Roadmap

- More community adapters (aider, codex, gemini-cli) via the generic CLI
- Optional escalation when an agent waits longer than a threshold
- Ideas welcome — open an issue

Deliberately **not** on the roadmap: a daemon, a web UI, orchestration. The
goal is to stay a small tmux plugin.

## Contributing

Issues and PRs welcome. Please include your tmux version (`tmux -V`) and agent
versions in bug reports. New adapters: keep them tiny, dependency-free, and
follow the existing style.

## License

[MIT](LICENSE)
