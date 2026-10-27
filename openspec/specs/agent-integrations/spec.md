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

The repository SHALL provide a TPM-compatible tmux plugin, a Claude Code marketplace plugin, and an OpenCode 2.x TUI plugin that share one reporter and one version. The tmux plugin SHALL hold the only copy of the reporter. Installation MUST be user-level and MUST NOT merge hooks into or rewrite existing user configuration files.

#### Scenario: Tmux plugin load

- **WHEN** the user loads the repository as a tmux plugin
- **THEN** it configures the sidebar, key binding, and cleanup hook without additional setup

#### Scenario: Claude plugin enablement

- **WHEN** the user adds this repository as a Claude Code marketplace and enables the plugin
- **THEN** its hooks call the shared reporter and no manual hook JSON edit is required, even though Claude Code installs only the plugin's own directory

#### Scenario: OpenCode plugin install

- **WHEN** the user runs the OpenCode installer, or the tmux plugin loads with OpenCode auto-install enabled and OpenCode detected
- **THEN** the user's OpenCode plugin directory gains a link to the loaded tmux plugin's OpenCode adapter, any earlier copied adapter or server plugin file from this project is removed, and no agent configuration file is rewritten

#### Scenario: OpenCode plugin uninstall

- **WHEN** the user runs the uninstaller
- **THEN** the link and any earlier copied adapter or server plugin file from this project are removed

#### Scenario: Foreign plugin directory

- **WHEN** the OpenCode plugin path is a real directory or a link that this project did not create
- **THEN** the installer leaves it untouched and reports that it did so

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

Because Claude Code sends no hook when a turn is interrupted, the system SHALL detect an interrupt of a `working` or `blocked` Claude agent from the session status in Claude Code's session registry, and set the agent to `idle` within a few seconds. An interrupt MUST be reported only after two consecutive `idle` readings while the agent is still `working` or `blocked`. Detection MUST stop when the agent leaves `working` and `blocked`, when a new prompt starts a new turn, or when the session's registry entry disappears or names another session.

#### Scenario: Interrupted tool call

- **WHEN** the user presses Esc while a Claude agent runs a tool
- **THEN** the agent becomes `idle` within a few seconds without any further input

#### Scenario: Interrupted text

- **WHEN** the user presses Esc while Claude writes text on the session's first prompt
- **THEN** the agent becomes `idle` within a few seconds

#### Scenario: Subagent interrupt

- **WHEN** a subagent's work is interrupted while the session stays `busy`
- **THEN** the main agent keeps its state

#### Scenario: Turn finishes normally

- **WHEN** the session turns `idle` and the turn's `Stop` arrives before a second reading
- **THEN** detection for that turn ends and the agent shows `done`

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

### Requirement: OpenCode adapter auto-install

When `@tmux-orchestrator-opencode-auto-install` is `on` or unset, each tmux plugin load SHALL link the OpenCode adapter if OpenCode is detected: `opencode` is on the tmux server's `PATH` or the user's `~/.config/opencode` directory exists. If OpenCode is not detected, the load MUST NOT create any file or directory. When the option is `off`, the load MUST NOT create, change, or remove the adapter link.

#### Scenario: OpenCode installed, default option

- **WHEN** the tmux plugin loads with the option unset and `~/.config/opencode` exists
- **THEN** the OpenCode plugin directory links to the loaded copy's adapter

#### Scenario: OpenCode on PATH only

- **WHEN** the tmux plugin loads with the option `on`, `opencode` on the tmux server's `PATH`, and no `~/.config/opencode`
- **THEN** the adapter link is created

#### Scenario: OpenCode not installed

- **WHEN** the tmux plugin loads with the option `on`, no `opencode` on `PATH`, and no `~/.config/opencode`
- **THEN** no OpenCode directory or link is created

#### Scenario: Switching plugin copies

- **WHEN** OpenCode is detected and the user reloads tmux with a different copy of the tmux plugin
- **THEN** the adapter link points to the newly loaded copy

#### Scenario: Auto-install off

- **WHEN** the tmux plugin loads with the option `off` and an adapter link from an earlier load exists
- **THEN** the link is left as it is

### Requirement: Attached Claude background sessions

A Claude Code background session SHALL be tracked as an agent of the pane that shows it with `claude attach <arg>`. A pane shows a session when a process in the pane runs `claude attach <arg>`, is not suspended, and `<arg>` resolves to that session. The agent MUST otherwise follow the same state mapping and naming rules as a Claude agent running in the pane.

#### Scenario: Event from an attached session

- **WHEN** a background session's hook fires and pane `%2` runs `claude attach f7ca13fb` for that session
- **THEN** the event updates the agent of pane `%2`

#### Scenario: Event from a session nobody shows

- **WHEN** a background session's hook fires and no pane shows that session
- **THEN** no agent is created or changed and no notification is sent

#### Scenario: Attach argument before other options

- **WHEN** the pane runs `claude --settings {...} attach f7ca13fb`
- **THEN** `f7ca13fb` is used as the attach argument

### Requirement: Attach argument resolution

The attach argument SHALL resolve to the background session whose short id equals it. Otherwise it SHALL resolve to the session whose session id starts with it, and otherwise to the only running background session whose name contains it, ignoring case. If no session or more than one session matches, the argument MUST resolve to nothing.

#### Scenario: Short id

- **WHEN** the argument is `f7ca13fb` and a session's short id is `f7ca13fb`
- **THEN** the argument resolves to that session

#### Scenario: Short id that does not start the session id

- **WHEN** the argument is `0dd1ab1e`, a session's short id is `0dd1ab1e` and its session id starts with `5e55`
- **THEN** the argument resolves to that session

#### Scenario: Part of the name

- **WHEN** the argument is `title wrap` and only the session named `Agent title wrap settings` contains it
- **THEN** the argument resolves to that session

#### Scenario: Ambiguous name

- **WHEN** the argument is `agent` and two running sessions have names containing it
- **THEN** the argument resolves to nothing and no pane shows either session

### Requirement: Attached session discovery

When a pane, window or tmux session is selected, the system SHALL check the selected pane for an attach viewer. If it shows a session that is not yet its agent, the system SHALL add that agent with the name and state Claude Code reports for the session, or `unknown` when the state has no matching agent state.

#### Scenario: Selecting a pane after attaching

- **WHEN** the user attaches to a background session that is `blocked` in pane `%2` and selects pane `%2`
- **THEN** pane `%2` gains a `blocked` agent named after the session, before the session sends any hook

### Requirement: Attached session removal

The system SHALL remove an attached agent from its pane once the pane no longer shows that session: the viewer exited, switched to the agent view, or was suspended. It SHALL check this when a pane, window or tmux session is selected, when a pane exits, and when the session's next hook arrives.

#### Scenario: Back to the agent view

- **WHEN** the user presses `←` in an attached pane and later selects another pane
- **THEN** the attached agent's row is removed

#### Scenario: Suspended viewer

- **WHEN** the user suspends the viewer with `Ctrl+Z` and the session's next hook arrives
- **THEN** the attached agent's row is removed and no notification is sent

#### Scenario: Running agent untouched

- **WHEN** a selection change happens while a pane runs an ordinary Claude Code session
- **THEN** that pane's agent is not removed

### Requirement: Claude Code agent rename

The reporter SHALL rename a Claude Code agent session by sending the rename control message to the messaging socket listed for the session in Claude's session registry, and SHALL treat the rename as done only once the registry shows the new name within three seconds. Any other outcome MUST fail the rename with a reason, and there MUST NOT be a fallback that changes only the sidebar.

#### Scenario: Claude confirms

- **WHEN** a Claude agent is renamed and the registry then shows the new name
- **THEN** the rename succeeds and the agent name is updated

#### Scenario: Claude ignores the message

- **WHEN** a Claude Code update ignores the rename message
- **THEN** the rename fails with a message that the internal rename message may have changed

### Requirement: OpenCode agent rename

The reporter SHALL rename an OpenCode agent session by sending `rename <sid> <title>` to the adapter's control socket. The adapter SHALL rename the session through the plugin API and answer `ok`, or `error` with the reason. A missing socket, no answer or an error MUST fail the rename with a reason.

#### Scenario: OpenCode refuses

- **WHEN** OpenCode refuses to rename a session
- **THEN** the rename fails with OpenCode's reason

#### Scenario: Old adapter

- **WHEN** the OpenCode adapter does not answer rename requests
- **THEN** the rename fails and asks to restart OpenCode

### Requirement: Contract tests for agent internals

The project SHALL provide contract tests that run the installed Claude Code and OpenCode in a private tmux server and check the internals the plugin relies on, without sending a prompt.

#### Scenario: Claude Code update drops the rename message

- **WHEN** the Claude contract test runs against a Claude Code that ignores the rename message
- **THEN** the test fails and names the missing behaviour

### Requirement: Claude subagent tracking

The reporter SHALL track a Claude agent's main-thread state from main-thread events only, and its live subagents, each with its own state, from the subagent's own events. A subagent SHALL be listed from its first event, including `SubagentStart`, until its `SubagentStop`. An interrupt or a new session MUST clear the list, and a subagent with no event for 30 minutes MUST be dropped.

#### Scenario: Interrupt

- **WHEN** the user interrupts the main thread
- **THEN** the subagent list is cleared until a subagent sends another event

### Requirement: Agent state after the last subagent

When the last subagent ends while the agent is `working` and its main thread is `idle` or `done`, the agent SHALL take its main thread's state.

#### Scenario: Background subagent outlives its main thread

- **WHEN** the main thread stops while a background subagent works, and the subagent then ends
- **THEN** the agent is `done`, not `working`
