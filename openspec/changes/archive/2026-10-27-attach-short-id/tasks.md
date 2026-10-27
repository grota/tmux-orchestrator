# Tasks

## 1. Attach resolution

- [x] 1.1 Match `.id == arg` before the session ID prefix in `attach_session`
- [x] 1.2 Add an attach test whose short ID does not start its session ID; verify `tests/attach-test.sh` passes

## 2. Cleanup and contract

- [x] 2.1 Remove the `Notification` branch and the `notification_type` field from `report.sh`; verify `tests/claude-fixtures-test.sh` passes
- [x] 2.2 Extend `tests/contract/claude-test.sh` with `claude --bg`, `claude attach` and the adopted row's state; verify it passes and removes its session
