# Adapters find the reporter through tmux

Claude Code installs a marketplace plugin by copying only the plugin's own directory into its cache, so the Claude adapter cannot reach the reporter by a path relative to itself. The OpenCode adapter used to carry an absolute reporter path written at install time, which went stale when the tmux plugin moved or updated. Both adapters always run inside a pane of the tmux server whose sidebar they feed. The tmux plugin therefore publishes its reporter path in the global option `@tmux-orchestrator-reporter` on every load, and adapters read it from there. The tmux plugin copy that is loaded owns the only reporter.

## Considered Options

- **A path relative to the adapter.** Rejected: it works only from a git checkout, never from the marketplace cache.
- **A path written at install time.** Rejected: it goes stale on every update or switch between a TPM clone and a checkout.
- **A copy of the reporter inside each adapter.** Rejected: two reporters drift apart, and only the tmux copy can install the sidebar format.
- **A system package that puts the reporter on `PATH`.** Deferred: it needs packaging per platform. Adapters keep `PATH` as a fallback so it can be added later.

## Consequences

- Each Claude hook makes one extra tmux call, about 2 ms.
- Reloading tmux with another copy of the plugin switches every adapter on its next event, without restarting agents.
- The OpenCode adapter is installed as a link to the loaded copy, so updating the tmux plugin updates it.
- An adapter can be newer than the reporter. A report protocol version turns that into a visible message instead of silent failure.
