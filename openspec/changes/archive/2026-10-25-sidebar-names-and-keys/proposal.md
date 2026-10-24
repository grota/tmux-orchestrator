# Proposal

## Why

Long agent names are cut to one line, so agents with similar names are hard to tell apart, and the time in state takes room from the name. The sidebar does not show which agent the client is looking at. The toggle key silently overwrites any binding the user already had on that key, leaves the old key bound after the option changes, and the orchestrator's key bindings are not discoverable from the sidebar.

## What Changes

- New option `@tmux-orchestrator-name-max-chars`: unset or `wrap` wraps the agent name over up to 4 lines, ending in `…` past that; a positive number `N` shows one line cut at `N` characters or the sidebar width, whichever is shorter; `nowrap` keeps one line cut to the width. **BREAKING**: the default changes from one truncated line to wrapping.
- Wrapped name lines are indented two columns, under the first character of the name.
- The time in state moves from the name line to the kind line, right-aligned, in the same grey.
- The focused agent's name is bold. No marker is added.
- A right-aligned, clickable `? keys` footer opens and closes the keys panel. The open state is global. The panel lists the toggle key and every tmux key binding whose command calls the reporter, read each time the panel opens.
- The toggle key is no longer bound over an existing binding that is not the plugin's; the plugin skips it and shows a one-time message. On reload, the plugin removes its own toggle binding from a previous key.
- The README says what the toggle key does and documents the new options and the keys panel.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `agent-sidebar`: agent rows gain name wrapping, the time on the kind line and a bold focused agent; the toggle binding stops overwriting user bindings; a keys panel is added.

## Impact

- `lib/sidebar-format`: agent row fragment (name lines, kind line, bold), new keys panel and footer fragments.
- `tmux-orchestrator.tmux`: format assembly for name lines, toggle key binding checks, click routing for the footer.
- `bin/tmux-orchestrator`: a subcommand that toggles the keys panel and refreshes its binding list.
- `tests/sidebar-test.sh`, `tests/install-test.sh`: new coverage.
- `README.md`: Sidebar section.
- Design follows ADR-0004 (fixed slots) and ADR-0008 (names wrap in the format).
