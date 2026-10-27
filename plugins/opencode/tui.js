// tmux-orchestrator OpenCode 2.x adapter.  It runs in the TUI, in the agent
// pane's own process, because only the TUI knows its pane and its tabs
// (ADR-0003).  It forwards agent events and tab snapshots to the shared
// reporter and never interprets them (ADR-0005).  It finds the reporter
// through the tmux server it runs in (ADR-0007).
import { spawn, spawnSync } from "node:child_process";
import { mkdirSync, unlinkSync } from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROTOCOL = "1";
const POLL_MS = 250;
const REPORTER_TIMEOUT_MS = 2000;

// Agent events the reporter maps to a state or a name.  Everything else,
// including high-frequency text streaming, stays in the TUI.
export const FORWARDED = new Set([
  "session.execution.started",
  "session.execution.succeeded",
  "session.execution.failed",
  "session.execution.interrupted",
  "permission.asked",
  "permission.replied",
  "form.created",
  "form.replied",
  "form.cancelled",
  "session.renamed",
]);

// A child session's own outcome must not end its root's turn.
const ROOT_ONLY = new Set([
  "session.execution.succeeded",
  "session.execution.failed",
  "session.execution.interrupted",
  "session.renamed",
]);

function sessionOf(event) {
  const data = event?.data ?? {};
  return data.sessionID ?? data.form?.sessionID;
}

// The open tabs with their status, in tab order, plus the active one.  A tab's
// status is what OpenCode's tab bar shows: a wait anywhere in the session's
// family, then activity.  Waits of a restored session load after its tab
// appears, so a later snapshot can turn a tab pending.  With tabs disabled, the
// session the TUI shows is the only agent.
export function snapshot(api) {
  const statusOf = (sid) => {
    const members = api.data.session.family?.(sid) ?? [sid];
    const pending = members.some(
      (id) =>
        (api.data.session.permission.list(id)?.length ?? 0) > 0 ||
        (api.data.session.form.list(id)?.length ?? 0) > 0,
    );
    if (pending) return "pending";
    return members.some((id) => api.data.session.status(id) === "running") ? "running" : "idle";
  };
  if (api.ui.tabs.enabled()) {
    const tabs = api.ui.tabs.list().map((tab) => ({
      sid: tab.sessionID,
      status: tab.attention ? "pending" : tab.busy ? "running" : "idle",
      title: tab.title ?? api.data.session.get(tab.sessionID)?.title ?? "",
    }));
    const active = api.ui.tabs.list().find((tab) => tab.active)?.sessionID ?? "";
    return { tabs, active };
  }
  const route = api.ui.router.current();
  if (route?.type !== "session") return { tabs: [], active: "" };
  const sid = api.data.session.root(route.sessionID) ?? route.sessionID;
  return {
    tabs: [{ sid, status: statusOf(sid), title: api.data.session.get(sid)?.title ?? "" }],
    active: sid,
  };
}

export function tabsArgs(pane, snap) {
  const args = ["tabs", "--pane", pane, "--active", snap.active];
  for (const tab of snap.tabs) args.push("--tab", tab.sid, tab.status, tab.title);
  return args;
}

export function snapshotKey(snap) {
  return JSON.stringify(snap);
}

// Reporter arguments for one OpenCode event, or null when it is not an agent
// event of a tab open in this TUI.
export function eventArgs(pane, event, api, open) {
  const type = event?.type;
  if (!FORWARDED.has(type)) return null;
  const sid = sessionOf(event);
  if (!sid) return null;
  const root = api.data.session.root(sid) ?? sid;
  if (!open.has(root)) return null;
  if (ROOT_ONLY.has(type) && sid !== root) return null;
  const args = ["report", "--pane", pane, "--kind", "opencode", "--event", type, "--session-id", root];
  if (type === "session.renamed" && event.data?.title) args.push("--name", event.data.title);
  return args;
}

// Runs reporter calls one at a time, in order, each bounded by a timeout.
export function createQueue(run) {
  let tail = Promise.resolve();
  return (args) => {
    tail = tail.then(() => run(args)).catch(() => {});
    return tail;
  };
}

// An explicit override, the path the tmux plugin publishes, then PATH.
export function findReporter(env = process.env) {
  if (env.TMUX_ORCHESTRATOR_REPORTER) return env.TMUX_ORCHESTRATOR_REPORTER;
  const socket = env.TMUX_SOCKET ? ["-L", env.TMUX_SOCKET] : [];
  try {
    const result = spawnSync("tmux", [...socket, "show-options", "-gv", "@tmux-orchestrator-reporter"], {
      encoding: "utf8",
      timeout: 1000,
      env,
    });
    const path = result.stdout?.trim();
    if (result.status === 0 && path) return path;
  } catch {
    // No tmux: fall through to PATH.
  }
  return "tmux-orchestrator";
}

let reporter;
function reporterPath() {
  reporter ??= findReporter();
  return reporter;
}

// Every call names the protocol, so an older reporter can say it needs updating.
function withProtocol(args) {
  return [args[0], "--protocol", PROTOCOL, ...args.slice(1)];
}

// The reporter call in flight, killed on exit so it cannot write the pane back
// after the final remove.
let running;

function killGroup(child) {
  try {
    process.kill(-child.pid, "SIGKILL");
  } catch {
    // Already gone.
  }
}

function runReporter(args) {
  return new Promise((resolve) => {
    let child;
    try {
      // Its own process group, so a kill also stops the tmux client it started.
      child = spawn(reporterPath(), withProtocol(args), { detached: true, stdio: "ignore", env: process.env });
    } catch {
      resolve();
      return;
    }
    running = child;
    const timer = setTimeout(() => killGroup(child), REPORTER_TIMEOUT_MS);
    const done = () => {
      clearTimeout(timer);
      if (running === child) running = undefined;
      resolve();
    };
    child.on("error", done);
    child.on("exit", done);
  });
}

// Fire and forget: used on exit, when the TUI may not wait for the child.
function runDetached(args) {
  try {
    const child = spawn(reporterPath(), withProtocol(args), { detached: true, stdio: "ignore", env: process.env });
    child.on("error", () => {});
    child.unref();
  } catch {
    // Reporting is best effort; the TUI must never fail because of it.
  }
}

// Pane IDs repeat across tmux servers, so the TUI's PID makes the name unique.
// XDG_RUNTIME_DIR, or macOS's per-user tmpdir, keeps other users out.
export function socketPath(pane, pid = process.pid) {
  const base =
    process.env.TMUX_ORCHESTRATOR_SOCKET_DIR ||
    join(process.env.XDG_RUNTIME_DIR || tmpdir(), `tmux-orchestrator-${process.getuid?.() ?? "user"}`);
  return { dir: base, path: join(base, `${pane.replace(/[^0-9A-Za-z]/g, "")}-${pid}.sock`) };
}

// Renames agent session SID to TITLE through OpenCode and returns the reply
// line for the reporter: "ok" or "error <reason>".
export async function renameSession(api, sid, title) {
  try {
    const result = await api.client.session.update({ sessionID: sid, title });
    if (result?.error) throw result.error;
    return "ok";
  } catch (err) {
    const reason = String(err?.message ?? err?.data?.message ?? err).replace(/\s+/g, " ");
    return `error OpenCode refused the rename: ${reason}`;
  }
}

// Listens for reporter lines: "focus <sid>" focuses that tab, and
// "rename <sid> <title>" renames that agent session and answers on the line.
function listenForControl(pane, api, onReady) {
  const { dir, path } = socketPath(pane);
  try {
    mkdirSync(dir, { recursive: true, mode: 0o700 });
    unlinkSync(path);
  } catch {
    // A missing stale socket is the normal case.
  }
  const server = createServer((connection) => {
    let buffer = "";
    connection.on("data", (chunk) => {
      buffer += chunk.toString();
      let newline;
      while ((newline = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, newline).trim();
        buffer = buffer.slice(newline + 1);
        const rename = /^rename (\S+) (.+)$/.exec(line);
        if (rename) {
          renameSession(api, rename[1], rename[2]).then((reply) => connection.end(`${reply}\n`));
          continue;
        }
        const match = /^focus (\S+)$/.exec(line);
        if (!match) continue;
        try {
          if (!(api.ui.tabs.enabled() && api.ui.tabs.focus(match[1]))) {
            api.ui.router.navigate({ type: "session", sessionID: match[1] });
          }
        } catch {
          // An unknown session is ignored.
        }
      }
    });
    connection.on("error", () => {});
  });
  server.on("error", () => {});
  server.listen(path, () => onReady(path));
  return () => {
    server.close();
    try {
      unlinkSync(path);
    } catch {
      // Already gone.
    }
  };
}

export function start(api, pane, run = runReporter) {
  reporter = findReporter();
  let closed = false;
  const enqueue = createQueue((args) => (closed ? undefined : run(args)));
  let open = new Set();
  let lastKey = "";

  const poll = () => {
    let snap;
    try {
      snap = snapshot(api);
    } catch {
      return;
    }
    open = new Set(snap.tabs.map((tab) => tab.sid));
    const key = snapshotKey(snap);
    if (key === lastKey) return;
    lastKey = key;
    enqueue(tabsArgs(pane, snap));
  };

  const stopListening = api.data.listen((message) => {
    const event = message?.details ?? message;
    try {
      const args = eventArgs(pane, event, api, open);
      if (args) enqueue(args);
    } catch {
      // A malformed event is ignored.
    }
  });
  const stopControl = listenForControl(pane, api, (path) => enqueue(["register", "--pane", pane, "--socket", path]));
  poll();
  const timer = setInterval(poll, POLL_MS);

  return () => {
    closed = true;
    clearInterval(timer);
    stopListening?.();
    stopControl();
    if (running) killGroup(running);
    runDetached(["remove", "--pane", pane]);
  };
}

export default {
  id: "tmux-orchestrator.opencode",
  setup(api) {
    const pane = process.env.TMUX_PANE;
    if (!pane || !api?.ui?.tabs || !api?.data?.listen) return () => {};
    try {
      return start(api, pane);
    } catch {
      return () => {};
    }
  },
};
