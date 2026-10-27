# Proposal

## Why

`claude attach <id>` takes the short ID that `claude agents --json` lists as `id`. The reporter resolved it by assuming the short ID starts the full session ID. That holds for every session observed so far, but Claude Code does not document it, so a change would silently stop attached sessions from being tracked.

## What Changes

- The attach argument resolves first to the session whose `id` equals it, then to a session ID starting with it, then to a unique part of a name.
- The Claude adapter drops its unused `Notification` branch: the hook was never registered, and the state module ignores the event.
- The Claude contract test starts an unprompted background session, attaches it in a pane, and checks that the reporter adopts it with Claude's state.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `agent-integrations`: attach argument resolution matches the documented short ID first.

## Impact

- `bin/tmux-orchestrator`, `plugins/claude/hooks/report.sh`, `tests/attach-test.sh`, `tests/contract/claude-test.sh`, CHANGELOG.
