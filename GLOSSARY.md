# tmux-orchestrator

Glossary for the tmux-native agent orchestrator: a persistent view of agents running in tmux.

## Language

**Agent**:
A Claude Code or OpenCode process running in a tmux pane whose state this project tracks.
_Avoid_: worker, bot

**Agent kind**:
The product an agent belongs to: Claude Code or OpenCode.
_Avoid_: agent type, agent name

**Agent pane**:
The tmux pane an agent runs in.
_Avoid_: agent window, terminal

**Agent session**:
A conversation inside Claude Code or OpenCode, identified by its own id and name.
_Avoid_: session, conversation

**Tmux session**:
A collection of windows inside one tmux server.
_Avoid_: session

**Agent state**:
The lifecycle value shown for an agent: `working`, `blocked`, `done`, `idle`, `error`, or `unknown`.
_Avoid_: status, agent status

**Agent notification**:
A user-facing message emitted when an agent enters `blocked`, `error`, or `done`.
_Avoid_: alert (a tmux alert is a different mechanism)

**Notification channel**:
A delivery path for agent notifications: the tmux status line or the desktop.
_Avoid_: transport, backend

**Notification pause**:
A global, indefinite suppression of agent notification delivery that does not stop state tracking.
_Avoid_: mute, disable (those change channel configuration)

**Sidebar**:
The persistent vertical area drawn by tmux's side status line, listing tmux sessions and their agents.
_Avoid_: panel, sidebar pane, area
