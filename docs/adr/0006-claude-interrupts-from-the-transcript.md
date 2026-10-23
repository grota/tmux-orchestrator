# Claude interrupts are read from the transcript

Claude Code sends no hook when the user interrupts a turn, and a live test showed that the `idle_prompt` notification does not fire after an interrupt either. An interrupted agent would therefore show `working` until its next prompt, which defeats a sidebar meant to be read at a glance. Claude Code does write a main-thread transcript entry starting with `[Request interrupted by user` at the moment of the interrupt. We watch for that entry during each turn and report it as an adapter-made `claude:Interrupted` event. This is a fallback for a named gap, as ADR-0001 allows, not a second source of state.

## Considered Options

- **Accept the gap.** Rejected: an interrupted agent looks busy indefinitely.
- **Check the transcript from tmux focus hooks.** Rejected: nothing changes until the user switches pane, window or session, so the sidebar is wrong exactly when it is glanced at.
- **Read the screen with `capture-pane`.** Rejected: more fragile than the transcript, and ADR-0001 prefers the agent's own records.

## Consequences

- One background watcher per busy Claude agent, polling every 3 seconds and reading only appended bytes. Idle agents cost nothing.
- Each pane keeps a generation token, so a new prompt retires the previous watcher without tracking process IDs.
- A watcher ends when the agent leaves `working`/`blocked`, the pane closes, or the transcript has not grown for an hour.
- The transcript format is undocumented. If the marker changes, detection silently stops; a fixture test pins the current text.
