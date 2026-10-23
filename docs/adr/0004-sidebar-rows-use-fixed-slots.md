# Sidebar agent rows use fixed slots per pane

An agent pane can host several agents, one per OpenCode tab, but a tmux format can loop over sessions, windows and panes, not over anything inside a pane. We store each agent in a numbered slot of pane options (`@agent_1_*` to `@agent_9_*`) and build the sidebar format at load time by repeating one row fragment per slot. Data stays in options and style stays in the format, so names keep today's single escaping and the format keeps truncating them to the live sidebar width.

## Considered Options

- **One row per pane, rolling up its tabs.** Rejected: a blocked background tab would be hidden behind the active tab's name, and clicking could not focus the tab that needs attention.
- **Row templates.** The reporter writes each pane's rows as one format string and the sidebar expands it with `#{E:...}`. This allows any number of tabs and the shortest format. Rejected because names would need escaping for two passes (storing and expanding), so a tab title such as `#{pane_id}` becomes an injection risk. Also, truncating to the live, drag-resized width works on options and was not shown to work on literal text, and the rows become hard to read in `show-options`.
- **A render script in the format (`#(...)`).** Rejected: tmux runs it per client every `status-interval`, so updates lag, and its cached output makes per-client markers such as the current-session `▸` and `list=focus` awkward.

## Consequences

- At most nine agents per pane get their own row. Nine is our choice, not a tmux limit; it keeps the generated format short and row IDs within tmux's 15-byte limit for `range=user` (for example `%12:3`). Raising it means changing one number.
- Agents beyond the ninth collapse into one `+N more` row that shows their rolled-up state with the session rollup priority. Clicking it selects the pane.
- Closing a tab shifts the later slots down by one.
- Glyphs and colours live in the format fragment, so a later feature can read them from options such as `@tmux-orchestrator-icon-blocked` and apply changes on the next redraw without the reporter.
