# Proposal

## Why

A Claude Code agent's row has one icon for the agent and its subagents together. A main thread that has finished while a background subagent works looks the same as a main thread at work, and once that subagent ends the row stays `working` until the main thread's next `Stop`.

## What Changes

- The reporter keeps a Claude agent's main-thread state, from main-thread events only, and its live subagents with their own states, keyed by `agent_id`.
- `SubagentStart` is registered, so a subagent is listed when it starts.
- While subagents run, the row shows the main thread's icon, then the subagents' rollup with their count; the name's first line gives up those columns.
- When the last subagent ends and the agent shows `working` while its main thread is `idle` or `done`, the agent takes the main thread's state.
- Session rollups and notifications keep using the agent's overall state.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `agent-sidebar`: Claude agent rows show a subagent indicator.
- `agent-integrations`: the Claude adapter forwards `SubagentStart`, and the reporter tracks subagents.

## Impact

- `lib/agent-state.sh`, `bin/tmux-orchestrator`, `lib/sidebar-format`, `tmux-orchestrator.tmux`, `plugins/claude/hooks/hooks.json`, tests, README, CHANGELOG.
