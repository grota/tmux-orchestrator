# Spec Delta

## ADDED Requirements

### Requirement: Attached Claude background sessions

A Claude Code background session SHALL be tracked as an agent of the pane that shows it with `claude attach <arg>`. A pane shows a session when a process in the pane runs `claude attach <arg>`, is not suspended, and `<arg>` resolves to that session. The agent MUST otherwise follow the same state mapping and naming rules as a Claude agent running in the pane.

#### Scenario: Event from an attached session

- **WHEN** a background session's hook fires and pane `%2` runs `claude attach f7ca13fb` for that session
- **THEN** the event updates the agent of pane `%2`

#### Scenario: Event from a session nobody shows

- **WHEN** a background session's hook fires and no pane shows that session
- **THEN** no agent is created or changed and no notification is sent

#### Scenario: Attach argument before other options

- **WHEN** the pane runs `claude --settings {...} attach f7ca13fb`
- **THEN** `f7ca13fb` is used as the attach argument

### Requirement: Attach argument resolution

The attach argument SHALL resolve to the session whose id starts with it. Otherwise it SHALL resolve to the only running background session whose name contains it, ignoring case. If no session or more than one session matches, the argument MUST resolve to nothing.

#### Scenario: Short id

- **WHEN** the argument is `f7ca13fb` and a session id starts with `f7ca13fb`
- **THEN** the argument resolves to that session

#### Scenario: Part of the name

- **WHEN** the argument is `title wrap` and only the session named `Agent title wrap settings` contains it
- **THEN** the argument resolves to that session

#### Scenario: Ambiguous name

- **WHEN** the argument is `agent` and two running sessions have names containing it
- **THEN** the argument resolves to nothing and no pane shows either session

### Requirement: Attached session discovery

When a pane, window or tmux session is selected, the system SHALL check the selected pane for an attach viewer. If it shows a session that is not yet its agent, the system SHALL add that agent with the name and state Claude Code reports for the session, or `unknown` when the state has no matching agent state.

#### Scenario: Selecting a pane after attaching

- **WHEN** the user attaches to a background session that is `blocked` in pane `%2` and selects pane `%2`
- **THEN** pane `%2` gains a `blocked` agent named after the session, before the session sends any hook

### Requirement: Attached session removal

The system SHALL remove an attached agent from its pane once the pane no longer shows that session: the viewer exited, switched to the agent view, or was suspended. It SHALL check this when a pane, window or tmux session is selected, when a pane exits, and when the session's next hook arrives.

#### Scenario: Back to the agent view

- **WHEN** the user presses `←` in an attached pane and later selects another pane
- **THEN** the attached agent's row is removed

#### Scenario: Suspended viewer

- **WHEN** the user suspends the viewer with `Ctrl+Z` and the session's next hook arrives
- **THEN** the attached agent's row is removed and no notification is sent

#### Scenario: Running agent untouched

- **WHEN** a selection change happens while a pane runs an ordinary Claude Code session
- **THEN** that pane's agent is not removed
