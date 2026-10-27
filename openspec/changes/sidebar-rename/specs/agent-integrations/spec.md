# Spec Delta

## ADDED Requirements

### Requirement: Claude Code agent rename

The reporter SHALL rename a Claude Code agent session by sending the rename control message to the messaging socket listed for the session in Claude's session registry, and SHALL treat the rename as done only once the registry shows the new name within three seconds. Any other outcome MUST fail the rename with a reason, and there MUST NOT be a fallback that changes only the sidebar.

#### Scenario: Claude confirms

- **WHEN** a Claude agent is renamed and the registry then shows the new name
- **THEN** the rename succeeds and the agent name is updated

#### Scenario: Claude ignores the message

- **WHEN** a Claude Code update ignores the rename message
- **THEN** the rename fails with a message that the internal rename message may have changed

### Requirement: OpenCode agent rename

The reporter SHALL rename an OpenCode agent session by sending `rename <sid> <title>` to the adapter's control socket. The adapter SHALL rename the session through the plugin API and answer `ok`, or `error` with the reason. A missing socket, no answer or an error MUST fail the rename with a reason.

#### Scenario: OpenCode refuses

- **WHEN** OpenCode refuses to rename a session
- **THEN** the rename fails with OpenCode's reason

#### Scenario: Old adapter

- **WHEN** the OpenCode adapter does not answer rename requests
- **THEN** the rename fails and asks to restart OpenCode

### Requirement: Contract tests for agent internals

The project SHALL provide contract tests that run the installed Claude Code and OpenCode in a private tmux server and check the internals the plugin relies on, without sending a prompt.

#### Scenario: Claude Code update drops the rename message

- **WHEN** the Claude contract test runs against a Claude Code that ignores the rename message
- **THEN** the test fails and names the missing behaviour
