import assert from "node:assert/strict";
import test from "node:test";

import { createQueue, eventArgs, snapshot, socketPath, tabsArgs } from "../plugins/opencode/tui.js";

// A fake OpenCode 2.x TUI API: tabs, sessions with roots, pending requests.
function fakeApi({ tabs = [], roots = {}, families = {}, running = [], permissions = {}, forms = {}, titles = {}, enabled = true, route } = {}) {
  return {
    ui: {
      tabs: { enabled: () => enabled, list: () => tabs, focus: () => true },
      router: { current: () => route ?? { type: "home" }, navigate: () => {} },
    },
    data: {
      session: {
        root: (id) => roots[id] ?? id,
        family: (id) => families[id] ?? [id],
        get: (id) => (titles[id] ? { id, title: titles[id] } : undefined),
        status: (id) => (running.includes(id) ? "running" : "idle"),
        permission: { list: (id) => permissions[id] ?? [] },
        form: { list: (id) => forms[id] ?? [] },
      },
    },
  };
}

const ev = (type, data) => ({ id: "e", type, created: 0, data });

test("snapshot lists tabs in order with OpenCode's own status, title and the active tab", () => {
  const api = fakeApi({
    tabs: [
      { sessionID: "ses_a", title: "api", active: false, busy: true, attention: false },
      { sessionID: "ses_b", title: "docs", active: true, busy: false, attention: false },
      { sessionID: "ses_c", active: false, busy: true, attention: "permission" },
    ],
    titles: { ses_c: "web" },
  });
  assert.deepEqual(snapshot(api), {
    tabs: [
      { sid: "ses_a", status: "running", title: "api" },
      { sid: "ses_b", status: "idle", title: "docs" },
      { sid: "ses_c", status: "pending", title: "web" },
    ],
    active: "ses_b",
  });
});

test("with tabs disabled the shown session and its children make the only agent", () => {
  const api = fakeApi({
    enabled: false,
    route: { type: "session", sessionID: "ses_child" },
    roots: { ses_child: "ses_root" },
    families: { ses_root: ["ses_root", "ses_child"] },
    forms: { ses_child: [{ id: "f" }] },
  });
  assert.deepEqual(snapshot(api), { tabs: [{ sid: "ses_root", status: "pending", title: "" }], active: "ses_root" });
  const busy = fakeApi({
    enabled: false,
    route: { type: "session", sessionID: "ses_root" },
    families: { ses_root: ["ses_root", "ses_child"] },
    running: ["ses_child"],
  });
  assert.equal(snapshot(busy).tabs[0].status, "running");
  assert.deepEqual(snapshot(fakeApi({ enabled: false })), { tabs: [], active: "" });
});

test("tab snapshots become reporter arguments", () => {
  assert.deepEqual(tabsArgs("%7", { tabs: [{ sid: "a", status: "idle", title: "two words" }], active: "a" }), [
    "tabs", "--pane", "%7", "--active", "a", "--tab", "a", "idle", "two words",
  ]);
});

test("agent events of open tabs are forwarded with their name", () => {
  const api = fakeApi();
  const open = new Set(["ses_a"]);
  for (const type of [
    "session.execution.started",
    "session.execution.succeeded",
    "session.execution.failed",
    "session.execution.interrupted",
    "permission.asked",
    "permission.replied",
    "form.replied",
    "form.cancelled",
  ]) {
    assert.deepEqual(eventArgs("%7", ev(type, { sessionID: "ses_a" }), api, open), [
      "report", "--pane", "%7", "--kind", "opencode", "--event", type, "--session-id", "ses_a",
    ], type);
  }
  assert.deepEqual(eventArgs("%7", ev("form.created", { form: { id: "f", sessionID: "ses_a" } }), api, open).slice(6), [
    "form.created", "--session-id", "ses_a",
  ]);
});

test("streaming and unknown events stay in the TUI", () => {
  const open = new Set(["ses_a"]);
  for (const type of ["session.text.delta", "session.step.started", "session.created", "session.updated", "session.idle"]) {
    assert.equal(eventArgs("%7", ev(type, { sessionID: "ses_a" }), fakeApi(), open), null, type);
  }
});

test("events for sessions not open in this TUI are ignored", () => {
  assert.equal(eventArgs("%7", ev("permission.asked", { sessionID: "ses_x" }), fakeApi(), new Set(["ses_a"])), null);
});

test("a child session's waits block the root, its outcome does not end it", () => {
  const api = fakeApi({ roots: { ses_child: "ses_a" } });
  const open = new Set(["ses_a"]);
  assert.deepEqual(eventArgs("%7", ev("permission.asked", { sessionID: "ses_child" }), api, open).slice(-2), ["--session-id", "ses_a"]);
  assert.deepEqual(eventArgs("%7", ev("form.created", { form: { sessionID: "ses_child" } }), api, open).slice(-2), ["--session-id", "ses_a"]);
  for (const type of ["session.execution.succeeded", "session.execution.failed", "session.execution.interrupted", "session.renamed"]) {
    assert.equal(eventArgs("%7", ev(type, { sessionID: "ses_child", title: "x" }), api, open), null, type);
  }
});

test("a rename carries the new title", () => {
  const args = eventArgs("%7", ev("session.renamed", { sessionID: "ses_a", title: "fix login" }), fakeApi(), new Set(["ses_a"]));
  assert.deepEqual(args.slice(-2), ["--name", "fix login"]);
});

test("the queue runs reporter calls one at a time in order", async () => {
  const log = [];
  const run = async (args) => {
    log.push(`start ${args[0]}`);
    await new Promise((resolve) => setTimeout(resolve, args[0] === "slow" ? 30 : 1));
    log.push(`end ${args[0]}`);
  };
  const enqueue = createQueue(run);
  enqueue(["slow"]);
  await enqueue(["fast"]);
  assert.deepEqual(log, ["start slow", "end slow", "start fast", "end fast"]);
});

test("a failing reporter call does not stop the queue", async () => {
  const log = [];
  const enqueue = createQueue(async (args) => {
    if (args[0] === "bad") throw new Error("boom");
    log.push(args[0]);
  });
  enqueue(["bad"]);
  await enqueue(["good"]);
  assert.deepEqual(log, ["good"]);
});

test("the focus socket of the same pane differs between TUIs", () => {
  assert.notEqual(socketPath("%3", 100).path, socketPath("%3", 200).path);
  assert.match(socketPath("%3", 100).path, /\/3-100\.sock$/);
});
