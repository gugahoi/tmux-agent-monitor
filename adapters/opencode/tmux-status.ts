import type { Plugin } from "@opencode-ai/plugin";

// active = this pane is the focused one AND a client is actually attached
// (window_active alone is true even for sessions nobody is looking at).
const ACTIVE = "#{&&:#{&&:#{pane_active},#{window_active}},#{session_attached}}";

export const TmuxStatus: Plugin = async ({ $ }) => {
  if (!process.env.TMUX) return {};
  const pane = process.env.TMUX_PANE ?? "";
  const stamp = async (v: string) => {
    const prev = (
      await $`tmux show-option -qpv @agent_state`.quiet().nothrow().text()
    ).trim();
    await $`tmux set-option -p @agent_state ${v}`.quiet().nothrow();
    await $`tmux set-option -p @agent_state_ts ${Math.floor(Date.now() / 1000)}`.quiet().nothrow();
    // Opt-in notification, fired on *entering* wait/done (edge-triggered).
    // {agent}/{pane}/{branch}/{icon}/{icon_path}/{agent_icon_path}/{badge_path}
    // are substituted before the command runs.
    const hook =
      v === "wait" && prev !== "wait" ? "@agent-monitor-on-wait" :
      v === "done" && prev !== "done" ? "@agent-monitor-on-done" : "";
    if (hook) {
      const cmd = (
        await $`tmux show-option -gqv ${hook}`.quiet().nothrow().text()
      ).trim();
      if (cmd) {
        const branch = (
          await $`tmux display-message -p ${"#{b:pane_current_path}"}`.quiet().nothrow().text()
        ).trim();
        const iconsDir = (
          await $`tmux show-option -gqv @agent_icons`.quiet().nothrow().text()
        ).trim();
        const icon = v === "wait" ? "\u{1F534}" : v === "done" ? "\u{1F7E2}" : "\u26AA";
        const iconPath = iconsDir ? `${iconsDir}/agent-${v}.png` : "";
        const agentIconPath = iconsDir ? `${iconsDir}/logo-opencode.png` : "";
        const badgePath = iconsDir ? `${iconsDir}/badge-opencode-${v}.png` : "";
        const filled = cmd
          .replaceAll("{agent}", "opencode")
          .replaceAll("{pane}", pane)
          .replaceAll("{branch}", branch)
          .replaceAll("{icon}", icon)
          .replaceAll("{icon_path}", iconPath)
          .replaceAll("{agent_icon_path}", agentIconPath)
          .replaceAll("{badge_path}", badgePath);
        await $`tmux run-shell -b ${filled}`.quiet().nothrow();
      }
    }
  };
  await $`tmux set-option -p @agent opencode`.quiet().nothrow();
  return {
    event: async ({ event }) => {
      // Widen to string: opencode's permission event is named permission.updated
      // on the v1 event bus (this plugin) and permission.asked on v2 — handle both.
      const type: string = event.type;
      switch (type) {
        case "message.updated":                             await stamp("busy"); break;
        case "session.idle": {
          // If you're already watching this pane there's nothing to review:
          // idle (no notification), otherwise done.
          const active = (
            await $`tmux display-message -p ${ACTIVE}`.quiet().nothrow().text()
          ).trim();
          await stamp(active === "1" ? "idle" : "done");
          break;
        }
        case "permission.asked": case "permission.updated": await stamp("wait"); break;
        case "session.deleted":
          await $`tmux set-option -up @agent`.quiet().nothrow();
          await $`tmux set-option -up @agent_state`.quiet().nothrow();
          await $`tmux set-option -up @agent_state_ts`.quiet().nothrow();
          break;
      }
    },
  };
};
