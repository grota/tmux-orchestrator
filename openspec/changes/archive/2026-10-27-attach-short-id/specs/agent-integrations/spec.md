# Spec Delta

## MODIFIED Requirements

### Requirement: Attach argument resolution

The attach argument SHALL resolve to the background session whose short id equals it. Otherwise it SHALL resolve to the session whose session id starts with it, and otherwise to the only running background session whose name contains it, ignoring case. If no session or more than one session matches, the argument MUST resolve to nothing.

#### Scenario: Short id

- **WHEN** the argument is `f7ca13fb` and a session's short id is `f7ca13fb`
- **THEN** the argument resolves to that session

#### Scenario: Short id that does not start the session id

- **WHEN** the argument is `0dd1ab1e`, a session's short id is `0dd1ab1e` and its session id starts with `5e55`
- **THEN** the argument resolves to that session

#### Scenario: Part of the name

- **WHEN** the argument is `title wrap` and only the session named `Agent title wrap settings` contains it
- **THEN** the argument resolves to that session

#### Scenario: Ambiguous name

- **WHEN** the argument is `agent` and two running sessions have names containing it
- **THEN** the argument resolves to nothing and no pane shows either session
