# AI agent tmux monitor & picker — plan

Working doc. Goal: know which AI-agent instance across many worktrees needs me,
and jump straight to it. Covers **claude, opencode, pi**. Not yet implemented —
iterating on the design.

Ships as a **dedicated TPM plugin repo, `gugahoi/tmux-agent-monitor`** (one
repository holds the `.tmux` entry, the shell scripts, and the per-agent
adapters). The tmux side loads via TPM; the agent-side adapters are installed
**ad-hoc** into each agent's config dir by an installer script — see "Packaging
& installation".

State lives in two agent-neutral tmux **pane options**:

- `@agent` — the agent name (`claude` / `opencode` / `pi`). Its presence is the
  registry: a pane with `@agent` set *is* a tracked agent instance.
- `@agent_state` — `idle` / `busy` / `wait` / `done`.

## Problem

- One agent instance per worktree, **one tmux session per worktree**.
- Today the only signal is a transient macOS notification (`terminal-notifier`
  via claude's `Notification`/`Stop` hooks). Once dismissed, nothing on screen
  says which instances still need attention. State lives only in my head.
- `window-status-format` is ` #I #W ` — drops `#F`, so even tmux's own
  bell/activity flags aren't rendered. `monitor-bell`/`bell-action any` are set
  but nothing fires them.

## Decisions locked in

- **Layout: session per worktree.** Rules out tmux-native `monitor-bell` +
  `next-window -a` (they only see the *attached* session). Anything useful must
  read across all sessions via `tmux list-panes -a` and jump with `switch-client`.
- **Distinguish states**, not just "needs attention": `wait` vs `done` vs
  `busy` vs `idle`.
- **Per-pane options** (`@agent` + `@agent_state`), not window. Gives the picker
  an exact `session:window.pane` target, and `@agent` doubles as the registry —
  no process-sniffing for `node`.

## State model

| state  | badge | meaning                              |
|--------|-------|--------------------------------------|
| `idle` | ⚪    | alive, nothing pending               |
| `busy` | 🟡    | actively processing                  |
| `wait` | 🔴    | needs input / permission (blocking)  |
| `done` | 🟢    | finished response, unreviewed        |
| (unset)|       | not an agent pane / session ended    |

Focusing a `wait`/`done` pane downgrades it to `idle` (I've now seen it):

```tmux
# .tmux.conf
set-hook -g pane-focus-in 'run-shell -b "case $(tmux show-option -qpv @agent_state) in wait|done) tmux set-option -p @agent_state idle;; esac"'
```

## Per-agent adapters

Each agent stamps `@agent`/`@agent_state` from its own hook surface. Capability
(verified 2026-08-31):

| agent    | mechanism                                             | states achievable | confidence          |
|----------|-------------------------------------------------------|-------------------|---------------------|
| claude   | full hooks (Session/Prompt/Notification/Stop)         | idle·busy·wait·done | solid             |
| **pi**   | **native event bus** `pi.on(channel,…)` — extension   | idle·busy·done (no distinct `wait` — no mid-turn approval) | **solid** — channels verified |
| opencode | TS plugin `event` hook (`session.idle`, `message.updated`, `permission.asked`, `session.created/deleted`) | idle·busy·wait·done | **solid** — `permission.asked` fires on request |

**All three are well-supported: claude ≈ opencode (full four states) → pi (three
states, no distinct `wait`).** pi has no mid-turn approval prompt to surface as
`wait`, so `turn_end → done` ("your turn") covers it.

### claude — shared state script + hook wiring

`~/.claude/tmux-agent-state.sh <agent> <event>` (also the generic CLI stamp
helper for any hook-driven agent):

```bash
#!/usr/bin/env bash
set -u
[ -n "${TMUX:-}" ] || exit 0
pane="${TMUX_PANE:-}"; [ -n "$pane" ] || exit 0
agent="${1:-}"; event="${2:-}"
active=$(tmux display-message -t "$pane" -p '#{window_active}' 2>/dev/null)
case "$event" in
  start)  st=idle ;;                                   # SessionStart
  prompt) st=busy ;;                                   # UserPromptSubmit
  notify) st=wait ;;                                   # Notification
  stop)   [ "$active" = 1 ] && st=idle || st=done ;;   # Stop (focused = nothing to review)
  end)    tmux set-option -up -t "$pane" @agent; tmux set-option -up -t "$pane" @agent_state; exit 0 ;;
  *) exit 0 ;;
esac
tmux set-option -p -t "$pane" @agent "$agent"
tmux set-option -p -t "$pane" @agent_state "$st"
```

Wire into `settings.json` alongside the existing hooks (keep `notify.sh` doing
only macOS notifications):

- `SessionStart`     → `tmux-agent-state.sh claude start`
- `UserPromptSubmit` → `tmux-agent-state.sh claude prompt`  (already clears the notifier)
- `Notification`     → `tmux-agent-state.sh claude notify`
- `Stop`             → `tmux-agent-state.sh claude stop`
- `SessionEnd`       → `tmux-agent-state.sh claude end`

### pi — extension

`~/.config/pi/extensions/tmux-status/index.ts` (~20 lines). Channel strings
**verified** against the runtime event bus (`pi.on` → `eventBus.on`):
`turn_start`, `turn_end`, `session_start`, `session_shutdown`,
`agent_start/end/settled`, `tool_execution_start/end`, `message_*` all emit.

```ts
import { execFile } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const tmux = (...a: string[]) =>
  process.env.TMUX && execFile("tmux", a, () => {});
const set = (v: string) => tmux("set-option", "-p", "@agent_state", v);

export default function tmuxStatus(pi: ExtensionAPI): void {
  tmux("set-option", "-p", "@agent", "pi");
  set("idle");
  pi.on("turn_start", () => set("busy"));
  pi.on("turn_end", () => set("done"));   // focus hook downgrades to idle
  pi.on("session_shutdown", () => tmux("set-option", "-up", "@agent"));
}
```
> **Not `project_trust`:** it is a *decision* handler
> (`ext.handlers.get("project_trust")`, first yes/no wins), not an observe-event,
> and fires once as a trust gate — wrong mechanism and wrong semantics for
> `wait`. Dropped.

pi event types confirmed in `@earendil-works/pi-coding-agent` exports:
`TurnStartEvent`, `TurnEndEvent`, `SessionStartEvent`, `SessionShutdownEvent`,
`ToolExecutionStart/EndEvent`, `ToolCallEvent`, `AgentSettledEvent`,
`Message{Start,End,Update}Event`.

### opencode — plugin

`~/.config/opencode/plugin/tmux-status.ts`:

```ts
import type { Plugin } from "@opencode-ai/plugin";

export const TmuxStatus: Plugin = async ({ $ }) => {
  const set = (v: string) =>
    process.env.TMUX && $`tmux set-option -p @agent_state ${v}`.quiet().nothrow();
  if (process.env.TMUX) await $`tmux set-option -p @agent opencode`.quiet().nothrow();
  return {
    event: async ({ event }) => {
      switch (event.type) {
        case "message.updated":                             await set("busy"); break;
        case "session.idle":                                await set("done"); break;
        case "permission.asked": case "permission.updated": await set("wait"); break;
        case "session.deleted":
          if (process.env.TMUX) await $`tmux set-option -up @agent`.quiet().nothrow();
          break;
      }
    },
  };
};
```
`permission.asked` (installed opencode 1.18.23) **verified to fire on request** —
`PermissionNext.ask()` publishes via `Bus.publish()` *before* awaiting the reply,
so `→ wait` is correct. Older versions named it `permission.updated`; both are
handled. `permission.replied` is unused — focus/`message` events move it off
`wait` naturally.

opencode event types: `session.created`, `session.idle`, `session.deleted`,
`session.error`, `message.updated`, `tool.execute.before/after`,
`permission.asked`, `permission.replied`.

### Fallback wrapper (hook-less agents only)

All three covered agents self-register via the adapters above, so no wrapper is
needed. For a future agent with *no* hook surface, a shell wrapper stamps
`@agent`/`running` on launch and clears on exit:

```bash
# ~/.zshrc (or a stow'd shell file) — only for hook-less agents
_agent_run() {
  local name="$1"; shift
  [ -n "$TMUX" ] && { tmux set-option -p @agent "$name"; tmux set-option -p @agent_state running; }
  command "$name" "$@"; local rc=$?
  [ -n "$TMUX" ] && { tmux set-option -up @agent; tmux set-option -up @agent_state; }
  return $rc
}
# e.g. someagent() { _agent_run someagent "$@"; }
```

## Components

### 1. Picker — `Alt+a` (centerpiece)

Mirrors the existing `sesh`/`wt` popups (`display-popup -E fzf`). Lists every
live agent across all sessions, sorted so `wait` floats to top; live preview of
each pane's last 40 lines; type worktree/agent name to filter; Enter jumps
exactly.

`~/.claude/tmux-agent-picker.sh`:

```bash
#!/usr/bin/env bash
# Alt+a: pick an AI-agent instance across ALL tmux sessions by status.
set -u

rows() {
  tmux list-panes -a -F '#{@agent}|#{@agent_state}|#{session_name}|#{b:pane_current_path}|#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null \
  | awk -F'|' '$1!=""' \
  | while IFS='|' read -r agent st sess dir target; do
      case "$st" in
        wait) b="🔴 waiting" ;; done) b="🟢 done   " ;;
        busy) b="🟡 busy   " ;; idle) b="⚪ idle   " ;;
        *)    b="   ${st:-?}" ;;
      esac
      printf '%s\t%-8s\t%s\t%s\t%s\n' "$b" "$agent" "$dir" "$sess" "$target"
    done
}

sel=$(rows | sort \
  | fzf --ansi --with-nth=1,2,3,4 --delimiter='\t' \
        --prompt='🤖 ' --header='status · agent · worktree · session' \
        --preview 'tmux capture-pane -pt "$(printf "%s" {} | cut -f5)" -S -40' \
        --preview-window 'down:60%:wrap')
[ -z "$sel" ] && exit 0
t=$(printf '%s' "$sel" | cut -f5)
tmux switch-client -t "${t%%:*}"
tmux select-window -t "$t"
tmux select-pane -t "$t"
```

```tmux
bind-key -n M-a display-popup -w 80% -h 70% -E "$HOME/.claude/tmux-agent-picker.sh"
```

### 2. Ambient status-right roll-up (glance)

Live count from any session, refreshes on `status-interval` (10s).
`~/.claude/tmux-agent-summary.sh` counts `@agent_state` over `list-panes -a` and
prints e.g. `🔴2 🟢1`. Prepend `#(~/.claude/tmux-agent-summary.sh)` to
`status-right`.

### 3. `prefix + a` fast jump (optional)

Skip the list, jump straight to the next blocker (`wait` before `done`) across
sessions via `switch-client`. Subsumed by the picker but handy.

### 4. Inline window badge (optional)

Render state in `window-status-format`. Slightly awkward with per-pane state
(format would need to aggregate panes → window). Lower priority; the picker +
roll-up mostly cover it.

## Packaging & installation

Everything lives in **one repository**, structured as a TPM-installable tmux
plugin:

```
tmux-agent-monitor/
  agent-monitor.tmux            # TPM entry: sets hook + M-a binding + options, resolves script dir
  scripts/
    tmux-agent-state.sh         # state stamp (claude hooks + generic CLI helper)
    tmux-agent-picker.sh        # Alt+a picker
    tmux-agent-summary.sh       # status-right roll-up
  adapters/
    pi/tmux-status/index.ts     # → ~/.config/pi/extensions/tmux-status/
    opencode/tmux-status.ts     # → ~/.config/opencode/plugin/
    claude/hooks.json           # snippet to merge into ~/.claude/settings.json
  install.sh                    # ad-hoc installer for the adapters/ side
  README.md
```

**Two install surfaces, on purpose:**

1. **tmux side — TPM.** `set -g @plugin 'gugahoi/tmux-agent-monitor'`. The
   `.tmux` entry resolves its own dir and wires the bindings to `scripts/`, so
   nothing is hardcoded to `~/.claude`.
2. **agent side — ad-hoc.** A tmux plugin can't reach into agent config dirs, so
   `install.sh` symlinks/copies `adapters/` into place: the pi extension → pi's
   extensions dir, the opencode plugin → opencode's plugin dir, and the claude
   hooks snippet merged into `settings.json`. Ad-hoc because each agent owns its
   own config and there's no shared installer across them.

`agent-monitor.tmux` (TPM entry):

```bash
#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmux set-option -g @agent_scripts "$CURRENT_DIR/scripts"

# focus-downgrade hook
tmux set-hook -g pane-focus-in \
  'run-shell -b "case $(tmux show-option -qpv @agent_state) in wait|done) tmux set-option -p @agent_state idle;; esac"'

# Alt+a picker
tmux bind-key -n M-a display-popup -w 80% -h 70% -E "$CURRENT_DIR/scripts/tmux-agent-picker.sh"
```

> **Path note:** paths shown earlier as `~/.claude/tmux-agent-*.sh` resolve to
> `$CURRENT_DIR/scripts/*` once packaged. Exception: the **claude hooks** in
> `settings.json` are invoked by claude (not tmux), so they reference the
> installed script by a stable path (symlink from `install.sh`, or the repo
> path directly).
>
> **status-right roll-up** is left to manual setup — I hand-craft `status-right`,
> so the plugin exposes `scripts/tmux-agent-summary.sh` and I add
> `#(…/tmux-agent-summary.sh)` to my own `status-right` rather than have the
> plugin mutate it (re-sourcing would append repeatedly).

## Open questions / iterate here

1. **Verify `#{@agent}` / `#{@agent_state}` resolve in `list-panes -a`** (pane
   user-options in format context). First thing to check when wiring —
   everything hinges on it.
2. **Multiple agent panes per window** — handled since state is per-pane, but
   confirm the flux-dev-layout case behaves.
3. **`busy` accuracy** — a focused finish goes `idle`; an unfocused finish goes
   `done`. Is `busy` worth keeping, or collapse to just wait/done/idle?
4. **Focus downgrade timing** — should merely *focusing* a `done` pane clear it,
   or only on the next prompt? (Glancing = reviewed vs. actually engaging.)
5. **Inline badge** — build it, or is picker + roll-up enough?
6. **Sort/preview polish** — sort order, preview height, icons, filter by
   worktree vs agent vs session.
7. **Detached sessions** — picker can jump into them (`switch-client` attaches);
   confirm that's desired vs. surfacing them differently.
8. **Naming** — instances keyed by worktree dir + session name. Enough to
   disambiguate, or stamp the agent session title too?
9. **Per-agent hook surfaces — RESOLVED (2026-08-31):**
   - pi: event-bus channels verified against the runtime (`turn_start`,
     `turn_end`, `session_shutdown`, …). `project_trust` dropped (decision
     handler, not observe-event). No distinct `wait`. ✓
   - opencode: `permission.asked` (v1.18.23; older `permission.updated`) **fires
     on request** via `Bus.publish()` before awaiting reply → `wait` correct. ✓
10. **Fallback-wrapper reliability** — clears state on agent exit, but does it
    cover all launch paths? Panes closing clear the option automatically;
    lingering shells need the post-exit clear.
11. **Detect vs stamp** — worth a process-name fallback in the picker for agents
    started without a hook/wrapper, or is stamping the only supported path?
12. **Repo placement — RESOLVED:** dedicated repo `gugahoi/tmux-agent-monitor`,
    TPM-installed. ✓
13. **Adapter install strategy** — `install.sh` symlink (edits reflect live) vs.
    copy (stable, survives repo move)? And how the claude `hooks.json` merge
    handles an existing `settings.json` (jq merge vs. manual).
