# Spec Delta

## MODIFIED Requirements

### Requirement: Event-driven transitions

The system SHALL derive state only from agent events and from the user viewing an agent, and MUST NOT infer state from terminal contents. A completion SHALL produce `done` only when the agent was `working` or `blocked`.

#### Scenario: Work begins

- **WHEN** a user prompt is submitted, a tool starts or finishes, or the agent reports activity
- **THEN** the state becomes `working`

#### Scenario: Agent needs a person

- **WHEN** the agent requests permission, asks a question, or shows an input form
- **THEN** the state becomes `blocked`

#### Scenario: Turn completes

- **WHEN** the agent reports that its turn finished while `working` or `blocked`
- **THEN** the state becomes `done`

#### Scenario: Completion without activity

- **WHEN** the agent reports that its turn finished while `idle`
- **THEN** the state stays `idle`

#### Scenario: Turn interrupted

- **WHEN** the agent reports an interrupted turn
- **THEN** the state becomes `idle`

#### Scenario: Agent failure

- **WHEN** the integration reports an authentication, billing, rate-limit, or server failure
- **THEN** the state becomes `error`

#### Scenario: Failure is retained

- **WHEN** a completion event arrives after a failure without new work
- **THEN** the state remains `error`

#### Scenario: Failure clears

- **WHEN** the next activity event arrives after an error
- **THEN** the state becomes `working`

#### Scenario: Done clears on focus

- **WHEN** the exact agent pane is focused and, for an OpenCode agent, its tab is the active tab
- **THEN** a `done` state clears to `idle`

#### Scenario: Done stays on a background tab

- **WHEN** an OpenCode pane is focused while a `done` agent's tab is not active
- **THEN** that agent stays `done` until its tab becomes active

### Requirement: Pane state storage

The system SHALL store each agent's state, name, kind, agent session identifier, and last agent event as tmux user options on its agent pane, in the pane's tab order. It MUST NOT require a daemon, background service, or state file outside the tmux server.

#### Scenario: Sidebar reads shared state

- **WHEN** any client renders the sidebar
- **THEN** it reads the same tmux options written by the reporter

#### Scenario: Several agents in one pane

- **WHEN** an OpenCode pane has three tabs open
- **THEN** the pane stores three agents in tab order

#### Scenario: Tmux server stops

- **WHEN** the tmux server exits
- **THEN** all agent state is gone and no external state remains

### Requirement: Agent identity

The system SHALL record an agent name, an agent kind of `claude` or `opencode`, and the integration's session identifier for every tracked agent. An agent is one agent session open in a pane: a Claude Code pane holds one agent and an OpenCode pane holds one per tab.

#### Scenario: Name unavailable

- **WHEN** the integration cannot provide an agent name
- **THEN** the system uses the pane's working-directory basename as the name

#### Scenario: Name is refreshed

- **WHEN** the integration later provides a different agent name
- **THEN** the recorded name is updated without changing the pane or its state

### Requirement: State removal

The system SHALL remove an agent when the integration reports its agent session ended, when its OpenCode tab closes, when the OpenCode TUI exits, or when the pane is destroyed. Removing one agent MUST NOT change the other agents in the same pane.

#### Scenario: SessionEnd

- **WHEN** a Claude agent reports its session ended
- **THEN** the pane's agent is removed and it no longer appears in the sidebar

#### Scenario: Tab closed

- **WHEN** one of three OpenCode tabs closes
- **THEN** only that agent is removed and the other two keep their state and order

#### Scenario: OpenCode exits

- **WHEN** the OpenCode TUI in a pane exits
- **THEN** all agents of that pane are removed

#### Scenario: Pane destroyed

- **WHEN** a pane with agents is closed
- **THEN** its agents disappear with it and the session summary is recomputed

### Requirement: Main-thread only

Activity and waits from a subagent or child session SHALL count toward the agent that started it, but a subagent's completion MUST NOT complete that agent.

#### Scenario: Subagent finishes

- **WHEN** a subagent emits a completion event while the main agent is still working
- **THEN** the agent keeps showing `working`

#### Scenario: Subagent needs permission

- **WHEN** a subagent requests permission
- **THEN** the agent that started it becomes `blocked`

## ADDED Requirements

### Requirement: Last agent event

The system SHALL record, for each agent, the last agent event it received with its kind, name, and detail, readable with tmux's option commands. It MUST NOT be shown in the sidebar.

#### Scenario: Diagnosing a state

- **WHEN** a Claude agent shows `error` after a rate limit
- **THEN** its recorded last agent event names `StopFailure` with the `rate_limit` detail
