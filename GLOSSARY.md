# tmux-orchestrator

Glossary for the tmux-native agent orchestrator: a persistent view of agents running in tmux.

## Language

**Agent**:
An agent session open in a tmux pane, whose state this project tracks. A Claude Code pane holds one agent; an OpenCode pane holds one per tab. Subagents are not agents: their activity counts toward the agent that started them.
_Avoid_: worker, bot, process

**Agent name**:
The label shown for an agent: its agent session's title, or the working-directory name when there is no title.
_Avoid_: title, label

**Focused agent**:
The agent a client is looking at: the one in the pane it views, and for OpenCode the one in that pane's active tab. At most one per client.
_Avoid_: selected agent, current agent, active agent

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

**Agent state**:
The lifecycle value shown for an agent: `working`, `blocked`, `done`, `idle`, `error`, or `unknown`.
_Avoid_: status, agent status

**Agent event**:
A lifecycle event as the agent kind itself names it, such as Claude Code's `PermissionRequest` or OpenCode's `session.idle`, together with its details. Agent state is derived from agent events, plus the user viewing the agent pane.
_Avoid_: hook, lifecycle event, normalized event

**Agent notification**:
A user-facing message emitted when an agent enters `blocked`, `error`, or `done`.
_Avoid_: alert (a tmux alert is a different mechanism)

**Notification channel**:
A delivery path for agent notifications: tmux clients, the terminal emulator, or the desktop notifier. Each is turned on or off on its own.
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
