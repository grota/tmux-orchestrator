# Design

## Context

See `proposal.md` for motivation and the delta specs for required behavior. The repository is new and has no runtime code yet. The only environment assumptions are a user-level tmux server, Claude Code 2.1.x, OpenCode 2.x, and tmux 3.9 or newer.

Verified facts that shape the design:

- `side-status` is a session option with `off`, `left`, and `right` choices, a `side-status-width` number, and a `side-status-format` string.
- tmux already binds border drag and double-click for `side-status-width`; the plugin must not reset width on refresh.
- Format loops `S:`, nested `W:`/`P:`, user options in conditions, `#{nl}`, and truncation all work in `side-status-format`.
- `mouse_status_range` exposes `session`, `window`, or `pane` at binding time, so a click handler can preserve normal status-bar behavior.
- Claude Code 2.1.306 hook inputs include `session_title`, `agent_id`, `PermissionRequest`, `StopFailure`, and `SessionEnd`.
- OpenCode lifecycle events are the same family used by herdr: `session.status`, `session.idle`, `session.error`, `permission.*`, `question.*`, and `tool.execute.*`.
- `display-message -c` targets one client, and each client exposes its current session; the active pane can be derived without a daemon.
- Desktop delivery has no portable command: Linux uses `notify-send`, macOS uses `osascript`, and either may be absent or fail.

## Goals / Non-Goals

**Goals:**

- One reporter writes all state; adapters only translate their own events.
- Sidebar rendering stays a static global format string with no renderer process.
- State is inspectable and editable with ordinary `tmux show-options` commands.
- Attention transitions reach the user even when the sidebar is not being watched.
- The repo is simultaneously a TPM plugin, a Claude marketplace plugin, and an OpenCode plugin.

**Non-Goals:**

- Screen scraping or process-state inference.
- A daemon, state database, or cross-server aggregation.
- Keyboard focus inside the sidebar, scrolling, or a popup console.
- Recovering state after a tmux server restart.
- Notification history, click-to-focus, per-agent snooze, timed pause, a default notification key binding, or a pause indicator in the sidebar.
- Automatic installation of the Claude plugin.

## Decisions

### State lives in tmux options

Pane options hold `@agent_state`, `@agent_name`, `@agent_kind`, and `@agent_session`. Session options hold `@agent_count` and `@agent_rollup`.

Rationale: every tmux client and any future console already reads the same store. There is no lifecycle to manage, no stale socket, and no lock file. A pane's options vanish with the pane.

Alternatives rejected: a SQLite/JSON store (extra lifecycle and failure mode), a daemon (the reason herdr exists is its server; we do not need one), and deriving state from screen contents (ADR 0001).

Session summaries are derived data and may briefly lag under concurrent events. The reporter recomputes them after every write and on `pane-exited`; `reconcile` recomputes all sessions on demand. Because the computation is a fresh `list-panes` scan, a late writer cannot corrupt counts permanently.

### Static global format

The plugin sets one global `side-status-format`. The session section is an `S:` loop filtered by `@agent_count`; the agent section is `W:` > `P:` over the client's current session, filtered by `@agent_state`. Session rows use `range=session|…`; agent rows use `range=user|<pane-id>` so the click handler receives the target pane ID.

Rationale: no process writes per-session format strings, so sessions and clients cannot disagree about the layout. The format reads the same options the reporter writes.

Alternatives rejected: a renderer that writes a per-session string on every event (more moving parts, same information), and a pane-based sidebar (ADR 0002).

Formatting rules:

- headers `Sessions` and `Agents`; a blank line between sections;
- agent row: state icon, name truncated with `…`, kind;
- current session row marked with `▸`;
- `list=on` around the list and `list=focus` on the active agent's row; overflow trims from the top, which may drop session rows when many agents exist;
- names are escaped by the reporter (`#` to `##`, control characters removed) before they reach the format.

### Click handling preserves the default status binding

`MouseDown1Status` is rebound to:

1. if `mouse_status_range` is `session`, `switch-client -t=`;
2. if it is `window`, `switch-client -t=` then `select-window -t=`;
3. for any other non-empty range, run the reporter's `select` command with the range value.

Agent rows use `range=user|<pane-id>`, so the reporter receives the exact pane ID and runs `select-window` and `select-pane` itself. The reporter then clears a `done` state on the selected pane.

Rationale: side-status clicks use the same mouse key as the normal status bar, so a narrow “only when x is inside the sidebar” handler would be brittle and would break other status plugins. Session and window ranges keep the default behavior. A pane range cannot use the special `=` target: tmux resolves it to the client's active pane, not the pane encoded in the range, so agent-row clicks would do nothing.

Alternatives rejected: `range=pane` with `=` (does not select the target pane), a separate mouse key (none exists for side-status), and coordinate sniffing (breaks with status at top, right side, and multi-client widths).

### Async name lookup

The Claude adapter writes the fallback name immediately and asks the tmux server to run the lookup in the background via `run-shell -b`. The lookup uses `claude agents --json`, filters by `session_id`, and writes `@agent_name` only if the value is non-empty. `SessionStart` and `UserPromptSubmit` trigger it.

Rationale: the hook stays inside its budget even when the CLI is slow or the session is not registered yet. A failed lookup is cosmetic and self-heals on the next prompt. OpenCode supplies a title directly, so it never runs the CLI.

### Done and error precedence

`error` is sticky across a following completion event. Any activity event clears it. `done` is cleared by the focus reconciler, which runs after selection commands and on `client-session-changed`, not by a timer.

OpenCode needs one bit of adapter-local memory: whether the current turn has seen activity. `session.idle` becomes `done` only if it has; otherwise it stays `idle`. An error sets a second bit so a following idle does not erase it. Both bits reset when activity resumes.

### Notifications are a reporter side effect

The reporter reads the previous pane state before writing the new one and emits only on a transition into `blocked`, `error`, or `done`. Changed events that report the same state, focus-clearing, and removal never emit. No queue or history is kept.

Text is assembled from the already-sanitized agent name and the same state icon as the sidebar. Tmux delivery iterates clients and calls `display-message -l -c` for each client whose active pane is not the agent. `-l` prevents a hostile name from expanding as a tmux format. Desktop delivery calls `notify-send` or `osascript` with the summary as an argument, never by interpolating it into a shell string.

Channel selection is read from `@tmux-orchestrator-notify` (`both`, `tmux`, `desktop`, `off`). Desktop capability is checked from the command's existence; `both` degrades to tmux, while `desktop` without a command is a silent no-op. All failures are swallowed after state has been written.

Suppression uses tmux's per-client session and active window, then the active pane. The tmux message is skipped only for clients viewing the agent. The desktop notification is skipped if any attached client is viewing it; with no clients, desktop delivery still occurs.

Deduplication is implicit in transition detection. The tmux cooldown stores an epoch timestamp in a pane option and suppresses a `done` message within two seconds of the previous tmux message for that agent; `blocked` and `error` bypass it. Desktop has no cooldown, so a real transition is never dropped from the persistent channel.

### Pause is a separate global switch

`notify pause` sets a global tmux option; `notify resume` unsets it; `notify status` reads the channel option, the pause option, and desktop availability. Pause is checked after state is written and before delivery, so the sidebar and session summaries keep updating.

The pause is indefinite and lazily observed: there is no timer process and no resume timestamp. It survives client detach and plugin reload because it is an option; it does not survive a tmux server restart, at which point all agent state is gone anyway. Resume does not replay missed transitions.

There is no default key binding and no sidebar footer. The README documents `bind-key` examples, and `notify status` is the only pause indicator.

### Packaging and installation

- Root `tmux-orchestrator.tmux` is the TPM entry and the only file that knows TPM conventions.
- `bin/tmux-orchestrator` is the shared POSIX shell reporter; it requires `jq` for Claude hook JSON and uses tmux formats for everything else.
- `plugins/claude/` contains the Claude manifest and hooks. Its hook resolves the shared reporter relative to `CLAUDE_PLUGIN_ROOT`, so the whole repository clone remains the source of truth.
- `plugins/opencode/` contains the OpenCode plugin. The installer copies it into the user's OpenCode plugin directory and substitutes the absolute reporter path, avoiding PATH assumptions.
- The README documents the manual Claude marketplace enablement, which cannot be automated under the user's restrictions.
- `@tmux-orchestrator-enabled` persists the toggle state across plugin reloads. `@tmux-orchestrator-side`, `@tmux-orchestrator-width`, `@tmux-orchestrator-toggle-key`, and `@tmux-orchestrator-notify` are the TPM options. `@tmux-orchestrator-notify-paused` is runtime state, not a user setting.

The plugin checks for `side-status` by querying the option, not by parsing `tmux -V`; capability checks survive backports and vendor builds.

### Hooks for lifecycle cleanup

The plugin appends, at fixed hook indexes, `after-select-pane`, `after-select-window`, `client-session-changed`, `pane-exited`, and `session-closed` hooks that call the reporter's `focus` or `reconcile` command. Fixed indexes make reloads idempotent. Appending instead of assigning preserves user hooks.

## Risks / Trade-offs

- **tmux < 3.9 has no side-status** → capability check disables the plugin with one message; the rest of tmux configuration still loads.
- **OpenCode event payloads can drift** → adapter reads only documented event names, falls back to the directory name, and is covered by an event-fixture test; the exact title field is verified during implementation.
- **Crash leaves stale state when no `SessionEnd` fires and the pane stays open** → `reconcile` is available for manual repair; normal exits and pane closes are covered. A process-liveness check is deferred because `pane_current_command` is not reliable for wrapped agent binaries.
- **Direct pane clicks may not clear `done` without focus events** → sidebar clicks and selection commands do; `pane-focus-in` can be added later if `focus-events` is enabled. This is a cosmetic delay, not a routing error.
- **Overriding `MouseDown1Status` affects other status-bar clicks** → session and window ranges keep the default behavior; only the plugin's user ranges invoke the reporter's `select`.
- **Overflow can hide the session section when many agents exist** → `list=focus` keeps the active agent visible; the alternative, hiding active agents, is worse.
- **`claude agents --json` may not list a just-started session** → fallback name is written immediately and refreshed on the next prompt; clicks use pane IDs, so routing is unaffected.
- **Concurrent events can race the summary recompute** → recompute is idempotent and repeated on pane exit; the final scan wins.
- **Notifications omit location, so duplicate agent names are ambiguous** → the sidebar is the disambiguator; the notification still names both agents the same, which is the accepted trade-off.
- **Suppression keys on the active pane, not terminal focus** → a notification may be suppressed while the terminal is in the background; terminal focus tracking is unreliable without `focus-events`, so the predictable rule wins.
- **Desktop delivery may be absent or broken** → `both` falls back to tmux, `desktop` degrades to no-op, and `notify status` reports availability. This does not cover a daemon that accepts the command and drops the notification.
- **Pause is invisible without a footer** → `notify status` is the source of truth; the README documents it next to the binding examples.

## Migration Plan

This is a new repository, so there is no data migration. Installation is opt-in and user-level. Notifications default to `both`; a user who does not want them sets `@tmux-orchestrator-notify off` or runs `notify pause`. Rollback consists of disabling the TPM plugin, removing the Claude marketplace plugin, and deleting the OpenCode plugin file; tmux options disappear when panes and sessions close. A cleanup command unsets options from still-open panes for an immediate rollback.

## Open Questions

- Exact OpenCode field carrying the session title and the payload shape of `session.status` on the installed 2.x version; the adapter treats either `info.title` or `title` as valid.
- Whether `list=on`/`list=focus` behaves acceptably in `side-status` in all overflow cases; this is a visual tuning issue and does not change the architecture.
- Exact `osascript` invocation and niri notification behavior; both are isolated behind the desktop adapter and covered by `notify status`.
