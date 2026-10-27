# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `@tmux-orchestrator-opencode-auto-install` option, `on` by default.
- `@tmux-orchestrator-notify-tmux`, `@tmux-orchestrator-notify-desktop` and `@tmux-orchestrator-notify-terminal` options; terminal is `off` by default.
- `@tmux-orchestrator-name-max-chars` option: `wrap` (default), `nowrap` or a character limit.
- Keys panel, opened from the `? keys` sidebar row, listing the bindings that call the reporter.
- The focused agent's name is emphasised in the sidebar.
- `@tmux-orchestrator-focus-style` option: `underlined` (default), `bold` or `none`.
- Claude Code background sessions shown with `claude attach` are tracked as the agent of that pane.
- Double-clicking a session row renames the tmux session.
- Double-clicking an agent row renames the Claude Code or OpenCode agent session.
- `rename` and `rename-prompt` reporter commands.
- Contract tests for the Claude Code and OpenCode internals the plugin relies on.

### Changed

- The OpenCode adapter is linked on each plugin load when OpenCode is detected.
- README command-line commands are grouped under "Optional command line commands".
- **BREAKING:** Long agent names wrap over up to four lines by default.
- The time in state moved to the agent's kind line, right-aligned.
- The toggle key is not bound when the key already has a user binding, and a previous toggle key is unbound on reload.
- `notify status` reports the pause state and each notification channel's setting.

### Removed

- **BREAKING:** `@tmux-orchestrator-opencode` option. Set `@tmux-orchestrator-opencode-auto-install off` to keep the adapter unlinked.
- **BREAKING:** `@tmux-orchestrator-notify` and `@tmux-orchestrator-notify-via` options. Use the per-channel options; set all three to `off` to replace `notify off`.
