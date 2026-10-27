#!/usr/bin/env bash
# Renames agents from the sidebar's prompt against fake agents: a Claude
# session registry with a messaging socket, and an OpenCode adapter socket.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/tmux-orchestrator"
. "$ROOT/tests/helpers.sh"
S="tmux-orchestrator-rename-$$"
export TMUX_SOCKET=$S
TMP=$(mktemp -d "${TMPDIR:-/tmp}/tmux-orchestrator-rename.XXXXXX")
export CLAUDE_CONFIG_DIR="$TMP/claude"
mkdir -p "$CLAUDE_CONFIG_DIR/sessions"
PIDS=()

cleanup() {
	for pid in ${PIDS[@]+"${PIDS[@]}"}; do kill "$pid" 2>/dev/null || true; done
	tmux -L "$S" kill-server 2>/dev/null || true
	rm -rf "$TMP"
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }

# fake_agent MODE SOCKET [REGISTRY]: claude applies a rename frame to the
# registry; claude-deaf ignores it; opencode answers ok, or an error for ses_gone.
fake_agent() {
	python3 -I - "$@" <<'EOF' &
import json, os, socket, sys
mode, path = sys.argv[1], sys.argv[2]
registry = sys.argv[3] if len(sys.argv) > 3 else None
server = socket.socket(socket.AF_UNIX)
server.bind(path)
server.listen()
while True:
    conn, _ = server.accept()
    line = conn.makefile().readline().strip()
    if mode == "claude":
        frame = json.loads(line)
        if frame.get("type") == "control" and frame.get("action") == "rename":
            data = json.load(open(registry))
            data["name"] = frame["name"]
            json.dump(data, open(registry, "w"))
    elif mode == "opencode":
        sid = line.split(" ")[1]
        conn.sendall(b"error OpenCode refused the rename: Session not found\n" if sid == "ses_gone" else b"ok\n")
    conn.close()
EOF
	PIDS+=($!)
	for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -S $2 ]] && return 0; sleep 0.1; done
	fail "fake agent did not listen on $2"
}

tmux -L "$S" new-session -d -s alpha -x 120 -y 40 'sleep 300'
tmux -L "$S" set-option -g @tmux-orchestrator-opencode-auto-install off
tmux -L "$S" split-window -t alpha -d 'sleep 300'
"$ROOT/tmux-orchestrator.tmux"
PC=$(tmux -L "$S" display -p -t alpha:0.0 '#{pane_id}')
PO=$(tmux -L "$S" display -p -t alpha:0.1 '#{pane_id}')

# The double click renames a session row with tmux's own prompt and an agent
# row through the reporter; the keys panel leaves it out.
KEYS=$(tmux -L "$S" list-keys -T root DoubleClick1Status)
[[ $KEYS == *'rename-session'* && $KEYS == *'rename-prompt #{mouse_status_range} #{client_name}'* ]] || fail "double click binding: $KEYS"
[[ $("$BIN" select keys; tmux -L "$S" show-options -gv @tmux-orchestrator-keys-list) != *DoubleClick1Status* ]] || fail 'keys panel lists the double click'
"$BIN" select keys

# A Claude agent is renamed in Claude, and the sidebar follows once the
# session registry confirms it.
report_state "$PC" idle old-claude claude ses_claude
fake_agent claude "$TMP/claude.sock" "$CLAUDE_CONFIG_DIR/sessions/101.json"
printf '{"pid":101,"sessionId":"ses_claude","name":"old-claude","messagingSocketPath":"%s"}' "$TMP/claude.sock" >"$CLAUDE_CONFIG_DIR/sessions/101.json"
"$BIN" rename "$PC:1" 'new claude name' || fail 'claude rename failed'
assert_eq "$(jq -r .name "$CLAUDE_CONFIG_DIR/sessions/101.json")" 'new claude name'
assert_eq "$(opt "$PC" @agent_1_name_raw)" 'new claude name'

# A Claude that ignores the rename fails loudly and keeps the old name.
fake_agent claude-deaf "$TMP/deaf.sock"
printf '{"pid":101,"sessionId":"ses_claude","name":"new claude name","messagingSocketPath":"%s"}' "$TMP/deaf.sock" >"$CLAUDE_CONFIG_DIR/sessions/101.json"
ERR=$("$BIN" rename "$PC:1" ignored 2>&1) && fail 'ignored rename succeeded'
[[ $ERR == *'Claude did not apply the rename'* ]] || fail "unexpected error: $ERR"
assert_eq "$(opt "$PC" @agent_1_name_raw)" 'new claude name'

# A Claude session missing from the registry fails too.
rm "$CLAUDE_CONFIG_DIR/sessions/101.json"
ERR=$("$BIN" rename "$PC:1" lost 2>&1) && fail 'rename without registry succeeded'
[[ $ERR == *'no running Claude session ses_claude'* ]] || fail "unexpected error: $ERR"

# OpenCode answers on its adapter socket; a refusal keeps the old name.
"$BIN" tabs --pane "$PO" --active ses_a --tab ses_a idle api --tab ses_gone idle docs
fake_agent opencode "$TMP/opencode.sock"
"$BIN" register --pane "$PO" --socket "$TMP/opencode.sock"
"$BIN" rename "$PO:1" 'api v2' || fail 'opencode rename failed'
assert_eq "$(opt "$PO" @agent_1_name_raw)" 'api v2'
ERR=$("$BIN" rename "$PO:2" whatever 2>&1) && fail 'refused rename succeeded'
[[ $ERR == *'OpenCode refused the rename: Session not found'* ]] || fail "unexpected error: $ERR"
assert_eq "$(opt "$PO" @agent_2_name_raw)" docs

# The prompt: a client types a name with quotes, $, ~, #, a comma, ; and \.  The
# answer never passes through a shell, so it arrives unchanged.
(env -u TMUX TERM=xterm-256color timeout 10 script -qefc "stty rows 40 cols 120; tmux -L $S attach -t alpha" /dev/null >/dev/null 2>&1) &
PIDS+=($!)
CLIENT=''
for _ in 1 2 3 4 5 6 7 8 9 10; do
	CLIENT=$(tmux -L "$S" list-clients -F '#{client_name}' | head -n 1)
	[[ -n $CLIENT ]] && break
	sleep 0.2
done
[[ -n $CLIENT ]] || fail 'no client attached'
"$BIN" rename-prompt "$PO:1" "$CLIENT"
# C-u clears the prefilled name.
tmux -L "$S" send-keys -K -c "$CLIENT" C-u
tmux -L "$S" send-keys -K -l -c "$CLIENT" 'it'\''s "$HOME" ~ #1, ok; \x {a}'
tmux -L "$S" send-keys -K -c "$CLIENT" Enter
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
	[[ $(opt "$PO" @agent_1_name_raw) != 'api v2' ]] && break
	sleep 0.2
done
assert_eq "$(opt "$PO" @agent_1_name_raw)" 'it'\''s "$HOME" ~ #1, ok; \x {a}'
[[ -z $(tmux -L "$S" show-options -gqv @tmux-orchestrator-rename-row) ]] || fail 'rename row left behind'

# The prompt starts from the current name, # included.
"$BIN" rename-prompt "$PO:1" "$CLIENT"
tmux -L "$S" send-keys -K -c "$CLIENT" End
tmux -L "$S" send-keys -K -l -c "$CLIENT" '!'
tmux -L "$S" send-keys -K -c "$CLIENT" Enter
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
	[[ $(opt "$PO" @agent_1_name_raw) == *'!' ]] && break
	sleep 0.2
done
assert_eq "$(opt "$PO" @agent_1_name_raw)" 'it'\''s "$HOME" ~ #1, ok; \x {a}!'

printf 'rename tests passed\n'
