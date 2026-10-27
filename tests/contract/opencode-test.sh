#!/usr/bin/env bash
# Contract test: checks that the installed OpenCode still loads the adapter
# and has the plugin API it uses (ADR-0009).  It runs a real OpenCode TUI in
# a private tmux server, with its own config, data and state directories, on
# a session created through the API.  It sends no prompt and needs no model.
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BIN="$ROOT/bin/tmux-orchestrator"
S="tmux-orchestrator-contract-oc-$$"
export TMUX_SOCKET=$S
TMP=$(mktemp -d "${TMPDIR:-/tmp}/tmux-orchestrator-contract.XXXXXX")
OC_ENV=(env "XDG_CONFIG_HOME=$TMP/home/.config" "XDG_DATA_HOME=$TMP/data" "XDG_STATE_HOME=$TMP/state")
RENAMED="tmo contract renamed $$"

cleanup() {
	tmux -L "$S" kill-server 2>/dev/null || true
	rm -rf "$TMP"
}
trap cleanup EXIT

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	if [[ -n ${PANE:-} ]]; then
		printf -- '--- OpenCode pane ---\n' >&2
		tmux -L "$S" capture-pane -p -t "$PANE" 2>/dev/null | grep -v '^[[:space:]]*$' >&2 || true
	fi
	exit 1
}
pass() { printf 'ok: %s\n' "$*"; }
opt() { tmux -L "$S" show-options -pqv -t "$PANE" "$1"; }

command -v opencode >/dev/null 2>&1 || fail 'opencode is not on PATH'
printf 'OpenCode %s\n' "$(opencode --version 2>/dev/null)"

# The adapter is linked the way the plugin links it: a directory symlink
# holding a bare tui.js.
"$BIN" install opencode --home "$TMP/home" --quiet
SID=$(cd "$ROOT" && "${OC_ENV[@]}" opencode api --standalone session.create -d '{"title":"tmo-contract"}' 2>/dev/null | jq -r '.data.id // empty')
[[ -n $SID ]] || fail 'opencode api session.create returned no session id'
pass "session.create made $SID"

tmux -L "$S" -f /dev/null new-session -d -x 150 -y 40 -c "$ROOT" \
	"$(printf '%q ' "${OC_ENV[@]}" opencode --standalone --session "$SID" .)"
tmux -L "$S" set-option -g @tmux-orchestrator-reporter "$BIN"
PANE=$(tmux -L "$S" display -p '#{pane_id}')

# The TUI loads the adapter, which reports its tab and registers its socket.
for _ in $(seq 1 60); do
	[[ $(opt @agent_1_sid) == "$SID" && -S $(opt @agent_socket) ]] && break
	sleep 0.5
done
[[ -S $(opt @agent_socket) ]] || fail 'the adapter did not register its control socket'
[[ $(opt @agent_1_sid) == "$SID" ]] || fail "the adapter did not report the tab of $SID"
[[ $(opt @agent_1_kind) == opencode ]] || fail 'the reported agent is not an OpenCode agent'
pass 'the TUI loads the adapter, which reports the tab and registers its socket'

# Rename: the reporter's own path, through api.client.session.update.
"$BIN" rename "$PANE:1" "$RENAMED" || fail 'the adapter could not rename the session'
pass 'api.client.session.update renamed the session'
for _ in $(seq 1 20); do
	[[ $(opt @agent_1_event) == opencode:session.renamed ]] && break
	sleep 0.25
done
[[ $(opt @agent_1_event) == opencode:session.renamed ]] || fail 'no session.renamed event reached the reporter'
[[ $(opt @agent_1_name_raw) == "$RENAMED" ]] || fail 'the sidebar does not show the new name'
pass 'session.renamed carries the new title back to the sidebar'
tmux -L "$S" capture-pane -p -t "$PANE" | grep -Fq "$RENAMED" || fail 'OpenCode does not show the new title'
pass 'OpenCode shows the new title'

# A refused rename is reported, not swallowed.
"$BIN" tabs --pane "$PANE" --active "$SID" --tab "$SID" idle "$RENAMED" --tab ses_00000000000000000000000000 idle ghost
ERR=$("$BIN" rename "$PANE:2" nope 2>&1) && fail 'renaming an unknown session succeeded'
[[ $ERR == *'OpenCode refused the rename'* ]] || fail "unexpected error: $ERR"
pass 'a rename OpenCode refuses fails with its reason'

printf 'opencode contract passed\n'
