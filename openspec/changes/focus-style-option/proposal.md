# Proposal

## Why

The focused agent's name is always bold. Some terminal themes render bold close to normal weight, and some users want no emphasis at all.

## What Changes

- Add `@tmux-orchestrator-focus-style`: `underlined` (default), `bold` or `none`. It is read live, with no reload. Any other value behaves like `underlined`.
- **BREAKING**: The focused agent's name is underlined by default instead of bold. Set the option to `bold` to keep the previous look.
- Every wrapped line of the focused name carries the emphasis.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `agent-sidebar`: the focused agent emphasis is configurable.

## Impact

- `lib/sidebar-format`, `tmux-orchestrator.tmux`: a new `emph` fragment replaces the inline bold.
- `tests/sidebar-test.sh`, `README.md`, `CHANGELOG.md`.
