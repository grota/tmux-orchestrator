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
- Claude Code 2.1.x and/or OpenCode 2.x (tested with 2.1.3). OpenCode 1.x is not
  supported.
- `python3` or `nc` with `-U` support, to focus an OpenCode tab from the
  sidebar.
- Optional desktop notifications: `notify-send` on Linux or `osascript` on macOS.

The plugin checks for `side-status` and refuses to enable the sidebar on older
tmux builds. Nothing else in the tmux configuration is prevented from loading.

## Install

The `/home/you/tmux-orchestrator` paths below are placeholders for the checkout.
Replace them with its absolute path; from the checkout root,
`./bin/tmux-orchestrator` is equivalent for the shell examples.

All installation is user-level. No existing hook JSON or agent configuration
file is rewritten.

### tmux

Run the entry point from your tmux configuration:

```tmux
run-shell '/home/you/tmux-orchestrator/tmux-orchestrator.tmux'
```

Then reload tmux:

```sh
tmux source-file ~/.tmux.conf
```

The repository has no published remote yet, so TPM's `set -g @plugin` form does
not work until it does. Reloading is safe: the entry point replaces its own
hooks and bindings instead of adding duplicates.

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

The installer copies the OpenCode TUI plugin into the user's plugin directory
and substitutes the absolute path to this checkout's reporter:

```sh
/home/you/tmux-orchestrator/bin/tmux-orchestrator install
```

This writes:

```text
~/.config/opencode/plugins/tmux-orchestrator/tui.js
```

OpenCode loads it in each TUI, so it knows the pane and the tabs it runs in. The
installer also deletes `~/.config/opencode/plugins/tmux-orchestrator.js`, the
server plugin of earlier versions. It does not edit `opencode.json` or any other agent configuration. Remove the
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
- A Claude Code pane has one agent row. An OpenCode pane has one row per tab, in
  tab order.
- A pane shows at most nine agent rows. Further agents collapse into one
  `+N more` row whose icon is the most urgent state among them.
- Clicking a session row switches the client to that session. Clicking an agent
  row switches to its session, selects its window, and focuses its exact pane.
  For an OpenCode row it also focuses that tab. Clicking `+N more` selects the
  pane.
- When there are more rows than fit, the list keeps the focused agent's row
  visible. It may trim session rows first, and it does not scroll the terminal.

The plugin rebinds `MouseDown1Status` to handle these clicks, which replaces any
existing binding for it.

### State icons

| State   | Icon | Colour |
| ------- | ---- | ------ |
| working | `◐`  | yellow |
| blocked | `●`  | red    |
| error   | `×`  | red    |
| done    | `✓`  | teal   |
| idle    | `○`  | green  |
| unknown | `·`  | grey   |

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

- `both`: tmux and desktop. Falls back to tmux when no desktop command exists.
- `tmux`: tmux clients only.
- `desktop`: desktop only. Does nothing if no desktop command exists.
- `off`: no notifications. State tracking continues.

Notification text is:

```text
● fix-login blocked
● Agent blocked: fix-login
```

Kind and tmux location are deliberately omitted. A client that is viewing the
agent's pane (and, for OpenCode, its active tab) does not receive the tmux message, and the desktop notification is
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

The plugin forwards these hooks to the reporter, which maps them:

| Event                                                  | State                               |
| ------------------------------------------------------ | ----------------------------------- |
| `SessionStart`                                         | `idle`                              |
| `UserPromptSubmit`, `PostToolUse`, `ElicitationResult` | `working`                           |
| `PreToolUse`                                           | `working`                           |
| `PreToolUse` for `AskUserQuestion` or `ExitPlanMode`   | `blocked`                           |
| `PermissionRequest`, `Elicitation`                     | `blocked`                           |
| `Stop`                                                 | `done` after work, otherwise `idle` |
| `StopFailure`                                          | `error`                             |
| interrupt (Esc), read from the transcript              | `idle`                              |
| `SessionEnd`                                           | removed                             |

Subagent tool calls and permission requests count toward the main agent. A
subagent never starts, completes or ends it. `PostToolUseFailure` is not treated
as an agent error. A `Stop` after an `error` keeps `error` until new activity.

Claude Code sends no hook when you interrupt a turn with Esc. While a turn runs,
a background watcher reads the new lines of the session transcript every 3
seconds and moves the agent to `idle` when Claude Code records the interrupt.
The watcher stops when the turn ends, when the next prompt starts a new one, when
the pane closes, or after an hour without transcript activity. It relies on the
transcript's interrupt text, which Claude Code does not document.

The last hook received is stored in the pane option `@agent_1_event`, for
example `claude:StopFailure:rate_limit`.

The session title is used when the hook provides one. Otherwise the reporter
uses the working-directory basename immediately and asynchronously refreshes the
name from `claude agents --json` on `SessionStart` and `UserPromptSubmit`.
If the lookup is slow or fails, the fallback name remains.

## OpenCode events

The adapter runs in the OpenCode TUI and reports each open tab as its own agent.
It forwards these events to the reporter, which maps them:

- `session.execution.started`, `permission.replied`, `form.replied` and
  `form.cancelled` to `working`.
- `permission.asked` and `form.created` to `blocked`.
- `session.execution.succeeded` to `done` after work, otherwise to `idle`.
- `session.execution.failed` to `error`.
- `session.execution.interrupted` to `idle`.
- `session.renamed` to a new agent name.

Other events, such as streamed text, stay in the TUI.

Opening a tab adds an agent: `working` if the session is running, `blocked` if
it has a pending permission or form, and `idle` otherwise. Closing a tab removes
that agent without deleting its session. Exiting the TUI removes all of the
pane's agents. With tabs disabled, the session the TUI shows is the pane's only
agent.

Subagents run as child sessions and count toward their root tab. A child asking
for permission or input blocks the root. A child finishing, failing or being
interrupted does not end the root's turn.

A completion after `session.execution.failed` keeps `error` until new activity.
The tab's session title is the agent name. Without a title, the working-directory
basename is used.

Clicking a tab's row focuses that tab. The reporter sends the request over a
Unix socket that the TUI opens in `/tmp/tmux-orchestrator-<uid>/`.

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
- Claude Code interrupts are read from the session transcript, whose format is
  undocumented. If a Claude Code update changes the interrupt text, an
  interrupted agent stays `working` until your next prompt.
- An OpenCode agent on a background tab stays `done` until its tab becomes
  active, even when its pane is focused.
- Focusing an OpenCode tab from the sidebar needs `python3` or `nc -U`. Without
  either, the click selects the pane but not the tab.
- `done` clears only when a pane, window or session selection happens. An agent
  that finishes in the pane you are already looking at stays `done` until you
  select something or click its row.
- Notifications omit location, so two agents with the same name are ambiguous;
  use the sidebar to disambiguate.
- State disappears when the tmux server exits. There is no external history.
- The Claude name lookup depends on `claude agents --json`; a missing or slow
  lookup falls back to the directory basename.
- Desktop delivery depends on `notify-send` or `osascript`; a command that
  accepts a notification and drops it cannot be detected.
