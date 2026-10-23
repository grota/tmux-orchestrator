# Spec Delta

## Purpose

Defines how Claude Code and OpenCode report lifecycle events to the shared reporter, how agent names are resolved, and how the three installable artifacts are packaged and kept from disrupting the agents they observe.

## ADDED Requirements

### Requirement: Claude Code event mapping
The Claude Code adapter SHALL map main-thread hook events to states as follows: `SessionStart` to `idle`, `UserPromptSubmit` to `working`, `PreToolUse` and `PostToolUse` to `working`, `PermissionRequest` to `blocked`, `Stop` to `done`, `StopFailure` to `error`, and `SessionEnd` to removal. It MUST ignore events carrying a subagent identifier and MUST NOT treat tool failures as agent errors.

#### Scenario: Permission prompt
- **WHEN** Claude Code requests permission for a tool
- **THEN** the agent state becomes `blocked`

#### Scenario: Permission resolved
- **WHEN** the approved tool finishes
- **THEN** the agent state returns to `working`

#### Scenario: Subagent event
- **WHEN** a hook fires from a subagent
- **THEN** the pane state is unchanged

#### Scenario: Failed tool
- **WHEN** a tool exits with an error but the agent continues
- **THEN** the state stays `working` and does not become `error`

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
The OpenCode adapter SHALL map `session.created` to `idle`; `chat.message`, `tool.execute.before`, `tool.execute.after`, `permission.replied`, `question.replied`, `question.rejected`, and `session.compacted` to `working`; `permission.asked` and `question.asked` to `blocked`; `session.idle` to `done` after activity in the turn and to `idle` otherwise; `session.error` to `error`; and `session.deleted` to removal.

#### Scenario: Turn completes
- **WHEN** `session.idle` arrives after a prompt or tool activity
- **THEN** the state becomes `done`

#### Scenario: Idle at startup
- **WHEN** `session.idle` arrives before any activity in the turn
- **THEN** the state stays `idle`

#### Scenario: Error then idle
- **WHEN** `session.idle` arrives after `session.error` without new activity
- **THEN** the state remains `error`

#### Scenario: Child session permission
- **WHEN** a child session asks for permission or a question
- **THEN** the root pane becomes `blocked`

#### Scenario: Child session completion
- **WHEN** a child session becomes idle while the root session is working
- **THEN** the root pane keeps `working`

### Requirement: OpenCode name resolution
The OpenCode adapter SHALL use the session title reported by OpenCode as the agent name and MUST update it when the title changes. If no title is available, it SHALL use the working-directory basename.

#### Scenario: Renamed session
- **WHEN** OpenCode reports an updated session title
- **THEN** the agent row shows the new title without changing state

### Requirement: Name safety
The system MUST strip newlines and control characters from agent names, escape `#` so names cannot inject tmux format directives, and truncate only at render time.

#### Scenario: Hostile name
- **WHEN** an agent name contains `#[` or a newline
- **THEN** the sidebar renders it literally as text and the layout is not altered

### Requirement: Packaging
The repository SHALL provide a TPM-compatible tmux plugin, a Claude Code marketplace plugin, and an OpenCode plugin that share one reporter and one version. Installation MUST be user-level and MUST NOT merge hooks into existing user configuration files.

#### Scenario: Tmux plugin load
- **WHEN** the user loads the repository as a tmux plugin
- **THEN** it configures the sidebar, key binding, and cleanup hook without additional setup

#### Scenario: Claude plugin enablement
- **WHEN** the user adds this repository as a Claude Code marketplace and enables the plugin
- **THEN** its hooks call the shared reporter and no manual hook JSON edit is required

#### Scenario: OpenCode plugin install
- **WHEN** the user runs the installer
- **THEN** the OpenCode plugin is placed in the user's OpenCode plugin directory and no agent configuration file is rewritten

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
