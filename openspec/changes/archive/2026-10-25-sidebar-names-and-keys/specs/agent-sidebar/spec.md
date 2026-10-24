# Spec Delta

## MODIFIED Requirements

### Requirement: Agent list

The sidebar SHALL list the tracked agents of the client's current session in stable window and pane order, and in tab order within a pane, showing a state icon and the agent name, followed by a line with the agent kind and, unless hidden, the time in state right-aligned.

#### Scenario: Agent row content

- **WHEN** a Claude agent named `fix-login` has been working for 45 seconds in the current session
- **THEN** its first line shows the working icon and `fix-login`, and the line below shows `claude` with `45s` right-aligned

#### Scenario: Time hidden

- **WHEN** `@tmux-orchestrator-time` is `off`
- **THEN** the kind line shows only the agent kind

#### Scenario: OpenCode tabs

- **WHEN** an OpenCode pane has two tabs named `api` and `docs`
- **THEN** the sidebar shows two rows for that pane, in tab order, each with its own state

#### Scenario: Duplicate names

- **WHEN** two agents in one session share a name
- **THEN** both rows are shown and each still targets its own pane and tab

#### Scenario: Long name

- **WHEN** an agent name does not fit the sidebar width and wrapping is off
- **THEN** the displayed name is truncated with an ellipsis and the row remains clickable

### Requirement: Keyboard control

The system SHALL provide a tmux key binding, `prefix + O` by default, that shows and hides the sidebar, and a command usable from `run-shell`. The key MUST be configurable and MUST NOT require keyboard focus inside the sidebar.

#### Scenario: Toggle off

- **WHEN** the user presses the toggle binding while the sidebar is visible
- **THEN** the sidebar hides for all sessions and agent tracking continues

#### Scenario: Toggle on

- **WHEN** the user presses the toggle binding while the sidebar is hidden
- **THEN** the sidebar returns on its configured side with current state

## ADDED Requirements

### Requirement: Agent name length

The sidebar SHALL fit agent names according to `@tmux-orchestrator-name-max-chars`: unset or `wrap` wraps the name over up to four lines, a positive number `N` shows one line cut at `N` characters or the available width, whichever is shorter, and `nowrap` shows one line cut to the available width. A cut name MUST end in `…`.

#### Scenario: Short name with wrapping

- **WHEN** the option is unset and the agent name fits on one line
- **THEN** the name takes one line and no empty line follows it

#### Scenario: Long name with wrapping

- **WHEN** the option is `wrap` and the agent name needs two lines at the current width
- **THEN** the name continues on a second line indented two columns, under its first character

#### Scenario: Name longer than four lines

- **WHEN** the option is `wrap` and the agent name needs more than four lines
- **THEN** four lines are shown and the fourth ends in `…`

#### Scenario: Fixed character limit

- **WHEN** the option is `12` and the agent name is `refactor-the-login-flow`
- **THEN** one line shows the first characters of the name cut to 12 characters ending in `…`

#### Scenario: No wrapping

- **WHEN** the option is `nowrap` and the agent name does not fit
- **THEN** one line shows the name cut to the sidebar width, ending in `…`

#### Scenario: Resize while wrapped

- **WHEN** the user drags the sidebar border to a new width
- **THEN** wrapped names are re-wrapped to the new width on the next redraw, without any agent event

### Requirement: Focused agent emphasis

The sidebar SHALL show the focused agent's name in bold for the client viewing it. Other agents' names MUST NOT be bold, and no extra marker column is added.

#### Scenario: Focused Claude agent

- **WHEN** the client views a pane holding one Claude agent
- **THEN** that agent's name is bold in that client's sidebar

#### Scenario: Focused OpenCode tab

- **WHEN** the client views an OpenCode pane whose active tab is `docs`
- **THEN** only the `docs` agent's name is bold, not the other tabs of that pane

#### Scenario: Two clients

- **WHEN** two clients view different agent panes of the same session
- **THEN** each client's sidebar shows its own focused agent in bold

### Requirement: Keys panel

The sidebar SHALL end with a right-aligned, clickable `? keys` row that opens and closes the keys panel for all clients. The open panel MUST list the toggle key and every tmux key binding whose command calls the reporter, with its key table, key and reporter subcommand, read when the panel opens. It MUST NOT list fixed mouse actions or tmux's own border actions.

#### Scenario: Open the panel

- **WHEN** the user clicks `? keys` while the panel is closed
- **THEN** every client's sidebar shows the keys panel listing `prefix O` for the toggle

#### Scenario: Close the panel

- **WHEN** the user clicks `? keys` while the panel is open
- **THEN** the panel closes for every client

#### Scenario: User binding discovered

- **WHEN** the user has bound `prefix N` to run the reporter's `notify pause` and then opens the panel
- **THEN** the panel lists `prefix N` with `notify pause`

#### Scenario: Binding added after load

- **WHEN** the user adds a binding that calls the reporter after the plugin loaded, then closes and reopens the panel
- **THEN** the new binding is listed without reloading the plugin

#### Scenario: Toggle key skipped

- **WHEN** the toggle key was not bound because of a conflicting user binding
- **THEN** the panel does not list a toggle key

### Requirement: Toggle key does not overwrite user bindings

The plugin SHALL bind the toggle key only when that key has no binding in the prefix table or is already bound to the plugin's toggle. Otherwise it MUST leave the existing binding in place and show a message naming the key once per plugin load. On load, the plugin MUST remove its own toggle binding from any other prefix key.

#### Scenario: Key already used by the user

- **WHEN** the user's configuration binds `prefix O` to another command before the plugin loads
- **THEN** `prefix O` keeps the user's command and tmux shows a message that the toggle key was not bound

#### Scenario: Plugin reloaded

- **WHEN** the plugin loads again with the same toggle key
- **THEN** the toggle binding is refreshed and no message is shown

#### Scenario: Toggle key changed

- **WHEN** the toggle key changes from `O` to `T` and the plugin reloads
- **THEN** `prefix T` toggles the sidebar and `prefix O` no longer has the plugin's binding
