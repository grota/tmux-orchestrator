# Design

## Context

The sidebar format is assembled at load from `lib/sidebar-format`. One agent row fragment is repeated per slot (ADR-0004). The name is cut with `#{=/W/…:@agent_{I}_name}`, where `W` is the live `side-status-width` minus room for the icon and the time. The fragment already computes the focused agent for `list=focus`: window active, pane active, and `@agent_active` equal to the slot. Clicks reach `MouseDown1Status`, which routes `session` and `window` ranges to tmux and every user range to `tmux-orchestrator select`. The toggle key is bound unconditionally with `bind-key`.

## Goals / Non-Goals

**Goals:**

- Wrap names in the format so they follow the live width (ADR-0008).
- Keep the change inside the existing slot model and click router.

**Non-Goals:**

- Per-client keys panel state.
- Leaving `MouseDown1Status` alone when the user has a binding for it. It is still replaced, as today.
- Display-column-aware wrapping for wide characters.

## Decisions

### Name lines are cut with regex offsets

Line `k` (1 to 4) shows `#{=/W:#{s/^#{=/O:@tmux-orchestrator-dots}//:@agent_{I}_name}}`. Here `W = side-status-width - 2` is the name width, and `O = (k-1)·W` is a prefix of a long dot string set as a global option at load. A probe on tmux next-3.9 confirmed that `s/` and `=/` take expanded arguments and count multibyte characters as one. Line `k > 1` is wrapped in a conditional on the remaining text being non-empty, so short names add no lines. Line 4 uses `#{=/W/…:}` so the overflow ends in `…`. The dot string must be at least `3·W_max` long; the plugin sizes it to 3 × 500 characters. The alternative, the reporter writing the lines into slot options, is rejected in ADR-0008.

### Mode selection in the format

`@tmux-orchestrator-name-max-chars` is read live by the format, like `@tmux-orchestrator-time`:

- `nowrap`: line 1 only, cut to `W` with `…`.
- A positive integer `N`: line 1 cut to `min(N, W)`, using `#{e|<:...}` to choose between them.
- Anything else, including unset and `wrap`: lines 1 to 4.

A changed option therefore applies on the next redraw, without a reload. A value that is neither `nowrap`, `wrap` nor a positive integer falls back to `wrap`.

### Kind line carries the time

The kind line becomes `  #[fg=colour8]<kind>#[align=right]<time> #[align=left]`, keeping the existing `@tmux-orchestrator-time off` conditional. Every name line then uses the full `W` and no longer subtracts 11 columns.

### Bold focused agent

The focus condition already used for `list=focus` also wraps the name lines in `#[bold]`…`#[nobold]`. The condition is evaluated per client because `side-status-format` is expanded per client.

### Keys panel

- **Footer row:** a row after `#[nolist]`, outside the trimmed list, with `#[align=right range=user|keys]? keys`. The user range name `keys` cannot collide with agent ranges, which always start with `%`.
- **Click routing:** the existing user-range branch of the click router passes `keys` to `tmux-orchestrator select keys`. `select_agent` dispatches it to a new keys toggle before any pane parsing. This keeps `MouseDown1Status` a single binding.
- **Toggle:** the keys toggle flips the global `@tmux-orchestrator-keys` (`1` or unset). When opening, it runs `list-keys` and keeps the bindings that call the reporter: their command contains `bin/tmux-orchestrator` (any checkout path) or `#{@tmux-orchestrator-reporter}` (the form the README examples use). It stores them in `@tmux-orchestrator-keys-list` as plain lines of the form `<table> <key>  <subcommand>`, then refreshes the clients.
- **Toggle key in the list:** the toggle key is found like any other binding, so a skipped toggle key is simply absent.
- **Escaping and fit:** stored text is escaped for `#` with the existing `escape_hash` and rendered with `#[nl]` separators, each line cut to the width.
- **Why on open:** looking bindings up at load would miss bindings defined later; looking them up on each open costs one `list-keys` per click.

### Toggle key binding checks

At load, `list-keys -T prefix <key>` is inspected:

- No binding, or a binding whose command contains `$REPORTER' toggle`: bind it.
- Otherwise: skip it and run `display-message` naming the key.

Before binding, the plugin scans `list-keys -T prefix` for other keys whose command calls the reporter's `toggle` (same match as the keys panel) and runs `unbind-key` on them. Matching on the reporter, not only on `toggle`, avoids touching other plugins.

## Risks / Trade-offs

- [The format grows by about 4 name lines × 9 slots] → Each line is about 150 bytes, measured well within tmux limits. ADR-0008 records the cap.
- [Wide characters overflow a wrapped line by a column or two] → Accepted and noted in ADR-0008.
- [A TPM checkout path change means a scan for the current reporter path misses the old binding] → Recognise our bindings by the reporter's file name (`bin/tmux-orchestrator` followed by a subcommand), not its full path, so a binding left by a moved checkout is still found and cleaned up.
- [The default changes to wrapping, so rows get taller] → `nowrap` restores the old look. Noted as BREAKING in the proposal.
- [A user command that mentions the reporter but does not call a subcommand is listed oddly] → The panel shows whatever follows the reporter reference. Acceptable for a reference list.
