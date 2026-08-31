import type { Plugin } from "@opencode-ai/plugin";

export const TmuxStatus: Plugin = async ({ $ }) => {
  if (!process.env.TMUX) return {};
  const pane = process.env.TMUX_PANE ?? "";
  const stamp = async (v: string) => {
    const prev = (
      await $`tmux show-option -qpv @agent_state`.quiet().nothrow().text()
    ).trim();
    await $`tmux set-option -p @agent_state ${v}`.quiet().nothrow();
    await $`tmux set-option -p @agent_state_ts ${Math.floor(Date.now() / 1000)}`.quiet().nothrow();
    // Opt-in on-wait notification (edge-triggered); {agent}/{pane} substituted.
    if (v === "wait" && prev !== "wait") {
      const cmd = (
        await $`tmux show-option -gqv @agent-monitor-on-wait`.quiet().nothrow().text()
      ).trim();
      if (cmd)
        await $`tmux run-shell -b ${cmd.replaceAll("{agent}", "opencode").replaceAll("{pane}", pane)}`
          .quiet()
          .nothrow();
    }
  };
  await $`tmux set-option -p @agent opencode`.quiet().nothrow();
  return {
    event: async ({ event }) => {
      switch (event.type) {
        case "message.updated":                             await stamp("busy"); break;
        case "session.idle":                                await stamp("done"); break;
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
