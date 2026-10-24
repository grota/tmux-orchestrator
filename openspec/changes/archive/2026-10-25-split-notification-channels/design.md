# Design

## Context

`notify_agent` in `bin/tmux-orchestrator` reads `@tmux-orchestrator-notify` (`both|tmux|desktop|off`) to pick tmux and/or the "desktop part", then `@tmux-orchestrator-notify-via` (`desktop|terminal|both|none`) to pick how that desktop part is delivered. The terminal route (`notify_terminal`, OSC 9) is therefore nested under the desktop channel. `notify_status` prints the channel, pause state, desktop availability, and `via`.

## Goals / Non-Goals

**Goals:**
- Three independent on/off options, read once per notification.
- Keep the current delivery code paths (`display-message`, `notify_desktop`, `notify_terminal`) and their suppression rules.

**Non-Goals:**
- Honouring or migrating the old options.
- A master switch or new pause behaviour.
- Changing notification text or OSC 9 client selection.

## Decisions

- **Option parsing:** one helper, `channel_on <name> <default>`, returns success when the option is `on`, or when it is unset or unrecognised and the default is `on`. Alternative: accept `1/0/true/false` too. Rejected: the other `@tmux-orchestrator-*` toggles (`time`, `opencode`) use `on`/`off` only.
- **Terminal follows the desktop rules:** it is suppressed when any client views the agent and has no cooldown, as today under `via terminal`. Both reach the user outside tmux, so a viewer already sees the change.
- **Early exit:** when all three channels are off, `notify_agent` returns before listing clients, as it does today for `notify off`.
- **Status output:** replace `notifications: <channel>` and `via:` with `notifications: active|paused|off` (`off` when all three channels are off) followed by one line per channel (`tmux: on`, `desktop: on`, `terminal: off`), then the existing `desktop: available (...)|unavailable` detail folded into the desktop line, for example `desktop: on (notify-send)` or `desktop: on (unavailable)`.
- **Terminal default `off`:** Ghostty, iTerm2, WezTerm and Windows Terminal turn OSC 9 into a system popup, so with `notify-send` also on, every event would show twice. Users over SSH turn it on.

## Risks / Trade-offs

- [Silent breakage for users of the old options] → BREAKING entry in the CHANGELOG and README; the defaults still notify, so nobody silently loses notifications unless they had `notify off`.
- [A user who had `notify off` starts receiving notifications] → Called out in the CHANGELOG with the replacement settings.

## Migration Plan

| Old setting | New settings |
| --- | --- |
| `notify both` (default) | defaults |
| `notify tmux` | `notify-desktop off` |
| `notify desktop` | `notify-tmux off` |
| `notify off` | all three `off` |
| `notify-via terminal` | `notify-desktop off`, `notify-terminal on` |
| `notify-via both` | `notify-terminal on` |
| `notify-via none` | `notify-desktop off` |
