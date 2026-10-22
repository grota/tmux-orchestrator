import assert from "node:assert/strict";
import test from "node:test";

import { createTracker, reduceEvent } from "../plugins/opencode/tmux-orchestrator.js";

const ev = (type, properties = {}) => ({ type, properties });

test("root session starts idle and carries its title", () => {
  const t = createTracker();
  const a = reduceEvent(t, ev("session.created", { info: { id: "root", title: "fix-login" } }));
  assert.deepEqual(a, { state: "idle", name: "fix-login", sid: "root" });
  assert.equal(t.root, "root");
});

test("activity events become working", () => {
  for (const type of [
    "chat.message",
    "tool.execute.before",
    "tool.execute.after",
    "permission.replied",
    "question.replied",
    "question.rejected",
    "session.compacted",
  ]) {
    const t = createTracker();
    reduceEvent(t, ev("session.created", { sessionID: "root" }));
    const a = reduceEvent(t, ev(type, { sessionID: "root" }));
    assert.equal(a.state, "working", type);
  }
});

test("root permission and question requests block", () => {
  for (const type of ["permission.asked", "question.asked"]) {
    const t = createTracker();
    reduceEvent(t, ev("session.created", { sessionID: "root" }));
    assert.equal(reduceEvent(t, ev(type, { sessionID: "root" })).state, "blocked");
  }
});

test("child permission blocks the root and child completion is ignored", () => {
  const t = createTracker();
  reduceEvent(t, ev("session.created", { info: { id: "root" } }));
  assert.equal(
    reduceEvent(t, ev("session.created", { info: { id: "child", parentID: "root" } })),
    null,
  );
  assert.equal(reduceEvent(t, ev("permission.asked", { sessionID: "child" })).state, "blocked");
  assert.equal(reduceEvent(t, ev("session.idle", { sessionID: "child" })), null);
  assert.equal(t.root, "root");
});

test("idle is done after activity and idle otherwise", () => {
  const t = createTracker();
  reduceEvent(t, ev("session.created", { sessionID: "root" }));
  assert.equal(reduceEvent(t, ev("session.idle", { sessionID: "root" })).state, "idle");
  reduceEvent(t, ev("chat.message", { sessionID: "root" }));
  assert.equal(reduceEvent(t, ev("session.idle", { sessionID: "root" })).state, "done");
  assert.equal(reduceEvent(t, ev("session.idle", { sessionID: "root" })).state, "idle");
});

test("error persists across idle and clears on new activity", () => {
  const t = createTracker();
  reduceEvent(t, ev("session.created", { sessionID: "root" }));
  assert.equal(reduceEvent(t, ev("session.error", { sessionID: "root" })).state, "error");
  assert.equal(reduceEvent(t, ev("session.idle", { sessionID: "root" })).state, "error");
  assert.equal(reduceEvent(t, ev("tool.execute.before", { sessionID: "root" })).state, "working");
});

test("title updates are name-only and child titles are ignored", () => {
  const t = createTracker();
  reduceEvent(t, ev("session.created", { info: { id: "root", title: "old" } }));
  reduceEvent(t, ev("session.created", { info: { id: "child", parentID: "root", title: "child" } }));
  assert.deepEqual(
    reduceEvent(t, ev("session.updated", { info: { id: "child", title: "child-2" } })),
    null,
  );
  assert.deepEqual(
    reduceEvent(t, ev("session.updated", { info: { id: "root", title: "new" } })),
    { name: "new", sid: "root" },
  );
});

test("root deletion removes and child deletion only forgets the child", () => {
  const t = createTracker();
  reduceEvent(t, ev("session.created", { info: { id: "root" } }));
  reduceEvent(t, ev("session.created", { info: { id: "child", parentID: "root" } }));
  assert.equal(reduceEvent(t, ev("session.deleted", { sessionID: "child" })), null);
  assert.equal(t.children.has("child"), false);
  assert.deepEqual(reduceEvent(t, ev("session.deleted", { sessionID: "root" })), {
    remove: true,
    sid: "root",
  });
  assert.equal(t.root, undefined);
});

test("unrelated events are ignored", () => {
  const t = createTracker();
  reduceEvent(t, ev("session.created", { sessionID: "root" }));
  assert.equal(reduceEvent(t, ev("session.unknown", { sessionID: "root" })), null);
});

test("child completion leaves the root working after its permission resolves", () => {
  const t = createTracker();
  reduceEvent(t, ev("session.created", { info: { id: "root" } }));
  reduceEvent(t, ev("session.created", { info: { id: "child", parentID: "root" } }));
  assert.equal(reduceEvent(t, ev("permission.asked", { sessionID: "child" })).state, "blocked");
  assert.equal(reduceEvent(t, ev("permission.replied", { sessionID: "child" })).state, "working");
  assert.equal(reduceEvent(t, ev("session.idle", { sessionID: "child" })), null);
  assert.equal(t.root, "root");
});

test("child question requests block the root too", () => {
  const t = createTracker();
  reduceEvent(t, ev("session.created", { info: { id: "root" } }));
  reduceEvent(t, ev("session.created", { info: { id: "child", parentID: "root" } }));
  assert.equal(reduceEvent(t, ev("question.asked", { sessionID: "child" })).state, "blocked");
  assert.equal(reduceEvent(t, ev("question.rejected", { sessionID: "child" })).state, "working");
});
