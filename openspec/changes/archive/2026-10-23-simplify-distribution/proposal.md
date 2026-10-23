# Proposal

## Why

The Claude Code adapter finds the reporter three directories above its own `hooks/` folder. That works only from a git checkout: Claude Code copies a marketplace plugin's directory alone into its cache, so an installed plugin cannot reach `bin/tmux-orchestrator` and reports nothing. The OpenCode installer copies the adapter and bakes in an absolute reporter path, so it goes stale when the tmux plugin moves or updates. The README installs everything from a checkout under `/home/you`.

## What Changes

- The tmux plugin publishes its reporter path in a tmux option on every load. Both adapters look the reporter up there, so the reporter always comes from the tmux plugin copy that is loaded.
- **BREAKING**: The OpenCode adapter is installed as a symlink to the loaded copy's `plugins/opencode` directory, not as a copy with a substituted path. Setting `@tmux-orchestrator-opencode on` makes the tmux plugin create and maintain the link; the `install opencode` and `uninstall opencode` commands stay for scripted setups.
- Adapters send a report protocol version. A reporter that does not know the version ignores the call and shows a one-time message asking to update.
- A restored OpenCode tab that is waiting for permission or input shows `blocked`, including waits in its child sessions.
- The README installs through TPM (`grota/tmux-orchestrator`) and the Claude Code marketplace. Running from a git checkout (`run-shell`, `--plugin-dir`) moves to a Development section.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `agent-integrations`: packaging changes to TPM, a marketplace plugin that needs no repository files, and an OpenCode symlink; new requirements for reporter discovery and the report protocol version; OpenCode tab tracking catches waits that load after a tab appears.

## Impact

- **Code**: `tmux-orchestrator.tmux`, `bin/tmux-orchestrator` (install commands, protocol check), `plugins/claude/hooks/report.sh`, `plugins/opencode/tui.js`.
- **Tests**: install, fixtures and plugin tests move from substituted paths to the tmux option; new cases for the symlink option and the protocol check.
- **Docs**: README install and development sections; ADR-0007.
- **Users**: OpenCode users rerun `install opencode` or set the new option once; the old copied `tui.js` is replaced by the link.
