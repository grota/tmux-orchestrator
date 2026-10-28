## MODIFIED Requirements

### Requirement: State presentation

The sidebar SHALL use a distinct icon and color for each state: `working` yellow `●`, `blocked` red `◉`, `error` red `×`, `done` teal `✓`, `idle` green `○`, and `unknown` grey `·`.

#### Scenario: Completed agent

- **WHEN** an agent enters `done`
- **THEN** its row shows a teal `✓`

#### Scenario: Working agent

- **WHEN** an agent enters `working`
- **THEN** its row shows a yellow `●`

#### Scenario: Session rollup icon

- **WHEN** a session rollup is `blocked`
- **THEN** its session row shows a red `◉`

#### Scenario: Blocked count in a session row

- **WHEN** a session has two blocked agents
- **THEN** its session row shows `◉2`

### Requirement: Subagent indicator

While a Claude Code agent has live subagents, its row SHALL show its main thread's state icon, then the icon of the most urgent state among its subagents followed by their count. The first line of the name MUST give up the columns the indicator takes, and wrapped lines MUST continue where it stops. Without subagents, the row SHALL show one icon for the agent's state.

#### Scenario: Main thread done, subagent working

- **WHEN** a Claude agent's main thread has finished and one background subagent is working
- **THEN** its row starts with `✓ ●1`

#### Scenario: A subagent waits for the user

- **WHEN** one subagent works and another waits for a permission
- **THEN** the subagent icon is the blocked icon and the count is 2
