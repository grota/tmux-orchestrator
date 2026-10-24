# Proposal

## Why

The OpenCode adapter is linked only when the user opts in with `@tmux-orchestrator-opencode on`, although the plugin can tell on its own whether OpenCode is installed. The README also puts command-line commands that most users never run (the alias, maintenance, pause and resume, manual OpenCode install) in the middle of the setup instructions.

## What Changes

- **BREAKING**: Remove `@tmux-orchestrator-opencode`.
- Add `@tmux-orchestrator-opencode-auto-install` (`on` or `off`, default `on`). On each plugin load with `on`, the adapter is linked only when OpenCode is detected: `opencode` is on the tmux server's `PATH` or `~/.config/opencode` exists. Without OpenCode, nothing is created.
- With `off`, the plugin does not touch the adapter link, including one it created earlier.
- The manual `install opencode` and `uninstall opencode` commands keep their current behaviour.
- README: add an "Optional command line commands" section before Development, holding the alias, Maintenance, Pause and resume, and the manual OpenCode install and uninstall commands. The OpenCode install section states that the adapter is linked automatically when OpenCode is installed and that OpenCode needs a restart after the first install. The state icon colour column stays as text.
- Add `CHANGELOG.md` with entries for the option change.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `agent-integrations`: the OpenCode adapter is linked automatically when OpenCode is detected, controlled by `@tmux-orchestrator-opencode-auto-install`, replacing the opt-in `@tmux-orchestrator-opencode`.

## Impact

- `tmux-orchestrator.tmux`: reads the new option and detects OpenCode before calling the installer.
- `tests/install-test.sh`: load-time linking cases move to the new option and detection.
- `README.md`, new `CHANGELOG.md`.
- Users with `@tmux-orchestrator-opencode on` in their tmux configuration keep working because the new default links when OpenCode is present; the old line becomes a no-op.
- The README sections for the toggle key and Notifications are rewritten by `sidebar-names-and-keys` and `split-notification-channels`; this change only moves sections.
