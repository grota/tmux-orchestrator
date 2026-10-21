# Persistent info in tmux for an agent orchestrator

Initial analysis, 2026-10-21. Goal: show orchestrator status that stays visible when switching tmux windows and sessions, and design an agent orchestrator integrated in tmux.

Nothing below has been tested live yet. Facts come from the local `man tmux` and the sources at the end.

## Environment

- **tmux version.** `next-3.9` (a 3.9 development build).
- **Config.** `~/.config/tmux/tmux.conf`. It does not use `side-status` or floating panes yet.

## Key constraint

Panes always belong to one window, including floating panes. No pane is shared across windows or sessions. What persists across windows and sessions is the status line, which is drawn by tmux itself.

## Options

### 1. Side status line (best for always-visible info)

`side-status` (3.9 builds) draws a vertical status line on the left or right of the terminal. It refreshes every `status-interval` seconds, like the normal status line. Set with `-g`, it shows in every window and session.

```tmux
set -g side-status right
set -g side-status-width 30
set -g side-status-format "#{E:@agents}"
set -g status-interval 2
```

Related options: `side-status-style`. The format can produce several rows with `#[nl]` or a newline. Rows drawn with `list=on` scroll to keep the `list=focus` row visible.

The orchestrator can push state without polling:

```sh
tmux set -g @agents "build ok\nreview running\ntests failed" && tmux refresh-client -S
```

A `#(script)` call in the format is the polling alternative.

Limits: display only, no keyboard input. The normal status line supports clickable mouse ranges; support in the side status line is not verified.

The normal status line can also grow to 5 rows (`status 5` plus `status-format[]`).

### 2. Modal floating pane on a key (best for interaction)

Floating panes arrived in tmux 3.7 and became complete in 3.8. Relevant `new-pane` flags:

- **`-x`, `-y`, `-X`, `-Y`.** Size and position, also as `%` of the window.
- **`-O`.** Modal pane: always active, blocks other panes. One per window.
- **`-K`.** All keys, including the prefix, go to the modal pane.
- **`-C`.** Close on mouse click outside.
- **`-D`.** Close on `Escape` or `C-c`.
- **`-A`.** Stays visible above a zoomed pane.

A floating pane belongs to its window, so it does not follow window switches. Use a key binding that opens the orchestrator console as a modal floating pane (or `display-popup`) over the current window. tmux 3.9 is expected to make `display-popup` open a modal floating pane.

### 3. Pane that follows you (not recommended)

Hooks can move one real pane into each window you select:

```tmux
set-hook -g after-select-window 'join-pane -h -l 30 -s orchestrator:0.0'
set-hook -g client-session-changed 'join-pane -h -l 30 -s orchestrator:0.0'
```

`join-pane` moves the pane, so it is never in two windows at once. It changes every window's layout, conflicts with zoom, and needs edge-case handling (target is the current window, the pane died). Use it only if a live interactive pane must always be visible.

## Proposed architecture

The orchestrator, in order of data flow:

1. **Runs headless,** as a daemon or in a hidden tmux session.
2. **Pushes status** into `@` user options and calls `refresh-client -S`. The side status line renders it everywhere.
3. **Opens a console** through a key binding that starts a modal floating pane with the interactive UI.
4. **Receives events** from tmux hooks (`pane-exited`, `alert-bell`, `session-window-changed`) that call `run-shell` to notify it.

## Open questions for the next session

- Do clickable ranges work in `side-status-format`?
- Should `side-status` be global (`-g`) or per session?
- What does the orchestrator need to receive from hooks, and in which format?
- Language and process model for the orchestrator daemon.

## Sources

- [Tmux 3.7 released with initial floating pane support](https://linuxiac.com/tmux-3-7-terminal-multiplexer-released-with-initial-floating-pane-support/)
- [Tmux 3.8 floating pane improvements](https://linuxiac.com/tmux-3-8-terminal-multiplexer-brings-floating-pane-improvements-built-in-themes/)
- [tmux PR #5293: floating panes with join-pane](https://github.com/tmux/tmux/pull/5293)
- [tmux-toggle-popup floating-pane backend](https://github.com/loichyan/tmux-toggle-popup/pull/70)
- [Waylon Walker: tmux join-pane](https://waylonwalker.com/tmux-join-pane/)
- [Baeldung: hiding tmux panes](https://www.baeldung.com/linux/tmux-pane-hide)
- Local `man tmux` (`next-3.9`): `side-status`, `new-pane`, `status-format`, `join-pane`.
