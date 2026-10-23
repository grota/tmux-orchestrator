# Spec Delta

## MODIFIED Requirements

### Requirement: Agent list

The sidebar SHALL list the tracked agents of the client's current session in stable window and pane order, and in tab order within a pane, showing a state icon, agent name, and agent kind on one row per agent.

#### Scenario: Agent row content

- **WHEN** a Claude agent named `fix-login` is working in the current session
- **THEN** its row shows the working icon, `fix-login`, and `claude`

#### Scenario: OpenCode tabs

- **WHEN** an OpenCode pane has two tabs named `api` and `docs`
- **THEN** the sidebar shows two rows for that pane, in tab order, each with its own state

#### Scenario: Duplicate names

- **WHEN** two agents in one session share a name
- **THEN** both rows are shown and each still targets its own pane and tab

#### Scenario: Long name

- **WHEN** an agent name does not fit the sidebar width
- **THEN** the displayed name is truncated with an ellipsis and the row remains clickable

### Requirement: Mouse navigation

The sidebar SHALL switch the clicking client to the selected session when a session row is clicked, and to the selected agent's session, window, and pane when an agent row is clicked. Clicking an OpenCode agent row SHALL also focus that agent's tab.

#### Scenario: Session row click

- **WHEN** the user clicks a session row for a different session
- **THEN** the clicking client switches to that session

#### Scenario: Agent row click

- **WHEN** the user clicks an agent row in a split window
- **THEN** the clicking client switches to that session, selects that window, and focuses that exact pane

#### Scenario: OpenCode tab row click

- **WHEN** the user clicks the row of an OpenCode tab that is not active
- **THEN** the client focuses that pane and the TUI in it shows that tab

#### Scenario: Clicking the current agent

- **WHEN** the user clicks the row of the agent that is already focused
- **THEN** focus does not change and its `done` state clears

## ADDED Requirements

### Requirement: Per-pane row limit

The sidebar SHALL show at most nine agent rows per pane. Agents beyond the ninth SHALL be shown as one `+N more` row with the rolled-up state of those agents, using the session rollup priority. Clicking it SHALL select the pane.

#### Scenario: Ten tabs

- **WHEN** an OpenCode pane has ten tabs and the tenth is `blocked`
- **THEN** nine agent rows are shown followed by a `+1 more` row with the blocked icon

#### Scenario: Tab closed below the limit

- **WHEN** a pane drops from ten tabs to nine
- **THEN** the `+N more` row disappears and nine agent rows are shown
