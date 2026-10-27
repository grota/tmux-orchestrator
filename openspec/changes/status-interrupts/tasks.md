# Tasks

## 1. Detection

- [x] 1.1 Replace the transcript watcher with one that reads `status` from the registry file of the session, reporting `claude:Interrupted` after two `idle` readings while the agent is `working` or `blocked`
- [x] 1.2 Start it on every Claude `UserPromptSubmit` with a session ID; stop when the state changes, a new token replaces it, or the registry entry disappears or names another session
- [x] 1.3 Drop `--transcript` from the Claude adapter and the reporter internals; keep accepting the flag

## 2. Tests and docs

- [x] 2.1 Rewrite the interrupt cases in `tests/reporter-test.sh` and `tests/claude-fixtures-test.sh` around a fake registry, including the race with `Stop`
- [x] 2.2 Add the `status` check and the opt-in interrupted turn to `tests/contract/claude-test.sh`; verify it passes with `TMUX_ORCHESTRATOR_CONTRACT_TURN=1`
- [x] 2.3 ADR-0010, ADR-0006 marked superseded, README and CHANGELOG
