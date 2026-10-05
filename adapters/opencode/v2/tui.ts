import { execFile, execFileSync } from "node:child_process";
import { Plugin } from "@opencode/plugin/tui";

// opencode 2.x. Server plugins run in one shared background service, which
// can't tell which tmux pane a session belongs to — so this is a CLI plugin:
// it runs inside each TUI process, whose TMUX_PANE is the pane it's drawn in.

// Run tmux; resolves trimmed stdout, or "" on any error.
const tmux = (...a: string[]): Promise<string> =>
  new Promise((resolve) => {
    execFile("tmux", a, (err, out) => resolve(err ? "" : out.trim()));
  });

// active = this pane is the focused one AND a client is actually attached
// (window_active alone is true even for sessions nobody is looking at).
const ACTIVE = "#{&&:#{&&:#{pane_active},#{window_active}},#{session_attached}}";

// In auto-accept mode the TUI answers permission requests as soon as they're
// asked. Only one still open after this long is actually waiting on you.
const GRACE_MS = 500;

export default Plugin.define({
  id: "tmux-agent-monitor",
  setup(ctx) {
    const pane = process.env.TMUX_PANE;
    if (!process.env.TMUX || !pane) return;
    let disposed = false;
    const roots = new Set<string>(); // root sessions this TUI has had on screen
    const running = new Set<string>(); // ...of those, the ones mid-turn
    const asks = new Map<string, { root: string; ripe: boolean }>(); // open permission/form requests

    // Opt-in notification, fired on *entering* wait/done (edge-triggered).
    // {agent}/{pane}/{branch}/{icon}/{icon_path}/{agent_icon_path}/{badge_path}
    // are substituted before the command runs.
    const fireHook = async (option: string, state: string): Promise<void> => {
      const cmd = await tmux("show-option", "-gqv", option);
      if (!cmd) return;
      const branch = await tmux("display-message", "-t", pane, "-p", "#{b:pane_current_path}");
      const iconsDir = await tmux("show-option", "-gqv", "@agent_icons");
      const icon = state === "wait" ? "\u{1F534}" : state === "done" ? "\u{1F7E2}" : "\u26AA";
      const iconPath = iconsDir ? `${iconsDir}/agent-${state}.png` : "";
      const agentIconPath = iconsDir ? `${iconsDir}/logo-opencode.png` : "";
      const badgePath = iconsDir ? `${iconsDir}/badge-opencode-${state}.png` : "";
      await tmux(
        "run-shell", "-b",
        cmd
          .replaceAll("{agent}", "opencode")
          .replaceAll("{pane}", pane)
          .replaceAll("{branch}", branch)
          .replaceAll("{icon}", icon)
          .replaceAll("{icon_path}", iconPath)
          .replaceAll("{agent_icon_path}", agentIconPath)
          .replaceAll("{badge_path}", badgePath),
      );
    };

    // Serialized, so two events can't both read the old state and double-notify.
    // "settle" = the turn is over: done, or idle if you're already watching.
    // It only applies coming out of busy/wait, so it never re-notifies.
    let queue = Promise.resolve();
    const stamp = (next: "wait" | "busy" | "settle"): Promise<void> =>
      (queue = queue.then(async () => {
        if (disposed) return;
        const prev = await tmux("show-option", "-qpv", "-t", pane, "@agent_state");
        let v: string = next;
        if (next === "settle") {
          if (prev !== "busy" && prev !== "wait") return;
          v = (await tmux("display-message", "-t", pane, "-p", ACTIVE)) === "1" ? "idle" : "done";
        }
        if (v === prev) return;
        await tmux("set-option", "-p", "-t", pane, "@agent_state", v);
        await tmux("set-option", "-p", "-t", pane, "@agent_state_ts", `${Math.floor(Date.now() / 1000)}`);
        if (v === "wait") await fireHook("@agent-monitor-on-wait", v);
        if (v === "done") await fireHook("@agent-monitor-on-done", v);
      }));
    const refresh = () =>
      void stamp([...asks.values()].some((a) => a.ripe) ? "wait" : running.size ? "busy" : "settle");

    // Every TUI shares the server's event stream, so only follow sessions this
    // TUI has had on screen (not its tab bar: tabs are shared between TUIs in
    // the same directory). Returns the session's root (subagents roll up to
    // it) when it's ours, otherwise undefined.
    const ours = async (sessionID: string): Promise<string | undefined> => {
      const route = ctx.ui.router.current();
      if (route.type === "session") roots.add(ctx.data.session.root(route.sessionID));
      if (!ctx.data.session.get(sessionID)) await ctx.data.session.sync(sessionID).catch(() => {});
      const root = ctx.data.session.root(sessionID);
      return roots.has(root) ? root : undefined;
    };

    const ask = async (sessionID: string, id: string) => {
      const req = { root: "", ripe: false };
      asks.set(id, req); // claim first: an auto-accept reply can beat the await below
      const root = await ours(sessionID);
      if (!root || asks.get(id) !== req) return void asks.delete(id);
      req.root = root;
      setTimeout(() => {
        if (asks.get(id) !== req) return;
        req.ripe = true;
        refresh();
      }, GRACE_MS);
    };
    const answer = (id: string) => {
      if (asks.delete(id)) refresh();
    };
    // A session's open requests can't outlive its turn.
    const end = (root: string) => {
      running.delete(root);
      for (const [id, req] of asks) if (req.root === root) asks.delete(id);
    };
    // Only root sessions drive the pane; a subagent runs inside its parent's turn.
    const turn = async (sessionID: string, busy: boolean) => {
      if ((await ours(sessionID)) !== sessionID) return;
      if (busy) running.add(sessionID);
      else end(sessionID);
      refresh();
    };

    queue = queue.then(async () => {
      await tmux("set-option", "-p", "-t", pane, "@agent", "opencode");
      await tmux("set-option", "-p", "-t", pane, "@agent_state", "idle");
      await tmux("set-option", "-p", "-t", pane, "@agent_state_ts", `${Math.floor(Date.now() / 1000)}`);
    });

    const unsubscribe = [
      ctx.data.on("session.execution.started", (e) => void turn(e.data.sessionID, true)),
      ctx.data.on("session.execution.succeeded", (e) => void turn(e.data.sessionID, false)),
      ctx.data.on("session.execution.failed", (e) => void turn(e.data.sessionID, false)),
      ctx.data.on("session.execution.interrupted", (e) => void turn(e.data.sessionID, false)),
      ctx.data.on("permission.asked", (e) => void ask(e.data.sessionID, e.data.id)),
      ctx.data.on("permission.replied", (e) => answer(e.data.requestID)),
      ctx.data.on("form.created", (e) => void ask(e.data.form.sessionID, e.data.form.id)),
      ctx.data.on("form.replied", (e) => answer(e.data.id)),
      ctx.data.on("form.cancelled", (e) => answer(e.data.id)),
      ctx.data.on("session.deleted", (e) => {
        if (!roots.delete(e.data.sessionID)) return;
        end(e.data.sessionID);
        refresh();
      }),
    ];

    // TUI exiting (or the plugin reloading): untrack the pane. Synchronous so
    // it lands before the process is gone.
    return () => {
      disposed = true;
      for (const off of unsubscribe) off();
      try {
        execFileSync("tmux", [
          "set-option", "-u", "-p", "-t", pane, "@agent", ";",
          "set-option", "-u", "-p", "-t", pane, "@agent_state", ";",
          "set-option", "-u", "-p", "-t", pane, "@agent_state_ts",
        ], { stdio: "ignore" });
      } catch {}
    };
  },
});
