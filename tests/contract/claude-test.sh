#!/usr/bin/env bash
# Contract test: checks that the installed Claude Code still has the internal,
# undocumented behaviour the reporter relies on (ADR-0009).  It starts a real
# interactive Claude in a private tmux server, sends it no prompt, and needs
# no API turn.  Run it after a Claude Code update; a failure means a feature
# of this project broke.  The checkout must be a folder Claude already trusts.
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BIN="$ROOT/bin/tmux-orchestrator"
S="tmux-orchestrator-contract-$$"
export TMUX_SOCKET=$S
PROBE="tmo-contract-$$"
RENAMED="tmo-contract-renamed-$$"
REGISTRY_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions

cleanup() { tmux -L "$S" kill-server 2>/dev/null || true; }
trap cleanup EXIT

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	if [[ -n ${PANE:-} ]]; then
		printf -- '--- Claude pane ---\n' >&2
		tmux -L "$S" capture-pane -p -t "$PANE" 2>/dev/null | grep -v '^[[:space:]]*$' >&2 || true
	fi
	exit 1
}
pass() { printf 'ok: %s\n' "$*"; }

command -v claude >/dev/null 2>&1 || fail 'claude is not on PATH'
printf 'Claude Code %s\n' "$(claude --version 2>/dev/null)"

# A session started from inside Claude must not inherit its messaging socket.
tmux -L "$S" -f /dev/null new-session -d -x 150 -y 40 -c "$ROOT" \
	"env -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDECODE claude -n $PROBE"
PANE=$(tmux -L "$S" display -p '#{pane_id}')

# The session registry: one JSON file per running session.
REGISTRY=''
for _ in $(seq 1 60); do
	REGISTRY=$(grep -l "\"name\":\"$PROBE\"" "$REGISTRY_DIR"/*.json 2>/dev/null | head -n 1 || true)
	[[ -n $REGISTRY ]] && break
	sleep 0.5
done
[[ -n $REGISTRY ]] || fail "no session registry entry named $PROBE in $REGISTRY_DIR"
SID=$(jq -r '.sessionId // empty' "$REGISTRY")
SOCKET=$(jq -r '.messagingSocketPath // empty' "$REGISTRY")
[[ -n $SID ]] || fail 'registry entry has no sessionId'
[[ -n $SOCKET && -S $SOCKET ]] || fail 'registry entry has no messagingSocketPath socket'
pass 'session registry lists sessionId, name and messagingSocketPath'

# The reporter treats a pane whose current command is claude as a Claude pane.
[[ $(tmux -L "$S" display -p -t "$PANE" '#{pane_current_command}') == claude ]] ||
	fail "pane_current_command is $(tmux -L "$S" display -p -t "$PANE" '#{pane_current_command}'), not claude"
pass 'pane_current_command is claude'

# Names: `claude agents --json` lists the session with its name.
NAME=$(claude agents --json 2>/dev/null | jq -r --arg id "$SID" '.[] | select(.sessionId == $id) | .name' 2>/dev/null || true)
[[ $NAME == "$PROBE" ]] || fail "claude agents --json does not list $SID named $PROBE"
pass 'claude agents --json lists sessionId and name'

# Rename: the reporter's own path, from outside Claude's process tree.
"$BIN" report --pane "$PANE" --kind claude --event SessionStart --session-id "$SID" --name "$PROBE"
"$BIN" rename "$PANE:1" "$RENAMED" || fail 'the reporter could not rename Claude through its messaging socket'
[[ $(jq -r .name "$REGISTRY") == "$RENAMED" ]] || fail 'registry does not show the new name'
pass 'rename control message applied and confirmed by the registry'
for _ in $(seq 1 20); do
	tmux -L "$S" capture-pane -p -t "$PANE" | grep -Fq "$RENAMED" && break
	sleep 0.25
done
tmux -L "$S" capture-pane -p -t "$PANE" | grep -Fq "$RENAMED" || fail 'Claude does not show the new name'
pass 'Claude shows the new name'
NAME=$(claude agents --json 2>/dev/null | jq -r --arg id "$SID" '.[] | select(.sessionId == $id) | .name' 2>/dev/null || true)
[[ $NAME == "$RENAMED" ]] || fail 'claude agents --json does not show the new name'
pass 'claude agents --json shows the new name'

printf 'claude contract passed\n'
