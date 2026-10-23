# Design

## Context

See proposal.md for motivation. Claude Code copies a marketplace plugin whose source is a subdirectory into `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` without the rest of the repository; `frontend-design` from the official marketplace is cached that way on the development machine. Both adapters always run inside a pane of the tmux server whose sidebar they feed, so that server is the one place every adapter can reach. The maintainer runs Claude Code with `--plugin-dir <checkout>/plugins/claude` and switches the tmux plugin between TPM and `run-shell <checkout>/tmux-orchestrator.tmux`.

## Goals / Non-Goals

**Goals:**

- One copy of the reporter, owned by whichever tmux plugin copy is loaded.
- Adapters that work from the marketplace cache, a TPM clone, or a checkout, with no path baked in.
- Updating the tmux plugin also updates the OpenCode adapter.

**Non-Goals:**

- System packages (Homebrew, AUR). The `PATH` fallback keeps them possible later.
- Installing the Claude Code plugin from tmux. It stays a `/plugin` action.

## Decisions

### The reporter path lives in a tmux option

`tmux-orchestrator.tmux` sets `@tmux-orchestrator-reporter` to its own `bin/tmux-orchestrator` on every load. Adapters resolve the reporter in this order: `TMUX_ORCHESTRATOR_REPORTER`, the option (one `tmux show-options -gv` call, honouring `TMUX_SOCKET` like the reporter does), then `tmux-orchestrator` on `PATH`. Reloading tmux with another copy switches every adapter on its next event.

Alternatives: a relative path from the adapter (breaks in the marketplace cache), a path substituted at install time (goes stale on update or switch), and a second reporter copy inside the Claude plugin (two copies drift). See ADR-0007.

### OpenCode is installed as a link

`install opencode` makes `~/.config/opencode/plugins/tmux-orchestrator` a symbolic link to the running copy's `plugins/opencode`. OpenCode's discovery follows linked directories. The adapter no longer contains a placeholder: it resolves the reporter at `setup` through the same order, using `spawnSync` for the tmux call. The installer:

- replaces the path when it is a link into a `plugins/opencode` directory holding this project's `tui.js`, or a real directory holding a copied `tui.js` with this project's plugin ID (the previous install layout);
- leaves anything else untouched and prints why;
- removes the legacy `tmux-orchestrator.js` server file.

With `@tmux-orchestrator-opencode on`, the tmux plugin runs `install opencode --quiet` on each load, so the link follows a switch between TPM and a checkout. `uninstall opencode` removes the link and the legacy files. The bare `install` and `uninstall` stay as aliases.

### Report protocol version

Every adapter call passes `--protocol 1`. The reporter supports protocol 1 and treats a missing flag as 1. For any other value it applies nothing, and if the global option `@tmux-orchestrator-protocol-warned` does not already hold that value, it sets it and shows `tmux-orchestrator: update the tmux plugin (adapter protocol N)` to every attached client. The number only changes when the reporter command line changes incompatibly.

## Risks / Trade-offs

- [One extra tmux call per Claude hook] → About 2 ms, inside the existing 5-second hook budget.
- [OpenCode keeps the old link target until restart] → Documented: restart OpenCode after switching tmux plugin copies.
- [`--plugin-dir` adapter newer than a TPM reporter] → Caught by the protocol message instead of failing silently.

## Migration Plan

1. Reload tmux so the option is published.
2. Run `install opencode` or set `@tmux-orchestrator-opencode on`; the copied `tui.js` directory from the previous layout is replaced by the link.
3. Update or reinstall the Claude Code plugin.
4. To roll back, check out the previous commit, rerun its `install`, and reload tmux.
