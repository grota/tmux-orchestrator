# Tasks

## 1. Repository scaffold and compatibility gate

- [ ] 1.1 Create the TPM entry `tmux-orchestrator.tmux`, `bin/tmux-orchestrator`, and the adapter directories; verify `bash -n` passes on every shell file and the expected paths exist.
- [ ] 1.2 Implement the `side-status` capability check and the TPM options (`@tmux-orchestrator-enabled`, `-side`, `-width`, `-toggle-key`); verify on a throwaway tmux socket that loading on a fake unsupported server prints one warning and does not set `side-status`.
- [ ] 1.3 Add a minimal README with prerequisites (tmux 3.9+, jq), install paths, and the manual Claude enablement note; verify every command in it runs as written.

## 2. Shared reporter

- [ ] 2.1 Implement `report` for pane identity, state, name, kind, and session ID, including `#` escaping and control-character stripping; verify with a tmux-socket test that hostile names render literally.
- [ ] 2.2 Implement state removal and session summary recomputation for `@agent_count` and `@agent_rollup`; verify mixed, empty, and duplicate-event cases against a test socket.
- [ ] 2.3 Implement `focus` (clear `done` on the active pane of each client session), `reconcile` (rescan summaries), `gc`, and `toggle`; verify `done` clears only for the selected pane and counts survive a pane kill.
- [ ] 2.4 Add the reporter test script using a throwaway `tmux -L` socket and no network; verify it covers transitions, rollup priority, removal, and repeatability.

## 3. Sidebar

- [ ] 3.1 Build the global `side-status-format` with session and agent sections, state icons, truncation, current-session marker, and the no-agents line; verify a format snapshot on a test socket contains the expected rows and omits empty sessions.
- [ ] 3.2 Add the click binding that preserves `switch-client -t=` and adds window/pane selection based on `mouse_status_range`; verify session, window, and pane clicks on a live test client, including a split window.
- [ ] 3.3 Add the toggle key binding and persist enabled/side/width settings; verify off hides the sidebar, on restores the configured side, and a reload does not resurrect a disabled sidebar.
- [ ] 3.4 Add the lifecycle hooks (`after-select-pane`, `after-select-window`, `client-session-changed`, `pane-exited`, `session-closed`) at fixed indexes; verify a reload does not duplicate them and a pane close updates the summary.
- [ ] 3.5 Document sidebar options, key binding, resize, and overflow in the README; verify the documented commands produce the described state.

## 4. Agent notifications

- [ ] 4.1 Implement transition detection and notification text in the reporter for `blocked`, `error`, and `done`; verify exact tmux and desktop strings, icon use, and the absence of kind and tmux location with hostile and long names.
- [ ] 4.2 Implement `@tmux-orchestrator-notify` with `both`, `tmux`, `desktop`, and `off`, including `notify-send`/`osascript` detection and fallback; verify both, fallback, desktop-only-unavailable, and off with a fake desktop command.
- [ ] 4.3 Implement viewing suppression, unchanged-state deduplication, and the 2-second tmux cooldown with `blocked`/`error` bypass; verify one-client and multi-client cases and that desktop has no cooldown.
- [ ] 4.4 Implement `notify pause`, `notify resume`, and `notify status` with a global option; verify idempotence, reload persistence, state tracking while paused, and the documented status strings.
- [ ] 4.5 Add notification tests using a fake desktop command and a throwaway tmux socket; verify every trigger, channel, suppression, cooldown, and failure path runs without network access.
- [ ] 4.6 Document channel options, pause/resume/status commands, and tmux binding examples in the README; verify no key is bound by default and the documented commands run as written.

## 5. Claude Code adapter

- [ ] 5.1 Add the Claude plugin manifest and `hooks/hooks.json` mapping SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PermissionRequest, Stop, StopFailure, and SessionEnd; verify a hook-fixture test drives the expected state for each event.
- [ ] 5.2 Filter subagent events and ignore tool failures for agent state; verify fixtures with `agent_id` and `PostToolUseFailure` leave the pane unchanged or `working`.
- [ ] 5.3 Implement the async name refresh using `run-shell -b` and `claude agents --json` with a short timeout; verify a missing session falls back to the cwd basename and a later fixture updates the name without blocking.
- [ ] 5.4 Document Claude marketplace enablement and the `CLAUDE_PLUGIN_ROOT` path assumption in the README; verify installing from a local marketplace makes the hooks call the shared reporter.

## 6. OpenCode adapter

- [ ] 6.1 Implement the OpenCode plugin with the event mapping, root/child session handling, and title updates; verify an exported mapping function against fixture events for every declared event.
- [ ] 6.2 Implement the per-turn activity and error bits so `session.idle` becomes `done` only after activity and does not erase an error; verify startup-idle, activity-idle, and error-idle fixtures.
- [ ] 6.3 Verify child permission/question events block the root pane while child completion leaves it working; cover both with plugin tests.
- [ ] 6.4 Document OpenCode installation and title behavior in the README; verify the installer-placed plugin calls the absolute reporter path.

## 7. Packaging and installation

- [ ] 7.1 Add the Claude marketplace manifest and OpenCode installer with reporter-path substitution; verify installation into a temporary HOME creates the expected files and uninstall removes them.
- [ ] 7.2 Add the cleanup/uninstall path for options and hooks; verify rollback leaves no agent options on open panes and removes only this plugin's hook indexes.
- [ ] 7.3 Document the three installation modes, manual Claude step, supported tmux versions, notification defaults, and known limitations in the README; verify a fresh reader can follow the commands without editing hook JSON.

## 8. Integration verification

- [ ] 8.1 Run the full end-to-end scenario on tmux 3.9: two sessions, agents in split windows, all six states, clicks, toggle, resize, done clearing, and notifications; verify the sidebar and captured notifications match the stored options after each step.
- [ ] 8.2 Run the same scenario on an unsupported tmux build and with no tmux/Claude/OpenCode/desktop command available; verify the plugin fails visibly or silently as specified without blocking an agent.
