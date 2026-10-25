# Tasks

## 1. Viewer scan and resolution

- [x] 1.1 Add a viewer scan to `bin/tmux-orchestrator` (pane ids from `list-panes`, one `ps -A -ww -o pid= -o ppid= -o stat= -o args=`, descendants, `attach <arg>` after other options, suspended skipped); verify with a reporter test that uses a fake `ps` on `PATH` covering an option before `attach`, a suspended viewer and a `claude agents` process.
- [x] 1.2 Add attach argument resolution (session id prefix without calling Claude, else a unique case-insensitive name substring from `claude agents --json`); verify with a fake `claude` binary for short id, name part, ambiguous and unknown arguments.

## 2. Background events

- [x] 2.1 Make `plugins/claude/hooks/report.sh` forward events without `TMUX_PANE` as `report --background` with the session id, and exit when there is no session id; verify with `tests/attach-test.sh`, whose hooks run without `TMUX_PANE`.
- [x] 2.2 Handle `report --background` in the reporter: apply the event to every pane showing the session and mark the agent `@agent_attached` with the session id; with no viewer, remove the attached agent and send no notification; verify with reporter tests for both cases, including that no notification command runs.

## 3. Discovery and removal

- [x] 3.1 Extend `focus` to check the clients' active panes for viewers and add a newly attached session with its name and mapped state from `claude agents --json`; verify with a reporter test that a `blocked` session appears as `blocked` after `focus`.
- [x] 3.2 Extend `focus` to remove attached agents whose pane no longer shows their session, leaving ordinary Claude agents alone; verify with a reporter test that switches the fake viewer to `claude agents` and one with a normal Claude agent.

## 4. Documentation

- [x] 4.1 Document attached background sessions in the README (Claude Code events section) and replace the Known limitations line with the remaining limits (row stays until the next selection or hook after `←`, default tmux socket only); add a CHANGELOG entry; verify the README no longer says attached sessions are not tracked.

## 5. Integration

- [x] 5.1 Run every shell suite and `node --test tests/` and verify they pass.
- [x] 5.2 With the plugin loaded in a real tmux, attach a background session, select its pane, send a prompt, press `←` and select another pane; verify the row appears, updates, and disappears.
