#!/usr/bin/env bash
# End-to-end scenario: two sessions, split windows, six states, clicks, toggle,
# resize, done clearing, and notifications on one throwaway socket.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/tmux-orchestrator"
S="tmux-orchestrator-e2e-$$"
export TMUX_SOCKET=$S
TMP=$(mktemp -d)
CLIENT_LOG="$TMP/client.log"
export NOTIFY_LOG="$TMP/desktop.log"
mkdir -p "$TMP/bin"
cat >"$TMP/bin/notify-send" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${NOTIFY_LOG:?}"
EOS
chmod +x "$TMP/bin/notify-send"
export PATH="$TMP/bin:$PATH"

cleanup() {
	kill "${CLIENT_PID:-}" 2>/dev/null || true
	tmux -L "$S" kill-server 2>/dev/null || true
	rm -rf "$TMP"
}
trap cleanup EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }
assert_contains() { grep -aFq -- "$2" "$1" || fail "missing [$2] in $1"; }

tmux -L "$S" new-session -d -s alpha -n main -x 120 -y 40 'sleep 300'
tmux -L "$S" split-window -t alpha:main -d 'sleep 300'
tmux -L "$S" split-window -t alpha:main -d 'sleep 300'
tmux -L "$S" new-window -t alpha -n second 'sleep 300'
tmux -L "$S" split-window -t alpha:second -d 'sleep 300'
tmux -L "$S" split-window -t alpha:second -d 'sleep 300'
tmux -L "$S" new-session -d -s beta -n other -x 100 -y 40 'sleep 300'
"$ROOT/tmux-orchestrator.tmux"

P0=$(tmux -L "$S" display -p -t alpha:main.0 '#{pane_id}')
P1=$(tmux -L "$S" display -p -t alpha:main.1 '#{pane_id}')
P2=$(tmux -L "$S" display -p -t alpha:main.2 '#{pane_id}')
P3=$(tmux -L "$S" display -p -t alpha:second.0 '#{pane_id}')
P4=$(tmux -L "$S" display -p -t alpha:second.1 '#{pane_id}')
P5=$(tmux -L "$S" display -p -t alpha:second.2 '#{pane_id}')
PB=$(tmux -L "$S" display -p -t beta:other.0 '#{pane_id}')

"$BIN" report --pane "$P0" --state working --name e2e-working --kind claude --session-id s0
"$BIN" report --pane "$P1" --state blocked --name e2e-blocked --kind claude --session-id s1
"$BIN" report --pane "$P2" --state done --name e2e-done --kind claude --session-id s2
"$BIN" report --pane "$P3" --state idle --name e2e-idle --kind opencode --session-id s3
"$BIN" report --pane "$P4" --state error --name e2e-error --kind opencode --session-id s4
tmux -L "$S" set-option -p -t "$P5" @agent_kind claude
tmux -L "$S" set-option -p -t "$P5" @agent_name e2e-unknown
"$BIN" report --pane "$PB" --state error --name e2e-beta --kind claude --session-id sb
"$BIN" reconcile
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_count)" 6
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_rollup)" blocked
assert_eq "$(tmux -L "$S" show-options -v -t beta @agent_rollup)" error

(env -u TMUX TERM=xterm-256color timeout 10 script -qefc "tmux -L $S attach -t alpha" "$CLIENT_LOG" >/dev/null 2>&1) &
CLIENT_PID=$!
sleep 1
for text in Sessions Agents '▸' alpha beta e2e-working e2e-blocked e2e-done e2e-idle e2e-error e2e-unknown '◐' '●' '✓' '○' '×' '·'; do
	assert_contains "$CLIENT_LOG" "$text"
done

CLIENT_NAME=$(tmux -L "$S" list-clients -F '#{client_name}' | head -1)
# Session, window, and pane selection steps used by the click binding.
tmux -L "$S" switch-client -c "$CLIENT_NAME" -t beta
assert_eq "$(tmux -L "$S" display -p -c "$CLIENT_NAME" '#{client_session}')" beta
tmux -L "$S" switch-client -c "$CLIENT_NAME" -t alpha
tmux -L "$S" select-window -t alpha:main
tmux -L "$S" select-pane -t "$P2"
sleep 0.3
assert_eq "$(tmux -L "$S" show-options -pv -t "$P2" @agent_state)" idle

# Toggle and per-session native resize survive state refreshes.
"$BIN" toggle
assert_eq "$(tmux -L "$S" show-options -gv side-status)" off
"$BIN" toggle
assert_eq "$(tmux -L "$S" show-options -gv side-status)" left
tmux -L "$S" set-option -t alpha side-status-width 32
"$BIN" report --pane "$P0" --state working --name e2e-working --kind claude --session-id s0
assert_eq "$(tmux -L "$S" show-options -t alpha -v side-status-width)" 32

# Notifications: the client is on alpha:second, not the agent pane.
tmux -L "$S" select-window -t alpha:main
tmux -L "$S" select-pane -t "$P1"
: >"$NOTIFY_LOG"
"$BIN" report --pane "$P0" --state working --name e2e-working --kind claude --session-id s0
"$BIN" report --pane "$P0" --state blocked --name e2e-working --kind claude --session-id s0
assert_contains "$NOTIFY_LOG" '● Agent blocked: e2e-working'
assert_contains "$CLIENT_LOG" '● e2e-working blocked'
! grep -q 'claude\|%[0-9]' "$NOTIFY_LOG" || fail 'notification leaked kind or location'

kill "$CLIENT_PID" 2>/dev/null || true
CLIENT_PID=
printf 'end-to-end tests passed\n'
