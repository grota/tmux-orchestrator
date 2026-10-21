# The persistent area is the tmux side status line

The sidebar is drawn with tmux's `side-status`, not a real pane. Panes belong to one window, so a pane-based sidebar cannot stay visible across windows and sessions, cannot be seen by two clients viewing different windows, and would mutate every window layout. `side-status` is per-client chrome: always visible, mouse-clickable, and free of layout side effects.

## Considered Options

- **A real pane moved between windows.** Rejected: one window at a time, layout churn, breaks zoom and splits, fights multi-client use.
- **A popup console.** Deferred: focusable and scrollable, but modal, so it complements the sidebar rather than replacing it.
- **The normal status line with extra rows.** Rejected: horizontal and cramped; the sidebar is vertical.

## Consequences

- v1 requires tmux next-3.9; `side-status` is absent from 3.8 and earlier. The installer must refuse older tmux loudly.
- The sidebar cannot take keyboard focus or scroll. Navigation is mouse plus global key bindings; overflow is handled by `list=focus`.
- Agent state lives in tmux user options on the pane, so a future console or pane-based view can read the same store.
