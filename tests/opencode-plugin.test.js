import assert from "node:assert/strict";
import test from "node:test";
import { mkdtemp, readFile, writeFile, chmod } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

test("OpenCode plugin forwards lifecycle events to the reporter", async () => {
  const dir = await mkdtemp(join(tmpdir(), "tmux-orchestrator-plugin-"));
  const log = join(dir, "reporter.log");
  const reporter = join(dir, "reporter");
  await writeFile(reporter, `#!/usr/bin/env bash\nprintf '%s\\n' "$*" >> '${log}'\n`);
  await chmod(reporter, 0o755);

  const source = await readFile(
    new URL("../plugins/opencode/tmux-orchestrator.js", import.meta.url),
    "utf8",
  );
  const installed = join(dir, "plugin.js");
  await writeFile(installed, source.replace('"__REPORTER__"', JSON.stringify(reporter)));

  process.env.TMUX_PANE = "%7";
  const { TmuxOrchestratorPlugin } = await import(pathToFileURL(installed));
  const hooks = await TmuxOrchestratorPlugin();

  await hooks.event({
    event: { type: "session.created", properties: { info: { id: "root", title: "fix-login" } } },
  });
  await hooks["chat.message"]({ sessionID: "root", directory: "/tmp/project" });
  await hooks.event({
    event: { type: "permission.asked", properties: { sessionID: "root" } },
  });
  await hooks.event({
    event: { type: "session.deleted", properties: { sessionID: "root" } },
  });
  await sleep(300);

  const lines = (await readFile(log, "utf8")).trim().split("\n");
  assert.match(lines[0], /^report --pane %7 --kind opencode --state idle --name fix-login --session-id root/);
  assert.match(lines[1], /^report --pane %7 --kind opencode --state working --session-id root/);
  assert.match(lines[2], /^report --pane %7 --kind opencode --state blocked --session-id root/);
  assert.match(lines[3], /^remove --pane %7$/);
});

test("OpenCode v2 setup subscribes to the event stream", async () => {
  const dir = await mkdtemp(join(tmpdir(), "tmux-orchestrator-v2-"));
  const log = join(dir, "reporter.log");
  const reporter = join(dir, "reporter");
  await writeFile(reporter, `#!/usr/bin/env bash\nprintf '%s\\n' "$*" >> '${log}'\n`);
  await chmod(reporter, 0o755);

  const source = await readFile(
    new URL("../plugins/opencode/tmux-orchestrator.js", import.meta.url),
    "utf8",
  );
  const installed = join(dir, "plugin.js");
  await writeFile(installed, source.replace('"__REPORTER__"', JSON.stringify(reporter)));

  process.env.TMUX_PANE = "%8";
  const { default: definition } = await import(pathToFileURL(installed));
  const events = [
    { type: "session.created", properties: { info: { id: "root", title: "v2-agent" } } },
    { type: "permission.asked", properties: { sessionID: "root" } },
    { type: "session.idle", properties: { sessionID: "root" } },
    { type: "session.deleted", properties: { sessionID: "root" } },
  ];
  const ctx = {
    event: {
      async *subscribe() {
        for (const event of events) yield event;
      },
    },
  };
  const cleanup = await definition.setup(ctx);
  await sleep(300);
  cleanup();

  const lines = (await readFile(log, "utf8")).trim().split("\n");
  assert.match(lines[0], /^report --pane %8 --kind opencode --state idle --name v2-agent --session-id root/);
  assert.match(lines[1], /^report --pane %8 --kind opencode --state blocked --session-id root/);
  assert.match(lines[2], /^report --pane %8 --kind opencode --state done --session-id root/);
  assert.match(lines[3], /^remove --pane %8$/);
});
