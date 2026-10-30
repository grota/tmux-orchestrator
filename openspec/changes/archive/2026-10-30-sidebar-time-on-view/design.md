# Design

## Context

`set_state` records `@agent_<i>_since` whenever a slot's state changes. Two paths change state because the user viewed an agent, not because of an agent event: `focus_agents` (pane focus and sidebar clicks, through the `viewed` transition) and `tabs` (an OpenCode tab becoming active, through `tab.focused`). Both clear `done` to `idle`, so both restart the time.

## Goals / Non-Goals

**Goals:** viewing never restarts the state time by default; the old behavior stays available.

**Non-Goals:** a cache-expiry warning or highlight; changing which states viewing clears.

## Decisions

- **One helper for view-driven changes.** A `view_state` helper calls `set_state` and then puts the previous `since` back unless `@tmux-orchestrator-time-on-view` is `reset`. Both view paths call it instead of `set_state`. Alternative: a flag on `set_state`; rejected because every other caller would carry an argument it never uses.
- **Read the option per call** with `get_global`, so a change applies on the next view without a reload.
- **Empty `since` still starts the clock.** An agent with no recorded time gets one, as today.
- **The subagent main-thread icon** (`@agent_1_main`) has no time of its own and is untouched.

## Risks / Trade-offs

- An `idle` agent may show a time much longer than it has been `idle` → this is the intent; the glossary's **State time** defines it.
