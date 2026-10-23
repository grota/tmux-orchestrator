# Tasks

## 1. Decision record

- [x] 1.1 Record ADR-0007 (adapters find the reporter through a tmux option) with the rejected alternatives, and verify the Markdown formatter runs clean on it.

## 2. Reporter

- [x] 2.1 Make `tmux-orchestrator.tmux` publish `@tmux-orchestrator-reporter` on every load. Verify with a sidebar-test assertion that the option names the loaded copy's `bin/tmux-orchestrator`.
- [x] 2.2 Add `--protocol` handling to every reporter command, with the one-time warning option. Verify with reporter cases: protocol 1 and no flag apply the event; protocol 2 changes nothing, sets `@tmux-orchestrator-protocol-warned` and shows the message once.

## 3. Claude Code adapter

- [x] 3.1 Replace the relative lookup in `plugins/claude/hooks/report.sh` with the environment, tmux option, `PATH` order, and pass `--protocol 1`. Stage the file in the scratchpad for the user to copy. Verify with `tests/claude-fixtures-test.sh` run against the staged file and the tmux option alone (no `TMUX_ORCHESTRATOR_REPORTER`), plus a case where no reporter is found and the hook still exits 0.

## 4. OpenCode adapter

- [x] 4.1 Remove the `__REPORTER__` placeholder from `plugins/opencode/tui.js`, resolve the reporter at setup in the same order, and pass `--protocol 1` on every call. Verify with the node tests using a fake tmux on `PATH` that answers the option query.
- [x] 4.2 Rewrite `install opencode` and `uninstall opencode` to manage the link, replace the previous copied layout, leave foreign paths alone, and remove the legacy server file. Verify with `tests/install-test.sh` against a temporary home covering each case.
- [x] 4.3 Make `tmux-orchestrator.tmux` run `install opencode --quiet` when `@tmux-orchestrator-opencode` is `on`. Verify with an install-test case that loading the plugin twice from two different copies leaves the link pointing at the second.

## 5. Documentation

- [x] 5.1 Restructure the README: install through TPM with `grota/tmux-orchestrator` and through the Claude Code marketplace, the OpenCode option and command and a Development section for `run-shell` and `--plugin-dir`. Remove `/home/you` paths and the "three directories above" explanation. Run the Markdown formatter.

## 7. Restored OpenCode waits

- [x] 7.1 Take each tab's status from `ui.tabs.list()` (`attention`, then `busy`), and from the whole session family when tabs are disabled. Verify with the node snapshot tests, including a child-session form.
- [x] 7.2 Add the adapter-made `opencode:tab.pending` event (`blocked`) to the agent state module and apply it in `tabs` when a known tab reports a pending request while its agent is not `blocked`. Verify with module and reporter cases: a tab first reported `running` and then `pending` ends `blocked` and notifies once.
- [x] 7.3 Ask the user to restart OpenCode with a tab waiting for permission and confirm the row shows `blocked`.

## 6. Integration

- [x] 6.1 Run every test script and `node --test tests/`, and confirm that all pass.
- [ ] 6.2 (Skipped by the user on 2026-10-23: the reporter path and OpenCode link were confirmed live from the checkout; the switch to the TPM copy was not tested.) Ask the user to check live: reload tmux, run `install opencode`, restart OpenCode and a `--plugin-dir` Claude session, confirm both report, then switch to the other tmux plugin copy and confirm the reporter and link follow.
