import { execFile } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const tmux = (...a: string[]): void => {
  if (process.env.TMUX) execFile("tmux", a, () => {});
};

// Read a tmux value (option or format expansion). Resolves "" on any error.
const tmuxRead = (...a: string[]): Promise<string> =>
  new Promise((resolve) => {
    if (!process.env.TMUX) return resolve("");
    execFile("tmux", a, (err, out) => resolve(err ? "" : out.trim()));
  });

export default function tmuxStatus(pi: ExtensionAPI): void {
  const pane = process.env.TMUX_PANE ?? "";
  const target = pane ? ["-t", pane] : [];
  let prev = "";
  let running = false;

  // Opt-in notification, fired on *entering* a state (edge-triggered, once).
  // {agent}/{pane}/{branch}/{icon}/{icon_path}/{agent_icon_path}/{badge_path}
  // are substituted before the command runs.
  const fireHook = async (option: string, state: string): Promise<void> => {
    const cmd = await tmuxRead("show-option", "-gqv", option);
    if (!cmd) return;
    const branch = await tmuxRead(
      "display-message", ...target, "-p", "#{b:pane_current_path}",
    );
    const iconsDir = await tmuxRead("show-option", "-gqv", "@agent_icons");
    const icon = state === "wait" ? "\u{1F534}" : state === "done" ? "\u{1F7E2}" : "\u26AA";
    const iconPath = iconsDir ? `${iconsDir}/agent-${state}.png` : "";
    const agentIconPath = iconsDir ? `${iconsDir}/logo-pi.png` : "";
    const badgePath = iconsDir ? `${iconsDir}/badge-pi-${state}.png` : "";
    tmux(
      "run-shell", "-b",
      cmd
        .replaceAll("{agent}", "pi")
        .replaceAll("{pane}", pane)
        .replaceAll("{branch}", branch)
        .replaceAll("{icon}", icon)
        .replaceAll("{icon_path}", iconPath)
        .replaceAll("{agent_icon_path}", agentIconPath)
        .replaceAll("{badge_path}", badgePath),
    );
  };

  const set = (v: string): void => {
    const from = prev;
    prev = v;
    tmux("set-option", "-p", "@agent_state", v);
    tmux("set-option", "-p", "@agent_state_ts", `${Math.floor(Date.now() / 1000)}`);
    if (v === "wait" && from !== "wait") void fireHook("@agent-monitor-on-wait", v);
    if (v === "done" && from !== "done") void fireHook("@agent-monitor-on-done", v);
  };

  tmux("set-option", "-p", "@agent", "pi");
  set("idle");

  pi.on("agent_start", () => {
    running = true;
    set("busy");
  });

  // agent_settled = pi won't continue on its own (past auto-retry/compaction),
  // unlike turn_end which fires every turn. If you're already looking at this
  // pane there's nothing to review — idle, not done (so no notification fires).
  pi.on("agent_settled", async () => {
    running = false;
    const active = await tmuxRead(
      "display-message",
      ...target,
      "-p",
      "#{&&:#{&&:#{pane_active},#{window_active}},#{session_attached}}",
    );
    // A new run may have started during the await — don't clobber busy.
    if (running) return;
    set(active === "1" ? "idle" : "done");
  });

  // A blocking extension prompt (e.g. a permission gate) = waiting for you.
  pi.on("ui_prompt_start", () => set("wait"));
  pi.on("ui_prompt_end", () => set(running ? "busy" : "idle"));

  pi.on("session_shutdown", () => {
    tmux("set-option", "-up", "@agent");
    tmux("set-option", "-up", "@agent_state");
    tmux("set-option", "-up", "@agent_state_ts");
  });
}
