# Proposal

## Why

Claude Code 2.1.311 writes no interrupt marker when a turn is interrupted while Claude writes text, and on a session's first prompt the transcript does not exist yet when the watcher starts. In both cases an interrupted agent stays `working` until the next prompt. The session status in Claude's session registry turned `idle` within a second of every interrupt tested.

## What Changes

- Interrupts are detected from the registry `status`: two `idle` readings in a row, 2 seconds apart, while the agent is `working` or `blocked` and no `Stop` arrived.
- The transcript watcher and its one-hour limit are removed. The Claude adapter stops sending `--transcript`; the reporter accepts and ignores it.
- The Claude contract test checks the `status` field and, with `TMUX_ORCHESTRATOR_CONTRACT_TURN=1`, interrupts a Haiku turn.
- ADR-0010 supersedes ADR-0006.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `agent-integrations`: Claude Code interrupt detection reads the session status.

## Impact

- `bin/tmux-orchestrator`, `plugins/claude/hooks/report.sh`, `lib/agent-state.sh` (comment), `tests/reporter-test.sh`, `tests/claude-fixtures-test.sh`, `tests/contract/claude-test.sh`, ADR-0006, ADR-0010, README, CHANGELOG.
