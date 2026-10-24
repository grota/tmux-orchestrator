# Tasks

## 1. Auto-install on load

- [x] 1.1 In `tmux-orchestrator.tmux`, replace the `@tmux-orchestrator-opencode` read with `@tmux-orchestrator-opencode-auto-install` (anything but `off` means on) and call `install opencode --quiet` only when `opencode` is on `PATH` or `$HOME/.config/opencode` is a directory; verify by loading the plugin in a private tmux server with and without each signal
- [x] 1.2 Update `tests/install-test.sh`: replace the `@tmux-orchestrator-opencode on` case with cases for detected via config directory, detected via a stub `opencode` on `PATH`, not detected (no `~/.config/opencode` created), option `off` leaving an existing link untouched, and relinking to a second copy; verify `bash tests/install-test.sh` passes
- [x] 1.3 Check that no other file reads `@tmux-orchestrator-opencode` (`grep -rn 'tmux-orchestrator-opencode\b'` outside `openspec/` returns only the new option) and that the other test suites still pass

## 2. README and CHANGELOG

- [x] 2.1 Rewrite README Install › OpenCode to: the adapter is linked automatically when OpenCode is installed, restart OpenCode after the first install, and `set -g @tmux-orchestrator-opencode-auto-install off` disables it; verify the section no longer mentions `@tmux-orchestrator-opencode on`
- [x] 2.2 Add `## Optional command line commands` before `## Development` and move into it, unchanged: the alias paragraph from Install › tmux, Maintenance, Pause and resume, and the manual `install`/`uninstall opencode` commands; leave one sentence in Notifications pointing to Pause and resume; verify every moved command still appears exactly once in the README
- [x] 2.3 Keep the state icon colour column as text; verify the table is unchanged
- [x] 2.4 Create `CHANGELOG.md` (Keep a Changelog 1.1.0) with `## [Unreleased]`: Added `@tmux-orchestrator-opencode-auto-install`; Removed `@tmux-orchestrator-opencode`; Changed the OpenCode adapter is linked automatically when OpenCode is detected; verify the file follows the format and other changes can append to it
