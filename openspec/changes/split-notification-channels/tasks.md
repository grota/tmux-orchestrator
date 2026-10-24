# Tasks

## 1. Channel options

- [x] 1.1 Replace `notify_channel` and `notify_via` in `bin/tmux-orchestrator` with a `channel_on` helper for `@tmux-orchestrator-notify-tmux` (default on), `-notify-desktop` (default on) and `-notify-terminal` (default off); verify with `bash -n bin/tmux-orchestrator`
- [x] 1.2 Rework `notify_agent` so each enabled channel delivers independently, keeping viewing suppression and the tmux `done` cooldown, with desktop and terminal suppressed when any client views the agent; verify the delivery scenarios in `tests/notifications-test.sh` pass
- [x] 1.3 Update `tests/notifications-test.sh`: drop the `@tmux-orchestrator-notify` and `-notify-via` setups and cover defaults (terminal off), terminal only, all off, unrecognised value, and old options ignored; verify `bash tests/notifications-test.sh` passes

## 2. Status

- [x] 2.1 Rewrite `notify_status` to print `notifications: active|paused` and one line per channel with desktop availability on the desktop line; add status assertions to `tests/notifications-test.sh` and verify it passes

## 3. Documentation

- [x] 3.1 Rewrite the README Notifications section for the three options, their defaults, and why terminal is off by default, keeping one sentence that points to pause; verify no README mention of `@tmux-orchestrator-notify ` or `-notify-via` remains with `grep -n 'notify-via\|tmux-orchestrator-notify ' README.md`
- [x] 3.2 Create `CHANGELOG.md` (Keep a Changelog 1.1.0) with Added entries for the three options and a Removed entry for `@tmux-orchestrator-notify` and `@tmux-orchestrator-notify-via` under `## [Unreleased]`; verify the file renders the expected headings

## 4. Integration

- [x] 4.1 Run every shell suite (`bash tests/<name>-test.sh`) and `node --test tests/` and verify they pass
