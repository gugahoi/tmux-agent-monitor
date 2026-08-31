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
