# Adapters forward agent events; one module owns their meaning

Agent state rules were split between the OpenCode plugin and several reporter functions, and the rule that an error survives a later completion existed twice. We now have each adapter forward agent events as its agent kind names them, with details such as `tool_name` or the error type. One agent state module holds the per-kind mapping tables, the transition rules and the notification decision. This keeps every rule in one place, tested without tmux, and loses no detail before the module sees it.

## Considered Options

- **Adapters translate to a small shared set of lifecycle events.** Rejected: it drops per-kind detail, such as telling `AskUserQuestion` apart from other tool calls, and spreads the mapping across two languages.
- **Adapters send generic events plus the original name as a label.** Rejected: the label carries the detail, but the mapping still lives in the adapters.
- **Adapters keep reporting final states.** Rejected: this is the split that caused the duplicated rules.

## Consequences

- Each adapter keeps only what needs its own process: the Claude adapter parses the hook payload and filters subagents, and the OpenCode adapter maps child sessions to their root and tracks tabs. The reporter contains no payload parsing for any agent kind.
- The OpenCode adapter forwards only an allowlist of event names, because each forwarded event starts a reporter process and OpenCode emits many events per second. The meaning of each event stays in the module.
- Whether a completion counts as `done` is derived from the previous state, not from per-process flags. A Claude `Stop` with no activity since the agent started now shows `idle` instead of `done`.
- The last agent event is stored in `@agent_event` for diagnosis and is not shown in the sidebar.
- The OpenCode adapter calls the reporter one event at a time, so events cannot be applied out of order.
