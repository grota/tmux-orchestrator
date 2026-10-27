#!/usr/bin/env bash
# Contract test: checks that the installed Claude Code still has the internal,
# undocumented behaviour the reporter relies on (ADR-0009, ADR-0010).  It
# starts a real interactive Claude in a private tmux server and sends it no
# prompt, so it needs no API turn.  TMUX_ORCHESTRATOR_CONTRACT_TURN=1 also
# interrupts one Haiku turn to check interrupt detection end to end.  Run it after a Claude Code update; a failure means a feature
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
	"env -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDECODE claude --model haiku -n $PROBE"
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
[[ $(jq -r '.status // empty' "$REGISTRY") == idle ]] || fail "registry status is $(jq -c .status "$REGISTRY"), not idle"
pass 'session registry reports status idle before a prompt'

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

# Interrupts: the registry status goes idle without a Stop hook.
if [[ ${TMUX_ORCHESTRATOR_CONTRACT_TURN:-} == 1 ]]; then
	tmux -L "$S" send-keys -t "$PANE" -l 'Write a 6000-word story in 12 numbered chapters about a lighthouse keeper. Do not use any tools.'
	tmux -L "$S" send-keys -t "$PANE" Enter
	"$BIN" report --pane "$PANE" --kind claude --event UserPromptSubmit --session-id "$SID"
	for _ in $(seq 1 40); do
		[[ $(jq -r .status "$REGISTRY") == busy ]] && break
		sleep 0.25
	done
	[[ $(jq -r .status "$REGISTRY") == busy ]] || fail 'registry status did not turn busy during a turn'
	sleep 1.5
	tmux -L "$S" send-keys -t "$PANE" Escape
	for _ in $(seq 1 60); do
		[[ $(tmux -L "$S" show-options -pqv -t "$PANE" @agent_1_event) == claude:Interrupted ]] && break
		sleep 0.25
	done
	[[ $(tmux -L "$S" show-options -pqv -t "$PANE" @agent_1_event) == claude:Interrupted ]] ||
		fail "an interrupted turn was not detected; registry status is $(jq -r .status "$REGISTRY")"
	[[ $(tmux -L "$S" show-options -pqv -t "$PANE" @agent_1_state) == idle ]] || fail 'the interrupted agent is not idle'
	pass 'an interrupted turn is detected from the registry status'
else
	printf 'skip: interrupt detection (set TMUX_ORCHESTRATOR_CONTRACT_TURN=1; costs one Haiku turn)\n'
fi

# Attached background sessions: a session started with --bg and no prompt
# waits for one, so it costs no model turn.
BG=$(cd "$ROOT" && env -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDECODE \
	claude --bg -n "$PROBE-bg" </dev/null 2>/dev/null | awk '/^backgrounded/ { print $3; exit }')
[[ -n $BG ]] || fail 'claude --bg printed no short id'
trap 'claude stop "$BG" >/dev/null 2>&1; claude rm "$BG" >/dev/null 2>&1; cleanup' EXIT
BG_JSON=$(claude agents --json 2>/dev/null | jq -c --arg id "$BG" '.[] | select(.id == $id)')
BG_SID=$(jq -r '.sessionId // empty' <<<"$BG_JSON")
[[ -n $BG_SID ]] || fail "claude agents --json does not list background session $BG with a sessionId"
[[ $(jq -r .kind <<<"$BG_JSON") == background ]] || fail 'the background session is not listed as background'
[[ $(jq -r '.state // empty' <<<"$BG_JSON") =~ ^(working|blocked|done|failed|stopped)$ ]] ||
	fail "unexpected background state: $(jq -c .state <<<"$BG_JSON")"
pass 'claude agents --json lists the background session with id, sessionId and state'
# Observed, not documented; the reporter matches the id first anyway.
[[ $BG_SID == "$BG"* ]] || printf 'note: the short id %s no longer starts the session id %s\n' "$BG" "$BG_SID"

# `claude attach <id>` in a pane: the reporter finds it in the process table
# and adopts the session when a client views the pane.
tmux -L "$S" new-window -d -n attached -c "$ROOT" \
	"env -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDECODE claude attach $BG"
ATTACHED=$(tmux -L "$S" display -p -t :attached '#{pane_id}')
tmux -L "$S" select-window -t :attached
(env -u TMUX TERM=xterm-256color timeout 30 script -qefc "tmux -L $S attach" /dev/null >/dev/null 2>&1 </dev/null &)
for _ in $(seq 1 40); do
	"$BIN" focus
	[[ $(tmux -L "$S" show-options -pqv -t "$ATTACHED" @agent_attached) == "$BG_SID" ]] && break
	sleep 0.5
done
[[ $(tmux -L "$S" show-options -pqv -t "$ATTACHED" @agent_attached) == "$BG_SID" ]] ||
	fail "the reporter did not adopt background session $BG shown by claude attach"
pass 'claude attach is found in the process table and adopted'
# An unprompted background session waits for its first prompt.
[[ $(tmux -L "$S" show-options -pqv -t "$ATTACHED" @agent_1_state) == blocked ]] ||
	fail "the attached row is $(tmux -L "$S" show-options -pqv -t "$ATTACHED" @agent_1_state), not blocked from its state"
pass 'the attached row takes the state claude agents --json reports'

printf 'claude contract passed\n'
