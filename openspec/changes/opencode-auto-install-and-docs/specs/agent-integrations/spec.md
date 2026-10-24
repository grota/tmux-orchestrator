# Spec Delta

## MODIFIED Requirements

### Requirement: Packaging

The repository SHALL provide a TPM-compatible tmux plugin, a Claude Code marketplace plugin, and an OpenCode 2.x TUI plugin that share one reporter and one version. The tmux plugin SHALL hold the only copy of the reporter. Installation MUST be user-level and MUST NOT merge hooks into or rewrite existing user configuration files.

#### Scenario: Tmux plugin load

- **WHEN** the user loads the repository as a tmux plugin
- **THEN** it configures the sidebar, key binding, and cleanup hook without additional setup

#### Scenario: Claude plugin enablement

- **WHEN** the user adds this repository as a Claude Code marketplace and enables the plugin
- **THEN** its hooks call the shared reporter and no manual hook JSON edit is required, even though Claude Code installs only the plugin's own directory

#### Scenario: OpenCode plugin install

- **WHEN** the user runs the OpenCode installer, or the tmux plugin loads with OpenCode auto-install enabled and OpenCode detected
- **THEN** the user's OpenCode plugin directory gains a link to the loaded tmux plugin's OpenCode adapter, any earlier copied adapter or server plugin file from this project is removed, and no agent configuration file is rewritten

#### Scenario: OpenCode plugin uninstall

- **WHEN** the user runs the uninstaller
- **THEN** the link and any earlier copied adapter or server plugin file from this project are removed

#### Scenario: Foreign plugin directory

- **WHEN** the OpenCode plugin path is a real directory or a link that this project did not create
- **THEN** the installer leaves it untouched and reports that it did so

## ADDED Requirements

### Requirement: OpenCode adapter auto-install

When `@tmux-orchestrator-opencode-auto-install` is `on` or unset, each tmux plugin load SHALL link the OpenCode adapter if OpenCode is detected: `opencode` is on the tmux server's `PATH` or the user's `~/.config/opencode` directory exists. If OpenCode is not detected, the load MUST NOT create any file or directory. When the option is `off`, the load MUST NOT create, change, or remove the adapter link.

#### Scenario: OpenCode installed, default option

- **WHEN** the tmux plugin loads with the option unset and `~/.config/opencode` exists
- **THEN** the OpenCode plugin directory links to the loaded copy's adapter

#### Scenario: OpenCode on PATH only

- **WHEN** the tmux plugin loads with the option `on`, `opencode` on the tmux server's `PATH`, and no `~/.config/opencode`
- **THEN** the adapter link is created

#### Scenario: OpenCode not installed

- **WHEN** the tmux plugin loads with the option `on`, no `opencode` on `PATH`, and no `~/.config/opencode`
- **THEN** no OpenCode directory or link is created

#### Scenario: Switching plugin copies

- **WHEN** OpenCode is detected and the user reloads tmux with a different copy of the tmux plugin
- **THEN** the adapter link points to the newly loaded copy

#### Scenario: Auto-install off

- **WHEN** the tmux plugin loads with the option `off` and an adapter link from an earlier load exists
- **THEN** the link is left as it is
