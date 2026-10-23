# agent-sidebar Specification

## Purpose

Defines the persistent tmux sidebar that shows agent-bearing sessions and the agents in the current session, and the mouse and key actions that navigate from it.

## Requirements

### Requirement: Persistent sidebar surface

The system SHALL render the agent overview in tmux `side-status`. The sidebar MUST be visible by default whenever the sidebar is enabled, including when the current session has no agents.

#### Scenario: Tmux without side-status

- **WHEN** the user loads the plugin on tmux older than 3.9
- **THEN** the plugin reports that `side-status` is required and does not enable the sidebar

#### Scenario: Sidebar enabled

- **WHEN** the plugin loads on a supported tmux server
- **THEN** the sidebar appears on the configured side without consuming a pane

#### Scenario: Current session has no agents

- **WHEN** the current session has no tracked agents
- **THEN** the sidebar still renders its session list and a `no agents in this session` line

### Requirement: Sidebar configuration

The sidebar SHALL default to the left side with a width of 28 columns. The side MUST be configurable as `left` or `right`, and the width MUST be configurable and resizable with tmux's built-in status-border drag.

#### Scenario: Drag resize

- **WHEN** the user drags the sidebar border
- **THEN** the width changes for that session and is not overwritten by state refreshes

#### Scenario: Reset width

- **WHEN** the user double-clicks the sidebar border
- **THEN** the width returns to the configured default

### Requirement: Session list

The sidebar SHALL list every tmux session on the server that has at least one tracked agent, in stable tmux session order, showing a rollup state icon, the session name, and the agent count. The client's current session MUST be visually marked.

#### Scenario: Multiple agent sessions

- **WHEN** two sessions have agents and a third has none
- **THEN** only the two agent sessions are listed

#### Scenario: Current session marker

- **WHEN** the client is attached to one of the listed sessions
- **THEN** that session's row is marked as current

#### Scenario: Other session is detached

- **WHEN** an agent session has no attached client
- **THEN** it remains listed and can be clicked

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

### Requirement: State presentation

The sidebar SHALL use a distinct icon and color for each state: `working` yellow `◐`, `blocked` red `●`, `error` red `×`, `done` teal `✓`, `idle` green `○`, and `unknown` grey `·`.

#### Scenario: Completed agent

- **WHEN** an agent enters `done`
- **THEN** its row shows a teal `✓`

#### Scenario: Session rollup icon

- **WHEN** a session rollup is `blocked`
- **THEN** its session row shows a red `●`

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

### Requirement: Keyboard control

The system SHALL provide a tmux key binding to toggle the sidebar and a command usable from `run-shell`; the binding MUST be configurable and MUST NOT require keyboard focus inside the sidebar.

#### Scenario: Toggle off

- **WHEN** the user presses the toggle binding while the sidebar is visible
- **THEN** the sidebar hides for all sessions and agent tracking continues

#### Scenario: Toggle on

- **WHEN** the user presses the toggle binding while the sidebar is hidden
- **THEN** the sidebar returns on its configured side with current state

### Requirement: Refresh

The sidebar SHALL reflect a state change without manual refresh and MUST NOT redraw more often than needed when no state changes.

#### Scenario: State reported

- **WHEN** the reporter changes a pane state
- **THEN** attached clients redraw the sidebar immediately

#### Scenario: No clients attached

- **WHEN** a state change occurs while no client is attached
- **THEN** the change is recorded and appears when a client next attaches

### Requirement: Overflow

When the listed rows do not fit the available height, the sidebar MUST keep the focused agent's row visible and MUST NOT scroll the terminal or accept keyboard scrolling.

#### Scenario: Too many agents

- **WHEN** the current session has more agent rows than fit
- **THEN** the sidebar keeps the focused agent visible and trims rows it cannot show

### Requirement: Per-pane row limit

The sidebar SHALL show at most nine agent rows per pane. Agents beyond the ninth SHALL be shown as one `+N more` row with the rolled-up state of those agents, using the session rollup priority. Clicking it SHALL select the pane.

#### Scenario: Ten tabs

- **WHEN** an OpenCode pane has ten tabs and the tenth is `blocked`
- **THEN** nine agent rows are shown followed by a `+1 more` row with the blocked icon

#### Scenario: Tab closed below the limit

- **WHEN** a pane drops from ten tabs to nine
- **THEN** the `+N more` row disappears and nine agent rows are shown
