# Design

## Context

State icons come from two places: the `icon` macro in `lib/sidebar-format`, which also drives session rollups and the subagent indicator, and `state_icon` in `bin/tmux-orchestrator`, which notifications use. The blocked count in session rows hardcodes `●` in `lib/sidebar-format`. See proposal.md for motivation.

## Goals / Non-Goals

**Goals:**

- Every state icon is a glyph JetBrains Mono covers, so all icons share one font's metrics.

**Non-Goals:**

- Supporting every terminal font. Other fonts may still lack a glyph.
- Changing colors or the `▸` current-session marker.

## Decisions

- **Working → `●` (U+25CF), blocked → `◉` (U+25C9).** Both are in JetBrains Mono (checked with `fc-list ':charset=25CF'` and `':charset=25C9'`). A solid dot reads as "live", and the ringed dot reads as a stop sign for a state that needs the user. The alternative `◔` (U+25D4) for working was rejected in favour of the user's choice.
- **Swap both icons in one change.** Reusing `●` for working requires moving blocked off it, or two states would share an icon and break the "distinct icon" requirement.

## Risks / Trade-offs

- [`◉` and `●` look alike in small cells] → Color separates them (red vs yellow), and the blocked count in session rows carries the same red `◉`.
- [External scripts matching `●` in notifications break] → Called out as breaking in the proposal and README.
