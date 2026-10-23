# Spec Delta

## Purpose

Defines when an agent state change produces a notification, what the notification says, which channels deliver it, and how a user pauses delivery without losing state tracking.

## ADDED Requirements

### Requirement: Attention-only triggers
The system SHALL notify only when an agent transitions into `blocked`, `error`, or `done`. It MUST NOT notify for `working`, `idle`, or `unknown`, for a repeated state, for `done` clearing on focus, or for agent removal.

#### Scenario: Agent blocks
- **WHEN** an agent changes from `working` to `blocked`
- **THEN** one notification is produced

#### Scenario: Turn finishes
- **WHEN** an agent changes from `working` to `done`
- **THEN** one notification is produced

#### Scenario: Work starts
- **WHEN** an agent changes from `idle` to `working`
- **THEN** no notification is produced

#### Scenario: Focus clears done
- **WHEN** focusing an agent pane changes `done` to `idle`
- **THEN** no notification is produced

#### Scenario: Duplicate event
- **WHEN** an event reports the state the agent already has
- **THEN** no notification is produced

### Requirement: Notification content
The tmux notification SHALL contain the state icon, agent name, and state, in the form `● fix-login blocked`. The desktop notification SHALL contain the same icon and the text `Agent <state>: <name>`, such as `● Agent blocked: fix-login`. Notifications MUST NOT contain agent kind or tmux session, window, or pane information.

#### Scenario: Blocked agent
- **WHEN** the agent named `fix-login` enters `blocked`
- **THEN** the tmux message is `● fix-login blocked` and the desktop summary is `● Agent blocked: fix-login`

#### Scenario: Done agent
- **WHEN** the agent named `fix-login` enters `done`
- **THEN** the tmux message is `✓ fix-login done` and the desktop summary is `✓ Agent done: fix-login`

#### Scenario: Error agent
- **WHEN** the agent named `fix-login` enters `error`
- **THEN** the tmux message is `× fix-login error` and the desktop summary is `× Agent error: fix-login`

#### Scenario: Hostile name
- **WHEN** an agent name contains `#[` or a newline
- **THEN** the notification shows the literal text and no tmux format expansion occurs

### Requirement: Notification channels
The system SHALL provide the option `@tmux-orchestrator-notify` with values `both`, `tmux`, `desktop`, and `off`, defaulting to `both`.

#### Scenario: Both available
- **WHEN** the option is `both` and a supported desktop command exists
- **THEN** each notification is delivered to both channels

#### Scenario: Desktop unavailable
- **WHEN** the option is `both` and neither `notify-send` nor `osascript` exists
- **THEN** notifications are delivered to tmux only

#### Scenario: Desktop only unavailable
- **WHEN** the option is `desktop` and no supported desktop command exists
- **THEN** no notification is delivered and state tracking continues

#### Scenario: Channels off
- **WHEN** the option is `off`
- **THEN** no notification is delivered and state tracking continues

### Requirement: Viewing suppression
The system SHALL skip the tmux notification for a client whose active pane is the agent that changed. It SHALL skip the desktop notification if any attached client has that agent as its active pane.

#### Scenario: One client views the agent
- **WHEN** an agent changes state while one client has its pane active and another does not
- **THEN** only the other client receives the tmux message, and no desktop notification is sent

#### Scenario: No client views the agent
- **WHEN** an agent changes state and no attached client has its pane active
- **THEN** every attached client receives the tmux message and the desktop notification is sent

#### Scenario: No clients attached
- **WHEN** an agent changes state with no clients attached
- **THEN** no tmux message is possible and the desktop notification is still sent when enabled

### Requirement: Deduplication and tmux cooldown
The system MUST suppress notifications for unchanged consecutive states. It SHALL apply a 2-second per-agent cooldown to tmux messages, except that `blocked` and `error` MUST bypass the cooldown. Desktop notifications SHALL use deduplication without a cooldown.

#### Scenario: Rapid completion
- **WHEN** an agent enters `done`, returns to `working`, and enters `done` again within 2 seconds
- **THEN** the second tmux message is suppressed by the cooldown and the second desktop notification is delivered

#### Scenario: Repeated state
- **WHEN** an agent reports `done` again without leaving `done`
- **THEN** neither channel produces a notification

#### Scenario: Block during cooldown
- **WHEN** an agent enters `blocked` within 2 seconds of its previous tmux notification
- **THEN** the blocked tmux message is delivered

#### Scenario: Desktop cooldown
- **WHEN** a real transition occurs within 2 seconds of the previous transition for that agent
- **THEN** the desktop notification is delivered

### Requirement: Global pause
The system SHALL provide `notify pause`, `notify resume`, and `notify status`. Pause MUST be global, indefinite, and idempotent, and MUST suppress notifications on all channels while state tracking and the sidebar continue.

#### Scenario: Pause
- **WHEN** the user runs `notify pause`
- **THEN** subsequent attention transitions produce no notification and states continue to update

#### Scenario: Resume
- **WHEN** the user runs `notify resume`
- **THEN** subsequent attention transitions notify again

#### Scenario: Repeated pause
- **WHEN** the user runs `notify pause` while already paused
- **THEN** the command succeeds and the paused state is unchanged

#### Scenario: Pause survives reload
- **WHEN** the plugin is reloaded or a client detaches while paused
- **THEN** notifications remain paused

#### Scenario: Pause does not change the view
- **WHEN** notifications are paused
- **THEN** the sidebar continues to show current states and does not add a pause indicator

### Requirement: Notification status
`notify status` SHALL report the configured channels, whether delivery is paused, and whether desktop delivery is available.

#### Scenario: Status while paused
- **WHEN** the option is `both` and notifications are paused
- **THEN** the output includes `notifications: paused (both)`

#### Scenario: Status while off
- **WHEN** the option is `off`
- **THEN** the output includes `notifications: off`

#### Scenario: Status without desktop
- **WHEN** the option is `both` and no desktop command exists
- **THEN** the output indicates tmux delivery and unavailable desktop delivery

### Requirement: No default key binding
The system MUST NOT bind a key for notification pause by default. The README MUST show how to bind `notify pause` and `notify resume` in tmux.

#### Scenario: Fresh install
- **WHEN** the plugin loads without user configuration
- **THEN** no notification-control key is bound

#### Scenario: Documented binding
- **WHEN** the user follows the README binding example
- **THEN** the documented tmux command runs `notify pause` or `notify resume`

### Requirement: Delivery failure isolation
A failed or unavailable notification channel MUST NOT change agent state, block the reporting path, or prevent the other channel from delivering.

#### Scenario: Desktop command fails
- **WHEN** the desktop command exits nonzero
- **THEN** the state is already recorded and tmux delivery is unaffected

#### Scenario: No tmux clients
- **WHEN** no client is attached
- **THEN** the reporter does not retry tmux delivery and exits successfully
