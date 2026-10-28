# Tasks

## 1. Icons

- [x] 1.1 Change the working icon to `●` and the blocked icon to `◉` in the `icon` macro in `lib/sidebar-format`, and the blocked count `●N` to `◉N` in session rows; update `tests/sidebar-test.sh` and verify it passes
- [x] 1.2 Change `state_icon` in `bin/tmux-orchestrator` to the same glyphs; update `tests/notifications-test.sh` and verify it passes
- [x] 1.3 Update the glyph list and notification assertions in `tests/e2e-test.sh` and verify it passes

## 2. Docs

- [x] 2.1 Update the icon table, rollup and subagent examples, and notification examples in `README.md`; verify `git grep '◐'` finds nothing outside `openspec/changes/archive`
- [x] 2.2 Update the working and blocked glyphs in `docs/diagrams/architecture-animated.svg` and verify it renders in a browser
