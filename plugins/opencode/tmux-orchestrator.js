// tmux-orchestrator OpenCode adapter.
//
// The installer replaces __REPORTER__ with the absolute path to the shared
// reporter.  The adapter only translates OpenCode events into reporter calls;
// it never touches OpenCode configuration or transcript files.
import { spawn } from "node:child_process";

const REPORTER = "__REPORTER__";
const ACTIVITY = new Set([
  "chat.message",
  "tool.execute.before",
  "tool.execute.after",
  "permission.replied",
  "question.replied",
  "question.rejected",
  "session.compacted",
]);
const BLOCKED = new Set(["permission.asked", "question.asked"]);

function titleOf(info, properties) {
  const title = info?.title ?? properties?.title;
  return typeof title === "string" && title.trim() ? title : undefined;
}

function sessionIDOf(properties) {
  return properties?.sessionID ??
    properties?.info?.id ??
    properties?.session?.id ??
    undefined;
}

export function createTracker() {
  return {
    root: undefined,
    children: new Map(),
    activity: false,
    error: false,
  };
}

function rootOf(tracker, sessionID) {
  if (!sessionID) return tracker.root;
  if (sessionID === tracker.root) return tracker.root;
  let id = sessionID;
  while (tracker.children.has(id)) id = tracker.children.get(id);
  if (tracker.children.has(sessionID) && id === tracker.root) return id;
  if (!tracker.root) tracker.root = id;
  return id === tracker.root ? id : undefined;
}

// Pure event reducer.  Returns { state, name?, sid? } or { remove: true }.
export function reduceEvent(tracker, event) {
  const type = event?.type;
  const properties = event?.properties ?? {};
  const info = properties.info ?? {};
  const sessionID = sessionIDOf(properties);

  if (info.id && info.parentID) {
    tracker.children.set(info.id, info.parentID);
    if (!tracker.root) tracker.root = info.parentID;
  }

  if (type === "session.created") {
    if (!tracker.root) tracker.root = info.parentID ?? sessionID;
    if (sessionID && sessionID !== tracker.root) return null;
    tracker.activity = false;
    tracker.error = false;
    return { state: "idle", name: titleOf(info, properties), sid: tracker.root };
  }

  if (type === "session.updated") {
    if (sessionID && tracker.root && sessionID !== tracker.root) return null;
    const name = titleOf(info, properties);
    return name ? { name, sid: tracker.root ?? sessionID } : null;
  }

  if (type === "session.deleted") {
    if (sessionID && sessionID === tracker.root) {
      tracker.root = undefined;
      tracker.activity = false;
      tracker.error = false;
      return { remove: true, sid: sessionID };
    }
    if (sessionID) tracker.children.delete(sessionID);
    return null;
  }

  const root = rootOf(tracker, sessionID);
  if (!root) return null;

  if (ACTIVITY.has(type)) {
    tracker.activity = true;
    tracker.error = false;
    return { state: "working", sid: root };
  }

  if (BLOCKED.has(type)) {
    tracker.activity = true;
    tracker.error = false;
    return { state: "blocked", sid: root };
  }

  if (type === "session.idle") {
    // A child session finishing must not complete the root session.
    if (sessionID && sessionID !== root) return null;
    if (tracker.error) return { state: "error", sid: root };
    if (!tracker.activity) return { state: "idle", sid: root };
    tracker.activity = false;
    return { state: "done", sid: root };
  }

  if (type === "session.error") {
    tracker.error = true;
    tracker.activity = false;
    return { state: "error", sid: root };
  }

  return null;
}

function runReporter(args) {
  try {
    const child = spawn(REPORTER, args, {
      detached: true,
      stdio: "ignore",
      env: process.env,
    });
    child.on("error", () => {});
    child.unref();
  } catch {
    // Reporting is best effort; an agent must never fail because of it.
  }
}

function report(pane, action, cwd) {
  if (action.remove) {
    runReporter(["remove", "--pane", pane]);
    return;
  }
  const args = ["report", "--pane", pane, "--kind", "opencode"];
  if (action.state) args.push("--state", action.state);
  if (action.name) args.push("--name", action.name);
  if (action.sid) args.push("--session-id", action.sid);
  if (cwd) args.push("--cwd", cwd);
  runReporter(args);
}

function createHandler(pane) {
  const tracker = createTracker();
  return (event) => {
    const action = reduceEvent(tracker, event);
    if (!action) return;
    const properties = event?.properties ?? {};
    const cwd = properties.info?.directory ?? properties.directory ?? properties.cwd;
    report(pane, action, cwd);
  };
}

// OpenCode v1 hook shape.  Kept so older servers and the unit tests can drive
// the same reducer; v2 loads the default definition below.
export const TmuxOrchestratorPlugin = async () => {
  const pane = process.env.TMUX_PANE || process.env.TMUX_ORCHESTRATOR_PANE;
  if (!pane) return {};
  const handle = createHandler(pane);
  return {
    event: async ({ event }) => handle(event),
    "chat.message": async ({ sessionID, directory }) => {
      handle({ type: "chat.message", properties: { sessionID, directory } });
    },
  };
};

export default {
  id: "tmux-orchestrator.opencode",
  async setup(ctx) {
    const pane = process.env.TMUX_PANE || process.env.TMUX_ORCHESTRATOR_PANE;
    if (!pane || !ctx?.event?.subscribe) return () => {};
    const handle = createHandler(pane);
    const controller = new AbortController();
    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
          handle(event);
        }
      } catch (error) {
        if (error?.name !== "AbortError") {
          // The sidebar must never take down the agent's plugin host.
        }
      }
    })();
    return () => controller.abort();
  },
};
