# Spec Delta

## MODIFIED Requirements

### Requirement: Claude Code interrupt detection

Because Claude Code sends no hook when a turn is interrupted, the system SHALL detect an interrupt of a `working` or `blocked` Claude agent from the session status in Claude Code's session registry, and set the agent to `idle` within a few seconds. An interrupt MUST be reported only after two consecutive `idle` readings while the agent is still `working` or `blocked`. Detection MUST stop when the agent leaves `working` and `blocked`, when a new prompt starts a new turn, or when the session's registry entry disappears or names another session.

#### Scenario: Interrupted tool call

- **WHEN** the user presses Esc while a Claude agent runs a tool
- **THEN** the agent becomes `idle` within a few seconds without any further input

#### Scenario: Interrupted text

- **WHEN** the user presses Esc while Claude writes text on the session's first prompt
- **THEN** the agent becomes `idle` within a few seconds

#### Scenario: Subagent interrupt

- **WHEN** a subagent's work is interrupted while the session stays `busy`
- **THEN** the main agent keeps its state

#### Scenario: Turn finishes normally

- **WHEN** the session turns `idle` and the turn's `Stop` arrives before a second reading
- **THEN** detection for that turn ends and the agent shows `done`
