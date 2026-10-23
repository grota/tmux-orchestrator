# Tasks

## 1. Spikes that can change the plan

- [x] 1.1 Prototype the slot format on a throwaway tmux socket. Render three slots and a `+N more` row from one fragment, and confirm with a pty client that names truncate after a border drag and that clicking slot 3 delivers `%<pane>:3` to `mouse_status_range`. Record the result in design.md.
- [x] 1.2 Install a stub `~/.config/opencode/plugins/tmux-orchestrator/tui.js` that only logs, and confirm with `opencode api plugin.list` and a TUI launch that OpenCode v2.1.3 loads it in the TUI with no server entry. If it does not, add an empty server entry and record that in design.md.
- [x] 1.3 Ask the user to run a live Claude Code check: interrupt a turn with Esc and wait 70 seconds with a logging `Notification` hook. If no `idle_prompt` arrives, remove the "Claude Code interrupt recovery" requirement from the delta spec and add the gap to the README known limitations.

## 2. Agent state module

- [x] 2.1 Create `lib/agent-state.sh` with `agent_transition` holding the Claude, OpenCode, adapter-made and tmux event tables, the completion, error-retention, interrupt and viewed rules, the rank function and the notify decision. Verify that `bash -n` passes and the module runs no `tmux` command (`grep` finds none).
- [x] 2.2 Add `tests/agent-state-test.sh`, which sources the module without tmux and covers every mapped event, `ignore` for unmapped ones, completion from `idle`, error retention and clearing, `idle_prompt` from each state, `viewed` and the notify flag. Verify that it passes.

## 3. Reporter and storage

- [x] 3.1 Rewrite `report` in `bin/tmux-orchestrator` around slots: find or create the agent's slot by session ID, apply `agent_transition`, and write the slot fields and `@agent_<i>_event`. Remove `--state` and the Claude JSON parsing. Verify with `tests/reporter-test.sh` updated to send agent events.
- [x] 3.2 Add the `tabs` snapshot command (diff, open, close, reorder, active slot), `register`, and slot-aware `remove`. Verify with new reporter cases: three tabs, closing the middle one keeps the other two in order, and `remove` clears all slots.
- [x] 3.3 Recompute `@agent_n`, `@agent_rollup` and the overflow per pane, and the Tmux session count and rollup from pane rollups. Verify with a reporter case of ten agents where the tenth is `blocked`.
- [x] 3.4 Make `focus`, `select ROW`, notification viewing and the tmux cooldown slot-aware. `select %P:i` sends `focus <sid>` to `@agent_socket` and ignores a missing socket. Verify with `tests/notifications-test.sh` updated, including the background-tab case, and a reporter case that `select` writes to a test socket.
- [x] 3.5 Make `cleanup` and `gc` clear both old and new option names, and delete `state_colour`, `VALID_STATES` and the duplicated validation. Verify with `tests/install-test.sh` and a `cleanup` case that leaves no `@agent_*` option.

## 4. Sidebar

- [x] 4.1 Turn `lib/sidebar-format` into the icon, agent-row and overflow fragments, and make `tmux-orchestrator.tmux` expand nine slots at load time. Verify that reloading twice is idempotent and that `tests/sidebar-test.sh` passes with several agents per pane, a hostile name, truncation and the `+N more` row.
- [x] 4.2 Bind clicks so that `%P:i` and `%P:+` ranges run `select` while session ranges keep `switch-client`. Verify with a sidebar test click on slot 2 of a pane.
- [x] 4.3 Update the README sidebar section for per-tab rows, the nine-row limit and the overflow row, and run the Markdown formatter.

## 5. Claude adapter

- [x] 5.1 Move payload parsing into `plugins/claude/hooks/report.sh`. Forward subagent events, pass `--detail` and `--refresh` as designed, and keep the 5-second hook budget. Verify with `tests/claude-fixtures-test.sh`.
- [x] 5.2 Add `Elicitation`, `ElicitationResult` and `Notification` (`idle_prompt`) to `hooks.json`, and add fixtures for `AskUserQuestion`, `ExitPlanMode`, an elicitation pair, a subagent `PermissionRequest` and `idle_prompt`. Verify that the fixture test passes.
- [x] 5.3 Update the README Claude Code events table and run the Markdown formatter.

## 6. OpenCode TUI plugin

- [x] 6.1 Rewrite `plugins/opencode/` as a TUI plugin with a pure core: map events to root sessions, filter to open tabs, build snapshots and diff them. Delete the server plugin and the v1 export. Verify with `tests/opencode.test.js` rewritten for the core using v2 event shapes (`data`, not `properties`).
- [x] 6.2 Add the serial reporter queue with its kill timeout, the 250 ms tab poll, the focus socket and dispose cleanup. Verify with `tests/opencode-plugin.test.js` driving a fake `api` and a fake reporter: events stay in order, a closed tab sends a snapshot, a socket `focus` line calls `ui.tabs.focus`, and dispose unlinks the socket.
- [x] 6.3 Update `install` and `uninstall` to write and remove `plugins/tmux-orchestrator/tui.js` and to delete the legacy file. Verify with `tests/install-test.sh` against a temporary home.
- [x] 6.4 Update the README OpenCode section: v2 only, the tested version, install path, the events table, tabs and focus. Run the Markdown formatter.

## 7. Integration

- [x] 7.1 Run every test script and `node --test tests/`, and confirm that all pass.
- [x] 7.2 Ask the user to run a live check: one Claude pane and one OpenCode pane with three tabs. Confirm the rows, a permission wait on a background tab, closing a tab, a click focusing a tab, and the TUI exit removing the rows.

## 8. Claude interrupt detection

- [x] 8.1 Record ADR-0006 (Claude interrupts are read from the transcript as a fallback for a named gap) and verify the Markdown formatter runs clean on it.
- [x] 8.2 Add the adapter-made `claude:Interrupted` event to the agent state module, mapping to `idle`. Verify with new cases in `tests/agent-state-test.sh`.
- [x] 8.3 Add the `watch-interrupt` command and start it from `report` on `UserPromptSubmit` when a transcript path is given, with a per-pane generation token, a 3-second tick, new-bytes-only scanning that ignores sidechain entries, and the exit conditions from the spec. Verify with reporter cases using a temporary transcript: a marker sets `idle`, a sidechain marker does not, a new prompt retires the old watcher, and `Stop` ends it.
- [x] 8.4 Pass `transcript_path` from `plugins/claude/hooks/report.sh` (staged in the scratchpad for the user to copy) and verify `tests/claude-fixtures-test.sh` with a fixture transcript.
- [x] 8.5 Update the README Claude section and known limitations, and run the Markdown formatter.
- [x] 8.6 Ask the user to repeat the Esc test and confirm the row turns `idle` within a few seconds.
