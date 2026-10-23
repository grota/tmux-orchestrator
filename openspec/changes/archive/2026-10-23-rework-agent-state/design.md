# Design

## Context

See proposal.md for motivation. The decisions behind this design are recorded in ADR-0003 (the OpenCode adapter runs in the TUI), ADR-0004 (fixed sidebar slots) and ADR-0005 (adapters forward agent events). Terms follow `GLOSSARY.md`: an agent is one agent session open in a pane, and an OpenCode pane hosts one agent per tab.

The current code has one reporter script (`bin/tmux-orchestrator`). It stores six loose `@agent_*` options per pane and renders them with a one-line `lib/sidebar-format`. The format repeats the state icon logic twice. Claude payload parsing lives in the reporter. The OpenCode plugin is a server plugin that tracks one root session per process.

Facts this design relies on were checked against OpenCode v2.1.3's source and the Claude Code hooks documentation:

- The TUI plugin API offers `ui.tabs.list()`, `ui.tabs.focus(id)`, `ui.router.current()`, `data.listen()` and `data.session.root(id)`.
- Closing a tab emits no event.
- `<config>/plugins/<name>/tui.js` is discovered without config edits.
- `PreToolUse` fires for every tool call.
- tmux `range=user` IDs are limited to 15 bytes.

## Goals / Non-Goals

**Goals:**

- Every agent event meaning and state rule lives in one module, tested without tmux.
- One storage layout and one row fragment serve both agent kinds.
- OpenCode tabs are tracked, shown, focused and removed per pane.

**Non-Goals:**

- Custom glyphs and colours. The format keeps them in one fragment so this can be added later.
- Notification policy changes beyond the viewing rule (architecture candidate 3, deferred).
- OpenCode 1.x support.

## Decisions

### Agent state module

`lib/agent-state.sh` is a bash file sourced by the reporter and by its tests. It does no tmux I/O. Its interface is one function:

```text
agent_transition PREV KIND EVENT [DETAIL]
  -> "set STATE NOTIFY" | "forget" | "ignore"
```

The function holds:

- the mapping tables, as `case` patterns on `KIND:EVENT:DETAIL`;
- the completion rule: `done` only from `working` or `blocked`, and `error` retained;
- the `tmux:viewed` rule;
- the rank used for rollups.

`NOTIFY` is 1 when the state changes into `blocked`, `error` or `done`.

Alternatives were per-adapter rules or normalised events; see ADR-0005. A bash module was chosen over JS because the Claude path is bash and the reporter is the single writer.

### Adapter-made events

Some changes have no agent event, so adapters or the reporter make one:

- `opencode:tab.opened:<running|pending|idle>`, which gives the initial state;
- `opencode:tab.closed`, which gives `forget`;
- `opencode:tab.focused` and `tmux:viewed`, which clear `done`.

The OpenCode adapter does not send these individually. It sends a `tabs` snapshot (an ordered list of `sid:status` plus the active sid) whenever its tab list changes. The reporter diffs that snapshot against the stored slots and feeds each difference through `agent_transition`. One snapshot message is simpler than three event kinds, and it also carries the tab order.

### Subagents

Claude hooks from a subagent carry `agent_id`. The Claude adapter stops dropping them. Their activity and permission waits apply to the main agent. A subagent's completion arrives as `SubagentStop`, which is not hooked, so it cannot complete the agent. OpenCode child-session events map to their root through `data.session.root(id)`. A child's `session.execution.succeeded` is ignored unless the session is a root.

### Reporter interface

```text
report  --pane P --kind K --event E [--detail D] [--agent SID] [--name N] [--cwd C] [--refresh]
tabs    --pane P --active SID  SID:STATUS ...       (OpenCode snapshot)
remove  --pane P                                     (all agents of the pane)
register --pane P --socket PATH                      (OpenCode focus socket)
select  ROW                                          (%12:3 or %12:+)
focus | reconcile | gc | toggle | notify ... | cleanup | install | uninstall
```

`--state` is removed. For each event the reporter:

1. finds the agent's slot by session ID, creating it if new;
2. reads the previous state and calls `agent_transition`;
3. writes the slot and `@agent_<i>_event`;
4. recomputes the pane rollup and overflow, then the Tmux session rollup;
5. notifies if the transition asked for it.

### Storage layout

Pane options:

- `@agent_n`: the agent count.
- Per slot: `@agent_<i>_sid`, `_state`, `_name` (escaped), `_name_raw`, `_kind`, `_event` and `_notified_at`.
- `@agent_active`: the active tab's slot.
- `@agent_rollup`: the pane rollup.
- `@agent_more_n` and `@agent_more_state`: the overflow.
- `@agent_socket`: the focus socket path.

All agents are stored, including those past nine, so the overflow rollup stays exact. Closing a tab shifts the later slots down. A Tmux session keeps `@agent_count` (the sum of `@agent_n`) and `@agent_rollup`. Removal clears every `@agent_*` pane option by listing them, so the field list exists once.

### Sidebar format

`lib/sidebar-format` becomes a small template with three fragments:

- the state icon, written once and used by the session row, the agent rows and the overflow row;
- one agent row with a `{i}` placeholder;
- the overflow row.

`tmux-orchestrator.tmux` expands the agent row for `i` from 1 to 9 at load time and sets `side-status-format`. Agent rows use `range=user|#{pane_id}:{i}`, and the overflow row uses `range=user|#{pane_id}:+`. Names stay in options, so `#{=/…/…:@agent_{i}_name}` truncation and the single `#` escaping are unchanged. A row is active (`list=focus`) when its pane is active and `{i}` equals `@agent_active`, or when the pane has one agent.

Spike result (task 1.1, tmux next-3.9): a pty client rendered nine generated slots plus the overflow row. SGR clicks on slots 1 and 3 and on the overflow row delivered `%0:1`, `%0:3` and `%0:+` to `mouse_status_range`. A hostile name rendered literally, and narrowing the session's `side-status-width` re-truncated names with `…`.

### OpenCode TUI plugin

`plugins/opencode/tui.js` exports `{ id, setup(api) }` and works as follows:

- **Pane.** It reads `TMUX_PANE` and does nothing outside tmux.
- **Tab polling.** Every 250 ms it reads `ui.tabs.list()`, or `ui.router.current()` when tabs are disabled. When the ordered list, the statuses or the active tab change, it sends a `tabs` snapshot. A tab's status is `pending` when `data.session.permission.list` or `data.session.form.list` is non-empty, and `running` when `data.session.status` is `running`.
- **Events.** `data.listen()` forwards an allowlist of event names. Each event's session is mapped to its root, and an event is dropped if the root is not an open tab.
- **Order.** A promise queue spawns one reporter at a time and waits for it to exit, with a 2-second kill timeout.
- **Focus socket.** A Unix socket server runs at `/tmp/tmux-orchestrator-$UID/<pane-number>.sock` in a `0700` directory. Any stale file is unlinked before `listen`. The path is registered with `register`. The line protocol is `focus <sid>`.
- **Dispose.** On dispose it closes the socket, unlinks it and runs `remove --pane`.

Spike result (task 1.2, OpenCode v2.1.3): a directory holding only `tui.js` loaded in the TUI with no server entry. It saw the pane's `TMUX_PANE`, `ui.tabs.enabled()`, `ui.tabs.list()`, `ui.router.current()`, `data.listen` and `data.session.root`, and its dispose function ran on exit.

The installer writes `~/.config/opencode/plugins/tmux-orchestrator/tui.js` with the reporter path substituted. It deletes the legacy `~/.config/opencode/plugins/tmux-orchestrator.js`.

### Claude adapter

`plugins/claude/hooks/report.sh` parses the payload with `jq`. It reads `hook_event_name`, `session_id`, `cwd`, `session_title`, `tool_name` and `error`. It then calls `report --kind claude` with:

- `--detail` set to the tool name for `PreToolUse` or the error type for `StopFailure`;
- `--refresh` on `SessionStart` and `UserPromptSubmit` when no title is present.

`hooks.json` adds `Elicitation` and `ElicitationResult`.

### Claude interrupt detection

Claude Code fires no hook on an interrupt, and the live test showed no `idle_prompt` either. It does write a main-thread transcript entry whose text starts with `[Request interrupted by user` at the moment of the interrupt. On `UserPromptSubmit`, the reporter starts `watch-interrupt` with `tmux run-shell -b`, so it runs outside the hook budget. The watcher:

- stores a generation token in `@agent_1_watch` and exits as soon as the token changes, so each pane has at most one live watcher without PID tracking;
- every 3 seconds checks that the agent is still `working` or `blocked`, then reads only the complete lines appended since its last offset;
- reports the adapter-made `claude:Interrupted` event on a matching line that is not a sidechain entry;
- exits when the agent leaves `working`/`blocked`, the pane or server is gone, the token changes, or the transcript has not grown for one hour.

Alternatives were a screen check (more fragile), a check on tmux focus hooks (too late for a sidebar meant to be read at a glance) and accepting the gap. See ADR-0006.

### Viewing

A client views an agent when the agent's pane is the client's active pane and its slot is `@agent_active` (always true for a one-agent pane). `focus` sends `tmux:viewed` for those agents only. `tab.focused` comes from the OpenCode snapshot. Notification suppression uses the same test.

## Risks / Trade-offs

- [The transcript format is undocumented] → Accepted. If the marker text changes, detection silently stops and an interrupted Claude agent stays `working` until its next prompt. A fixture test pins the current format.
- [One watcher process per busy Claude agent] → Each tick is about three short process spawns and a read of the new bytes only. Idle agents have no watcher.
- [A directory plugin with only `tui.js` may not load in v2.1.3] → A spike verifies it with `opencode api plugin.list` before the adapter is written. The fallback is a minimal `index.js` server entry with an empty `setup`.
- [A subagent's `PostToolUse` can flip a blocked main agent to `working` while the main thread still waits] → Accepted. The next main-thread event corrects it, and this matches OpenCode child behaviour.
- [Read-modify-write races between a reporter call and the `focus` hook] → Accepted as rare. Each later event rewrites the slot it touches.
- [The OpenCode 2.x plugin API is young] → The README states the tested version. The adapter catches every error so the TUI never fails because of it.
- [Ranges in a nine-times repeated fragment make the format long] → The sidebar test checks render time stays unnoticeable on a session with 30 panes.

## Migration Plan

1. Reinstall: run `tmux-orchestrator install` for OpenCode, reload tmux, and update the Claude plugin.
2. Options left by the old version are ignored by the new format. `cleanup` and `gc` remove both the old and the new option names.
3. To roll back, check out the previous commit, rerun `install` and reload tmux.
