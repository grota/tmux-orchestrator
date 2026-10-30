## 1. Reporter

- [x] 1.1 Add `view_state` to `bin/tmux-orchestrator`, keeping `since` unless `@tmux-orchestrator-time-on-view` is `reset`
- [x] 1.2 Use it in `focus_agents` and in the OpenCode `tab.focused` path of `tabs`

## 2. Tests

- [x] 2.1 In `tests/reporter-test.sh`, assert that focus and tab focus keep `@agent_1_since` by default and restart it with `reset`

## 3. Docs

- [x] 3.1 Describe the state time and `@tmux-orchestrator-time-on-view` in `README.md`
- [x] 3.2 Add the option to `CHANGELOG.md` under Unreleased
