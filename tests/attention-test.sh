#!/usr/bin/env bash
# The attention key: its binding, and which agent and client it brings forward.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/tmux-orchestrator"
. "$ROOT/tests/helpers.sh"
S="tmux-orchestrator-attention-$$"
export TMUX_SOCKET=$S
TMP=$(mktemp -d)
RAISE_LOG="$TMP/raise.log"

cleanup() {
	kill "${C1_PID:-}" "${C2_PID:-}" 2>/dev/null || true
	tmux -L "$S" kill-server 2>/dev/null || true
	rm -rf "$TMP"
}
trap cleanup EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }
pane_of() { tmux -L "$S" display -p -t "$1" '#{pane_id}'; }
# FORMAT read for client NAME, and the client attached to SESSION.
client_fmt() { tmux -L "$S" list-clients -F "#{client_name} $2" | awk -v c="$1" '$1 == c { print $2 }'; }
client_of() { tmux -L "$S" list-clients -F '#{client_session} #{client_name}' | awk -v s="$1" '$1 == s { print $2 }'; }
attach() {
	(env -u TMUX TERM=xterm-256color timeout 60 script -qefc "tmux -L $S attach -t $1" "$TMP/$1.log" >/dev/null 2>&1) &
	local i
	for i in $(seq 1 30); do
		[[ -n $(client_of "$1") ]] && break
		sleep 0.1
	done
}

tmux -L "$S" new-session -d -s alpha -n main -x 120 -y 40 'sleep 300'
tmux -L "$S" set-option -g @tmux-orchestrator-opencode-auto-install off
tmux -L "$S" split-window -t alpha:main -d 'sleep 300'
tmux -L "$S" new-window -d -t alpha -n other 'sleep 300'
tmux -L "$S" new-session -d -s beta -n agents -x 120 -y 40 'sleep 300'
tmux -L "$S" new-window -d -t beta -n other 'sleep 300'
"$ROOT/tmux-orchestrator.tmux"
P0=$(pane_of alpha:main.0)
P1=$(pane_of alpha:main.1)
PB=$(pane_of beta:agents.0)

# No key is bound by default.  A key binds in the prefix table, or in the
# table the option names, and moves when the table changes.
tmux -L "$S" list-keys | grep -q ' attention' && fail 'attention key bound by default'
tmux -L "$S" set-option -g @tmux-orchestrator-attention-key M-a
"$ROOT/tmux-orchestrator.tmux"
tmux -L "$S" list-keys -T prefix M-a | grep -q ' attention' || fail 'not bound after the prefix'
tmux -L "$S" set-option -g @tmux-orchestrator-attention-table root
"$ROOT/tmux-orchestrator.tmux"
tmux -L "$S" list-keys -T root M-a | grep -q ' attention' || fail 'not bound in the root table'
[[ -z $(tmux -L "$S" list-keys -T prefix M-a 2>/dev/null) ]] || fail 'prefix binding left behind'
# A user's own binding is never overwritten.
tmux -L "$S" bind-key -n M-s display-message mine
tmux -L "$S" set-option -g @tmux-orchestrator-attention-key M-s
"$ROOT/tmux-orchestrator.tmux"
tmux -L "$S" list-keys -T root M-s | grep -q 'display-message mine' || fail 'user binding overwritten'
[[ -z $(tmux -L "$S" list-keys -T root M-a 2>/dev/null) ]] || fail 'old key left behind'
tmux -L "$S" set-option -gu @tmux-orchestrator-attention-key
"$ROOT/tmux-orchestrator.tmux"

tmux -L "$S" set-option -g @tmux-orchestrator-raise-command \
	"printf '%s %s\\n' \"\$TMUX_ORCHESTRATOR_CLIENT\" \"\$TMUX_ORCHESTRATOR_PANE\" >>$RAISE_LOG"
tmux -L "$S" select-window -t alpha:other
tmux -L "$S" select-window -t beta:other
attach alpha
C1_PID=$!
attach beta
C2_PID=$!
C1=$(client_of alpha)
C2=$(client_of beta)

# Without an agent that needs attention, the client is told so.
report_state "$P0" idle zero claude s0
"$BIN" attention "$C1"
for _ in $(seq 1 30); do
	grep -aFq 'No agent needs' "$TMP/alpha.log" && break
	sleep 0.1
done
grep -aFq 'No agent needs' "$TMP/alpha.log" || fail 'no message without attention'

# Blocked comes first, then error, then done.  The blocked agent's session is
# shown by the other client, so that client goes to it, not the one pressing.
report_state "$P0" error p0-error claude s0
report_state "$P1" done p1-done claude s1
report_state "$PB" blocked pb-blocked claude sb
"$BIN" attention "$C1"
assert_eq "$(client_fmt "$C2" '#{pane_id}')" "$PB"
assert_eq "$(client_fmt "$C1" '#{window_name}')" other
assert_eq "$(tail -n 1 "$RAISE_LOG")" "$C2 $PB"

# From the client viewing it, the next press goes on to the error, which the
# client in its session shows.
"$BIN" attention "$C2"
assert_eq "$(client_fmt "$C1" '#{pane_id}')" "$P0"
assert_eq "$(tail -n 1 "$RAISE_LOG")" "$C1 $P0"
"$BIN" attention "$C1"
assert_eq "$(client_fmt "$C1" '#{pane_id}')" "$P1"

# After the last one it wraps to the first.
tmux -L "$S" set-option -p -t "$P1" @agent_1_state done
"$BIN" attention "$C1"
assert_eq "$(tail -n 1 "$RAISE_LOG")" "$C2 $PB"

# With no client in the agent's session, the client pressing the key goes.
kill "$C2_PID" 2>/dev/null || true
C2_PID=
for _ in $(seq 1 30); do
	[[ -z $(client_of beta) ]] && break
	sleep 0.1
done
"$BIN" attention "$C1"
assert_eq "$(client_fmt "$C1" '#{pane_id}')" "$PB"
assert_eq "$(tail -n 1 "$RAISE_LOG")" "$C1 $PB"

printf 'attention tests passed\n'
