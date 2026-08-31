import { execFile } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const tmux = (...a: string[]) =>
  process.env.TMUX && execFile("tmux", a, () => {});
const set = (v: string) => {
  tmux("set-option", "-p", "@agent_state", v);
  tmux("set-option", "-p", "@agent_state_ts", `${Math.floor(Date.now() / 1000)}`);
};

export default function tmuxStatus(pi: ExtensionAPI): void {
  tmux("set-option", "-p", "@agent", "pi");
  set("idle");
  pi.on("turn_start", () => set("busy"));
  pi.on("turn_end", () => set("done")); // focus hook downgrades to idle
  pi.on("session_shutdown", () => {
    tmux("set-option", "-up", "@agent");
    tmux("set-option", "-up", "@agent_state");
    tmux("set-option", "-up", "@agent_state_ts");
  });
}
