# Spec Delta

## Purpose

Defines how lifecycle events become a normalized per-agent state, how agent identity is recorded, and how per-session summaries are kept in tmux options so every client sees the same view.

## ADDED Requirements

### Requirement: Normalized agent states
The system SHALL assign each tracked agent exactly one state: `working`, `blocked`, `done`, `idle`, `error`, or `unknown`.

#### Scenario: Newly started agent
- **WHEN** an agent session starts and has not produced work yet
- **THEN** its state is `idle`

#### Scenario: Marked agent without a state
- **WHEN** a pane carries an agent kind and name but no valid state value
- **THEN** the system presents it as `unknown` and does not hide it

#### Scenario: Single state at a time
- **WHEN** a new lifecycle event arrives
- **THEN** the agent has exactly one current state, replacing the previous one except where an explicit retention rule applies

### Requirement: Event-driven transitions
The system SHALL derive state only from declared lifecycle events and MUST NOT infer state from terminal contents.

#### Scenario: Work begins
- **WHEN** a user prompt is submitted, a tool starts or finishes, or the agent reports activity
- **THEN** the state becomes `working`

#### Scenario: Agent needs a person
- **WHEN** the agent requests permission or asks a question
- **THEN** the state becomes `blocked`

#### Scenario: Turn completes
- **WHEN** the agent reports that its turn finished
- **THEN** the state becomes `done`

#### Scenario: Agent failure
- **WHEN** the integration reports an authentication, billing, rate-limit, or server failure
- **THEN** the state becomes `error`

#### Scenario: Failure is retained
- **WHEN** a completion event arrives immediately after a failure without new work
- **THEN** the state remains `error`

#### Scenario: Failure clears
- **WHEN** the next activity event arrives after an error
- **THEN** the state becomes `working`

#### Scenario: Done clears on focus
- **WHEN** the exact agent pane is focused
- **THEN** a `done` state clears to `idle`

### Requirement: Pane state storage
The system SHALL store the current state, agent name, agent kind, and agent session identifier as tmux user options on the agent pane. It MUST NOT require a daemon, background service, or state file outside the tmux server.

#### Scenario: Sidebar reads shared state
- **WHEN** any client renders the sidebar
- **THEN** it reads the same tmux options written by the reporter

#### Scenario: Tmux server stops
- **WHEN** the tmux server exits
- **THEN** all agent state is gone and no external state remains

### Requirement: Agent identity
The system SHALL record an agent name, an agent kind of `claude` or `opencode`, and the integration's session identifier for every tracked agent.

#### Scenario: Name unavailable
- **WHEN** the integration cannot provide an agent name
- **THEN** the system uses the pane's working-directory basename as the name

#### Scenario: Name is refreshed
- **WHEN** the integration later provides a different agent name
- **THEN** the recorded name is updated without changing the pane or its state

### Requirement: Session summary
The system SHALL maintain, for each tmux session, the number of tracked agents and a rollup state using the priority `blocked`, `error`, `done`, `working`, `idle`, `unknown`.

#### Scenario: Mixed states
- **WHEN** a session has one blocked agent and one working agent
- **THEN** the session rollup is `blocked`

#### Scenario: Empty session
- **WHEN** the last tracked agent in a session is removed
- **THEN** the session count is zero and the session is not listed as an agent session

#### Scenario: Summary refresh
- **WHEN** any agent state changes or an agent pane exits
- **THEN** the affected session summary is recomputed

### Requirement: State removal
The system SHALL remove all agent options for a pane when the integration reports the agent session ended or when the pane is destroyed.

#### Scenario: SessionEnd
- **WHEN** the agent reports its session ended
- **THEN** the pane's agent options are removed and it no longer appears in the sidebar

#### Scenario: Pane destroyed
- **WHEN** a pane with agent options is closed
- **THEN** the pane's options disappear with it and the session summary is recomputed

### Requirement: Main-thread only
Events emitted by subagents MUST NOT change the state of the pane's agent session.

#### Scenario: Subagent finishes
- **WHEN** a subagent emits a completion event while the main agent is still working
- **THEN** the pane keeps showing `working`
