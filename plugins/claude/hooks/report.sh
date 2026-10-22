#!/usr/bin/env bash
# Resolve the shared reporter from the repository checkout that contains this
# plugin.  CLAUDE_PLUGIN_ROOT is intentionally not used for the repository
# root: the plugin lives one directory below it.
set -u
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd || true)
reporter=${TMUX_ORCHESTRATOR_REPORTER:-$root/bin/tmux-orchestrator}
if [[ ! -x $reporter ]]; then
	reporter=$(command -v tmux-orchestrator 2>/dev/null || true)
fi
[[ -n $reporter ]] || exit 0
exec "$reporter" report --source claude --json
