# tmux-orchestrator specification

This document is the single source of truth for what tmux-orchestrator does and why: a persistent tmux view of the coding agents running in it. Requirements use SHALL and MUST; each has scenarios that pin its behaviour. Decisions record the choices behind the design and the options they rejected. Change this document in the same commit as the behaviour it describes. New terms go in the glossary and new decisions in section 6; this project keeps no separate `GLOSSARY.md`, `docs/adr/` or OpenSpec changes.

## Contents

1. [Glossary](#1-glossary)
2. [Agent state](#2-agent-state)
3. [Agent integrations](#3-agent-integrations)
4. [Sidebar](#4-sidebar)
5. [Notifications](#5-notifications)
6. [Decisions](#6-decisions)

## 1. Glossary

**Agent**:
An agent session open in a tmux pane, whose state this project tracks. A Claude Code pane holds one agent; an OpenCode pane holds one per tab. Subagents are not agents: their activity counts toward the agent that started them.
_Avoid_: worker, bot, process

**Agent name**:
The label shown for an agent: its agent session's title, or the working-directory name when there is no title.
_Avoid_: title, label

**Focused agent**:
The agent a client is looking at: the one in the pane it views, and for OpenCode the one in that pane's active tab. At most one per client. With tmux's `focus-events` on, a client whose terminal window does not have focus views no agent.
_Avoid_: selected agent, current agent, active agent

**Next agent key**:
An optional key binding that brings the user to the next agent across all tmux sessions, those that need attention first.
_Avoid_: attention key, jump key

**Agent kind**:
The product an agent belongs to: Claude Code or OpenCode.
_Avoid_: agent type, agent name

**Agent pane**:
The tmux pane that hosts one or more agents.
_Avoid_: agent window, terminal

**Tab**:
An OpenCode tab showing one root agent session. Closing a tab ends that agent without ending the agent session.
_Avoid_: window, view

**Agent session**:
A conversation inside Claude Code or OpenCode, identified by its own id and name.
_Avoid_: session, conversation

**Tmux session**:
A collection of windows inside one tmux server.
_Avoid_: session

**Background task**:
A command a Claude agent or one of its subagents left running while it goes on: a `Bash` call with `run_in_background`, or a `Monitor`. It never changes the agent state. A subagent's background tasks also keep that subagent listed as a waiting subagent.
_Avoid_: background job, background process, shell

**Agent state**:
The lifecycle value shown for an agent: `working`, `blocked`, `done`, `idle`, `error`, or `unknown`.
_Avoid_: status, agent status

**State time**:
How long since the agent's own agent events last changed its agent state. Viewing the agent does not count as a change.
_Avoid_: timer, elapsed, age, time in state

**Agent event**:
A lifecycle event as the agent kind itself names it, such as Claude Code's `PermissionRequest` or OpenCode's `session.idle`, together with its details. Agent state is derived from agent events, plus the user viewing the agent pane.
_Avoid_: hook, lifecycle event, normalized event

**Agent notification**:
A user-facing message emitted when an agent enters `blocked`, `error`, or `done`.
_Avoid_: alert (a tmux alert is a different mechanism)

**Notification channel**:
A delivery path for agent notifications: the desktop notifier or the terminal emulator. Each is turned on or off on its own.
_Avoid_: transport, backend

**Notification pause**:
A global, indefinite suppression of agent notification delivery that does not stop state tracking.
_Avoid_: mute, disable (those change channel configuration)

**Sidebar**:
The persistent vertical area drawn by tmux's side status line, listing tmux sessions and their agents.
_Avoid_: panel, sidebar pane, area

**Keys panel**:
A part of the sidebar, opened and closed by a click, that lists the configurable key bindings acting on the orchestrator.
_Avoid_: help, cheatsheet, legend

**Options panel**:
A part of the sidebar, opened and closed by a click, that shows the plugin's options with their current values, explains one when its label is clicked, and changes one when its value is clicked, until tmux restarts.
_Avoid_: settings, preferences, config panel

## 2. Agent state

Defines how lifecycle events become a normalized per-agent state, how agent identity is recorded, and how per-session summaries are kept in tmux options so every client sees the same view.

### Normalized agent states

The system SHALL assign each tracked agent exactly one state: `working`, `blocked`, `done`, `idle`, `error`, or `unknown`.

#### Scenario: Newly started agent

- **WHEN** an agent session starts and has not produced work yet
- **THEN** its state is `idle`

#### Scenario: Marked agent without a state

- **WHEN** a pane carries an agent kind and name but no valid state value
- **THEN** the system presents it as `unknown` and does not hide it

#### Scenario: Single state at a time

- **WHEN** a new lifecycle event arrives
- **THEN** the agent has exactly one current state, replacing the previous one except where an explicit retention rule applies

### Event-driven transitions

The system SHALL derive state only from agent events and from the user viewing an agent, and MUST NOT infer state from terminal contents. A completion SHALL produce `done` only when the agent was `working` or `blocked`.

#### Scenario: Work begins

- **WHEN** a user prompt is submitted, a tool starts or finishes, or the agent reports activity
- **THEN** the state becomes `working`

#### Scenario: Agent needs a person

- **WHEN** the agent requests permission, asks a question, or shows an input form
- **THEN** the state becomes `blocked`

#### Scenario: Turn completes

- **WHEN** the agent reports that its turn finished while `working` or `blocked`
- **THEN** the state becomes `done`

#### Scenario: Completion without activity

- **WHEN** the agent reports that its turn finished while `idle`
- **THEN** the state stays `idle`

#### Scenario: Turn interrupted

- **WHEN** the agent reports an interrupted turn
- **THEN** the state becomes `idle`

#### Scenario: Agent failure

- **WHEN** the integration reports an authentication, billing, rate-limit, or server failure
- **THEN** the state becomes `error`

#### Scenario: Failure is retained

- **WHEN** a completion event arrives after a failure without new work
- **THEN** the state remains `error`

#### Scenario: Failure clears

- **WHEN** the next activity event arrives after an error
- **THEN** the state becomes `working`

#### Scenario: Done clears on focus

- **WHEN** the exact agent pane is focused and, for an OpenCode agent, its tab is the active tab
- **THEN** a `done` state clears to `idle`

#### Scenario: Done stays in a background terminal window

- **WHEN** `focus-events` is on and the only client showing a `done` agent's pane is in a terminal window without focus
- **THEN** the agent stays `done` until that window gets focus

#### Scenario: Done stays on a background tab

- **WHEN** an OpenCode pane is focused while a `done` agent's tab is not active
- **THEN** that agent stays `done` until its tab becomes active

### Pane state storage

The system SHALL store each agent's state, name, kind, agent session identifier, and last agent event as tmux user options on its agent pane, in the pane's tab order. It MUST NOT require a daemon, background service, or state file outside the tmux server.

#### Scenario: Sidebar reads shared state

- **WHEN** any client renders the sidebar
- **THEN** it reads the same tmux options written by the reporter

#### Scenario: Several agents in one pane

- **WHEN** an OpenCode pane has three tabs open
- **THEN** the pane stores three agents in tab order

#### Scenario: Tmux server stops

- **WHEN** the tmux server exits
- **THEN** all agent state is gone and no external state remains

### Agent identity

The system SHALL record an agent name, an agent kind of `claude` or `opencode`, and the integration's session identifier for every tracked agent. An agent is one agent session open in a pane: a Claude Code pane holds one agent and an OpenCode pane holds one per tab.

#### Scenario: Name unavailable

- **WHEN** the integration cannot provide an agent name
- **THEN** the system uses the pane's working-directory basename as the name

#### Scenario: Name is refreshed

- **WHEN** the integration later provides a different agent name
- **THEN** the recorded name is updated without changing the pane or its state

### Session summary

The system SHALL maintain, for each tmux session, the number of tracked agents and a rollup state using the priority `blocked`, `error`, `done`, `working`, `idle`, `unknown`.

#### Scenario: Mixed states

- **WHEN** a session has one blocked agent and one working agent
- **THEN** the session rollup is `blocked`

#### Scenario: Empty session

- **WHEN** the last tracked agent in a session is removed
- **THEN** the session count is zero and the session is not listed as an agent session

#### Scenario: Summary refresh

- **WHEN** any agent state changes or an agent pane exits
- **THEN** the affected session summary is recomputed

### State removal

The system SHALL remove an agent when the integration reports its agent session ended, when its OpenCode tab closes, when the OpenCode TUI exits, or when the pane is destroyed. Removing one agent MUST NOT change the other agents in the same pane.

#### Scenario: SessionEnd

- **WHEN** a Claude agent reports its session ended
- **THEN** the pane's agent is removed and it no longer appears in the sidebar

#### Scenario: Tab closed

- **WHEN** one of three OpenCode tabs closes
- **THEN** only that agent is removed and the other two keep their state and order

#### Scenario: OpenCode exits

- **WHEN** the OpenCode TUI in a pane exits
- **THEN** all agents of that pane are removed

#### Scenario: Pane destroyed

- **WHEN** a pane with agents is closed
- **THEN** its agents disappear with it and the session summary is recomputed

### Main-thread only

Activity and waits from a subagent or child session SHALL count toward the agent that started it, but a subagent's completion MUST NOT complete that agent.

#### Scenario: Subagent finishes

- **WHEN** a subagent emits a completion event while the main agent is still working
- **THEN** the agent keeps showing `working`

#### Scenario: Subagent needs permission

- **WHEN** a subagent requests permission
- **THEN** the agent that started it becomes `blocked`

### Last agent event

The system SHALL record, for each agent, the last agent event it received with its kind, name, and detail, readable with tmux's option commands. It MUST NOT be shown in the sidebar.

#### Scenario: Diagnosing a state

- **WHEN** a Claude agent shows `error` after a rate limit
- **THEN** its recorded last agent event names `StopFailure` with the `rate_limit` detail

## 3. Agent integrations

Defines how Claude Code and OpenCode report lifecycle events to the shared reporter, how agent names are resolved, and how the three installable artifacts are packaged and kept from disrupting the agents they observe.

### Claude Code event mapping

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

### Claude Code name resolution

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

### OpenCode event mapping

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

### OpenCode name resolution

The OpenCode adapter SHALL use each tab's session title as that agent's name and MUST update it when OpenCode reports a rename. If no title is available, it SHALL use the working-directory basename.

#### Scenario: Renamed session

- **WHEN** OpenCode reports `session.renamed` for an open tab
- **THEN** that agent's row shows the new title without changing state

### Name safety

The system MUST strip newlines and control characters from agent names, escape `#` so names cannot inject tmux format directives, and truncate only at render time.

#### Scenario: Hostile name

- **WHEN** an agent name contains `#[` or a newline
- **THEN** the sidebar renders it literally as text and the layout is not altered

### Packaging

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

### Compatibility check

The system MUST refuse to enable the sidebar when the running tmux lacks `side-status`, reporting the requirement once without preventing other tmux configuration from loading.

#### Scenario: Old tmux

- **WHEN** the plugin loads on tmux 3.8
- **THEN** it prints that tmux 3.9 or newer is required and leaves `side-status` disabled

### Failure isolation

A reporting failure MUST NOT block, fail, or alter the observed agent. The adapter SHALL complete within a short budget when tmux is unavailable, the server is gone, or the reporter errors.

#### Scenario: Tmux server unavailable

- **WHEN** an event fires outside tmux or after the server exited
- **THEN** the adapter exits successfully and the agent continues normally

#### Scenario: Reporter error

- **WHEN** the reporter cannot write an option
- **THEN** the adapter does not retry indefinitely and does not surface an agent error

### Repeatable updates

Applying the same event or recomputing a session summary multiple times MUST produce the same result and MUST NOT duplicate rows or corrupt counts.

#### Scenario: Duplicate event

- **WHEN** the same state event is delivered twice
- **THEN** the pane shows one row in the same state

#### Scenario: Concurrent activity

- **WHEN** events from two agents in one session update the summary concurrently
- **THEN** the final count and rollup match the states stored on the panes

### Claude Code interrupt detection

Because Claude Code sends no hook when a turn is interrupted, the system SHALL detect an interrupt of a `working` or `blocked` Claude agent from the session status in Claude Code's session registry, and set the agent to `idle` within a few seconds. An interrupt MUST be reported only after two consecutive `idle` or `shell` readings while the agent is still `working` or `blocked`; `shell` is what an idle session with background shells still running reports. Detection MUST stop when the agent leaves `working` and `blocked`, when a new prompt starts a new turn, or when the session's registry entry disappears or names another session.

#### Scenario: Interrupted tool call

- **WHEN** the user presses Esc while a Claude agent runs a tool
- **THEN** the agent becomes `idle` within a few seconds without any further input

#### Scenario: Interrupted text

- **WHEN** the user presses Esc while Claude writes text on the session's first prompt
- **THEN** the agent becomes `idle` within a few seconds

#### Scenario: Interrupt with background shells

- **WHEN** the user presses Esc while the agent has a background `Bash` task running
- **THEN** the registry reads `shell`, and the agent becomes `idle` within a few seconds and keeps its background task

#### Scenario: Subagent interrupt

- **WHEN** a subagent's work is interrupted while the session stays `busy`
- **THEN** the main agent keeps its state

#### Scenario: Turn finishes normally

- **WHEN** the session turns `idle` and the turn's `Stop` arrives before a second reading
- **THEN** detection for that turn ends and the agent shows `done`

### OpenCode tab tracking

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

### OpenCode tab focus

The OpenCode adapter SHALL accept a request to focus one of its tabs from the reporter and MUST focus that tab in the TUI running in that pane only.

#### Scenario: Focus request

- **WHEN** the reporter asks the pane's adapter to focus a tab
- **THEN** that TUI shows the tab and no other TUI changes

### Ordered event delivery

The OpenCode adapter MUST apply agent events in the order OpenCode emitted them, so a later event never takes effect before an earlier one.

#### Scenario: Rapid events

- **WHEN** an execution starts and a permission is asked within a few milliseconds
- **THEN** the final state is `blocked`

### Reporter discovery

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

### Report protocol version

Adapters SHALL send a report protocol version with every reporter call. A reporter that does not support that version MUST ignore the call and SHALL show one tmux message per tmux server asking the user to update the tmux plugin.

#### Scenario: Newer adapter than reporter

- **WHEN** an adapter sends a protocol version the reporter does not support
- **THEN** no agent state changes and attached clients see one message asking to update the tmux plugin

#### Scenario: Matching versions

- **WHEN** an adapter sends the reporter's protocol version
- **THEN** the event is applied normally and no message is shown

### OpenCode adapter auto-install

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

### Attached Claude background sessions

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

### Attach argument resolution

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

### Attached session discovery

When a pane, window or tmux session is selected, the system SHALL check the selected pane for an attach viewer. If it shows a session that is not yet its agent, the system SHALL add that agent with the name and state Claude Code reports for the session, or `unknown` when the state has no matching agent state.

#### Scenario: Selecting a pane after attaching

- **WHEN** the user attaches to a background session that is `blocked` in pane `%2` and selects pane `%2`
- **THEN** pane `%2` gains a `blocked` agent named after the session, before the session sends any hook

### Attached session removal

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

### Claude Code agent rename

The reporter SHALL rename a Claude Code agent session by sending the rename control message to the messaging socket listed for the session in Claude's session registry, and SHALL treat the rename as done only once the registry shows the new name within three seconds. Any other outcome MUST fail the rename with a reason, and there MUST NOT be a fallback that changes only the sidebar.

#### Scenario: Claude confirms

- **WHEN** a Claude agent is renamed and the registry then shows the new name
- **THEN** the rename succeeds and the agent name is updated

#### Scenario: Claude ignores the message

- **WHEN** a Claude Code update ignores the rename message
- **THEN** the rename fails with a message that the internal rename message may have changed

### OpenCode agent rename

The reporter SHALL rename an OpenCode agent session by sending `rename <sid> <title>` to the adapter's control socket. The adapter SHALL rename the session through the plugin API and answer `ok`, or `error` with the reason. A missing socket, no answer or an error MUST fail the rename with a reason.

#### Scenario: OpenCode refuses

- **WHEN** OpenCode refuses to rename a session
- **THEN** the rename fails with OpenCode's reason

#### Scenario: Old adapter

- **WHEN** the OpenCode adapter does not answer rename requests
- **THEN** the rename fails and asks to restart OpenCode

### Contract tests for agent internals

The project SHALL provide contract tests that run the installed Claude Code and OpenCode in a private tmux server and check the internals the plugin relies on, without sending a prompt.

#### Scenario: Claude Code update drops the rename message

- **WHEN** the Claude contract test runs against a Claude Code that ignores the rename message
- **THEN** the test fails and names the missing behaviour

### Claude subagent tracking

The reporter SHALL track a Claude agent's main-thread state from main-thread events only, and its live subagents, each with its own state, from the subagent's own events. A subagent SHALL be listed from its first event, including `SubagentStart`, until its `SubagentStop`. The reporter SHALL record the background tasks a subagent launches from its `PostToolUse` hooks. When the subagent's `SubagentStop` lists one of them as running in `background_tasks`, the subagent SHALL stay listed as `idle`, a waiting subagent, until a `Stop` or `SubagentStop` lists none of them; its next own event makes it active again. An interrupt or a new session MUST clear the list. A subagent with no event for 30 minutes MUST be dropped, and a waiting subagent that no hook has listed a task of for six hours MUST be dropped.

#### Scenario: Fork waits on its own background command

- **WHEN** a fork launches a background `Bash` command and ends its turn while the command runs
- **THEN** the fork stays listed as `idle` until the command ends and the fork resumes and stops with no running task of its own

#### Scenario: Interrupt

- **WHEN** the user interrupts the main thread
- **THEN** the subagent list is cleared until a subagent sends another event

### Claude background task tracking

The reporter SHALL track the background tasks a Claude agent and its subagents launch: a `Bash` call with `run_in_background` or a `Monitor` call, added from the `PostToolUse` hook of whichever actor made it. A main-thread `UserPromptSubmit` hook whose prompt is a `<task-notification>` with status `completed`, `failed` or `killed` SHALL remove the task it names. A `Stop` or `SubagentStop` hook that carries `background_tasks` SHALL replace the list with its `shell` and `monitor` tasks whose status is `running`; one without that field MUST leave the list alone. A new session MUST clear the list, and an interrupt MUST NOT. A task that no `Stop` or `SubagentStop` has listed for six hours since its launch MUST be dropped. Reporters handling events of the same pane MUST NOT lose each other's updates. Background tasks MUST NOT change the agent state, the session rollup or notifications.

#### Scenario: Task ends while the agent is idle

- **WHEN** a background `Bash` task finishes after the agent's turn ended
- **THEN** Claude Code starts a turn to deliver its result, and that turn's `Stop` no longer lists the task

#### Scenario: Interrupt

- **WHEN** the user presses Esc while two background tasks run
- **THEN** both stay listed

#### Scenario: Parallel launches

- **WHEN** Claude launches two background commands in one message and both `PostToolUse` hooks run at once
- **THEN** both tasks are listed

#### Scenario: Subagent launch

- **WHEN** a subagent runs `Bash` with `run_in_background`
- **THEN** the agent's task count grows by one

#### Scenario: Task ends during a turn

- **WHEN** a task ends while the agent is still working
- **THEN** Claude Code delivers a task notification through `UserPromptSubmit` and the count drops at once

### Agent state after the last subagent

When no listed subagent is `working` or `blocked` any more while the agent is `working` and its main thread is `idle` or `done`, the agent SHALL take its main thread's state. A waiting subagent does not keep the agent `working`.

#### Scenario: Background subagent outlives its main thread

- **WHEN** the main thread stops while a background subagent works, and the subagent then ends
- **THEN** the agent is `done`, not `working`

#### Scenario: Subagent waits on its own background task

- **WHEN** the main thread has stopped and a subagent stops while its background command runs
- **THEN** the agent is `done`

## 4. Sidebar

Defines the persistent tmux sidebar that shows agent-bearing sessions and the agents in the current session, and the mouse and key actions that navigate from it.

### Persistent sidebar surface

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

### Sidebar configuration

The sidebar SHALL default to the left side with a width of 28 columns. The side MUST be configurable as `left` or `right`, and the width MUST be configurable and resizable with tmux's built-in status-border drag.

#### Scenario: Drag resize

- **WHEN** the user drags the sidebar border
- **THEN** the width changes for that session and is not overwritten by state refreshes

#### Scenario: Reset width

- **WHEN** the user double-clicks the sidebar border
- **THEN** the width returns to the configured default

### Session list

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

### Agent list

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

### State presentation

The sidebar SHALL use a distinct icon and color for each state: `working` yellow `●`, `blocked` red `◉`, `error` red `×`, `done` teal `✓`, `idle` green `○`, and `unknown` grey `·`.

#### Scenario: Completed agent

- **WHEN** an agent enters `done`
- **THEN** its row shows a teal `✓`

#### Scenario: Working agent

- **WHEN** an agent enters `working`
- **THEN** its row shows a yellow `●`

#### Scenario: Session rollup icon

- **WHEN** a session rollup is `blocked`
- **THEN** its session row shows a red `◉`

#### Scenario: Blocked count in a session row

- **WHEN** a session has two blocked agents
- **THEN** its session row shows `◉2`

### Mouse navigation

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

### Keyboard control

The system SHALL provide a tmux key binding, `prefix + O` by default, that shows and hides the sidebar, and a command usable from `run-shell`. The key MUST be configurable and MUST NOT require keyboard focus inside the sidebar.

#### Scenario: Toggle off

- **WHEN** the user presses the toggle binding while the sidebar is visible
- **THEN** the sidebar hides for all sessions and agent tracking continues

#### Scenario: Toggle on

- **WHEN** the user presses the toggle binding while the sidebar is hidden
- **THEN** the sidebar returns on its configured side with current state

### Refresh

The sidebar SHALL reflect a state change without manual refresh and MUST NOT redraw more often than needed when no state changes.

#### Scenario: State reported

- **WHEN** the reporter changes a pane state
- **THEN** attached clients redraw the sidebar immediately

#### Scenario: No clients attached

- **WHEN** a state change occurs while no client is attached
- **THEN** the change is recorded and appears when a client next attaches

### Overflow

When the listed rows do not fit the available height, the sidebar MUST keep the focused agent's row visible and MUST NOT scroll the terminal or accept keyboard scrolling.

#### Scenario: Too many agents

- **WHEN** the current session has more agent rows than fit
- **THEN** the sidebar keeps the focused agent visible and trims rows it cannot show

### Per-pane row limit

The sidebar SHALL show at most nine agent rows per pane. Agents beyond the ninth SHALL be shown as one `+N more` row with the rolled-up state of those agents, using the session rollup priority. Clicking it SHALL select the pane.

#### Scenario: Ten tabs

- **WHEN** an OpenCode pane has ten tabs and the tenth is `blocked`
- **THEN** nine agent rows are shown followed by a `+1 more` row with the blocked icon

#### Scenario: Tab closed below the limit

- **WHEN** a pane drops from ten tabs to nine
- **THEN** the `+N more` row disappears and nine agent rows are shown

### Agent name length

The sidebar SHALL fit agent names according to two options. `@tmux-orchestrator-name-wrap` unset or `wrap` wraps the name over up to four lines, and `nowrap` shows one line cut to the available width. `@tmux-orchestrator-name-max-chars` set to a positive number `N` first cuts the name at `N` characters; with `nowrap` the line is cut at `N` or the available width, whichever is shorter, and with `wrap` the cut name wraps. Any other value of `@tmux-orchestrator-name-max-chars` sets no limit. A cut name MUST end in `…`.

#### Scenario: Short name with wrapping

- **WHEN** both options are unset and the agent name fits on one line
- **THEN** the name takes one line and no empty line follows it

#### Scenario: Long name with wrapping

- **WHEN** wrapping is on and the agent name needs two lines at the current width
- **THEN** the name continues on a second line indented two columns, under its first character

#### Scenario: Name longer than four lines

- **WHEN** wrapping is on and the agent name needs more than four lines
- **THEN** four lines are shown and the fourth ends in `…`

#### Scenario: Fixed character limit

- **WHEN** the wrap option is `nowrap`, the length is `12` and the agent name is `refactor-the-login-flow`
- **THEN** one line shows the first characters of the name cut to 12 characters ending in `…`

#### Scenario: No wrapping

- **WHEN** the wrap option is `nowrap`, the length is unset and the agent name does not fit
- **THEN** one line shows the name cut to the sidebar width, ending in `…`

#### Scenario: Length with wrapping

- **WHEN** wrapping is on, the length is `30` and the agent name is `refactor-the-login-flow-and-more-words`
- **THEN** the name is cut to `refactor-the-login-flow-and-mo…` and wraps over two lines at 28 columns

#### Scenario: Resize while wrapped

- **WHEN** the user drags the sidebar border to a new width
- **THEN** wrapped names are re-wrapped to the new width on the next redraw, without any agent event

### Focused agent emphasis

The sidebar SHALL emphasise the focused agent's name for the client viewing it, in the style set by `@tmux-orchestrator-focus-style`: `underlined` (the default), `bold`, or `none`. Any other value MUST behave like `underlined`. The style MUST apply on the next redraw without a reload, and to every line of a wrapped name. Other agents' names MUST NOT be emphasised, and no extra marker column is added.

#### Scenario: Focused Claude agent

- **WHEN** the client views a pane holding one Claude agent and the option is unset
- **THEN** that agent's name is underlined in that client's sidebar

#### Scenario: Focused OpenCode tab

- **WHEN** the client views an OpenCode pane whose active tab is `docs`
- **THEN** only the `docs` agent's name is emphasised, not the other tabs of that pane

#### Scenario: Two clients

- **WHEN** two clients view different agent panes of the same session
- **THEN** each client's sidebar emphasises its own focused agent

#### Scenario: Bold style

- **WHEN** `@tmux-orchestrator-focus-style` is set to `bold`
- **THEN** the focused agent's name is bold and not underlined, without a reload

#### Scenario: No emphasis

- **WHEN** `@tmux-orchestrator-focus-style` is `none`
- **THEN** the focused agent's name looks like any other agent's name

### Next agent key

When `@tmux-orchestrator-next-agent-key` is set, the system SHALL bind that key in the tmux key table named by `@tmux-orchestrator-next-agent-table` (`prefix` by default; `root` binds it without the prefix). Without the key option it MUST NOT bind anything. Like the toggle key, it MUST NOT overwrite a binding it did not create, and a reload MUST remove its earlier binding of another key or table.

Pressing the key SHALL bring the user to another agent, across all tmux sessions, from one list: agents that need attention first (`blocked`, then `error`, then `done`, and within each state the one whose state time is longest), then every other agent in sidebar order. The first agent that became `blocked`, `error` or `done` after the previous press SHALL be chosen; otherwise the agent after the one the pressing client views, wrapping after the last, or the first when the client views none. The time of each press SHALL be stored in `@tmux-orchestrator-next-agent-at`. The client brought to the agent SHALL be one already showing the agent's window, else one attached to the agent's tmux session, else the pressing client, and the system SHALL then run `@tmux-orchestrator-raise-command` as for a notification click. With no agents, the pressing client SHALL show `No agents`.

#### Scenario: Agent in another terminal window

- **WHEN** the user presses the key in one terminal window and the most urgent agent's tmux session is attached in another terminal window
- **THEN** that other client switches to the agent, and the raise command brings its window forward

#### Scenario: Going through every agent

- **WHEN** one agent is `blocked`, one in `error`, one `done` and two are `idle`, and the user keeps pressing the key from the client showing the previous agent
- **THEN** the user visits the `blocked`, `error` and `done` agents, then the `idle` ones, then starts over

#### Scenario: New urgent agent during a lap

- **WHEN** the user is going through the `idle` agents and another agent becomes `blocked`
- **THEN** the next press goes to that agent, and the press after it continues the lap

#### Scenario: Known urgent agent does not pin the user

- **WHEN** an agent stays `blocked` while the user presses the key from an `idle` agent
- **THEN** the key goes on to the next `idle` agent, and reaches the `blocked` one again when the lap wraps

#### Scenario: Agent in a detached session

- **WHEN** no client is attached to the agent's tmux session
- **THEN** the pressing client switches to it

#### Scenario: Key already taken

- **WHEN** `M-a` is already bound in the root table by the user and the next agent key is set to `M-a` in `root`
- **THEN** the user's binding stays and the next agent key is not bound

### Keys panel

The sidebar SHALL start with a right-aligned row holding a clickable `? keys` entry that opens and closes the keys panel for all clients. The open panel MUST list the toggle key and every tmux key binding whose command calls the reporter, with its key table, key and reporter subcommand, read when the panel opens. It MUST NOT list fixed mouse actions or tmux's own border actions.

#### Scenario: Open the panel

- **WHEN** the user clicks `? keys` while the panel is closed
- **THEN** every client's sidebar shows the keys panel listing `prefix O` for the toggle

#### Scenario: Close the panel

- **WHEN** the user clicks `? keys` while the panel is open
- **THEN** the panel closes for every client

#### Scenario: User binding discovered

- **WHEN** the user has bound `prefix N` to run the reporter's `notify pause` and then opens the panel
- **THEN** the panel lists `prefix N` with `notify pause`

#### Scenario: Binding added after load

- **WHEN** the user adds a binding that calls the reporter after the plugin loaded, then closes and reopens the panel
- **THEN** the new binding is listed without reloading the plugin

#### Scenario: Toggle key skipped

- **WHEN** the toggle key was not bound because of a conflicting user binding
- **THEN** the panel does not list a toggle key

### Options panel

The sidebar SHALL show a clickable `≡ options` entry left of `? keys` that opens and closes the options panel for all clients. Opening one of the two panels MUST close the other. The panel SHALL list the options of `lib/options-panel` under group headings, each on a line with its label and its current value, `none` or the default when unset:

| Group | Line | Option `@tmux-orchestrator-…` | Click on the value |
|---|---|---|---|
| sidebar | `side` | `side` | `left`, `right` |
| sidebar | `width` | `width` | prompt, a number of at least 10 |
| sidebar | `state time` | `time` | `on`, `off` |
| sidebar | `time on view` | `time-on-view` | `keep`, `reset` |
| sidebar | `wrap agent names` | `name-wrap` | `wrap`, `nowrap` |
| sidebar | `agent names length` | `name-max-chars` | prompt, a number of at least 1 |
| sidebar | `focused style` | `focus-style` | `underlined`, `bold`, `none` |
| notifications | `desktop` | `notify-desktop` | `on`, `off` |
| notifications | `terminal` | `notify-terminal` | `off`, `on` |
| notifications | `paused` | `notify-paused` | `off`, `on` |
| notifications | `desktop timeout` | `notify-timeout` | prompt, a number of at least 1 |
| notifications | `raise command` | `raise-command` | prompt, any text |
| keys | `sidebar toggle` | `toggle-key` | prompt, one key name |
| keys | `next agent` | `next-agent-key` | prompt, one key name |
| keys | `next agent table` | `next-agent-table` | prompt, any text |
| tmux | `window names` | `window-name` | `on`, `force`, `off` |
| tmux | `focus events` | `focus-events` | `on`, `off` |

Clicking a value with a list SHALL set the option's next value; a value outside the list MUST go to the first value. Clicking a value with a prompt SHALL ask the clicking client for a new value, prefilled with the current one: an empty answer MUST unset the option, and an answer that is not valid MUST change nothing and show the reason. The answer MUST reach the option unchanged, like rename answers. Every change SHALL apply at once: an option read only at plugin load SHALL make the plugin loader run again. The panel MUST NOT write any file: a reload of the tmux configuration or a tmux restart brings back the configured values.

Clicking a label SHALL open that option's description under its line, with the underlying tmux option, and close the one open before; clicking it again SHALL close it. The description MUST wrap at spaces to the current sidebar width, following a border drag.

#### Scenario: Short window

- **WHEN** the options panel is open with a description and the sidebar is taller than the window
- **THEN** the options row and the panel are shown in full and the end of the agent list is cut

#### Scenario: Open the options panel

- **WHEN** the user clicks `≡ options` while the keys panel is open
- **THEN** the keys panel closes and every client's sidebar shows the options panel

#### Scenario: Toggle a boolean

- **WHEN** `@tmux-orchestrator-time` is unset and the user clicks the value of the `state time` line
- **THEN** the option becomes `off`, the line shows `off` and the state time disappears

#### Scenario: Cycle a list

- **WHEN** the window names value is `force` and the user clicks it
- **THEN** the option becomes `off` and window names show the user's format again, without reloading the plugin

#### Scenario: Value outside the list

- **WHEN** `@tmux-orchestrator-focus-style` is `banana` and the user clicks its value
- **THEN** the line showed `banana` and the option becomes `underlined`

#### Scenario: Prompt

- **WHEN** the user clicks the desktop timeout value and answers `9`
- **THEN** `@tmux-orchestrator-notify-timeout` is `9`

#### Scenario: Invalid answer

- **WHEN** the user answers `5` to the width prompt
- **THEN** the width stays as it was and tmux shows that it must be at least 10

#### Scenario: Empty answer

- **WHEN** the user clears the next agent key prompt and presses Enter
- **THEN** the option is unset, the plugin loader runs again and the next agent key is no longer bound

#### Scenario: Description

- **WHEN** the user clicks the `wrap agent names` label
- **THEN** the description of `wrap agent names` shows under its line wrapped to the sidebar width, followed by `@tmux-orchestrator-name-wrap`, and a second click closes it

#### Scenario: Restart

- **WHEN** the user turned `desktop` off from the panel and tmux restarts with a configuration that does not set it
- **THEN** desktop notifications are on again

### Toggle key does not overwrite user bindings

The plugin SHALL bind the toggle key only when that key has no binding in the prefix table or is already bound to the plugin's toggle. Otherwise it MUST leave the existing binding in place and show a message naming the key once per plugin load. On load, the plugin MUST remove its own toggle binding from any other prefix key.

#### Scenario: Key already used by the user

- **WHEN** the user's configuration binds `prefix O` to another command before the plugin loads
- **THEN** `prefix O` keeps the user's command and tmux shows a message that the toggle key was not bound

#### Scenario: Plugin reloaded

- **WHEN** the plugin loads again with the same toggle key
- **THEN** the toggle binding is refreshed and no message is shown

#### Scenario: Toggle key changed

- **WHEN** the toggle key changes from `O` to `T` and the plugin reloads
- **THEN** `prefix T` toggles the sidebar and `prefix O` no longer has the plugin's binding

### Rename from the sidebar

Double-clicking a session row SHALL open a prompt that renames that tmux session. Double-clicking an agent row SHALL open a prompt prefilled with the agent name, and the answer SHALL rename the agent session in its agent. An empty answer MUST change nothing. The double-click binding MUST NOT be listed in the keys panel.

#### Scenario: Rename a session

- **WHEN** the user double-clicks the `alpha` session row and enters `api`
- **THEN** the tmux session is renamed `api` and its row shows `api`

#### Scenario: Rename an agent

- **WHEN** the user double-clicks an agent row and enters `it's "$HOME"`
- **THEN** the agent session is renamed `it's "$HOME"` in its agent, and the row shows that name

### Rename answers are literal

A rename answer MUST reach tmux or the agent unchanged, whatever characters it holds, and MUST NOT pass through a shell.

#### Scenario: Special characters

- **WHEN** the user enters `it's "$HOME" ~ #1, ok; \x`
- **THEN** the new name is exactly that text

### Rename failures are visible

A rename the agent does not confirm MUST show the reason to the client and MUST leave the agent name unchanged.

#### Scenario: Agent does not confirm

- **WHEN** the agent does not confirm the rename
- **THEN** tmux shows a message with the reason and the row keeps the old name

### Window names follow the agent

The plugin SHALL replace every `#{pane_current_command}` in the global `automatic-rename-format` with a format that shows the agent name of the pane, cut to 20 characters, and the pane's command when the pane has no agent. For an OpenCode pane the agent is the one in its active tab. The rest of the format MUST be kept, and a format without `#{pane_current_command}` MUST stay unchanged. Reloading the plugin MUST NOT apply the replacement twice. With `@tmux-orchestrator-window-name` set to `force`, the plugin SHALL instead show the agent name in place of the whole format, so a format without `#{pane_current_command}` names agent windows too. With it set to `off`, the plugin SHALL give the user's format back. A format set after the plugin loaded is the user's format. The name MUST be escaped like the sidebar's (Name safety). A change of `@tmux-orchestrator-window-name` from the options panel SHALL apply at once. Window-level `automatic-rename-format` values and windows with `automatic-rename` off are not changed.

#### Scenario: Default format

- **WHEN** the format is tmux's default and the window's active pane runs the agent `fix-login`
- **THEN** the window is named `fix-login`, and `[tmux]` while that pane is in copy mode

#### Scenario: Long name

- **WHEN** the agent name is `a-very-long-agent-name-here`
- **THEN** the window is named `a-very-long-agent-na`

#### Scenario: No agent

- **WHEN** the window's active pane runs `bash` and no agent
- **THEN** the window is named `bash`

#### Scenario: Custom format

- **WHEN** the format is `#{pane_current_command}:#{b:pane_current_path}`
- **THEN** the agent name replaces the command and `:` with the directory follows it

#### Scenario: Format without the command

- **WHEN** the format is `#{b:pane_current_path}`
- **THEN** the plugin leaves it unchanged

#### Scenario: Reload

- **WHEN** the plugin loads twice
- **THEN** the format holds the replacement once

#### Scenario: Forced

- **WHEN** `@tmux-orchestrator-window-name` is `force`, the format is `#{b:pane_current_path}` and the active pane runs the agent `fix-login`
- **THEN** the window is named `fix-login`, also in copy mode, and the directory name when the pane has no agent

#### Scenario: Turned off

- **WHEN** `@tmux-orchestrator-window-name` is `off` and the plugin reloads
- **THEN** the format is the user's format again

#### Scenario: Agent renamed

- **WHEN** the agent is renamed from the sidebar or inside the agent
- **THEN** the window takes the new name the next time the pane draws

### Subagent indicator

While a Claude Code agent has live subagents, its row SHALL show its main thread's state icon, then the icon of the most urgent state among its subagents followed by their count. The first line of the name MUST give up the columns the indicator takes, and wrapped lines MUST continue where it stops. Without subagents, the row SHALL show one icon for the agent's state.

#### Scenario: Main thread done, subagent working

- **WHEN** a Claude agent's main thread has finished and one background subagent is working
- **THEN** its row starts with `✓ ●1`

#### Scenario: A subagent waits for the user

- **WHEN** one subagent works and another waits for a permission
- **THEN** the subagent icon is the blocked icon and the count is 2

#### Scenario: Main thread done, subagent waiting on a background task

- **WHEN** a Claude agent's main thread has finished and its only subagent waits on its own background command
- **THEN** its row starts with `✓ ○1`

### Background task indicator

While a Claude Code agent has background tasks, its row SHALL show, after its state icon and any subagent indicator, a blue `·` followed by the number of tasks. The first line of the name MUST give up the columns the indicator takes. Without background tasks, the row SHALL show no task indicator.

#### Scenario: Main thread done, subagent working, two tasks

- **WHEN** a Claude agent's main thread has finished, one subagent works and two background tasks run
- **THEN** its row starts with `✓ ●1 ·2`

#### Scenario: Tasks without subagents

- **WHEN** a `done` Claude agent has one background task and no subagents
- **THEN** its row starts with `✓ ·1` and the agent stays `done`

## 5. Notifications

Defines when an agent state change produces a notification, what the notification says, which channels deliver it, and how a user pauses delivery without losing state tracking.

### Attention-only triggers

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

### Notification content

The desktop and terminal notifications SHALL contain the state icon and the text `Agent <state>: <name>`, such as `◉ Agent blocked: fix-login`. Notifications MUST NOT contain agent kind or tmux session, window, or pane information.

#### Scenario: Blocked agent

- **WHEN** the agent named `fix-login` enters `blocked`
- **THEN** the desktop and terminal summary is `◉ Agent blocked: fix-login`

#### Scenario: Done agent

- **WHEN** the agent named `fix-login` enters `done`
- **THEN** the desktop and terminal summary is `✓ Agent done: fix-login`

#### Scenario: Error agent

- **WHEN** the agent named `fix-login` enters `error`
- **THEN** the desktop and terminal summary is `× Agent error: fix-login`

#### Scenario: Hostile name

- **WHEN** an agent name contains `#[` or a newline
- **THEN** the notification shows the literal text, with the newline as a space

### Viewing suppression

The system SHALL skip the desktop and terminal notifications if any attached client is viewing the agent that changed. A client views an agent when the agent's pane is the client's active pane and, for an OpenCode agent, its tab is the active tab. With tmux's `focus-events` on, a client views an agent only while its terminal window has focus, as tmux's `focused` client flag reports; with it off, the system cannot tell and treats every client as focused.

#### Scenario: One client views the agent

- **WHEN** an agent changes state while one client has its pane active and another does not
- **THEN** no desktop or terminal notification is sent

#### Scenario: No client views the agent

- **WHEN** an agent changes state and no attached client has its pane active
- **THEN** the enabled desktop and terminal notifications are sent

#### Scenario: Focus events turned on

- **WHEN** the plugin loads and `@tmux-orchestrator-focus-events` is not `off`
- **THEN** it sets tmux's `focus-events` to `on`

#### Scenario: Focus events left off

- **WHEN** the plugin loads with `@tmux-orchestrator-focus-events` set to `off` and `focus-events` not `on`
- **THEN** it shows a tmux message that agents in a background terminal window do not notify, and `notify status` reports `focus-events: off`

#### Scenario: Terminal window in the background

- **WHEN** `focus-events` is on and the only client with the agent's pane active is in a terminal window without focus
- **THEN** the enabled desktop and terminal notifications are sent

#### Scenario: Background OpenCode tab

- **WHEN** an OpenCode agent on a background tab becomes `blocked` while a client has its pane active
- **THEN** the enabled desktop and terminal notifications are sent

#### Scenario: No clients attached

- **WHEN** an agent changes state with no clients attached
- **THEN** no terminal sequence is possible and the desktop notification is still sent when enabled

### Deduplication

The system MUST suppress notifications for unchanged consecutive states, with no cooldown between real transitions.

#### Scenario: Repeated state

- **WHEN** an agent reports `done` again without leaving `done`
- **THEN** no channel produces a notification

#### Scenario: Rapid completion

- **WHEN** an agent enters `done`, returns to `working`, and enters `done` again within 2 seconds
- **THEN** both `done` transitions notify

### No tmux message

The system MUST NOT show agent notifications as tmux messages (`display-message`) and MUST ignore `@tmux-orchestrator-notify-tmux`. The sidebar shows the same state change for as long as it lasts.

#### Scenario: Client on another pane

- **WHEN** an agent enters `blocked` while a client shows another pane
- **THEN** that client's status line does not change and the enabled desktop and terminal notifications are sent

### Global pause

The system SHALL provide `notify pause`, `notify resume`, `notify toggle`, and `notify status`. Pause MUST be global, indefinite, and idempotent, and MUST suppress notifications on all channels while state tracking and the sidebar continue.

#### Scenario: Pause

- **WHEN** the user runs `notify pause`
- **THEN** subsequent attention transitions produce no notification and states continue to update

#### Scenario: Resume

- **WHEN** the user runs `notify resume`
- **THEN** subsequent attention transitions notify again

#### Scenario: Toggle

- **WHEN** the user runs `notify toggle`
- **THEN** a paused state becomes active and an active state becomes paused

#### Scenario: Repeated pause

- **WHEN** the user runs `notify pause` while already paused
- **THEN** the command succeeds and the paused state is unchanged

#### Scenario: Pause survives reload

- **WHEN** the plugin is reloaded or a client detaches while paused
- **THEN** notifications remain paused

#### Scenario: Pause does not change the view

- **WHEN** notifications are paused
- **THEN** the sidebar continues to show current states and does not add a pause indicator

### Notification status

`notify status` SHALL report whether delivery is paused, the setting of each channel, and whether desktop delivery is available.

#### Scenario: Status while paused

- **WHEN** notifications are paused
- **THEN** the output includes `notifications: paused`

#### Scenario: Status while off

- **WHEN** both channel options are `off`
- **THEN** the output includes `notifications: off`

#### Scenario: Status with defaults

- **WHEN** no channel option is set and notifications are not paused
- **THEN** the output includes `notifications: active`, `desktop: on`, and `terminal: off`

#### Scenario: Status without desktop

- **WHEN** the desktop channel is `on` and no desktop command exists
- **THEN** the output indicates that desktop delivery is unavailable

### No default key binding

The system MUST NOT bind a key for notification pause by default. The README MUST show how to bind `notify pause` and `notify resume` in tmux.

#### Scenario: Fresh install

- **WHEN** the plugin loads without user configuration
- **THEN** no notification-control key is bound

#### Scenario: Documented binding

- **WHEN** the user follows the README binding example
- **THEN** the documented tmux command runs `notify pause` or `notify resume`

### Delivery failure isolation

A failed or unavailable notification channel MUST NOT change agent state, block the reporting path, or prevent the other channels from delivering.

#### Scenario: Desktop command fails

- **WHEN** the desktop command exits nonzero
- **THEN** the state is already recorded and terminal delivery is unaffected

#### Scenario: No tmux clients

- **WHEN** no client is attached
- **THEN** the reporter sends no terminal sequence and exits successfully

#### Scenario: Terminal not writable

- **WHEN** the terminal channel is `on` and the most recently active client's tty cannot be written
- **THEN** no OSC 9 sequence is sent and the other channels deliver normally

### Per-channel notification options

The system SHALL provide one global option per notification channel, each accepting `on` or `off`: `@tmux-orchestrator-notify-desktop` (`notify-send` or `osascript`, default `on`), and `@tmux-orchestrator-notify-terminal` (an OSC 9 sequence to the terminal of the most recently active client, default `off`). A missing or unrecognised value MUST mean the channel's default. Each channel MUST be delivered independently of the others.

#### Scenario: Defaults

- **WHEN** neither option is set and a supported desktop command exists
- **THEN** each notification is delivered to the desktop notifier, and no OSC 9 sequence is written

#### Scenario: Desktop unavailable

- **WHEN** the desktop channel is `on` and neither `notify-send` nor `osascript` exists
- **THEN** the desktop channel delivers nothing and the other enabled channels still deliver

#### Scenario: Terminal only

- **WHEN** the desktop channel is `off` and the terminal channel is `on`
- **THEN** each notification is delivered only as an OSC 9 sequence

#### Scenario: All channels off

- **WHEN** both options are `off`
- **THEN** no notification is delivered and state tracking continues

#### Scenario: Unrecognised value

- **WHEN** `@tmux-orchestrator-notify-terminal` is set to `yes`
- **THEN** the terminal channel uses its default and stays off

### Focus from a desktop notification

A `notify-send` notification SHALL carry a default action, and clicking it SHALL bring one tmux client to the agent's pane, and for an OpenCode agent to its tab. The client SHALL be the one already showing the agent's window, else one attached to the agent's tmux session, else the most recently active one, never a control-mode client. After that, the system SHALL run the shell command in `@tmux-orchestrator-raise-command`, if set, with `TMUX_ORCHESTRATOR_PANE`, `TMUX_ORCHESTRATOR_SESSION`, `TMUX_ORCHESTRATOR_CLIENT`, `TMUX_ORCHESTRATOR_CLIENT_PID` and `TMUX_ORCHESTRATOR_CLIENT_TTY` in its environment, so it can raise the terminal window. Waiting for the click MUST NOT delay the reporter. The notification SHALL ask the daemon to close it after `@tmux-orchestrator-notify-timeout` seconds, 5 when the option is unset or not a positive whole number, and the wait MUST end at the same time, after which a click does nothing. `tmux-orchestrator focus-agent --pane ID [--session-id ID]` SHALL do the same as a click.

While an agent's previous `notify-send` notification is still open, the next one for that agent SHALL replace it instead of adding another, so each agent shows at most one notification. A click on the replaced notification SHALL focus the agent once.

#### Scenario: Agent notifies again while its notification is open

- **WHEN** `fix-login` enters `done`, and enters `blocked` while `✓ Agent done: fix-login` is still shown
- **THEN** `◉ Agent blocked: fix-login` takes the place of the `done` notification

#### Scenario: Previous notification gone

- **WHEN** the agent's previous notification expired, was dismissed or was clicked
- **THEN** the next notification is a new one

#### Scenario: Other agents

- **WHEN** two agents notify while both notifications are open
- **THEN** both are shown

#### Scenario: Click on a blocked agent

- **WHEN** the user clicks the notification `◉ Agent blocked: fix-login` while a client in the same tmux session shows another window
- **THEN** that client switches to the agent's pane and the notify command runs with that client's pid and tty

#### Scenario: Client elsewhere

- **WHEN** the only client is attached to another tmux session and the user clicks the notification
- **THEN** that client switches to the agent's session, window and pane

#### Scenario: Notification dismissed

- **WHEN** the user dismisses the notification or it expires
- **THEN** no client moves and the notify command does not run

#### Scenario: Notification timeout

- **WHEN** `@tmux-orchestrator-notify-timeout` is `12`
- **THEN** `notify-send` is asked to close the notification after 12 seconds, and a click after that does nothing

#### Scenario: Default notification timeout

- **WHEN** `@tmux-orchestrator-notify-timeout` is unset or `soon`
- **THEN** the notification closes after 5 seconds

#### Scenario: macOS

- **WHEN** the desktop command is `osascript`
- **THEN** the notification has no action and clicking it does nothing

## 6. Decisions

### D1. Agent state comes from lifecycle events, not screen scraping

Claude Code and OpenCode both expose lifecycle events. We report state from Claude Code hooks and an OpenCode plugin only, and do not parse pane contents. Screen parsing was rejected as a second, version-fragile source of truth that duplicates what the agents already emit.

**Consequences**

- Claude waiting at a login prompt is invisible; a hard crash can leave a stale state. Both are accepted in v1.
- Any future screen parsing is a fallback for a named gap, never a second authority.
- The same state vocabulary must fit both agents: `working`, `blocked`, `done`, `idle`, `error`, `unknown`.

### D2. The persistent area is the tmux side status line

The sidebar is drawn with tmux's `side-status`, not a real pane. Panes belong to one window, so a pane-based sidebar cannot stay visible across windows and sessions, cannot be seen by two clients viewing different windows, and would mutate every window layout. `side-status` is per-client chrome: always visible, mouse-clickable, and free of layout side effects.

**Considered options**

- **A real pane moved between windows.** Rejected: one window at a time, layout churn, breaks zoom and splits, fights multi-client use.
- **A popup console.** Deferred: focusable and scrollable, but modal, so it complements the sidebar rather than replacing it.
- **The normal status line with extra rows.** Rejected: horizontal and cramped; the sidebar is vertical.

**Consequences**

- v1 requires tmux next-3.9; `side-status` is absent from 3.8 and earlier. The installer must refuse older tmux loudly.
- The sidebar cannot take keyboard focus or scroll. Navigation is mouse plus global key bindings; overflow is handled by `list=focus`.
- Agent state lives in tmux user options on the pane, so a future console or pane-based view can read the same store.

### D3. The OpenCode adapter runs in the TUI, not the server

OpenCode 2.x runs every terminal TUI against one shared background service, and server plugins run inside that service. The service inherits `TMUX_PANE` from whichever pane first started it, its event stream covers every TUI and project, and only the TUI knows its tabs and which one is active. We therefore install the OpenCode adapter as a TUI plugin, which runs in the agent pane's own process and can map events, tabs and focus to that pane.

**Considered options**

- **A server plugin.** Rejected: it cannot tell which pane or tab an event belongs to, so it reports to a stale pane or to none.
- **A server plugin plus a TUI plugin.** Rejected: the TUI already receives the events the adapter needs, so a server half adds a second process without information.

**Consequences**

- The adapter is installed as `~/.config/opencode/plugins/tmux-orchestrator/tui.js`, which OpenCode discovers without editing `opencode.json` or `cli.json`.
- OpenCode 1.x is not supported; v1 plugins do not run in 2.x.
- Closing a tab fires no event, so the adapter detects tab changes by comparing `ui.tabs.list()` over time.
- A sidebar click focuses a tab through a Unix socket that the TUI plugin opens per pane, because no OpenCode command targets a single TUI.

### D4. Sidebar agent rows use fixed slots per pane

An agent pane can host several agents, one per OpenCode tab, but a tmux format can loop over sessions, windows and panes, not over anything inside a pane. We store each agent in a numbered slot of pane options (`@agent_1_*` to `@agent_9_*`) and build the sidebar format at load time by repeating one row fragment per slot. Data stays in options and style stays in the format, so names keep today's single escaping and the format keeps truncating them to the live sidebar width.

**Considered options**

- **One row per pane, rolling up its tabs.** Rejected: a blocked background tab would be hidden behind the active tab's name, and clicking could not focus the tab that needs attention.
- **Row templates.** The reporter writes each pane's rows as one format string and the sidebar expands it with `#{E:...}`. This allows any number of tabs and the shortest format. Rejected because names would need escaping for two passes (storing and expanding), so a tab title such as `#{pane_id}` becomes an injection risk. Also, truncating to the live, drag-resized width works on options and was not shown to work on literal text, and the rows become hard to read in `show-options`.
- **A render script in the format (`#(...)`).** Rejected: tmux runs it per client every `status-interval`, so updates lag, and its cached output makes per-client markers such as the current-session `▸` and `list=focus` awkward.

**Consequences**

- At most nine agents per pane get their own row. Nine is our choice, not a tmux limit; it keeps the generated format short and row IDs within tmux's 15-byte limit for `range=user` (for example `%12:3`). Raising it means changing one number.
- Agents beyond the ninth collapse into one `+N more` row that shows their rolled-up state with the session rollup priority. Clicking it selects the pane.
- Closing a tab shifts the later slots down by one.
- Glyphs and colours live in the format fragment, so a later feature can read them from options such as `@tmux-orchestrator-icon-blocked` and apply changes on the next redraw without the reporter.

### D5. Adapters forward agent events; one module owns their meaning

Agent state rules were split between the OpenCode plugin and several reporter functions, and the rule that an error survives a later completion existed twice. We now have each adapter forward agent events as its agent kind names them, with details such as `tool_name` or the error type. One agent state module holds the per-kind mapping tables, the transition rules and the notification decision. This keeps every rule in one place, tested without tmux, and loses no detail before the module sees it.

**Considered options**

- **Adapters translate to a small shared set of lifecycle events.** Rejected: it drops per-kind detail, such as telling `AskUserQuestion` apart from other tool calls, and spreads the mapping across two languages.
- **Adapters send generic events plus the original name as a label.** Rejected: the label carries the detail, but the mapping still lives in the adapters.
- **Adapters keep reporting final states.** Rejected: this is the split that caused the duplicated rules.

**Consequences**

- Each adapter keeps only what needs its own process: the Claude adapter parses the hook payload and filters subagents, and the OpenCode adapter maps child sessions to their root and tracks tabs. The reporter contains no payload parsing for any agent kind.
- The OpenCode adapter forwards only an allowlist of event names, because each forwarded event starts a reporter process and OpenCode emits many events per second. The meaning of each event stays in the module.
- Whether a completion counts as `done` is derived from the previous state, not from per-process flags. A Claude `Stop` with no activity since the agent started now shows `idle` instead of `done`.
- The last agent event is stored in `@agent_event` for diagnosis and is not shown in the sidebar.
- The OpenCode adapter calls the reporter one event at a time, so events cannot be applied out of order.

### D6. Claude interrupts are read from the session status

Claude Code sends no hook when the user interrupts a turn, and the `idle_prompt` notification does not fire after an interrupt either, so an interrupted agent would show `working` until its next prompt. Claude Code keeps each running session's `status` (`busy`, `waiting`, `idle`, or `shell` when it is idle with background shells running) in its session registry, the same one D9 uses, and `claude agents --json` documents the field. In every test it turned `idle` within a second of Esc, for a tool call and for text. While a turn runs, a watcher reads that status every 2 seconds and reports an interrupt after two `idle` or `shell` readings in a row while the agent is still `working` or `blocked`. This is a fallback for a named gap, as D1 allows.

**Considered options**

- **The `[Request interrupted by user` transcript entry.** Used first, then rejected: on Claude Code 2.1.311 an interrupt while Claude writes text leaves no entry, and on a session's first prompt the transcript does not exist yet when the `UserPromptSubmit` hook runs.
- **Poll `claude agents --json`.** Rejected: it is the documented source, but each call takes about 240 ms, every 2 seconds for each busy agent. The registry file is read with one `jq` call.
- **Report an interrupt on the first `idle` reading.** Rejected: a completed turn goes `idle` just before its `Stop` hook arrives, and the agent would show `idle` instead of `done`.
- **Check from tmux focus hooks, or read the screen with `capture-pane`.** Rejected: focus hooks change nothing until the user switches pane, and the screen is more fragile than the agent's own records.

**Consequences**

- Detection takes 2 to 4 seconds and works on the first prompt.
- The registry file and its `status` field are internal. `tests/contract/claude-test.sh` checks the field, and with `TMUX_ORCHESTRATOR_CONTRACT_TURN=1` it interrupts a Haiku turn to check detection end to end.
- A watcher ends when the agent leaves `working`/`blocked`, a new prompt starts a new watcher, or the registry entry disappears or names another session. There is no time limit: the watcher costs one `jq` call per tick.
- A pause where the main thread is `idle` while a turn is not over would read as an interrupt. None was seen in testing; `waiting` covers permission prompts and questions.

### D7. Adapters find the reporter through tmux

Claude Code installs a marketplace plugin by copying only the plugin's own directory into its cache, so the Claude adapter cannot reach the reporter by a path relative to itself. The OpenCode adapter used to carry an absolute reporter path written at install time, which went stale when the tmux plugin moved or updated. Both adapters always run inside a pane of the tmux server whose sidebar they feed. The tmux plugin therefore publishes its reporter path in the global option `@tmux-orchestrator-reporter` on every load, and adapters read it from there. The tmux plugin copy that is loaded owns the only reporter.

**Considered options**

- **A path relative to the adapter.** Rejected: it works only from a git checkout, never from the marketplace cache.
- **A path written at install time.** Rejected: it goes stale on every update or switch between a TPM clone and a checkout.
- **A copy of the reporter inside each adapter.** Rejected: two reporters drift apart, and only the tmux copy can install the sidebar format.
- **A system package that puts the reporter on `PATH`.** Deferred: it needs packaging per platform. Adapters keep `PATH` as a fallback so it can be added later.

**Consequences**

- Each Claude hook makes one extra tmux call, about 2 ms.
- Reloading tmux with another copy of the plugin switches every adapter on its next event, without restarting agents.
- The OpenCode adapter is installed as a link to the loaded copy, so updating the tmux plugin updates it.
- An adapter can be newer than the reporter. A report protocol version turns that into a visible message instead of silent failure.

### D8. Agent names wrap in the sidebar format

Long agent names wrap over several lines inside `side-status-format`, not in the reporter. Each line of a slot cuts the next piece of the name with a regex offset computed from the live `side-status-width` (`#{s/^#{=/W:@dots}//:name}`, then `#{=/W:...}`). Wrapping therefore follows a border drag on the next redraw, with no event and no reporter run, which D4 also relies on for truncation.

**Considered options**

- **The reporter writes the wrapped lines into slot options.** Rejected: the reporter does not run when the sidebar is resized, so lines would stay wrapped to a stale width until the agent's next event.
- **A render script in the format (`#(...)`).** Rejected for the reasons in D4.

**Consequences**

- A format cannot loop over characters, so every possible line is written into each slot in advance. Names wrap over at most 4 lines and end in `…` past that. Each line is conditional, so a short name uses only the lines it needs.
- Offsets count characters, not display columns. A name with wide characters (CJK, emoji) can overflow a line by a few columns.
- Nine slots with four name lines each exceed tmux's command size limit, so each slot's row is set as a global option (`@tmux-orchestrator-row-N`) and the format expands it with `#{E:...}`. These options hold only the static fragment. Agent names are still read from pane options with single escaping, so the injection concern of D4's row templates does not apply.
- Raising the cap means adding one more line fragment to each slot's option.

### D9. Claude agents are renamed through their messaging socket

Renaming an agent from the sidebar should rename it in the agent itself, so other agents and `claude agents` see the same name. Claude Code has no documented way to rename a running session from another process: `-n` only applies at start and `/rename` must be typed. Each running session does listen on a messaging socket listed in its session registry entry (`~/.claude/sessions/<pid>.json`, field `messagingSocketPath`). A `{"type":"control","action":"rename","name":"…"}` line on that socket renames the session; `claude agents` sends it for Ctrl+R. On Linux and macOS the socket's `0600` mode is its only guard, so the reporter can send it. We use it, and a rename counts only once the registry shows the new name; otherwise the rename fails with a message and the sidebar keeps the old name.

**Considered options**

- **Type `/rename` into the pane with `send-keys`.** Rejected: it works only when the prompt is idle and empty, and it would overwrite what the user is typing.
- **Show a sidebar-only label.** Rejected: the sidebar would disagree with the agent and with other agents, and a silently diverging name is worse than a visible failure.
- **Fall back to a sidebar-only label when the message fails.** Rejected for the same reason: a Claude update that drops the message must be noticed.

**Consequences**

- The control message and the registry fields are internal to Claude Code and can change in any release. `tests/contract/claude-test.sh` starts a real Claude and checks them, with `claude agents --json` and `pane_current_command`; run it after updating Claude Code.
- Other agents cannot message a renamed agent by its old name: in Claude Code 2.1.311 the send fails with "No agent named … is reachable". `ListAgents` shows the old name next to the new one ("says it was … until … ago") for ten minutes, and only for a name held at least ten seconds that Claude did not generate itself.
- OpenCode needs no internal path: its adapter renames through the plugin API (`api.client.session.update`), and `tests/contract/opencode-test.sh` checks it against a real OpenCode TUI.
- Windows would need the session's auth token; the plugin does not run there.

### D10. The terminal window is raised through a user command

Clicking a desktop notification, or pressing the next agent key, should show the agent, often in another terminal window. tmux can switch a client to the agent's pane, but it cannot raise the terminal window that runs the client, and how to do that depends on the compositor or window manager. The reporter therefore does the tmux part and hands the window part to a user command, `@tmux-orchestrator-raise-command`, with the client's pid and tty. `examples/raise-command-niri.sh` does it for niri.

**Considered options**

- **Raise the window in the reporter for known compositors.** Rejected: one code path per compositor, none of them testable here.
- **An XDG activation token from `notify-send --activation-token-fd`.** Rejected: only the terminal itself can use the token, and the reporter cannot pass it to the terminal.

**Consequences**

- `notify-send` runs in the background with `--wait` semantics and stays until the notification is clicked, dismissed or closed at `@tmux-orchestrator-notify-timeout`. A notification daemon that keeps notifications in a history list still shows a Focus action there after that, and it does nothing.
- Terminals that run several windows from one process (Ghostty, kitty, foot server) share one pid. The niri example tells them apart by writing a unique title to the client's tty for a moment, then restores the window's old title.

### D11. Background tasks come from the Stop hook

The sidebar shows how many background tasks a Claude agent and its subagents left running. A launch is visible: the `PostToolUse` payload carries `tool_input.run_in_background`, `agent_id`, and the task's `backgroundTaskId` in `tool_response`. Claude Code delivers each task's end to the main thread as a `UserPromptSubmit` hook whose `prompt` is a `<task-notification>` with the `<task-id>` and a `<status>`, whether the agent is idle or still working. Every `Stop` and `SubagentStop` payload carries `background_tasks` for the whole session, each with its `id`, `type` (`shell`, `monitor`, `subagent`) and `status`, but no owner. The reporter adds a task at launch, so it shows at once, removes it on its notification, and replaces the whole list from each `Stop` and `SubagentStop`, which also corrects anything a lost or late update got wrong. A subagent's task ends without a notification to the main thread, because Claude Code wakes the subagent instead, but the subagent's next `SubagentStop` lists the session's tasks. The count is the session's, not the main thread's alone, because the lists have no owner field.

**Considered options**

- **Read the task-notification Claude Code writes to the session transcript.** Built first, then rejected: the transcript format is internal, any line quoting a notification ended a task, and each event read the file. The hook's own `prompt` carries the same notification without reading any file.
- **A polling watcher per agent, as in D6.** Rejected: the notification already ends a task inside a turn, without a process per agent.

**Consequences**

- Only notifications with status `completed`, `failed` or `killed` end a task, so one that reports progress does not.
- A `Monitor` is listed by its tool-use ID until the next `Stop`, so its notification cannot end it before then.
- `Monitor`'s `PostToolUse` response has no `backgroundTaskId`, so it is listed by its tool-use ID until the next `Stop` gives its real ID.
- Two reporters for the same pane take turns through a lock directory, because parallel tool calls run their hooks at once and `flock` is missing on macOS. A lock held over about two seconds is taken over.
- A task that no `Stop` lists for six hours is dropped, so a missed end cannot keep a count forever.
- The adapter sends `--task`, `--tasks` and `--task-done` as optional report options. Older reporters skip them, so the report protocol stays at version 1.

### D12. An agent's open desktop notification is replaced by ID

Notification daemons stack one notification per call, so a busy agent leaves a pile of stale ones. `notify-send -p` prints the ID of the notification it shows, and `notify-send -r ID` replaces that notification. The waiter that `notify-send` runs for the click stores `ID TOKEN` in the pane option `@agent_notify_<session id>`, and clears it when its notification is clicked, dismissed or expires. The next notification for that agent passes `-r ID` only while the option is set.

**Considered options**

- **The `x-canonical-private-synchronous` hint keyed by the agent.** Rejected: it needs no stored state, but not every daemon honours it.
- **Keep the ID after the notification closes.** Rejected: what a daemon does with the ID of a closed notification is not specified, and a closed one no longer needs replacing.
- **A slot field such as `@agent_<i>_notify_id`.** Rejected: the waiter runs in the background and slots move when agents come and go; an option keyed by the session ID needs no move and goes away with the pane.

**Consequences**

- A replaced notification keeps its ID, so the old waiter still waits and sees a click on the new one. Only the waiter whose token is in the option acts on the click; the old one ends at its own timeout.
- An agent without a session ID gets a new notification each time.
- The macOS `osascript` channel and the terminal channel are unchanged.

### D13. No tmux message channel

Agent notifications used to appear as a tmux message, `display-message` on every client not viewing the agent. A client counts as viewing only while its terminal window has focus, so the message reached either a terminal window nobody was looking at, or a user working in another pane who could see the same change in the sidebar. It also replaced the status line for `display-time` and needed its own cooldown for `done`. The channel and `@tmux-orchestrator-notify-tmux` were removed; the sidebar is the in-tmux view, and the desktop and terminal channels reach the user elsewhere.

**Considered options**

- **Default the channel to `off`.** Rejected: it kept the cooldown and the per-slot `notified_at` state for a channel almost nobody would turn on.
- **Show the message only on clients with the sidebar hidden.** Rejected: more code for a rare case that the terminal channel already covers over SSH.

**Consequences**

- `notify status` no longer lists a `tmux` line.
- Agent slots no longer store `@agent_<i>_notified_at`.

### D14. Window names come from automatic-rename-format

Windows should be named after their agent without the user renaming them. The plugin replaces `#{pane_current_command}` in the global `automatic-rename-format` with `#{?@agent_active_name,#{=20:@agent_active_name},#{pane_current_command}}`. tmux keeps evaluating it, so the name follows the active pane, OpenCode tab switches and renames made inside the agent, and goes back to the command when the agent exits. Only the command part changes, so `[tmux]`, `[dead]` and any customisation around it stay. `force` wraps the whole format in that conditional instead, for users whose format does not show the command. The plugin records the user's format in `@tmux-orchestrator-window-name-user` and the format it set in `@tmux-orchestrator-window-name-set`. While the global format still equals the one set, a load starts again from the user's, so reloads and mode changes never apply the change twice; any other format is taken as the user's.

**Considered options**

- **`rename-window` when an agent is renamed from the sidebar.** Rejected: it turns `automatic-rename` off for that window for good, one of several agents in a window would overwrite the name, and renames made inside the agent would not follow.
- **Wrap the whole format in a conditional by default.** Rejected: an agent pane in copy mode would show the agent name instead of `[tmux]`. It is the `force` mode, for formats without the command.
- **Record only the inserted text and replace it back.** Rejected: it cannot undo `force`, whose wrapper surrounds the user's format.
- **Replace the format only when it is tmux's default.** Rejected: a customised format would never show agent names, and tmux can change its default.
- **Override `pane_current_command`.** Not possible: it is a built-in variable read from the pane's process, and user options must start with `@`.
- **Look up `@agent_<active>_name` in the format.** Not possible: tmux expands a nested `#{}` inside a variable name to text, not to a lookup. The reporter writes the active agent's name to the pane option `@agent_active_name` instead.

**Consequences**

- In `on` mode only the exact text `#{pane_current_command}` is replaced; forms with modifiers such as `#{b:pane_current_command}` keep showing the command unless the mode is `force`.
- tmux re-evaluates the name only when the pane changes, so a rename shows once the agent next draws.
- The name is stored with `#` doubled, because tmux reads `#[` in a window name as a style in the status line. `#{window_name}` printed outside a status line shows `##`.
- A window renamed by hand has `automatic-rename` off and keeps its name.

### D15. The options panel changes tmux options until restart

The options panel lets the user change live options with a click. A click sets the global tmux option the user would set in `tmux.conf`; nothing else stores it. The configuration stays the only record of chosen values, and a reload or restart brings them back.

**Considered options**

- **Write the change into `tmux.conf`.** Rejected: the plugin would have to find and edit a file the user owns, in any layout, and a stray edit breaks the user's configuration.
- **A separate state file the plugin reads on load.** Rejected: it breaks the rule that no state lives outside the tmux server (Pane state storage), and a value the user cannot see in `tmux.conf` overriding the one there would surprise.
- **Prompt for a value with `command-prompt`.** Rejected for these options: each takes a few fixed values, and a click per value is faster than typing one. Text and number options stay in `tmux.conf`.

**Consequences**

- Options read only at plugin load (side, width, keys, focus events) apply by running the plugin loader again, which is safe to repeat; the loader's own rules, such as never overwriting a user's key binding, apply unchanged. `window-name` is applied by the reporter's `window-name` command, which the plugin load also calls. OpenCode auto-install is not in the panel: turning it off only stops future links.
- The panel's lines come from `lib/options-panel`, which both the plugin loader (for the format) and the reporter (for clicks and descriptions) read.
- A label is a `range=user|d:<code>` range and a value a `range=user|o:<code>` range, so codes stay within tmux's 15-byte limit for the range argument. Clicks pass the client name, which a prompt needs.
- A double click is avoided for descriptions: tmux delivers its two single clicks first, which would change the value twice.
- Values are read in the sidebar format itself, so a click shows on the next redraw without the reporter writing the panel.

### D16. Option descriptions wrap at spaces in the format

An open option description wraps live in the sidebar format, like agent names (D8), but at spaces. Line `K` is read from `@tmux-orchestrator-info-l<K>` and the text left after it from `@tmux-orchestrator-info-r<K>`. The rest removes the longest start of the text that fits the width and ends at a space or at the end (`^.{1,W}( |$)`), or the first `W` characters of a word longer than the line (`[^ ]{W}`). The line is the text cut to its length minus the rest's length, without a trailing space. Each rest reads the previous one with `#{E:}`, so the format grows linearly with the number of lines.

**Considered options**

- **Pre-wrapped descriptions at 28 columns.** Rejected: they would not use a wider sidebar and would be cut on a narrower one.
- **The reporter wraps the text when the description opens.** Rejected: a border drag would leave it wrapped to the old width, as D8 explains for names.
- **A popup.** Rejected: it covers the pane the user is working in, while the description fits in the sidebar.
- **Take the line from a regex capture group.** Rejected: tmux's regex returned a shorter capture than the overall match, cutting lines after a comma.
- **Nest each rest inside the next.** Rejected: every step uses the text three times, so the format grows exponentially and exceeds tmux's command size.

**Consequences**

- Descriptions show at most 12 lines.
- The option name goes on fixed lines under the description, `@tmux-orchestrator-` then the rest, because wrapping would cut it mid-word.
- `name-wrap` and `name-max-chars` are separate options: cutting the name to `N` characters happens before wrapping, so the wrapped lines read the cut name.

### D17. The options and keys row is at the top of the sidebar

The `≡ options` and `? keys` entries share the sidebar's first row, and their panels open under it, above the session and agent lists. tmux cuts a side status line that is taller than the window at the bottom, and a format can neither measure the remaining height nor anchor content to the bottom. With the panels first, a short window loses the end of the agent list, never the panel the user is working in, and opening a panel or a description moves nothing else.

**Considered options**

- **Keep the row at the bottom and hide the lists while a description is open.** Rejected: the lists disappear even when there is room for them.
- **Move the row to the top only while the options panel is open.** Rejected: the row would jump, and the keys panel would keep the same risk.

**Consequences**

- Opening a panel pushes the lists down.

### D18. A subagent waiting on its background tasks stays listed

A subagent, often a fork, can launch a background command and end its turn while it runs. Claude Code fires `SubagentStop` then, keeps the subagent in its own agent list, and wakes it with a new `SubagentStart` when the command ends. The reporter records the tasks each subagent launches, so it can tell from the `background_tasks` of that `SubagentStop`, and of any later `Stop`, whether the subagent still waits. While it does, the subagent is listed as `idle`: it is not working, and it does not keep the agent `working`.

**Considered options**

- **Count a subagent's tasks in the background task indicator instead.** Rejected: the row would show a task with no subagent, which does not say that a subagent waits. The tasks are counted too, as D11 says, so the row shows both.
- **Drop the subagent at `SubagentStop`, as before.** Rejected: the sidebar then shows fewer subagents than Claude Code does.
- **Read the waiting state from the task notification's summary.** Rejected: the summary is prose meant for the model.

**Consequences**

- A subagent whose task ends without a later `Stop` or `SubagentStop` stays listed until its six-hour expiry.
- Subagent entries carry their task IDs: `id:state:tasks:time`.
