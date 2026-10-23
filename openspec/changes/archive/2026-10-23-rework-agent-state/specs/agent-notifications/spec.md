# Spec Delta

## MODIFIED Requirements

### Requirement: Viewing suppression

The system SHALL skip the tmux notification for a client that is viewing the agent that changed. It SHALL skip the desktop notification if any attached client is viewing that agent. A client views an agent when the agent's pane is the client's active pane and, for an OpenCode agent, its tab is the active tab.

#### Scenario: One client views the agent

- **WHEN** an agent changes state while one client has its pane active and another does not
- **THEN** only the other client receives the tmux message, and no desktop notification is sent

#### Scenario: No client views the agent

- **WHEN** an agent changes state and no attached client has its pane active
- **THEN** every attached client receives the tmux message and the desktop notification is sent

#### Scenario: Background OpenCode tab

- **WHEN** an OpenCode agent on a background tab becomes `blocked` while a client has its pane active
- **THEN** that client receives the tmux message and the desktop notification is sent

#### Scenario: No clients attached

- **WHEN** an agent changes state with no clients attached
- **THEN** no tmux message is possible and the desktop notification is still sent when enabled
