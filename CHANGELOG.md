# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Options panel, opened from the `≡ options` sidebar row: clicking a value changes the option until tmux restarts, and clicking a label shows its description.
- `@tmux-orchestrator-name-wrap` option: `wrap` (default) or `nowrap`.
- `option-answer` reporter command.
- `window-name` reporter command; `@tmux-orchestrator-window-name` is live.
- Window names show the agent name of the active pane through `automatic-rename-format`; `@tmux-orchestrator-window-name` is `on`, `force` or `off`.
- Next agent key: `@tmux-orchestrator-next-agent-key` and `@tmux-orchestrator-next-agent-table` bind a key that goes through all agents, those that are blocked, in error or done first.
- A Claude Code agent's row shows how many background tasks it and its subagents have running, as a blue `·` and a count.
- `@tmux-orchestrator-focus-events` option: the plugin turns on tmux's `focus-events` unless it is `off`, and warns when it stays off.
- Clicking a desktop notification brings a tmux client to the agent.
- A new `notify-send` notification replaces the agent's previous one while it is still shown.
- `@tmux-orchestrator-notify-timeout` option: seconds a desktop notification stays open and can be clicked, `5` by default.
- `@tmux-orchestrator-raise-command` option, run after a notification click or the next agent key to bring the terminal window forward, with `examples/raise-command-niri.sh` for niri.
- `focus-agent` command.
- `@tmux-orchestrator-opencode-auto-install` option, `on` by default.
- A Claude Code subagent that stops while its own background task runs stays in the subagent indicator as idle.
- `--task-done` report option.
- `@tmux-orchestrator-notify-desktop` and `@tmux-orchestrator-notify-terminal` options; terminal is `off` by default.
- `@tmux-orchestrator-name-max-chars` option: a character limit applied before wrapping.
- Keys panel, opened from the `? keys` sidebar row, listing the bindings that call the reporter.
- The focused agent's name is emphasised in the sidebar.
- `@tmux-orchestrator-focus-style` option: `underlined` (default), `bold` or `none`.
- Claude Code background sessions shown with `claude attach` are tracked as the agent of that pane.
- Double-clicking a session row renames the tmux session.
- Double-clicking an agent row renames the Claude Code or OpenCode agent session.
- `rename` and `rename-prompt` reporter commands.
- Contract tests for the Claude Code and OpenCode internals the plugin relies on.
- A Claude Code agent with subagents shows its main thread's icon and its subagents' rollup and count.
- `@tmux-orchestrator-time-on-view` option: `keep` (default) or `reset`.

### Changed

- The `? keys` entry and its panel moved to the top of the sidebar, next to `≡ options`.
- With tmux's `focus-events` on, a client in a terminal window without focus no longer counts as viewing its agent: the agent still notifies, and its `done` state clears when the window gets focus.
- The OpenCode adapter is linked on each plugin load when OpenCode is detected.
- README command-line commands are grouped under "Optional command line commands".
- **BREAKING:** Long agent names wrap over up to four lines by default.
- The time in state moved to the agent's kind line, right-aligned.
- **BREAKING:** Viewing a `done` agent no longer restarts its time in the sidebar.
- The toggle key is not bound when the key already has a user binding, and a previous toggle key is unbound on reload.
- `notify status` reports the pause state and each notification channel's setting.
- **BREAKING:** The `working` icon is a yellow `●` and the `blocked` icon is a red `◉`, in the sidebar and in notifications.

### Removed

- **BREAKING:** Notifications as tmux status-line messages, with their `done` cooldown.
- **BREAKING:** `@tmux-orchestrator-opencode` option. Set `@tmux-orchestrator-opencode-auto-install off` to keep the adapter unlinked.
- **BREAKING:** `@tmux-orchestrator-notify` and `@tmux-orchestrator-notify-via` options. Use the per-channel options; set both to `off` to replace `notify off`.

### Fixed

- A Claude Code agent's background task count drops when a task ends, not at the end of the turn.
- Parallel reports for one pane no longer lose an update when the pane lock is released between two attempts to take it.

- Pressing Esc in a Claude Code agent that has background shells running now sets it to `idle`; it stayed `working`.
- `claude attach <id>` resolves by the session's short ID before the session ID prefix.
- Claude Code interrupts are detected on a session's first prompt and while Claude writes text.
- The reporter and the plugin loader act on the tmux server they run in when it is not the default one (`tmux -L` or `-S`).
- A Claude Code agent no longer stays `working` after its last background subagent ends.
