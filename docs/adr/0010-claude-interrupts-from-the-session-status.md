# Claude interrupts are read from the session status

ADR-0006 detected an interrupt from the `[Request interrupted by user` entry Claude Code writes to the session transcript. Two live tests on Claude Code 2.1.311 showed that it stopped working: an interrupt while Claude writes text leaves no entry at all, and on a session's first prompt the transcript does not exist yet when the `UserPromptSubmit` hook runs, so no watcher started. Claude Code keeps each running session's `status` (`busy`, `waiting` or `idle`) in its session registry, the same one ADR-0009 uses, and `claude agents --json` documents the field. In every test it turned `idle` within a second of Esc, for a tool call and for text. While a turn runs, a watcher reads that status every 2 seconds and reports an interrupt after two `idle` readings in a row while the agent is still `working` or `blocked`.

## Considered Options

- **Keep the transcript marker and fix the first-prompt race.** Rejected: the marker is missing for interrupts during text.
- **Poll `claude agents --json`.** Rejected: it is the documented source, but each call takes about 240 ms, every 2 seconds for each busy agent. The registry file is read with one `jq` call.
- **Report an interrupt on the first `idle` reading.** Rejected: a completed turn goes `idle` just before its `Stop` hook arrives, and the agent would show `idle` instead of `done`.

## Consequences

- Detection takes 2 to 4 seconds and works on the first prompt.
- The registry file and its `status` field are internal. `tests/contract/claude-test.sh` checks the field, and with `TMUX_ORCHESTRATOR_CONTRACT_TURN=1` it interrupts a Haiku turn to check detection end to end.
- A watcher ends when the agent leaves `working`/`blocked`, a new prompt starts a new watcher, or the registry entry disappears or names another session. There is no time limit: the watcher costs one `jq` call per tick.
- A pause where the main thread is `idle` while a turn is not over would read as an interrupt. None was seen in testing; `waiting` covers permission prompts and questions.
- Adapters from before this change still send `--transcript`; the reporter ignores it.
