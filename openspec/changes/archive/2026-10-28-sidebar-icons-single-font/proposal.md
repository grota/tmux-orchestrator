# Proposal

## Why

The sidebar's state icons do not line up. The working icon `◐` (U+25D0) is missing from JetBrains Mono, so the terminal draws it from a fallback font with a different size and baseline, while every other icon comes from JetBrains Mono.

## What Changes

- The `working` icon changes from yellow `◐` to yellow `●`.
- The `blocked` icon changes from red `●` to red `◉`, which reads as a stop sign.
- The change applies everywhere state icons appear: agent rows, session rollup icons, the blocked count in session rows (`●2` becomes `◉2`), the subagent indicator, and tmux, desktop and terminal notifications.
- Colors stay with their states.
- **BREAKING**: Anything that matches the old glyphs in notifications or sidebar output must use the new ones.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `agent-sidebar`: the working and blocked icons change in State presentation and in the Subagent indicator scenario.
- `agent-notifications`: blocked notifications start with `◉` instead of `●`.

## Impact

- `lib/sidebar-format` (state icon macro, blocked count in session rows)
- `bin/tmux-orchestrator` (`state_icon`, used by notifications)
- `README.md`, `docs/diagrams/architecture-animated.svg`
- `tests/sidebar-test.sh`, `tests/notifications-test.sh`, `tests/e2e-test.sh`
