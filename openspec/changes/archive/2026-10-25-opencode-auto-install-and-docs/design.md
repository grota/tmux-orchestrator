# Design

## Context

`tmux-orchestrator.tmux` reads `@tmux-orchestrator-opencode` and, when it is `on`, runs `install opencode --quiet` on every load. `install_opencode` in `bin/tmux-orchestrator` already handles linking, relinking to another copy, and leaving foreign paths alone (`opencode_path_is_ours`). TPM runs the plugin script with the tmux server's environment, so its `PATH` is the one the server started with, often without directories added by shell startup files (such as `~/.opencode/bin`).

## Goals / Non-Goals

**Goals:**
- Link the adapter without user action whenever OpenCode is present, and never create OpenCode files when it is not.
- Keep the README's setup path short by moving rarely used commands to one later section.

**Non-Goals:**
- Registering the adapter through `opencode.json`: it would rewrite user configuration, which the Packaging requirement forbids.
- Removing the link when the option is turned `off`; `uninstall opencode` does that.
- Rewriting the toggle-key or Notifications README text (owned by `sidebar-names-and-keys` and `split-notification-channels`).

## Decisions

- **Detection lives in `tmux-orchestrator.tmux`, not in `install_opencode`.** The manual command must keep linking unconditionally, as today. The load script checks `command -v opencode` or `[[ -d $HOME/.config/opencode ]]` and only then calls the installer. Alternative: a `--if-detected` flag on `install`; rejected because nothing else needs it.
- **Two signals, either one suffices.** `PATH` alone misses installs whose bin directory is added by a shell startup file; the config directory alone misses a fresh install that has never run. OpenCode creates `~/.config/opencode` on first run, so the gap closes after one OpenCode start plus a tmux reload.
- **The option is `on` unless it is exactly `off`.** This matches how other on/off options (`@tmux-orchestrator-time`) are read and makes the default `on`.
- **The old option is ignored, not migrated.** Users who set `@tmux-orchestrator-opencode on` have OpenCode installed, so the new default produces the same link. Users who set it to `off` to avoid linking must set the new option to `off`; the CHANGELOG says so.
- **README order.** New `## Optional command line commands` goes immediately before `## Development`. It opens with the alias (moved from Install › tmux), then subsections for Maintenance, Pause and resume, and OpenCode install and uninstall. Notifications keeps one sentence pointing to Pause and resume. Section text is moved as is; edits from the other two changes are merged when they land.

## Risks / Trade-offs

- [OpenCode installed but never run, and its bin directory not on the server `PATH`] → No link until OpenCode has run once and tmux reloads. The README says to restart OpenCode after the first install, and the manual command remains.
- [A user without OpenCode who has a leftover `~/.config/opencode` directory] → Gets a harmless link; the adapter only loads inside OpenCode.
- [Users relying on the old option being unset to avoid a link] → Behaviour changes to linking; called out as BREAKING in the CHANGELOG.

## Migration Plan

Replace `set -g @tmux-orchestrator-opencode on` with nothing (default) or remove it; replace `off` with `set -g @tmux-orchestrator-opencode-auto-install off`. Rollback: revert the commit; the old option is read again.
