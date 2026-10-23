// tmux-orchestrator OpenCode 2.x adapter.  It runs in the TUI, in the agent
// pane's own process, because only the TUI knows its pane and its tabs
// (ADR-0003).  It forwards agent events and tab snapshots to the shared
// reporter and never interprets them (ADR-0005).
//
// The installer replaces __REPORTER__ with the absolute path to the reporter.
import { spawn } from "node:child_process";
import { mkdirSync, unlinkSync } from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";

const REPORTER = "__REPORTER__";
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

// The open tabs with their status, in tab order, plus the active one.  With
// tabs disabled, the session the TUI shows is the only agent.
export function snapshot(api) {
  const statusOf = (sid) => {
    const pending =
      (api.data.session.permission.list(sid)?.length ?? 0) > 0 ||
      (api.data.session.form.list(sid)?.length ?? 0) > 0;
    if (pending) return "pending";
    return api.data.session.status(sid) === "running" ? "running" : "idle";
  };
  if (api.ui.tabs.enabled()) {
    const tabs = api.ui.tabs.list().map((tab) => ({
      sid: tab.sessionID,
      status: statusOf(tab.sessionID),
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

function reporterPath() {
  return process.env.TMUX_ORCHESTRATOR_REPORTER || REPORTER;
}

function runReporter(args) {
  return new Promise((resolve) => {
    let child;
    try {
      child = spawn(reporterPath(), args, { stdio: "ignore", env: process.env });
    } catch {
      resolve();
      return;
    }
    const timer = setTimeout(() => child.kill("SIGKILL"), REPORTER_TIMEOUT_MS);
    const done = () => {
      clearTimeout(timer);
      resolve();
    };
    child.on("error", done);
    child.on("exit", done);
  });
}

// Fire and forget: used on exit, when the TUI may not wait for the child.
function runDetached(args) {
  try {
    const child = spawn(reporterPath(), args, { detached: true, stdio: "ignore", env: process.env });
    child.on("error", () => {});
    child.unref();
  } catch {
    // Reporting is best effort; the TUI must never fail because of it.
  }
}

export function socketPath(pane) {
  const base = process.env.TMUX_ORCHESTRATOR_SOCKET_DIR || join("/tmp", `tmux-orchestrator-${process.getuid?.() ?? "user"}`);
  return { dir: base, path: join(base, `${pane.replace(/[^0-9A-Za-z]/g, "")}.sock`) };
}

// Listens for "focus <sid>" lines from the reporter and focuses that tab.
function listenForFocus(pane, api, onReady) {
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
  const enqueue = createQueue(run);
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
  const stopFocus = listenForFocus(pane, api, (path) => enqueue(["register", "--pane", pane, "--socket", path]));
  poll();
  const timer = setInterval(poll, POLL_MS);

  return () => {
    clearInterval(timer);
    stopListening?.();
    stopFocus();
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
