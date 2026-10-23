# The OpenCode adapter runs in the TUI, not the server

OpenCode 2.x runs every terminal TUI against one shared background service, and server plugins run inside that service. The service inherits `TMUX_PANE` from whichever pane first started it, its event stream covers every TUI and project, and only the TUI knows its tabs and which one is active. We therefore install the OpenCode adapter as a TUI plugin, which runs in the agent pane's own process and can map events, tabs and focus to that pane.

## Considered Options

- **A server plugin.** Rejected: it cannot tell which pane or tab an event belongs to, so it reports to a stale pane or to none.
- **A server plugin plus a TUI plugin.** Rejected: the TUI already receives the events the adapter needs, so a server half adds a second process without information.

## Consequences

- The adapter is installed as `~/.config/opencode/plugins/tmux-orchestrator/tui.js`, which OpenCode discovers without editing `opencode.json` or `cli.json`.
- OpenCode 1.x is not supported; v1 plugins do not run in 2.x.
- Closing a tab fires no event, so the adapter detects tab changes by comparing `ui.tabs.list()` over time.
- A sidebar click focuses a tab through a Unix socket that the TUI plugin opens per pane, because no OpenCode command targets a single TUI.
