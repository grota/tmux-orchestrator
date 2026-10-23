# Spec Delta

## MODIFIED Requirements

### Requirement: Packaging

The repository SHALL provide a TPM-compatible tmux plugin, a Claude Code marketplace plugin, and an OpenCode 2.x TUI plugin that share one reporter and one version. The tmux plugin SHALL hold the only copy of the reporter. Installation MUST be user-level and MUST NOT merge hooks into or rewrite existing user configuration files.

#### Scenario: Tmux plugin load

- **WHEN** the user loads the repository as a tmux plugin
- **THEN** it configures the sidebar, key binding, and cleanup hook without additional setup

#### Scenario: Claude plugin enablement

- **WHEN** the user adds this repository as a Claude Code marketplace and enables the plugin
- **THEN** its hooks call the shared reporter and no manual hook JSON edit is required, even though Claude Code installs only the plugin's own directory

#### Scenario: OpenCode plugin install

- **WHEN** the user runs the OpenCode installer or sets `@tmux-orchestrator-opencode on`
- **THEN** the user's OpenCode plugin directory gains a link to the loaded tmux plugin's OpenCode adapter, any earlier copied adapter or server plugin file from this project is removed, and no agent configuration file is rewritten

#### Scenario: OpenCode plugin uninstall

- **WHEN** the user runs the uninstaller
- **THEN** the link and any earlier copied adapter or server plugin file from this project are removed

#### Scenario: Foreign plugin directory

- **WHEN** the OpenCode plugin path is a real directory or a link that this project did not create
- **THEN** the installer leaves it untouched and reports that it did so

### Requirement: OpenCode tab tracking

The OpenCode adapter SHALL track the TUI's open tabs and report a tab being opened, closed, or focused. A newly opened tab SHALL start as `working` when its session is running, `blocked` when it or one of its child sessions has a pending permission or form, and `idle` otherwise. A known tab whose pending permission or form becomes visible later SHALL become `blocked`. With tabs disabled, the session the TUI shows SHALL be the pane's only agent.

#### Scenario: Tab opened on a running session

- **WHEN** the user opens a tab for a session that is executing
- **THEN** a new agent appears for the pane in `working`

#### Scenario: Restored tab waiting for permission

- **WHEN** OpenCode restarts and restores a tab whose session was waiting for permission, and loads that request after the tab appears
- **THEN** the agent shows `blocked` as soon as the request is loaded

#### Scenario: Child session waiting

- **WHEN** a tab's child session has a pending form
- **THEN** a newly opened tab for that session starts as `blocked`

#### Scenario: Tab closed

- **WHEN** the user closes a tab
- **THEN** that agent's row disappears and the agent session is not deleted

#### Scenario: Tabs disabled

- **WHEN** the TUI runs with tabs disabled and the user switches session
- **THEN** the pane's single agent follows the session the TUI shows

## ADDED Requirements

### Requirement: Reporter discovery

The tmux plugin SHALL publish the absolute path of its reporter in the global option `@tmux-orchestrator-reporter` each time it loads. Adapters SHALL use, in order, the `TMUX_ORCHESTRATOR_REPORTER` environment variable, that option on the tmux server they run in, and `tmux-orchestrator` on `PATH`. An adapter that finds no reporter MUST exit without affecting the agent.

#### Scenario: Installed Claude plugin

- **WHEN** a Claude Code hook fires from the marketplace copy of the plugin inside a tmux pane
- **THEN** it reaches the reporter named by `@tmux-orchestrator-reporter`

#### Scenario: Switching plugin copies

- **WHEN** the user reloads tmux with a different copy of the tmux plugin
- **THEN** the next agent event from either adapter uses that copy's reporter without restarting the agent

#### Scenario: No reporter available

- **WHEN** the option is unset and no reporter is on `PATH`
- **THEN** the hook exits successfully and the agent continues normally

### Requirement: Report protocol version

Adapters SHALL send a report protocol version with every reporter call. A reporter that does not support that version MUST ignore the call and SHALL show one tmux message per tmux server asking the user to update the tmux plugin.

#### Scenario: Newer adapter than reporter

- **WHEN** an adapter sends a protocol version the reporter does not support
- **THEN** no agent state changes and attached clients see one message asking to update the tmux plugin

#### Scenario: Matching versions

- **WHEN** an adapter sends the reporter's protocol version
- **THEN** the event is applied normally and no message is shown
