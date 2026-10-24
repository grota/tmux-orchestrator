# Agent names wrap in the sidebar format

Long agent names wrap over several lines inside `side-status-format`, not in the reporter. Each line of a slot cuts the next piece of the name with a regex offset computed from the live `side-status-width` (`#{s/^#{=/W:@dots}//:name}`, then `#{=/W:...}`). Wrapping therefore follows a border drag on the next redraw, with no event and no reporter run, which ADR-0004 also relies on for truncation.

## Considered Options

- **The reporter writes the wrapped lines into slot options.** Rejected: the reporter does not run when the sidebar is resized, so lines would stay wrapped to a stale width until the agent's next event.
- **A render script in the format (`#(...)`).** Rejected for the reasons in ADR-0004.

## Consequences

- A format cannot loop over characters, so every possible line is written into each slot in advance. Names wrap over at most 4 lines and end in `…` past that. Each line is conditional, so a short name uses only the lines it needs.
- Offsets count characters, not display columns. A name with wide characters (CJK, emoji) can overflow a line by a few columns.
- Nine slots with four name lines each exceed tmux's command size limit, so each slot's row is set as a global option (`@tmux-orchestrator-row-N`) and the format expands it with `#{E:...}`. These options hold only the static fragment. Agent names are still read from pane options with single escaping, so the injection concern of ADR-0004's row templates does not apply.
- Raising the cap means adding one more line fragment to each slot's option.
