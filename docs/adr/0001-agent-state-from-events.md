# Agent state comes from lifecycle events, not screen scraping

Claude Code and OpenCode both expose lifecycle events, while Herdr derives Claude's state from its rendered screen. We report state from Claude Code hooks and an OpenCode plugin only, and do not parse pane contents. Screen parsing was rejected as a second, version-fragile source of truth that duplicates what the agents already emit.

## Consequences

- Claude waiting at a login prompt is invisible; a hard crash can leave a stale state. Both are accepted in v1.
- Any future screen parsing is a fallback for a named gap, never a second authority.
- The same state vocabulary must fit both agents: `working`, `blocked`, `done`, `idle`, `error`, `unknown`.
