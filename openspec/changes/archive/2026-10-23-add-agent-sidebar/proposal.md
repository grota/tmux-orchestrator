# Proposal

## Why

When several coding agents run in different tmux sessions, finding which one is working, blocked, or finished requires cycling through windows and reading each terminal. There is no persistent, tmux-native overview that both shows every agent across the server and switches directly to its pane, and no signal when an agent starts needing a person.

## What Changes

- Add a persistent vertical sidebar rendered by tmux `side-status`, showing:
  - every tmux session on the server that has at least one tracked agent, with a worst-state icon, its name, and agent count;
  - the agents in the current session, with state icon, agent session name, and agent kind.
- Track agent state from lifecycle events only (Claude Code hooks, OpenCode plugin events); no screen scraping.
- Store state in tmux user options on panes and sessions, so the sidebar and future clients read one source without a daemon.
- Support the states `working`, `blocked`, `done`, `idle`, `error`, and `unknown`.
- Make sidebar rows clickable: a session row switches the client to that session, an agent row switches to its window and pane.
- Notify on transitions into `blocked`, `error`, and `done`, through the tmux status line and, when available, the desktop. Notifications show only the state icon, agent name, and state; they never include agent kind or tmux location.
- Provide `notify pause`, `notify resume`, and `notify status` for a global, indefinite notification pause. No key is bound by default.
- Ship as one repository that is a TPM-compatible tmux plugin, a Claude Code marketplace plugin, and an OpenCode plugin. Installation is user-level.
- Refuse to run on tmux versions without `side-status` (older than 3.9) with a visible message.

## Capabilities

### New Capabilities

- `agent-state`: normalized agent state, transitions, name resolution, rollout to session rollup and counts, and storage in tmux options.
- `agent-sidebar`: `side-status` rendering, section and row content, icons, ordering, and mouse interaction.
- `agent-notifications`: attention-triggered delivery through tmux and the desktop, deduplication, focus suppression, and global pause control.
- `agent-integrations`: Claude Code and OpenCode event ingestion, adapter installation artifacts, and runtime compatibility checks.

### Modified Capabilities

None.

## Impact

- New tmux plugin entry point, shared reporter executable, and tests.
- New Claude Code plugin (hooks -> reporter) and OpenCode plugin (events -> reporter).
- Optional desktop notifications use `notify-send` on Linux or `osascript` on macOS; when neither exists, `both` falls back to tmux.
- Requires tmux 3.9 or newer; `side-status` is session-scoped and unsupported on stable 3.6-3.8.
- Agent state is ephemeral: it lives in the tmux server and disappears when the server stops.
- No network access, no daemon, and no state files outside tmux options.
