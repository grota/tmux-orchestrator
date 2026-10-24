# agent-notifications Specification

## Purpose

Defines when an agent state change produces a notification, what the notification says, which channels deliver it, and how a user pauses delivery without losing state tracking.

## Requirements

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

The tmux notification SHALL contain the state icon, agent name, and state, in the form `● fix-login blocked`. The desktop and terminal notifications SHALL contain the same icon and the text `Agent <state>: <name>`, such as `● Agent blocked: fix-login`. Notifications MUST NOT contain agent kind or tmux session, window, or pane information.

#### Scenario: Blocked agent

- **WHEN** the agent named `fix-login` enters `blocked`
- **THEN** the tmux message is `● fix-login blocked` and the desktop and terminal summary is `● Agent blocked: fix-login`

#### Scenario: Done agent

- **WHEN** the agent named `fix-login` enters `done`
- **THEN** the tmux message is `✓ fix-login done` and the desktop and terminal summary is `✓ Agent done: fix-login`

#### Scenario: Error agent

- **WHEN** the agent named `fix-login` enters `error`
- **THEN** the tmux message is `× fix-login error` and the desktop and terminal summary is `× Agent error: fix-login`

#### Scenario: Hostile name

- **WHEN** an agent name contains `#[` or a newline
- **THEN** the notification shows the literal text and no tmux format expansion occurs

### Requirement: Viewing suppression

The system SHALL skip the tmux notification for a client that is viewing the agent that changed. It SHALL skip the desktop and terminal notifications if any attached client is viewing that agent. A client views an agent when the agent's pane is the client's active pane and, for an OpenCode agent, its tab is the active tab.

#### Scenario: One client views the agent

- **WHEN** an agent changes state while one client has its pane active and another does not
- **THEN** only the other client receives the tmux message, and no desktop or terminal notification is sent

#### Scenario: No client views the agent

- **WHEN** an agent changes state and no attached client has its pane active
- **THEN** every attached client receives the tmux message and the enabled desktop and terminal notifications are sent

#### Scenario: Background OpenCode tab

- **WHEN** an OpenCode agent on a background tab becomes `blocked` while a client has its pane active
- **THEN** that client receives the tmux message and the enabled desktop and terminal notifications are sent

#### Scenario: No clients attached

- **WHEN** an agent changes state with no clients attached
- **THEN** no tmux message or terminal sequence is possible and the desktop notification is still sent when enabled

### Requirement: Deduplication and tmux cooldown

The system MUST suppress notifications for unchanged consecutive states. It SHALL apply a 2-second per-agent cooldown to tmux messages, except that `blocked` and `error` MUST bypass the cooldown. Desktop and terminal notifications SHALL use deduplication without a cooldown.

#### Scenario: Rapid completion

- **WHEN** an agent enters `done`, returns to `working`, and enters `done` again within 2 seconds
- **THEN** the second tmux message is suppressed by the cooldown and the second desktop notification is delivered

#### Scenario: Repeated state

- **WHEN** an agent reports `done` again without leaving `done`
- **THEN** no channel produces a notification

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

`notify status` SHALL report whether delivery is paused, the setting of each of the three channels, and whether desktop delivery is available.

#### Scenario: Status while paused

- **WHEN** notifications are paused
- **THEN** the output includes `notifications: paused`

#### Scenario: Status while off

- **WHEN** all three channel options are `off`
- **THEN** the output includes `notifications: off`

#### Scenario: Status with defaults

- **WHEN** no channel option is set and notifications are not paused
- **THEN** the output includes `notifications: active`, `tmux: on`, `desktop: on`, and `terminal: off`

#### Scenario: Status without desktop

- **WHEN** the desktop channel is `on` and no desktop command exists
- **THEN** the output indicates that desktop delivery is unavailable

### Requirement: No default key binding

The system MUST NOT bind a key for notification pause by default. The README MUST show how to bind `notify pause` and `notify resume` in tmux.

#### Scenario: Fresh install

- **WHEN** the plugin loads without user configuration
- **THEN** no notification-control key is bound

#### Scenario: Documented binding

- **WHEN** the user follows the README binding example
- **THEN** the documented tmux command runs `notify pause` or `notify resume`

### Requirement: Delivery failure isolation

A failed or unavailable notification channel MUST NOT change agent state, block the reporting path, or prevent the other channels from delivering.

#### Scenario: Desktop command fails

- **WHEN** the desktop command exits nonzero
- **THEN** the state is already recorded and tmux and terminal delivery are unaffected

#### Scenario: No tmux clients

- **WHEN** no client is attached
- **THEN** the reporter does not retry tmux delivery and exits successfully

#### Scenario: Terminal not writable

- **WHEN** the terminal channel is `on` and the most recently active client's tty cannot be written
- **THEN** no OSC 9 sequence is sent and the other channels deliver normally

### Requirement: Per-channel notification options

The system SHALL provide one global option per notification channel, each accepting `on` or `off`: `@tmux-orchestrator-notify-tmux` (tmux clients, default `on`), `@tmux-orchestrator-notify-desktop` (`notify-send` or `osascript`, default `on`), and `@tmux-orchestrator-notify-terminal` (an OSC 9 sequence to the terminal of the most recently active client, default `off`). A missing or unrecognised value MUST mean the channel's default. Each channel MUST be delivered independently of the others.

#### Scenario: Defaults

- **WHEN** none of the three options is set and a supported desktop command exists
- **THEN** each notification is delivered to tmux clients and the desktop notifier, and no OSC 9 sequence is written

#### Scenario: Desktop unavailable

- **WHEN** the desktop channel is `on` and neither `notify-send` nor `osascript` exists
- **THEN** the desktop channel delivers nothing and the other enabled channels still deliver

#### Scenario: Terminal only

- **WHEN** the tmux and desktop channels are `off` and the terminal channel is `on`
- **THEN** each notification is delivered only as an OSC 9 sequence

#### Scenario: All channels off

- **WHEN** all three options are `off`
- **THEN** no notification is delivered and state tracking continues

#### Scenario: Unrecognised value

- **WHEN** `@tmux-orchestrator-notify-terminal` is set to `yes`
- **THEN** the terminal channel uses its default and stays off

#### Scenario: Old options ignored

- **WHEN** `@tmux-orchestrator-notify` is `off` and the three channel options are unset
- **THEN** notifications are delivered with the channel defaults
