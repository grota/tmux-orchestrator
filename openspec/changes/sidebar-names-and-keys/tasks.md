# Tasks

## 1. Agent row layout

- [x] 1.1 Move the time in state to the kind line, right-aligned, keeping `@tmux-orchestrator-time off`; verify with a `tests/sidebar-test.sh` case that renders the format with `display -p` and checks the kind line holds `claude` and the time.
- [x] 1.2 Set the global dot-string option at load and generate name lines 1 to 4 per slot in `tmux-orchestrator.tmux`, with lines 2 to 4 conditional and line 4 ending in `…`; verify with sidebar tests for 1-line, 2-line and over-4-line names, plus a multibyte name.
- [x] 1.3 Read `@tmux-orchestrator-name-max-chars` live in the format (`wrap` or unset, positive `N`, `nowrap`, invalid falls back to `wrap`); verify each value in a sidebar test and that changing it applies without reloading.
- [x] 1.4 Verify that wrapping follows a width change by setting `side-status-width` in a test and checking the line split changes with no reporter call.
- [x] 1.5 Make the focused agent's name bold using the existing focus condition; verify with a sidebar test with two tabs that only the active one has `#[bold]`.
- [x] 1.6 Document `@tmux-orchestrator-name-max-chars`, the new kind line and the bold focused agent in the README Sidebar section, and verify the documented example renders as described.

## 2. Keys panel

- [x] 2.1 Add the right-aligned `? keys` footer with `range=user|keys` after the agent list, and the panel fragment shown when `@tmux-orchestrator-keys` is `1`; verify with a sidebar test that the footer is present and that the panel shows only when the option is set.
- [x] 2.2 Dispatch `select keys` to a keys toggle in `bin/tmux-orchestrator` that flips `@tmux-orchestrator-keys`, refreshes `@tmux-orchestrator-keys-list` from `list-keys` on open, and refreshes clients; verify with a reporter test that a binding added after load appears on the next open that a binding written as `#{@tmux-orchestrator-reporter} notify pause` appears, and that a binding not calling the reporter does not.
- [x] 2.3 Verify that `#` in a discovered command is escaped and does not expand in the panel.
- [x] 2.4 Document the keys panel in the README Sidebar section, and verify the README states it lists the toggle key and bindings that call the reporter.

## 3. Toggle key binding

- [x] 3.1 Bind the toggle key only when it is free or already the plugin's toggle, otherwise show a one-time message; verify with `tests/install-test.sh` that a pre-existing user `prefix O` binding survives load and a message is shown.
- [x] 3.2 Unbind the plugin's toggle from other prefix keys on load; verify with an install test that changing the key from `O` to `T` and reloading leaves `prefix O` unbound and `prefix T` bound.
- [x] 3.3 Replace the README's "not reserved" sentence with what the toggle key does (shows and hides the sidebar), its default, and the no-overwrite rule, and verify the `MouseDown1Status` note is still there.

## 4. Integration

- [x] 4.1 Run every shell suite and `node --test tests/`, and verify that all pass on a private tmux next-3.9 server.
- [x] 4.2 Load the plugin on a real server with long names, two clients and the keys panel open, and verify that drag-resize re-wraps names and each client bolds its own focused agent.
