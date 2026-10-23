# Proposal

## Why

The OpenCode integration does not work on OpenCode 2.x. Its plugin runs in OpenCode's shared background service, which cannot tell which tmux pane or tab an event belongs to. It also reads an event format and event names that 2.x no longer sends, so agents never appear or appear at the wrong time. Separately, agent state rules are split between the OpenCode plugin and several reporter functions, and Claude questions, plan approvals and MCP input forms show as `working` instead of `blocked`.

## What Changes

- **BREAKING**: The OpenCode integration becomes an OpenCode 2.x TUI plugin. OpenCode 1.x is no longer supported, and the installer removes the old server plugin file.
- An OpenCode pane can host several agents, one per tab. The sidebar lists up to nine of them per pane, and a `+N more` row carries the rolled-up state of the rest.
- Clicking an OpenCode tab's row switches to its pane and focuses that tab.
- Closing an OpenCode tab removes its row. Exiting the OpenCode TUI removes all of its rows.
- OpenCode 2.x events drive state, including explicit interrupts.
- Claude `AskUserQuestion` and `ExitPlanMode` waits and MCP input forms (`Elicitation`) show as `blocked`.
- An interrupted Claude agent returns to `idle` within a few seconds, detected from the session transcript because Claude Code sends no hook for it.
- A completion with no activity since the agent started shows `idle` instead of `done`.
- The last agent event is stored on the pane for diagnosis.
- Adapters forward agent events unchanged, and one agent state module owns their meaning (ADR-0005). The `report --state` command is removed.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `agent-integrations`: Claude event mapping gains question, plan and MCP-form waits and transcript-based interrupt detection. OpenCode event mapping, name resolution and packaging move to OpenCode 2.x TUI plugins.
- `agent-state`: an agent is an agent session in a pane, so a pane can hold several. Completion depends on prior activity, the last agent event is recorded, and removal covers closed tabs and an exited TUI.
- `agent-sidebar`: agent rows are per agent, not per pane, with a nine-row limit per pane and a rolled-up overflow row. Clicking an agent row also focuses its tab.
- `agent-notifications`: an OpenCode agent counts as viewed only when its pane and its tab are both active.

## Impact

- **Code**: `bin/tmux-orchestrator`, a new agent state module under `lib/`, `lib/sidebar-format` (generated from one row fragment), `tmux-orchestrator.tmux`, `plugins/claude/hooks/` (payload parsing moves here), and `plugins/opencode/` (rewritten as a TUI plugin).
- **Tests**: new tests for the agent state module that run without tmux. The OpenCode reducer tests shrink to root and tab tracking. The reporter, sidebar and fixture tests move from `--state` to agent events.
- **Docs**: README event tables, OpenCode install and requirements, and known limitations.
- **Dependencies**: OpenCode 2.x for the OpenCode integration. Focusing an OpenCode tab from the sidebar needs `python3` or `nc` with `-U`; without either, a click selects the pane but not the tab.
