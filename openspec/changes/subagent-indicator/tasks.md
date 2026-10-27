# Tasks

## 1. Tracking

- [x] 1.1 Add `agent_subagents` and `agent_subagents_summary` to the state module, with unit tests
- [x] 1.2 Keep `@agent_1_main` and `@agent_1_subagents` (with `_n` and `_state`) in the reporter; reset them for a new session; clear the main thread's `done` on view
- [x] 1.3 When the last subagent ends, give a `working` agent its main thread's `idle` or `done`
- [x] 1.4 Register `SubagentStart` and add its fixture

## 2. Sidebar

- [x] 2.1 Show the main and subagent icons with the count while subagents run, and narrow the name's first line by those columns, wrapped lines included
- [x] 2.2 Test the row, the return to one icon, and the background-subagent case in `tests/sidebar-test.sh`
- [x] 2.3 Verify with a live Haiku session that spawns a subagent

## 3. Docs

- [x] 3.1 README and CHANGELOG
