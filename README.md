# tmux-orchestrator

A tmux-native sidebar for Claude Code, Codex, and OpenCode agents. It shows every tmux
session with an agent, the agents in the current session, and switches to the
right session, window, and pane with one click.

State comes from agent lifecycle events, not from screen scraping. The reporter
stores it in tmux pane and session options, so there is no daemon, no state file,
and no external database.

[![tmux-orchestrator architecture](docs/diagrams/architecture.gif)](docs/diagrams/architecture.gif)

## Install

All installation is user-level. Each adapter has its own plugin package.

### Requirements

- tmux 3.9 or newer (`side-status` is required).
- `jq` for Claude Code and Codex hook payloads.
- Claude Code 2.1.x and/or OpenCode 2.x (tested with 2.1.3). OpenCode 1.x is not
  supported.
- Codex CLI 0.171.0, tested with plugin hooks enabled.
- `python3` or `nc` with `-U` support, to focus and rename OpenCode tabs and
  rename Claude Code agents.
- Optional, for desktop notifications: `notify-send` on Linux or `osascript` on
  macOS.

### tmux

Install with [TPM](https://github.com/tmux-plugins/tpm): add the
plugin to your tmux configuration, then press `prefix + I` (`prefix + U`
updates it).

```tmux
set -g @plugin 'grota/tmux-orchestrator'
```

### Claude Code

Add this repository as a marketplace and install the plugin,
then enable it in `/plugin` if needed. Sessions started afterwards are tracked.

```text
/plugin marketplace add grota/tmux-orchestrator
/plugin install tmux-orchestrator@tmux-orchestrator
```

To load the plugin for one session from a local checkout, start Claude Code
with `claude --plugin-dir /path/to/tmux-orchestrator/plugins/claude`.

### Codex

From the tmux-orchestrator checkout, add the local marketplace and install the plugin.

```bash
codex plugin marketplace add "$PWD/plugins/codex"
codex plugin add tmux-orchestrator@tmux-orchestrator
```

For daemon-backed sessions, include `thread-id` in the Codex terminal title.
Add this setting to the `[tui]` section of `~/.codex/config.toml`:

```toml
[tui]
terminal_title = ["thread-id", "spinner", "project"]
```

Start or resume Codex as usual inside tmux. Trust the tmux-orchestrator hooks
in `/hooks` and submit a prompt. The hook uses the thread ID to find its pane
on the default tmux server started with the usual socket. For a named tmux
server, set `TMUX_SOCKET` to the server name in the daemon's environment.
Sessions started with `--no-daemon` can use any terminal title.

Codex copies the plugin when it installs it. After updating tmux-orchestrator,
run `codex plugin add tmux-orchestrator@tmux-orchestrator` again, then trust
the hooks again in `/hooks` and restart running Codex sessions.

### OpenCode

Nothing to do: the tmux plugin links the OpenCode adapter when
OpenCode is installed. Restart OpenCode after the first install.

## Usage

### Sidebar

Every agent you run, in every tmux session, on one always-visible strip. No
more hunting through windows to find out who is done, who is stuck and who is
still thinking: one glance tells you. Toggle it with `prefix + O`, drag its
border to make room, double-click the border to snap it back.

- **Session rows** roll up their agents into the single most urgent state, and
  count who is blocked (`◉2`), failed (`×1`) or done (`✓1`). `▸` marks where
  you are.
- **Agent rows** show the state, the name, the kind (`claude`, `codex`, or `opencode`)
  and how long the agent has been in that state (`3m12s`), so the agent that
  has been waiting longest stands out.
  Codex shows the thread title when available and uses the directory name
  until a title is available. Use `/rename` in Codex to change the title.
- **Subagents and background work** are visible too: a Claude Code agent with
  subagents shows their state and count (`✓ ●2`), and its background tasks add
  a blue `·` and their count (`·2`).
- **Every OpenCode tab** is its own agent. A busy pane shows nine and folds the
  rest into a `+N more` row.
- **Click** a session to jump to it, or an agent to land on its exact pane
  and OpenCode tab.
- **Double-click** to rename: a session row renames the tmux session, an agent
  row renames the agent in Claude Code or OpenCode itself.
- **Window names** follow the agent in the window's active pane, cut to 20
  characters, and go back to the command when the agent exits.
- **`≡ options`**, on the top row, opens a panel with every option below except OpenCode
  auto-install. Click a value to change it, cycling through its choices or
  typing a new one; an empty answer goes back to the default. Click a label to
  read what the option does. Changes last until tmux restarts, and reloading
  `tmux.conf` brings back the values it sets, so put lasting choices there.
- **`? keys`**, on the top row, lists every key binding the plugin knows about.

| State   | Icon | Colour | Meaning                                    |
| ------- | ---- | ------ | ------------------------------------------ |
| working | `●`  | yellow | running a turn                             |
| blocked | `◉`  | red    | waiting for a permission or an answer      |
| error   | `×`  | red    | the turn failed; stays until next activity |
| done    | `✓`  | teal   | turn finished; clears when you view it     |
| idle    | `○`  | green  | nothing to do                              |
| unknown | `·`  | grey   | no state yet                               |

### Next agent key

One key to triage everything. Each press takes you straight to the next agent
that needs you, across all tmux sessions and terminal windows: blocked ones
first, then failed, then finished, the longest waiting first. Once those are
handled it keeps going through every other agent, then starts over. An agent
that starts needing you jumps the queue, so you never miss it. Pick the key in
[Options](#options); it is not bound until you do.

### Notifications

When an agent gets blocked, fails or finishes, you hear about it, unless you
are already looking at it.

- **Desktop notifications** reach you wherever you are. Click one and you land
  on the agent; with a raise command set (see [Options](#options)), its
  terminal window comes forward too. Each agent keeps at most one notification
  on screen: a new one replaces the old one instead of piling up.
- **Inside tmux, the sidebar is your notification.** Nothing flashes over your
  status line: the change is already on the sidebar, and it stays there until
  you deal with it.
- **Terminal notifications** (OSC 9) work even over SSH, in terminals that
  support them.

Need some quiet? Pause every notification with one command (see
[Commands](#commands)); the sidebar keeps updating.

### Agent messaging

Claude Code and Codex agents can message each other. The plugins ship an
`agent-messaging` skill, so you can ask an agent to "ask the Codex agent in
window 3 to review this diff". The skill runs the reporter's `agents`, `send`,
`wait` and `read` commands.

`send` types the message into the other agent's prompt and presses Enter.
The message opens with who sent it and how to reply, and the receiver
answers with `send` in the same way.

The receiving agent acts on a message with the permissions you gave it, as if
you had typed it. Keep risky actions behind each agent's approval prompts.
`send` never types into an agent that waits for your approval. It also waits
while you type in the target's pane.

## Options

Set options above the line that runs TPM (`run '~/.tmux/plugins/tpm/tpm'`). The
ones marked _live_ can also be changed later and apply at once. All of them can
be changed from the sidebar's `≡ options` panel.

| Option                                     | Default      | Description                                                                                    |
| ------------------------------------------ | ------------ | ---------------------------------------------------------------------------------------------- |
| `@tmux-orchestrator-side`                  | `left`       | Sidebar side: `left` or `right`.                                                               |
| `@tmux-orchestrator-width`                 | `28`         | Sidebar width in columns.                                                                      |
| `@tmux-orchestrator-toggle-key`            | `O`          | Key, after the prefix, that shows and hides the sidebar.                                       |
| `@tmux-orchestrator-name-wrap`             | `wrap`       | _Live._ `wrap` long names over up to four lines, or `nowrap` to cut them to one line.          |
| `@tmux-orchestrator-name-max-chars`        | unset        | _Live._ Cut names to this many characters first; unset for no limit.                           |
| `@tmux-orchestrator-focus-style`           | `underlined` | _Live._ How the agent you are viewing is marked: `underlined`, `bold` or `none`.               |
| `@tmux-orchestrator-time`                  | `on`         | _Live._ `off` hides the state time.                                                            |
| `@tmux-orchestrator-time-on-view`          | `keep`       | _Live._ `reset` restarts a `done` agent's time when you view it.                               |
| `@tmux-orchestrator-window-name`           | `on`         | _Live._ `off` leaves window names alone; `force` works without the command in your format.     |
| `@tmux-orchestrator-next-agent-key`         | unset        | Key that goes to the next agent needing you. Not bound unless set.                             |
| `@tmux-orchestrator-next-agent-table`       | `prefix`     | Key table of the next agent key; `root` binds it without the prefix.                            |
| `@tmux-orchestrator-notify-desktop`        | `on`         | _Live._ Desktop notifications (`notify-send` or `osascript`).                                  |
| `@tmux-orchestrator-notify-terminal`       | `off`        | _Live._ An OSC 9 notification shown by the terminal (Ghostty, iTerm2, WezTerm), even over SSH. |
| `@tmux-orchestrator-notify-timeout`        | `5`          | _Live._ Seconds a desktop notification stays open and can be clicked.                          |
| `@tmux-orchestrator-raise-command`         | unset        | _Live._ Shell command that brings the agent's terminal window forward.                         |
| `@tmux-orchestrator-focus-events`          | `on`         | `off` leaves tmux's `focus-events` alone; agents in background windows then do not notify.     |
| `@tmux-orchestrator-opencode-auto-install` | `on`         | `off` stops the plugin from linking the OpenCode adapter.                                      |

Examples:

```tmux
set -g @tmux-orchestrator-next-agent-key M-a
set -g @tmux-orchestrator-next-agent-table root   # no prefix needed
set -g @tmux-orchestrator-raise-command '~/.tmux/plugins/tmux-orchestrator/examples/raise-command-niri.sh'
```

`examples/raise-command-niri.sh` raises the terminal window on niri.

The plugin never overwrites a key binding of yours: if the toggle or next agent
key is taken, it keeps your binding and tells you.

## Commands

The plugin runs the reporter for you; these commands are for bindings, scripts
and recovery. The examples call the reporter `tmux-orchestrator`:

```sh
alias tmux-orchestrator="$(tmux show-options -gv @tmux-orchestrator-reporter)"
```

| Command                                  | What it does                                                                           |
| ---------------------------------------- | -------------------------------------------------------------------------------------- |
| `notify pause`, `resume`, `toggle`       | Stop or restart all notifications. The sidebar keeps updating; pause survives reloads. |
| `notify status`                          | Show whether notifications are paused and each channel's setting.                      |
| `focus-agent --pane ID`                  | Go to an agent, as a notification click does.                                          |
| `toggle`                                 | Show or hide the sidebar.                                                              |
| `reconcile`                              | Recompute every session summary after a crash or stale state.                          |
| `gc`                                     | Remove agents of panes whose process exited (`remain-on-exit`).                        |
| `cleanup`                                | Remove all agent options and hooks from the running server.                            |
| `install opencode`, `uninstall opencode` | Link or unlink the OpenCode adapter by hand.                                           |
| `agents`                                 | List the agents and their addresses (`%7`, or `%7:2` for an OpenCode tab).             |
| `send ADDRESS [TEXT]`                    | Type a message into an agent; TEXT or stdin. `--wait` also waits for its turn to end.  |
| `wait ADDRESS`                           | Wait until the agent stops working; exits 3 after `--timeout` (100 s).                 |
| `read ADDRESS`                           | Print the last `--lines` (80) lines of the agent's pane.                               |

Example bindings:

```tmux
bind-key N run-shell -b '#{@tmux-orchestrator-reporter} notify pause'
bind-key M run-shell -b '#{@tmux-orchestrator-reporter} notify resume'
```

## How it works

Details for advanced users.

### Claude Code events

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
| interrupt (Esc), read from the session status          | `idle`                              |
| `SubagentStart`                                        | lists the subagent                  |
| `SessionEnd`                                           | removed                             |

- Subagent tool calls and permission requests count toward the main agent. A
  waiting agent stays `blocked` until the one that waits calls a tool again,
  ends, or a new turn starts. Parallel tool calls cannot be told apart, so one
  finishing clears a wait raised by another.
- Subagents are listed from their first event until `SubagentStop`. One silent
  for 30 minutes is dropped. When the last one ends, the agent takes its main
  thread's state.
- Background tasks (`Bash` with `run_in_background`, or `Monitor`) are added at
  launch. Each `Stop` hook lists the tasks still running, and the sidebar takes
  that list. A task no `Stop` lists for six hours is dropped. Tasks never change
  the state or notify.
- Claude Code sends no hook for Esc. While a turn runs, a watcher reads the
  session's status from Claude Code's undocumented session registry every 2
  seconds and moves the agent to `idle` when the turn was interrupted (SPEC.md
  D6).
- The agent name is the session title, else the working-directory basename,
  refreshed from `claude agents --json`.
- The last hook is stored in the pane option `@agent_1_event`, for example
  `claude:StopFailure:rate_limit`.
- A background session shown with `claude attach <id|name>` is the agent of
  that pane while the pane shows it. Events from a session no pane shows are
  ignored.

### Codex events

One row per pane shows the Codex thread.

| Hook                                             | State change      |
| ------------------------------------------------ | ----------------- |
| `SessionStart`                                   | `idle`            |
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse`  | `working`         |
| `PermissionRequest`, `PreToolUse` for user input | `blocked`         |
| `Stop`                                           | `done` after work |
| `Interrupt`                                      | `idle`            |
| `SessionEnd`                                     | Remove the row    |

Codex rows have no sidebar rename action. Codex sends `SessionStart` only with
the first prompt, so the plugin adds an `idle` row when Codex sets its terminal
title at launch, and the thread takes the row over with its first prompt.
Model failures have no matching hook in this adapter.

### OpenCode events

The adapter runs in the OpenCode TUI and reports each open tab as its own agent:

- `session.execution.started`, `permission.replied`, `form.replied` and
  `form.cancelled` → `working`.
- `permission.asked` and `form.created` → `blocked`.
- `session.execution.succeeded` → `done` after work, otherwise `idle`.
- `session.execution.failed` → `error`.
- `session.execution.interrupted` → `idle`.
- `session.renamed` → a new agent name.

Opening a tab adds an agent, closing it removes the agent, and exiting the TUI
removes all of the pane's agents. Subagents run as child sessions and count
toward their root tab. The reporter focuses and renames tabs over a Unix socket
the TUI opens in `tmux-orchestrator-<uid>/` under `$XDG_RUNTIME_DIR` (or the
system temporary directory).

### Notifications

- Notification text is `◉ Agent blocked: fix-login`. Kind and location are
  left out.
- Nothing is sent while any client views the agent: its pane, and for OpenCode
  its active tab.
- The plugin turns on tmux's `focus-events`, so a terminal window without focus
  does not count as viewing. The terminal must report focus changes (Ghostty,
  kitty, WezTerm, iTerm2 and foot do).
- A click on a `notify-send` notification brings one client to the agent: the
  one showing its window, else one in its tmux session, else the most recently
  active one. The raise command then runs with `TMUX_ORCHESTRATOR_PANE`,
  `TMUX_ORCHESTRATOR_SESSION`, `TMUX_ORCHESTRATOR_CLIENT`,
  `TMUX_ORCHESTRATOR_CLIENT_PID` and `TMUX_ORCHESTRATOR_CLIENT_TTY` set.
- `osascript` notifications on macOS cannot be clicked.
- The terminal channel is off by default because those terminals turn it into a
  system notification too, so with desktop on you would see each one twice.

### Sidebar details

- Viewing a `done` agent clears it to `idle`; its time keeps running unless
  `@tmux-orchestrator-time-on-view` is `reset`.
- When rows do not fit, the list keeps the focused agent visible.
- The plugin rebinds `MouseDown1SideStatus` and `DoubleClick1SideStatus`,
  replacing any bindings of yours for them. The status line's own mouse
  bindings are left alone.
- The sidebar's on/off state is kept in `@tmux-orchestrator-enabled`, so a
  reload does not bring back a hidden sidebar.
- The adapters find the reporter through the global option
  `@tmux-orchestrator-reporter`; the tmux plugin holds its only copy.

## Development

Work from a git checkout, here `/path/to/checkout`. Load the tmux plugin from it
instead of TPM, and start Claude Code with the checkout's plugin:

```tmux
run-shell '/path/to/checkout/tmux-orchestrator.tmux'
```

```sh
claude --plugin-dir /path/to/checkout/plugins/claude
```

The adapters use the reporter of the loaded tmux plugin copy. After switching
between TPM and a checkout, reload tmux; running agents use the new reporter on
their next event, and OpenCode needs a restart. An adapter newer than the loaded
reporter is ignored, and tmux shows a one-time message.

Run the tests with `bash tests/<name>-test.sh` for each shell suite and
`node --test tests/` for the OpenCode adapter. They start private tmux servers
and do not touch the running one.

Some features rely on undocumented Claude Code and OpenCode internals. After
updating either, run the contract tests against the installed versions:

```sh
bash tests/contract/claude-test.sh
bash tests/contract/opencode-test.sh
```

Each starts a real agent in a private tmux server and needs no model.
`TMUX_ORCHESTRATOR_CONTRACT_TURN=1` also interrupts one Haiku turn in the Claude
test. The Claude test needs the checkout to be a folder Claude already trusts.

## Known limitations

- tmux 3.9 or newer is required; there is no fallback sidebar.
- A crashed agent that never sends `SessionEnd` can leave a stale row until
  `reconcile`, `gc`, or the pane closes.
- Claude Code interrupts and agent renames use undocumented Claude Code
  internals (SPEC.md D6, D9). If an update changes them, interrupted agents stay
  `working` and renames fail; `tests/contract/claude-test.sh` detects it.
- `done` clears only on a pane, window or session selection, so an agent that
  finishes in the pane you are looking at stays `done` until you select
  something. An OpenCode agent on a background tab stays `done` until its tab
  becomes active.
- Notifications omit location, so two agents with the same name are ambiguous.
- An agent cannot tell an agent message from your own typing apart from its
  wording, and text left in a prompt mixes with a message typed into it
  (SPEC.md D21).
- Agent messaging relies on Claude Code and Codex exporting their session ID
  to tool commands and submitting a bracketed paste on Enter. Both are
  undocumented; a message from an agent that no longer exports its ID arrives
  without a reply address.
- A Claude Code background session is tracked only while a pane shows it with
  `claude attach`, and only on the default tmux server.
- A long `? keys` panel hides the agent list until you close it.
- State disappears when the tmux server exits.
- A desktop notifier that accepts a notification and drops it cannot be
  detected.
