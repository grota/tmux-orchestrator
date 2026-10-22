# tmux-orchestrator

A tmux-native sidebar for Claude Code and OpenCode agents. It shows every tmux
session with an agent, the agents in the current session, and switches to the
right session, window, and pane with one click.

State comes from agent lifecycle events, not from screen scraping. The reporter
stores it in tmux pane and session options, so there is no daemon, no state file,
and no external database.

## Requirements

- tmux 3.9 or newer (`side-status` is required).
- `jq` for Claude Code hook payloads.
- Claude Code 2.1.x and/or OpenCode 2.x.
- Optional desktop notifications: `notify-send` on Linux or `osascript` on macOS.

The plugin checks for `side-status` and refuses to enable the sidebar on older
tmux builds. Nothing else in the tmux configuration is prevented from loading.

## Install

The `/home/you/tmux-orchestrator` paths below are placeholders for the checkout.
Replace them with its absolute path; from the checkout root,
`./bin/tmux-orchestrator` is equivalent for the shell examples.

All installation is user-level. No existing hook JSON or agent configuration
file is rewritten.

### tmux (TPM)

Add the repository as a TPM plugin, then reload tmux:

```tmux
set -g @plugin 'owner/tmux-orchestrator'
```

For a local checkout, source the entry point directly instead:

```tmux
run-shell '/home/you/tmux-orchestrator/tmux-orchestrator.tmux'
```

Reload with:

```sh
tmux source-file ~/.tmux.conf
```

TPM users can press `prefix + I` after adding the plugin.

### Claude Code

The Claude Code plugin cannot enable itself on every machine. Add this
repository as a marketplace, install the plugin, then enable it in the plugin
manager:

```text
/plugin marketplace add /home/you/tmux-orchestrator
/plugin install tmux-orchestrator@tmux-orchestrator
/plugin
```

In the `/plugin` interface, open the installed plugin and enable it. After the
next Claude Code session starts, the sidebar tracks it.

`hooks.json` invokes `"${CLAUDE_PLUGIN_ROOT}/hooks/report.sh"`. That script
resolves the shared reporter three directories above the plugin's `hooks/`
directory (or uses `TMUX_ORCHESTRATOR_REPORTER` when set). Keep the marketplace
source pointing at the whole repository checkout; do not copy only
`plugins/claude` somewhere else.

### OpenCode

The installer copies the OpenCode plugin into the user's plugin directory and
substitutes the absolute path to this checkout's reporter:

```sh
/home/you/tmux-orchestrator/bin/tmux-orchestrator install
```

This writes:

```text
~/.config/opencode/plugins/tmux-orchestrator.js
```

It does not edit `opencode.json` or any other agent configuration. Remove the
plugin with:

```sh
/home/you/tmux-orchestrator/bin/tmux-orchestrator uninstall
```

## Sidebar

By default the sidebar is on the left and 28 columns wide. Configure it before
the plugin loads:

```tmux
set -g @tmux-orchestrator-side right
set -g @tmux-orchestrator-width 32
set -g @tmux-orchestrator-toggle-key T
```

`@tmux-orchestrator-side` accepts `left` or `right`. The toggle key defaults to
`O` and is not reserved when set to another key. The enabled state is persisted
in `@tmux-orchestrator-enabled`, so reloading tmux does not bring back a
sidebar that was toggled off.

Drag the sidebar border to resize it. Double-click the border to reset the width
to `@tmux-orchestrator-width`. State refreshes do not reset a width changed by
dragging.

Rows:

- A session row shows the rollup icon, session name, and agent count. The
  current session is marked with `▸`.
- An agent row shows the state icon, agent name, and kind (`claude` or
  `opencode`). Long names are truncated with `…`.
- Clicking a session row switches the client to that session. Clicking an agent
  row switches to its session, selects its window, and focuses its exact pane.
- When there are more rows than fit, the list keeps the focused agent's row
  visible. It may trim session rows first, and it does not scroll the terminal.

### State icons

| State | Icon | Colour |
| --- | --- | --- |
| working | `◐` | yellow |
| blocked | `●` | red |
| error | `×` | red |
| done | `✓` | teal |
| idle | `○` | green |
| unknown | `·` | grey |

Session rollups use the priority `blocked > error > done > working > idle >
unknown`. `done` clears when the agent pane is focused. `error` stays until the
next activity event.

## Notifications

Notifications are sent for transitions into `blocked`, `error`, and `done`.
They are not sent for `working`, `idle`, `unknown`, repeated states, focus
clearing, or agent removal.

The default channel is `both`: tmux and the desktop where a supported desktop
command exists. Configure it with:

```tmux
set -g @tmux-orchestrator-notify both
```

Accepted values:

- `both` — tmux and desktop; falls back to tmux when no desktop command exists.
- `tmux` — tmux clients only.
- `desktop` — desktop only; silently does nothing if no desktop command exists.
- `off` — no notifications; state tracking continues.

Notification text is:

```text
● fix-login blocked
● Agent blocked: fix-login
```

Kind and tmux location are deliberately omitted. A client that is viewing the
agent's pane does not receive the tmux message, and the desktop notification is
skipped when any attached client is viewing it. A two-second per-agent cooldown
applies to tmux `done` messages; `blocked` and `error` bypass it. Desktop
notifications have no cooldown.

### Pause and resume

Pause is global and indefinite. It suppresses both channels while states keep
updating and the sidebar keeps rendering. There is no default pause key and no
pause indicator in the sidebar.

```sh
/home/you/tmux-orchestrator/bin/tmux-orchestrator notify pause
/home/you/tmux-orchestrator/bin/tmux-orchestrator notify resume
/home/you/tmux-orchestrator/bin/tmux-orchestrator notify status
```

Example tmux bindings:

```tmux
bind-key N run-shell -b '/home/you/tmux-orchestrator/bin/tmux-orchestrator notify pause'
bind-key M run-shell -b '/home/you/tmux-orchestrator/bin/tmux-orchestrator notify resume'
```

Pause survives plugin reloads and client detach because it is a tmux option.
`notify status` reports the channel, pause state, and desktop availability.

## Claude Code events

The plugin maps main-thread hooks:

| Event | State |
| --- | --- |
| `SessionStart` | `idle` |
| `UserPromptSubmit` | `working` |
| `PreToolUse`, `PostToolUse` | `working` |
| `PermissionRequest` | `blocked` |
| `Stop` | `done` |
| `StopFailure` | `error` |
| `SessionEnd` | removed |

Events with an `agent_id` (subagents) are ignored. `PostToolUseFailure` is not
treated as an agent error.

The session title is used when the hook provides one. Otherwise the reporter
uses the working-directory basename immediately and asynchronously refreshes the
name from `claude agents --json` on `SessionStart` and `UserPromptSubmit`.
If the lookup is slow or fails, the fallback name remains.

## OpenCode events

The OpenCode 2.x adapter subscribes to the event stream from its `setup`
function. It maps:

| Event | State |
| --- | --- |
| `session.created` | `idle` |
| `chat.message`, `tool.execute.before`, `tool.execute.after`, `permission.replied`, `question.replied`, `question.rejected`, `session.compacted` | `working` |
| `permission.asked`, `question.asked` | `blocked` |
| `session.idle` | `done` after activity, otherwise `idle` |
| `session.error` | `error` |
| `session.deleted` | removed |

Child session permission and question events block the root pane. Child
completion does not complete a working root. `session.idle` after `session.error`
keeps `error` until new activity. The session title becomes the agent name and is
updated when the title changes. Without a title, the working-directory basename
is used.

## Maintenance

Recompute every session summary after an unexpected shutdown or stale state:

```sh
/home/you/tmux-orchestrator/bin/tmux-orchestrator reconcile
```

Remove state from panes whose process has exited (for `remain-on-exit` panes):

```sh
/home/you/tmux-orchestrator/bin/tmux-orchestrator gc
```

Toggle the sidebar from a script or binding:

```sh
/home/you/tmux-orchestrator/bin/tmux-orchestrator toggle
```

Remove all agent options and this plugin's hook indexes from a running server:

```sh
/home/you/tmux-orchestrator/bin/tmux-orchestrator cleanup
```

## Known limitations

- tmux 3.9 or newer is required; there is no fallback sidebar.
- State is derived from lifecycle events only. A crashed agent that never sends
  `SessionEnd` can leave a stale row until `reconcile`, `gc`, or the pane closes.
- Selecting a different pane clears `done` through the `after-select-pane` hook.
  Sidebar agent-row clicks run `focus` explicitly, including for the active pane.
- `MouseDown1Status` is rebound to keep the normal `switch-client -t=` behavior
  and add window and pane selection for sidebar ranges.
- Notifications omit location, so two agents with the same name are ambiguous;
  use the sidebar to disambiguate.
- State disappears when the tmux server exits. There is no external history.
- The Claude name lookup depends on `claude agents --json`; a missing or slow
  lookup falls back to the directory basename.
- Desktop delivery depends on `notify-send` or `osascript`; a command that
  accepts a notification and drops it cannot be detected.
