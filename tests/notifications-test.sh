#!/usr/bin/env bash
# Notification channel, suppression, dedupe, cooldown, and pause tests.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/tmux-orchestrator"
S="tmux-orchestrator-notify-$$"
export TMUX_SOCKET=$S
FAKE="/tmp/tmux-orchestrator-fakebin-$$"
NOTIFY_LOG="/tmp/tmux-orchestrator-notify-log-$$"
CLIENT_LOG="/tmp/tmux-orchestrator-client-$$.log"
TMP_STATUS="/tmp/tmux-orchestrator-status-$$"
mkdir -p "$FAKE"
cat >"$FAKE/notify-send" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${NOTIFY_LOG:?}"
EOS
chmod +x "$FAKE/notify-send"
export NOTIFY_LOG
export PATH="$FAKE:$PATH"

cleanup() {
	kill "${CLIENT_PID:-}" 2>/dev/null || true
	tmux -L "$S" kill-server 2>/dev/null || true
	rm -rf "$FAKE" "$TMP_STATUS"
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }
assert_contains() { grep -aFq -- "$2" "$1" || fail "missing [$2] in $1"; }
count_lines() { [[ -f "$1" ]] && wc -l <"$1" || printf 0; }
count_tmux() { grep -acF -- "$1" "$CLIENT_LOG" 2>/dev/null || true; }

tmux -L "$S" new-session -d -s alpha -n main -x 120 -y 40 'sleep 300'
tmux -L "$S" split-window -t alpha:main -d 'sleep 300'
tmux -L "$S" new-session -d -s beta -n other -x 120 -y 40 'sleep 300'
"$ROOT/tmux-orchestrator.tmux"
P0=$(tmux -L "$S" display -p -t alpha:main.0 '#{pane_id}')
P1=$(tmux -L "$S" display -p -t alpha:main.1 '#{pane_id}')
PB=$(tmux -L "$S" display -p -t beta:other.0 '#{pane_id}')

"$BIN" report --pane "$P0" --state idle --name fix-login --kind claude --session-id s0
"$BIN" report --pane "$P1" --state idle --name other-agent --kind claude --session-id s1
: >"$NOTIFY_LOG"

# No tmux client at all: desktop channel still works, tmux has nowhere to go.
"$BIN" report --pane "$P0" --state working --name fix-login --kind claude --session-id s0
"$BIN" report --pane "$P0" --state blocked --name fix-login --kind claude --session-id s0
assert_eq "$(count_lines "$NOTIFY_LOG")" 1
assert_contains "$NOTIFY_LOG" '● Agent blocked: fix-login'
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_notified_at 2>/dev/null || true)" ''

# Hostile names are sanitized in both channels; kind and location are absent.
: >"$NOTIFY_LOG"
"$BIN" report --pane "$P0" --state working --name $'evil#[fg=red]\nline' --kind claude --session-id s0
"$BIN" report --pane "$P0" --state blocked --name $'evil#[fg=red]\nline' --kind claude --session-id s0
assert_contains "$NOTIFY_LOG" '● Agent blocked: evil#[fg=red] line'
! grep -q 'claude\|s0' "$NOTIFY_LOG" || fail 'notification leaked kind or location'

# A client viewing the agent suppresses both channels.
(env -u TMUX TERM=xterm-256color timeout 8 script -qefc "tmux -L $S attach -t alpha" "$CLIENT_LOG" >/dev/null 2>&1) &
CLIENT_PID=$!
sleep 0.8
tmux -L "$S" select-window -t alpha:main
tmux -L "$S" select-pane -t "$P0"
: >"$NOTIFY_LOG"
"$BIN" report --pane "$P0" --state working --name fix-login --kind claude --session-id s0
"$BIN" report --pane "$P0" --state blocked --name fix-login --kind claude --session-id s0
assert_eq "$(count_lines "$NOTIFY_LOG")" 0
assert_eq "$(grep -acF '● fix-login blocked' "$CLIENT_LOG" || true)" 0

# A client on another pane/session gets the tmux message; desktop is still sent.
tmux -L "$S" select-pane -t "$P1"
: >"$NOTIFY_LOG"
"$BIN" report --pane "$P0" --state working --name fix-login --kind claude --session-id s0
"$BIN" report --pane "$P0" --state blocked --name fix-login --kind claude --session-id s0
assert_contains "$NOTIFY_LOG" '● Agent blocked: fix-login'
assert_contains "$CLIENT_LOG" '● fix-login blocked'

# With two clients, one viewing suppresses desktop but the other still gets tmux.
tmux -L "$S" select-pane -t "$P0"
(env -u TMUX TERM=xterm-256color timeout 8 script -qefc "tmux -L $S attach -t beta" "$CLIENT_LOG.2" >/dev/null 2>&1) &
CLIENT2_PID=$!
for _ in $(seq 1 30); do
	[[ $(tmux -L "$S" list-clients -F '#{client_session}' | grep -c '^beta$' || true) == 1 ]] && break
	sleep 0.1
done
assert_eq "$(tmux -L "$S" list-clients | wc -l | tr -d ' ')" 2
: >"$NOTIFY_LOG"
"$BIN" report --pane "$P0" --state working --name fix-login --kind claude --session-id s0
"$BIN" report --pane "$P0" --state blocked --name fix-login --kind claude --session-id s0
assert_eq "$(count_lines "$NOTIFY_LOG")" 0
sleep 0.3
assert_contains "$CLIENT_LOG.2" '● fix-login blocked'

# Focus clears done on every client's own active pane, not just one.
tmux -L "$S" set-option -p -t "$P0" @agent_state done
tmux -L "$S" set-option -p -t "$PB" @agent_state done
"$BIN" focus
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_state)" idle
assert_eq "$(tmux -L "$S" show-options -pv -t "$PB" @agent_state)" idle
kill "$CLIENT2_PID" 2>/dev/null || true
CLIENT2_PID=
tmux -L "$S" select-pane -t "$P1"
tmux -L "$S" set-option -p -t "$P0" @agent_state blocked
BEFORE=$(count_lines "$NOTIFY_LOG")

# Duplicate state does not notify again.
"$BIN" report --pane "$P0" --state blocked --name fix-login --kind claude --session-id s0
assert_eq "$(count_lines "$NOTIFY_LOG")" "$BEFORE"

# done is desktop-deduped but tmux-done is under cooldown, so only desktop.
"$BIN" report --pane "$P0" --state done --name fix-login --kind claude --session-id s0
assert_eq "$(count_lines "$NOTIFY_LOG")" "$((BEFORE + 1))"
assert_contains "$NOTIFY_LOG" '✓ Agent done: fix-login'

# Focus clears done without a notification.
"$BIN" report --pane "$P0" --state working --name fix-login --kind claude --session-id s0
"$BIN" report --pane "$P0" --state done --name fix-login --kind claude --session-id s0
BEFORE=$(count_lines "$NOTIFY_LOG")
tmux -L "$S" select-window -t alpha:main
tmux -L "$S" select-pane -t "$P0"
"$BIN" focus
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_state)" idle
assert_eq "$(count_lines "$NOTIFY_LOG")" "$BEFORE"

# error bypasses the tmux cooldown.
tmux -L "$S" select-window -t alpha:main
tmux -L "$S" select-pane -t "$P1"
: >"$NOTIFY_LOG"
"$BIN" report --pane "$P0" --state working --name fix-login --kind claude --session-id s0
"$BIN" report --pane "$P0" --state error --name fix-login --kind claude --session-id s0
assert_contains "$NOTIFY_LOG" '× Agent error: fix-login'
assert_contains "$CLIENT_LOG" '× fix-login error'

# After the cooldown, done reaches tmux again.
"$BIN" report --pane "$P0" --state working --name fix-login --kind claude --session-id s0
sleep 2.1
"$BIN" report --pane "$P0" --state done --name fix-login --kind claude --session-id s0
assert_contains "$CLIENT_LOG" '✓ fix-login done'

# Pause suppresses both channels but keeps state.
"$BIN" notify pause
"$BIN" notify status | grep -q 'notifications: paused (both)' || fail 'pause status'
: >"$NOTIFY_LOG"
BEFORE_TMUX=$(grep -acF '● fix-login blocked' "$CLIENT_LOG" || true)
"$BIN" report --pane "$P0" --state working --name fix-login --kind claude --session-id s0
"$BIN" report --pane "$P0" --state blocked --name fix-login --kind claude --session-id s0
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_state)" blocked
assert_eq "$(count_lines "$NOTIFY_LOG")" 0
assert_eq "$(grep -acF '● fix-login blocked' "$CLIENT_LOG" || true)" "$BEFORE_TMUX"

"$BIN" notify resume
"$BIN" notify status | grep -q 'notifications: both' || fail 'resume status'
"$BIN" report --pane "$P0" --state working --name fix-login --kind claude --session-id s0
"$BIN" report --pane "$P0" --state blocked --name fix-login --kind claude --session-id s0
assert_eq "$(count_lines "$NOTIFY_LOG")" 1

# Channel off is reported explicitly.
tmux -L "$S" set-option -g @tmux-orchestrator-notify off
"$BIN" notify status | grep -q 'notifications: off' || fail 'off status'
: >"$NOTIFY_LOG"
"$BIN" report --pane "$P0" --state working --name fix-login --kind claude --session-id s0
"$BIN" report --pane "$P0" --state blocked --name fix-login --kind claude --session-id s0
assert_eq "$(count_lines "$NOTIFY_LOG")" 0

# Desktop-only with no desktop command is silent; both falls back to tmux.
NODESK="/tmp/tmux-orchestrator-nodesktop-$$"
mkdir -p "$NODESK"
for cmd in tmux date basename dirname tr head sed; do
	command -v "$cmd" >/dev/null 2>&1 && ln -s "$(command -v "$cmd")" "$NODESK/$cmd"
done
tmux -L "$S" set-option -g @tmux-orchestrator-notify both
: >"$NOTIFY_LOG"
env PATH="$NODESK" TMUX_BIN="$NODESK/tmux" /bin/bash "$BIN" report --pane "$P0" --state working --name fallback-agent --kind claude --session-id s0
env PATH="$NODESK" TMUX_BIN="$NODESK/tmux" /bin/bash "$BIN" report --pane "$P0" --state blocked --name fallback-agent --kind claude --session-id s0
assert_eq "$(count_lines "$NOTIFY_LOG")" 0
grep -aFq '● fallback-agent blocked' "$CLIENT_LOG" || fail 'both did not fall back to tmux'

tmux -L "$S" set-option -g @tmux-orchestrator-notify desktop
env PATH="$NODESK" TMUX_BIN="$NODESK/tmux" /bin/bash "$BIN" report --pane "$P0" --state working --name desktop-only-agent --kind claude --session-id s0
env PATH="$NODESK" TMUX_BIN="$NODESK/tmux" /bin/bash "$BIN" report --pane "$P0" --state blocked --name desktop-only-agent --kind claude --session-id s0
assert_eq "$(count_lines "$NOTIFY_LOG")" 0
! grep -aFq '● desktop-only-agent blocked' "$CLIENT_LOG" || fail 'desktop-only sent tmux message'
env PATH="$NODESK" TMUX_BIN="$NODESK/tmux" /bin/bash "$BIN" notify status >"$TMP_STATUS"
grep -q 'desktop: unavailable' "$TMP_STATUS" || fail 'status hid missing desktop command'
rm -rf "$NODESK"

# The tmux-only channel never calls the desktop command.
tmux -L "$S" set-option -g @tmux-orchestrator-notify tmux
: >"$NOTIFY_LOG"
"$BIN" report --pane "$P0" --state working --name tmux-only --kind claude --session-id s0
"$BIN" report --pane "$P0" --state blocked --name tmux-only --kind claude --session-id s0
assert_eq "$(count_lines "$NOTIFY_LOG")" 0
assert_contains "$CLIENT_LOG" '● tmux-only blocked'

# Pause is idempotent and survives a plugin reload.
tmux -L "$S" set-option -g @tmux-orchestrator-notify both
"$BIN" notify pause >/dev/null
"$BIN" notify pause >/dev/null
"$BIN" notify status | grep -q 'notifications: paused (both)' || fail 'pause idempotence'
"$ROOT/tmux-orchestrator.tmux"
"$BIN" notify status | grep -q 'notifications: paused (both)' || fail 'pause did not survive reload'
"$BIN" notify resume >/dev/null

kill "$CLIENT_PID" 2>/dev/null || true
CLIENT_PID=
printf 'notification tests passed\n'
