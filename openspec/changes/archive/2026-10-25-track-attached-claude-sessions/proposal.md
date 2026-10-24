# Proposal

## Why

A Claude Code background session opened in a pane with `claude attach <id|name>` never appears in the sidebar. Its hooks run in Claude Code's background process, which has no `TMUX_PANE`, so the Claude adapter drops every event. Users who work through background sessions see no agent at all.

## What Changes

- The Claude adapter forwards hook events that have no `TMUX_PANE` instead of dropping them, marked as coming from a background session.
- The reporter finds the pane showing that session: a pane whose process tree runs `claude attach <arg>`, not suspended, where `<arg>` resolves to the session. If no pane shows it, the event is dropped and no notification is sent.
- `<arg>` resolves by session id prefix (which covers the short id), otherwise by a unique, case-insensitive substring of the session name from `claude agents --json`. An ambiguous or unknown argument matches nothing.
- When a pane, window or session is selected, the reporter checks the selected pane for an attach viewer. A newly attached session gets its row at once, named and in the state reported by `claude agents --json`.
- An attached agent is removed from its pane when the pane no longer runs an attach viewer for it: the viewer exited, returned to the agent view, or was suspended. This is checked on selection changes, on `pane-exited`, and when the session's next hook arrives.
- README: replace the Known limitations line for `claude attach` with how attached sessions are tracked and their limits.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `agent-integrations`: adds tracking of Claude Code background sessions shown in a pane with `claude attach`.

## Impact

- `plugins/claude/hooks/report.sh`: forwards events without `TMUX_PANE`.
- `bin/tmux-orchestrator`: pane resolution for background events, attach-viewer scan on focus and pane exit, removal on detach.
- Tests: reporter tests with a fake `ps` and a fake `claude agents --json`.
- `README.md`, `CHANGELOG.md`.
- Works only with the default tmux server socket, because the background process has no `TMUX` variable.
