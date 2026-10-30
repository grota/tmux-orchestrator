# Proposal

## Why

Viewing a `done` agent clears it to `idle`, and that state change restarts the sidebar's time. After clicking an agent, the user can no longer see how long ago its turn finished, which is what tells them whether the agent's prompt cache (about one hour) is still warm.

## What Changes

- The sidebar's time becomes the **state time**: how long since the agent's own agent events last changed its state. Viewing an agent no longer restarts it.
- New `@tmux-orchestrator-time-on-view` option: `keep` (the default) keeps the state time when viewing clears `done`; `reset` restores the old behavior of restarting it. Any other value acts like `keep`.
- The option covers every view-driven change: a pane focus, a sidebar agent-row click, and an OpenCode tab focus.
- README and spec describe the time as the state time and document the option.

## Capabilities

### New Capabilities

### Modified Capabilities

- `agent-sidebar`: the agent list's time is the state time, and viewing an agent keeps or restarts it according to `@tmux-orchestrator-time-on-view`.

## Impact

- `bin/tmux-orchestrator`: the focus reconciler and the OpenCode tab-focus path.
- `tests/reporter-test.sh`, `README.md`, `CHANGELOG.md`.
- A cache-expiry indicator is out of scope.
