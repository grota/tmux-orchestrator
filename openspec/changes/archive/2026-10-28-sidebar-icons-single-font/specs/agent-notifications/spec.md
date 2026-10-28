## MODIFIED Requirements

### Requirement: Notification content

The tmux notification SHALL contain the state icon, agent name, and state, in the form `◉ fix-login blocked`. The desktop and terminal notifications SHALL contain the same icon and the text `Agent <state>: <name>`, such as `◉ Agent blocked: fix-login`. Notifications MUST NOT contain agent kind or tmux session, window, or pane information.

#### Scenario: Blocked agent

- **WHEN** the agent named `fix-login` enters `blocked`
- **THEN** the tmux message is `◉ fix-login blocked` and the desktop and terminal summary is `◉ Agent blocked: fix-login`

#### Scenario: Done agent

- **WHEN** the agent named `fix-login` enters `done`
- **THEN** the tmux message is `✓ fix-login done` and the desktop and terminal summary is `✓ Agent done: fix-login`

#### Scenario: Error agent

- **WHEN** the agent named `fix-login` enters `error`
- **THEN** the tmux message is `× fix-login error` and the desktop and terminal summary is `× Agent error: fix-login`

#### Scenario: Hostile name

- **WHEN** an agent name contains `#[` or a newline
- **THEN** the notification shows the literal text and no tmux format expansion occurs
