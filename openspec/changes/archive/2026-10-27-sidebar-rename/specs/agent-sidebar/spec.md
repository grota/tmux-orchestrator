# Spec Delta

## ADDED Requirements

### Requirement: Rename from the sidebar

Double-clicking a session row SHALL open a prompt that renames that tmux session. Double-clicking an agent row SHALL open a prompt prefilled with the agent name, and the answer SHALL rename the agent session in its agent. An empty answer MUST change nothing. The double-click binding MUST NOT be listed in the keys panel.

#### Scenario: Rename a session

- **WHEN** the user double-clicks the `alpha` session row and enters `api`
- **THEN** the tmux session is renamed `api` and its row shows `api`

#### Scenario: Rename an agent

- **WHEN** the user double-clicks an agent row and enters `it's "$HOME"`
- **THEN** the agent session is renamed `it's "$HOME"` in its agent, and the row shows that name

### Requirement: Rename answers are literal

A rename answer MUST reach tmux or the agent unchanged, whatever characters it holds, and MUST NOT pass through a shell.

#### Scenario: Special characters

- **WHEN** the user enters `it's "$HOME" ~ #1, ok; \x`
- **THEN** the new name is exactly that text

### Requirement: Rename failures are visible

A rename the agent does not confirm MUST show the reason to the client and MUST leave the agent name unchanged.

#### Scenario: Agent does not confirm

- **WHEN** the agent does not confirm the rename
- **THEN** tmux shows a message with the reason and the row keeps the old name
