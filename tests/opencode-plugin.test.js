import assert from "node:assert/strict";
import test from "node:test";
import { chmod, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { connect } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function fakeReporter() {
  const dir = await mkdtemp(join(tmpdir(), "tmux-orchestrator-plugin-"));
  const log = join(dir, "reporter.log");
  const reporter = join(dir, "reporter");
  await writeFile(reporter, `#!/usr/bin/env bash\nprintf '%s\\n' "$*" >> '${log}'\n`);
  await chmod(reporter, 0o755);
  process.env.TMUX_ORCHESTRATOR_REPORTER = reporter;
  process.env.TMUX_ORCHESTRATOR_SOCKET_DIR = join(dir, "sockets");
  const lines = async () => (await readFile(log, "utf8").catch(() => "")).trim().split("\n").filter(Boolean);
  return { dir, lines };
}

// A fake TUI whose tabs can change while the plugin runs.
function fakeTui() {
  const state = { tabs: [], focused: [], listener: undefined };
  const api = {
    ui: {
      tabs: {
        enabled: () => true,
        list: () => state.tabs,
        focus: (sid) => {
          state.focused.push(sid);
          return true;
        },
      },
      router: { current: () => ({ type: "home" }), navigate: () => {} },
    },
    data: {
      listen: (handler) => {
        state.listener = handler;
        return () => {
          state.listener = undefined;
        };
      },
      session: {
        root: (id) => id,
        get: () => undefined,
        status: () => "idle",
        permission: { list: () => [] },
        form: { list: () => [] },
      },
    },
  };
  const emit = (type, data) => state.listener?.({ details: { id: "e", type, created: 0, data } });
  return { api, state, emit };
}

test("the TUI plugin reports tabs, events in order, focus and exit", async () => {
  const { lines } = await fakeReporter();
  process.env.TMUX_PANE = "%7";
  const { default: plugin } = await import("../plugins/opencode/tui.js");
  const tui = fakeTui();
  tui.state.tabs = [
    { sessionID: "ses_a", title: "api", active: true, busy: false, attention: false },
    { sessionID: "ses_b", title: "docs", active: false, busy: false, attention: false },
  ];

  const dispose = plugin.setup(tui.api);
  await sleep(100);
  tui.emit("session.execution.started", { sessionID: "ses_b" });
  tui.emit("permission.asked", { sessionID: "ses_b" });
  tui.emit("session.text.delta", { sessionID: "ses_b" });
  tui.emit("permission.asked", { sessionID: "ses_other" });
  await sleep(200);

  // Closing a tab emits no event; the next poll sends a new snapshot.
  tui.state.tabs = [tui.state.tabs[0]];
  await sleep(400);

  let out = await lines();
  assert.equal(out[0], "tabs --pane %7 --active ses_a --tab ses_a idle api --tab ses_b idle docs");
  const register = out.find((line) => line.startsWith("register"));
  assert.match(register, /^register --pane %7 --socket .*\/7\.sock$/);
  const events = out.filter((line) => line.startsWith("report"));
  assert.deepEqual(events, [
    "report --pane %7 --kind opencode --event session.execution.started --session-id ses_b",
    "report --pane %7 --kind opencode --event permission.asked --session-id ses_b",
  ]);
  assert.equal(out.at(-1), "tabs --pane %7 --active ses_a --tab ses_a idle api");

  // The reporter's focus request reaches ui.tabs.focus through the socket.
  const socket = register.split(" --socket ")[1];
  await new Promise((resolve, reject) => {
    const client = connect(socket, () => client.end("focus ses_a\n"));
    client.on("close", resolve);
    client.on("error", reject);
  });
  await sleep(100);
  assert.deepEqual(tui.state.focused, ["ses_a"]);

  dispose();
  await sleep(300);
  out = await lines();
  assert.equal(out.at(-1), "remove --pane %7");
  assert.equal(existsSync(socket), false);
});

test("outside tmux the plugin does nothing", async () => {
  const saved = process.env.TMUX_PANE;
  delete process.env.TMUX_PANE;
  const { default: plugin } = await import("../plugins/opencode/tui.js");
  const tui = fakeTui();
  const dispose = plugin.setup(tui.api);
  assert.equal(tui.state.listener, undefined);
  dispose();
  process.env.TMUX_PANE = saved;
});
