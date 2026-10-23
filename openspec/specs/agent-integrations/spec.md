# agent-integrations Specification

## Purpose

Defines how Claude Code and OpenCode report lifecycle events to the shared reporter, how agent names are resolved, and how the three installable artifacts are packaged and kept from disrupting the agents they observe.

## Requirements

### Requirement: Claude Code event mapping

The Claude Code adapter SHALL map hook events to states as follows: `SessionStart` to `idle`; `UserPromptSubmit`, `PostToolUse`, `ElicitationResult`, and `PreToolUse` for any other tool to `working`; `PermissionRequest`, `Elicitation`, and `PreToolUse` for `AskUserQuestion` or `ExitPlanMode` to `blocked`; `Stop` to completion; `StopFailure` to `error`; and `SessionEnd` to removal. It MUST NOT treat tool failures as agent errors.

#### Scenario: Permission prompt

- **WHEN** Claude Code requests permission for a tool
- **THEN** the agent state becomes `blocked`

#### Scenario: Permission resolved

- **WHEN** the approved tool finishes
- **THEN** the agent state returns to `working`

#### Scenario: Question to the user

- **WHEN** Claude Code calls `AskUserQuestion` or `ExitPlanMode`
- **THEN** the agent state becomes `blocked` until the tool finishes

#### Scenario: MCP input form

- **WHEN** an MCP server requests input through an elicitation
- **THEN** the agent state becomes `blocked` and returns to `working` when the elicitation is answered

#### Scenario: Ordinary tool call

- **WHEN** Claude Code starts a tool that does not wait for the user
- **THEN** the agent state is `working`

#### Scenario: Failed tool

- **WHEN** a tool exits with an error but the agent continues
- **THEN** the state stays `working` and does not become `error`

#### Scenario: Subagent event

- **WHEN** a hook fires from a subagent
- **THEN** it applies to the pane's agent like a main-thread event, and no subagent event completes the agent

### Requirement: Claude Code name resolution

The Claude Code adapter SHALL use the session title supplied by the hook when present. Otherwise it SHALL look up the running session name asynchronously by session identifier and refresh it on the next submitted prompt. If the lookup has no result or fails, it MUST use the working-directory basename until a later refresh succeeds.

#### Scenario: Title present at start

- **WHEN** `SessionStart` provides a non-empty session title
- **THEN** the sidebar shows that title without running a lookup

#### Scenario: Session not yet listed

- **WHEN** the name lookup cannot find the new session at startup
- **THEN** the sidebar shows the directory basename and replaces it after a later successful lookup

#### Scenario: Lookup is slow

- **WHEN** the name lookup takes longer than the hook's budget
- **THEN** the hook returns without waiting and the state is already recorded

### Requirement: OpenCode event mapping

The OpenCode adapter SHALL map `session.execution.started`, `permission.replied`, `form.replied`, and `form.cancelled` to `working`; `permission.asked` and `form.created` to `blocked`; `session.execution.succeeded` to completion; `session.execution.failed` to `error`; and `session.execution.interrupted` to `idle`. Events from a child session SHALL apply to its root session's agent. Events for sessions not open in the TUI's tabs MUST be ignored.

#### Scenario: Turn completes

- **WHEN** `session.execution.succeeded` arrives after the execution started
- **THEN** the state becomes `done`

#### Scenario: Idle at startup

- **WHEN** `session.execution.succeeded` arrives while the agent is `idle`
- **THEN** the state stays `idle`

#### Scenario: Error then idle

- **WHEN** `session.execution.succeeded` arrives after `session.execution.failed` without new activity
- **THEN** the state remains `error`

#### Scenario: User interrupts

- **WHEN** `session.execution.interrupted` arrives
- **THEN** the state becomes `idle`

#### Scenario: Question form

- **WHEN** OpenCode creates a form for the user
- **THEN** the state becomes `blocked` until the form is answered or cancelled

#### Scenario: Child session permission

- **WHEN** a child session asks for permission or creates a form
- **THEN** the root session's agent becomes `blocked`

#### Scenario: Child session completion

- **WHEN** a child session's execution succeeds while the root session is working
- **THEN** the root session's agent keeps `working`

#### Scenario: Session in another TUI

- **WHEN** an event arrives for a session that is not open in this TUI
- **THEN** no agent in this pane changes

### Requirement: OpenCode name resolution

The OpenCode adapter SHALL use each tab's session title as that agent's name and MUST update it when OpenCode reports a rename. If no title is available, it SHALL use the working-directory basename.

#### Scenario: Renamed session

- **WHEN** OpenCode reports `session.renamed` for an open tab
- **THEN** that agent's row shows the new title without changing state

### Requirement: Name safety

The system MUST strip newlines and control characters from agent names, escape `#` so names cannot inject tmux format directives, and truncate only at render time.

#### Scenario: Hostile name

- **WHEN** an agent name contains `#[` or a newline
- **THEN** the sidebar renders it literally as text and the layout is not altered

### Requirement: Packaging

The repository SHALL provide a TPM-compatible tmux plugin, a Claude Code marketplace plugin, and an OpenCode 2.x TUI plugin that share one reporter and one version. Installation MUST be user-level and MUST NOT merge hooks into or rewrite existing user configuration files.

#### Scenario: Tmux plugin load

- **WHEN** the user loads the repository as a tmux plugin
- **THEN** it configures the sidebar, key binding, and cleanup hook without additional setup

#### Scenario: Claude plugin enablement

- **WHEN** the user adds this repository as a Claude Code marketplace and enables the plugin
- **THEN** its hooks call the shared reporter and no manual hook JSON edit is required

#### Scenario: OpenCode plugin install

- **WHEN** the user runs the installer
- **THEN** the OpenCode plugin is placed in the user's OpenCode plugin directory as a TUI plugin, any earlier server plugin file from this project is removed, and no agent configuration file is rewritten

#### Scenario: OpenCode plugin uninstall

- **WHEN** the user runs the uninstaller
- **THEN** both the TUI plugin and any earlier server plugin file from this project are removed

### Requirement: Compatibility check

The system MUST refuse to enable the sidebar when the running tmux lacks `side-status`, reporting the requirement once without preventing other tmux configuration from loading.

#### Scenario: Old tmux

- **WHEN** the plugin loads on tmux 3.8
- **THEN** it prints that tmux 3.9 or newer is required and leaves `side-status` disabled

### Requirement: Failure isolation

A reporting failure MUST NOT block, fail, or alter the observed agent. The adapter SHALL complete within a short budget when tmux is unavailable, the server is gone, or the reporter errors.

#### Scenario: Tmux server unavailable

- **WHEN** an event fires outside tmux or after the server exited
- **THEN** the adapter exits successfully and the agent continues normally

#### Scenario: Reporter error

- **WHEN** the reporter cannot write an option
- **THEN** the adapter does not retry indefinitely and does not surface an agent error

### Requirement: Repeatable updates

Applying the same event or recomputing a session summary multiple times MUST produce the same result and MUST NOT duplicate rows or corrupt counts.

#### Scenario: Duplicate event

- **WHEN** the same state event is delivered twice
- **THEN** the pane shows one row in the same state

#### Scenario: Concurrent activity

- **WHEN** events from two agents in one session update the summary concurrently
- **THEN** the final count and rollup match the states stored on the panes

### Requirement: Claude Code interrupt detection

Because Claude Code sends no hook when a turn is interrupted, the system SHALL detect an interrupt of a `working` or `blocked` Claude agent from the main-thread interrupt marker that Claude Code writes to the session transcript, and set the agent to `idle` within a few seconds. Detection MUST stop when the agent leaves `working` and `blocked`, when a new prompt starts a new turn, when the pane closes, or after one hour without transcript growth.

#### Scenario: Interrupted tool call

- **WHEN** the user presses Esc while a Claude agent runs a tool
- **THEN** the agent becomes `idle` within a few seconds without any further input

#### Scenario: Subagent interrupt

- **WHEN** a subagent's transcript entry records an interrupt
- **THEN** the main agent keeps its state

#### Scenario: Turn finishes normally

- **WHEN** the turn ends with `Stop`
- **THEN** detection for that turn ends and the agent shows `done`

### Requirement: OpenCode tab tracking

The OpenCode adapter SHALL track the TUI's open tabs and report a tab being opened, closed, or focused. A newly opened tab SHALL start as `working` when its session is running, `blocked` when it has a pending permission or form, and `idle` otherwise. With tabs disabled, the session the TUI shows SHALL be the pane's only agent.

#### Scenario: Tab opened on a running session

- **WHEN** the user opens a tab for a session that is executing
- **THEN** a new agent appears for the pane in `working`

#### Scenario: Tab closed

- **WHEN** the user closes a tab
- **THEN** that agent's row disappears and the agent session is not deleted

#### Scenario: Tabs disabled

- **WHEN** the TUI runs with tabs disabled and the user switches session
- **THEN** the pane's single agent follows the session the TUI shows

### Requirement: OpenCode tab focus

The OpenCode adapter SHALL accept a request to focus one of its tabs from the reporter and MUST focus that tab in the TUI running in that pane only.

#### Scenario: Focus request

- **WHEN** the reporter asks the pane's adapter to focus a tab
- **THEN** that TUI shows the tab and no other TUI changes

### Requirement: Ordered event delivery

The OpenCode adapter MUST apply agent events in the order OpenCode emitted them, so a later event never takes effect before an earlier one.

#### Scenario: Rapid events

- **WHEN** an execution starts and a permission is asked within a few milliseconds
- **THEN** the final state is `blocked`
