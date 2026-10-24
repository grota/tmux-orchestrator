# Design

## Context

Facts observed on Claude Code 2.1.310:

- A background session runs as `claude bg-spare` under the Claude daemon, with no `TMUX` or `TMUX_PANE`. Its hooks run our adapter with a normal payload (`session_id`, `transcript_path`, `cwd`).
- The viewer in the pane is the pane's own `claude` process, with `attach <arg>` somewhere in its arguments (aliases add options such as `--settings` before it). It fires no hooks.
- Pressing `←` makes the same process show the agent view, and its arguments change to `claude agents`. `Ctrl+Z` suspends it (`ps` state `T`).
- `claude agents --json` lists background sessions with `id` (the first 8 characters of `sessionId`), `sessionId`, `name`, and `state` (`working`, `blocked`, `done` seen). It takes about 0.2 s.

## Goals / Non-Goals

**Goals:**

- Track an attached background session as the Claude agent of the pane that shows it.
- Keep the existing state machine, naming and notification paths; only the pane lookup is new.

**Non-Goals:**

- Background sessions that no pane shows (no row, no notification).
- Non-default tmux sockets: the background process cannot know which server to report to.
- The `claude agents` view itself as an agent.

## Decisions

### Adapter: forward instead of exit

`report.sh` no longer exits when `TMUX_PANE` is unset. It passes `--background` instead of `--pane`, with the session id. It still exits when there is no session id, since nothing could be resolved.

### Viewer scan

One function lists attach viewers: `tmux list-panes -a -F '#{pane_id} #{pane_pid}'` plus one `ps -A -o pid= -o ppid= -o stat= -o args=`, walking each pane's descendants for a `claude` process whose arguments contain an `attach` word followed by an argument. Suspended processes (`T` in the state) are skipped. `ps` with these fields works on both Linux and macOS. The argument is taken as the rest of the line after ` attach `, because `ps` cannot keep quoted spaces apart.

### Resolution

An argument that is a prefix of the event's session id matches without calling Claude. Otherwise, `claude agents --json` is called once per run, and the argument matches the only background session whose name contains it, ignoring case. The Claude binary is found as the reporter already does for name lookups.

### Background events

`report --background --session-id S` scans viewers and keeps the panes whose argument resolves to `S`. If there are none, it removes an agent with session `S` from any pane still holding it (marked by `@agent_1_attached`) and stops. Otherwise it handles the event once per matching pane, as if it came with `--pane`. Notifications follow because the event goes through the normal path.

### Discovery and removal on focus

The focus hooks already run `tmux-orchestrator focus`. It additionally scans only the clients' active panes (cheap). For a viewer whose argument resolves to a session not already that pane's agent, it calls `claude agents --json`, then reports a synthetic event that adds the agent with the reported name, `@agent_1_attached` set to `1`, and the mapped state (`working`, `blocked`, `done`, `idle`; `failed` or `error` to `error`; anything else `unknown`). Then, for every pane whose agent has `@agent_1_attached`, if the pane has no viewer resolving to that agent's session, the agent is removed. `reconcile` on `pane-exited` already removes agents of exited panes.

The focus hook runs with `run-shell -b`, so `claude agents --json` never blocks tmux.

## Risks / Trade-offs

- [Pressing `←` sends no tmux event] → The row stays until the next selection change or the session's next hook. Documented.
- [`ps` truncates or merges arguments] → Long `--settings` values can push `attach` beyond what `ps` prints on some systems. Linux prints full arguments; macOS `ps -ww` does too, so `ps -ww` is used.
- [A name substring matching two sessions] → Resolves to nothing; using the short id always works.
- [Every focus change scans processes] → One `ps` call per focus event, only when a client's active pane has a `claude` process; measured cost is a few milliseconds.
