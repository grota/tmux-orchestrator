# Spec Delta

## ADDED Requirements

### Requirement: Claude subagent tracking

The reporter SHALL track a Claude agent's main-thread state from main-thread events only, and its live subagents, each with its own state, from the subagent's own events. A subagent SHALL be listed from its first event, including `SubagentStart`, until its `SubagentStop`. An interrupt or a new session MUST clear the list, and a subagent with no event for 30 minutes MUST be dropped.

#### Scenario: Interrupt

- **WHEN** the user interrupts the main thread
- **THEN** the subagent list is cleared until a subagent sends another event

### Requirement: Agent state after the last subagent

When the last subagent ends while the agent is `working` and its main thread is `idle` or `done`, the agent SHALL take its main thread's state.

#### Scenario: Background subagent outlives its main thread

- **WHEN** the main thread stops while a background subagent works, and the subagent then ends
- **THEN** the agent is `done`, not `working`
