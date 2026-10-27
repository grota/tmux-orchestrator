# Claude agents are renamed through their messaging socket

Renaming an agent from the sidebar should rename it in the agent itself, so other agents and `claude agents` see the same name. Claude Code has no documented way to rename a running session from another process: `-n` only applies at start and `/rename` must be typed. Each running session does listen on a messaging socket listed in its session registry entry (`~/.claude/sessions/<pid>.json`, field `messagingSocketPath`). A `{"type":"control","action":"rename","name":"…"}` line on that socket renames the session; `claude agents` sends it for Ctrl+R. On Linux and macOS the socket's `0600` mode is its only guard, so the reporter can send it. We use it, and a rename counts only once the registry shows the new name; otherwise the rename fails with a message and the sidebar keeps the old name.

## Considered Options

- **Type `/rename` into the pane with `send-keys`.** Rejected: it works only when the prompt is idle and empty, and it would overwrite what the user is typing.
- **Show a sidebar-only label.** Rejected: the sidebar would disagree with the agent and with other agents, and a silently diverging name is worse than a visible failure.
- **Fall back to a sidebar-only label when the message fails.** Rejected for the same reason: a Claude update that drops the message must be noticed.

## Consequences

- The control message and the registry fields are internal to Claude Code and can change in any release. `tests/contract/claude-test.sh` starts a real Claude and checks them, with `claude agents --json` and `pane_current_command`; run it after updating Claude Code.
- Other agents cannot message a renamed agent by its old name: in Claude Code 2.1.311 the send fails with "No agent named … is reachable". `ListAgents` shows the old name next to the new one ("says it was … until … ago") for ten minutes, and only for a name held at least ten seconds that Claude did not generate itself.
- OpenCode needs no internal path: its adapter renames through the plugin API (`api.client.session.update`), and `tests/contract/opencode-test.sh` checks it against a real OpenCode TUI.
- Windows would need the session's auth token; the plugin does not run there.
