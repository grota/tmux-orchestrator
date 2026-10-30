## MODIFIED Requirements

### Requirement: Agent list

The sidebar SHALL list the tracked agents of the client's current session in stable window and pane order, and in tab order within a pane, showing a state icon and the agent name, followed by a line with the agent kind and, unless hidden, the state time right-aligned. The state time SHALL measure how long since the agent's own agent events last changed its state. When viewing an agent clears its `done` state, the state time MUST keep running unless `@tmux-orchestrator-time-on-view` is `reset`, in which case it restarts. Any value other than `reset` MUST behave like `keep`, the default.

#### Scenario: Agent row content

- **WHEN** a Claude agent named `fix-login` has been working for 45 seconds in the current session
- **THEN** its first line shows the working icon and `fix-login`, and the line below shows `claude` with `45s` right-aligned

#### Scenario: Time hidden

- **WHEN** `@tmux-orchestrator-time` is `off`
- **THEN** the kind line shows only the agent kind

#### Scenario: Viewing keeps the state time

- **WHEN** an agent has been `done` for 10 minutes and the user focuses its pane, clicks its row, or, for OpenCode, activates its tab
- **THEN** it becomes `idle` and its time keeps counting from when it became `done`

#### Scenario: Viewing restarts the state time

- **WHEN** `@tmux-orchestrator-time-on-view` is `reset` and the user views a `done` agent
- **THEN** it becomes `idle` and its time restarts from zero

#### Scenario: Agent event restarts the state time

- **WHEN** an `idle` agent whose time was kept by viewing receives a prompt
- **THEN** it becomes `working` and its time restarts from zero

#### Scenario: OpenCode tabs

- **WHEN** an OpenCode pane has two tabs named `api` and `docs`
- **THEN** the sidebar shows two rows for that pane, in tab order, each with its own state

#### Scenario: Duplicate names

- **WHEN** two agents in one session share a name
- **THEN** both rows are shown and each still targets its own pane and tab

#### Scenario: Long name

- **WHEN** an agent name does not fit the sidebar width and wrapping is off
- **THEN** the displayed name is truncated with an ellipsis and the row remains clickable
