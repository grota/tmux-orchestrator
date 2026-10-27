# Spec Delta

## MODIFIED Requirements

### Requirement: Focused agent emphasis

The sidebar SHALL emphasise the focused agent's name for the client viewing it, in the style set by `@tmux-orchestrator-focus-style`: `underlined` (the default), `bold`, or `none`. Any other value MUST behave like `underlined`. The style MUST apply on the next redraw without a reload, and to every line of a wrapped name. Other agents' names MUST NOT be emphasised, and no extra marker column is added.

#### Scenario: Focused Claude agent

- **WHEN** the client views a pane holding one Claude agent and the option is unset
- **THEN** that agent's name is underlined in that client's sidebar

#### Scenario: Focused OpenCode tab

- **WHEN** the client views an OpenCode pane whose active tab is `docs`
- **THEN** only the `docs` agent's name is emphasised, not the other tabs of that pane

#### Scenario: Two clients

- **WHEN** two clients view different agent panes of the same session
- **THEN** each client's sidebar emphasises its own focused agent

#### Scenario: Bold style

- **WHEN** `@tmux-orchestrator-focus-style` is set to `bold`
- **THEN** the focused agent's name is bold and not underlined, without a reload

#### Scenario: No emphasis

- **WHEN** `@tmux-orchestrator-focus-style` is `none`
- **THEN** the focused agent's name looks like any other agent's name
