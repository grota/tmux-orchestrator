# Proposal

## Why

Renaming a tmux session or an agent means leaving the sidebar: `prefix $` for the session, `/rename` typed into a Claude pane, or OpenCode's own dialog. Renaming from the sidebar is quicker, and the name should change in the agent itself so other agents and `claude agents` agree with the sidebar.

## What Changes

- Double-clicking a session row opens tmux's rename prompt for that session.
- Double-clicking an agent row opens a prompt prefilled with the agent name. The answer renames the agent session in its agent:
  - Claude Code: a rename control message on the session's messaging socket, found in Claude's session registry. The message is internal to Claude Code (ADR-0009). The rename counts only once the registry shows the new name.
  - OpenCode: the adapter renames through `api.client.session.update` and answers `ok` or `error <reason>` on its control socket.
- A rename the agent does not confirm fails loudly: tmux shows the reason and the name stays unchanged. There is no sidebar-only fallback.
- New reporter commands `rename ROW NAME` and `rename-prompt ROW CLIENT`.
- Contract tests in `tests/contract/` check the Claude Code and OpenCode internals against the installed versions.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `agent-sidebar`: double-click renames sessions and agents.
- `agent-integrations`: agents are renamed in Claude Code and OpenCode.

## Impact

- `tmux-orchestrator.tmux`: binds `DoubleClick1Status`.
- `bin/tmux-orchestrator`: `rename` and `rename-prompt`; the keys panel skips the double-click binding.
- `plugins/opencode/tui.js`: the control socket answers rename requests. An adapter from before this change does not answer, so renaming fails until OpenCode restarts.
- `tests/rename-test.sh`, `tests/opencode-plugin.test.js`, `tests/contract/`, ADR-0009, README, CHANGELOG.
