# Proposal

## Why

`@tmux-orchestrator-notify` and `@tmux-orchestrator-notify-via` describe three delivery paths with two overlapping options: `desktop` means the desktop part in one option and `notify-send`/`osascript` in the other, and the terminal route hides behind the desktop channel. One on/off option per notification channel is easier to read and to configure.

## What Changes

- **BREAKING** Remove `@tmux-orchestrator-notify` and `@tmux-orchestrator-notify-via`. They are no longer read.
- Add three on/off options, one per notification channel:
  - `@tmux-orchestrator-notify-tmux` (default `on`): a message to tmux clients.
  - `@tmux-orchestrator-notify-desktop` (default `on`): `notify-send` or `osascript`.
  - `@tmux-orchestrator-notify-terminal` (default `off`): an OSC 9 sequence to the terminal emulator. Off by default because terminals that handle OSC 9 show a system popup, which would duplicate the desktop one.
- No master switch: turning every channel off means setting all three to `off`. `notify pause` is unchanged.
- Viewing suppression and the tmux `done` cooldown keep their current rules; the terminal channel follows the desktop rules.
- `notify status` reports each channel's setting instead of `notify` and `via`.
- README Notifications section rewritten for the three options; CHANGELOG entry for the removal and the new options.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `agent-notifications`: channel configuration becomes one option per channel (tmux, desktop, terminal); viewing suppression, cooldown, content, status, and failure isolation cover the terminal channel explicitly.

## Impact

- `bin/tmux-orchestrator`: `notify_channel`, `notify_via`, `notify_agent`, `notify_status`.
- `tests/notifications-test.sh`: option setup and status assertions.
- `README.md` Notifications section, new `CHANGELOG.md`.
- Users with `@tmux-orchestrator-notify` or `-notify-via` in their tmux configuration must switch to the new options; the old ones are silently ignored.
