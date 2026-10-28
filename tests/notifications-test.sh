#!/usr/bin/env bash
# Notification channel, suppression, dedupe, cooldown, and pause tests.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/tmux-orchestrator"
. "$ROOT/tests/helpers.sh"
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
# Keep the developer's real OpenCode plugin link untouched.
tmux -L "$S" set-option -g @tmux-orchestrator-opencode-auto-install off
tmux -L "$S" split-window -t alpha:main -d 'sleep 300'
tmux -L "$S" new-session -d -s beta -n other -x 120 -y 40 'sleep 300'
"$ROOT/tmux-orchestrator.tmux"
P0=$(tmux -L "$S" display -p -t alpha:main.0 '#{pane_id}')
P1=$(tmux -L "$S" display -p -t alpha:main.1 '#{pane_id}')
PB=$(tmux -L "$S" display -p -t beta:other.0 '#{pane_id}')

report_state "$P0" idle fix-login claude s0
report_state "$P1" idle other-agent claude s1
: >"$NOTIFY_LOG"

# No tmux client at all: desktop channel still works, tmux has nowhere to go.
report_state "$P0" working fix-login claude s0
report_state "$P0" blocked fix-login claude s0
assert_eq "$(count_lines "$NOTIFY_LOG")" 1
assert_contains "$NOTIFY_LOG" '◉ Agent blocked: fix-login'
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_1_notified_at 2>/dev/null || true)" ''

# Hostile names are sanitized in both channels; kind and location are absent.
: >"$NOTIFY_LOG"
report_state "$P0" working $'evil#[fg=red]\nline' claude s0
report_state "$P0" blocked $'evil#[fg=red]\nline' claude s0
assert_contains "$NOTIFY_LOG" '◉ Agent blocked: evil#[fg=red] line'
! grep -q 'claude\|s0' "$NOTIFY_LOG" || fail 'notification leaked kind or location'

# A client viewing the agent suppresses both channels.
(env -u TMUX TERM=xterm-256color timeout 60 script -qefc "tmux -L $S attach -t alpha" "$CLIENT_LOG" >/dev/null 2>&1) &
CLIENT_PID=$!
sleep 0.8
tmux -L "$S" select-window -t alpha:main
tmux -L "$S" select-pane -t "$P0"
: >"$NOTIFY_LOG"
report_state "$P0" working fix-login claude s0
report_state "$P0" blocked fix-login claude s0
assert_eq "$(count_lines "$NOTIFY_LOG")" 0
assert_eq "$(grep -acF '◉ fix-login blocked' "$CLIENT_LOG" || true)" 0

# A client on another pane/session gets the tmux message; desktop is still sent.
tmux -L "$S" select-pane -t "$P1"
: >"$NOTIFY_LOG"
report_state "$P0" working fix-login claude s0
report_state "$P0" blocked fix-login claude s0
assert_contains "$NOTIFY_LOG" '◉ Agent blocked: fix-login'
assert_contains "$CLIENT_LOG" '◉ fix-login blocked'

# With two clients, one viewing suppresses desktop but the other still gets tmux.
tmux -L "$S" select-pane -t "$P0"
(env -u TMUX TERM=xterm-256color timeout 60 script -qefc "tmux -L $S attach -t beta" "$CLIENT_LOG.2" >/dev/null 2>&1) &
CLIENT2_PID=$!
for _ in $(seq 1 30); do
	[[ $(tmux -L "$S" list-clients -F '#{client_session}' | grep -c '^beta$' || true) == 1 ]] && break
	sleep 0.1
done
assert_eq "$(tmux -L "$S" list-clients | wc -l | tr -d ' ')" 2
: >"$NOTIFY_LOG"
report_state "$P0" working fix-login claude s0
report_state "$P0" blocked fix-login claude s0
assert_eq "$(count_lines "$NOTIFY_LOG")" 0
sleep 0.3
assert_contains "$CLIENT_LOG.2" '◉ fix-login blocked'

# Focus clears done on every client's own active pane, not just one.
tmux -L "$S" set-option -p -t "$P0" @agent_1_state done
report_state "$PB" working beta-agent claude sb
report_state "$PB" done beta-agent claude sb
"$BIN" focus
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_1_state)" idle
assert_eq "$(tmux -L "$S" show-options -pv -t "$PB" @agent_1_state)" idle
kill "$CLIENT2_PID" 2>/dev/null || true
CLIENT2_PID=
tmux -L "$S" select-pane -t "$P1"
tmux -L "$S" set-option -p -t "$P0" @agent_1_state blocked
BEFORE=$(count_lines "$NOTIFY_LOG")

# Duplicate state does not notify again.
report_state "$P0" blocked fix-login claude s0
assert_eq "$(count_lines "$NOTIFY_LOG")" "$BEFORE"

# done is desktop-deduped but tmux-done is under cooldown, so only desktop.
report_state "$P0" done fix-login claude s0
assert_eq "$(count_lines "$NOTIFY_LOG")" "$((BEFORE + 1))"
assert_contains "$NOTIFY_LOG" '✓ Agent done: fix-login'

# Focus clears done without a notification.
report_state "$P0" working fix-login claude s0
report_state "$P0" done fix-login claude s0
BEFORE=$(count_lines "$NOTIFY_LOG")
tmux -L "$S" select-window -t alpha:main
tmux -L "$S" select-pane -t "$P0"
"$BIN" focus
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_1_state)" idle
assert_eq "$(count_lines "$NOTIFY_LOG")" "$BEFORE"

# error bypasses the tmux cooldown.
tmux -L "$S" select-window -t alpha:main
tmux -L "$S" select-pane -t "$P1"
: >"$NOTIFY_LOG"
report_state "$P0" working fix-login claude s0
report_state "$P0" error fix-login claude s0
assert_contains "$NOTIFY_LOG" '× Agent error: fix-login'
assert_contains "$CLIENT_LOG" '× fix-login error'

# After the cooldown, done reaches tmux again.
report_state "$P0" working fix-login claude s0
sleep 2.1
report_state "$P0" done fix-login claude s0
assert_contains "$CLIENT_LOG" '✓ fix-login done'

# Pause suppresses both channels but keeps state.
"$BIN" notify pause
"$BIN" notify status | grep -q 'notifications: paused' || fail 'pause status'
: >"$NOTIFY_LOG"
BEFORE_TMUX=$(grep -acF '◉ fix-login blocked' "$CLIENT_LOG" || true)
report_state "$P0" working fix-login claude s0
report_state "$P0" blocked fix-login claude s0
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_1_state)" blocked
assert_eq "$(count_lines "$NOTIFY_LOG")" 0
assert_eq "$(grep -acF '◉ fix-login blocked' "$CLIENT_LOG" || true)" "$BEFORE_TMUX"

"$BIN" notify resume
"$BIN" notify status | grep -q 'notifications: active' || fail 'resume status'
report_state "$P0" working fix-login claude s0
report_state "$P0" blocked fix-login claude s0
assert_eq "$(count_lines "$NOTIFY_LOG")" 1

# Defaults: tmux and desktop on, terminal off.
"$BIN" notify status >"$TMP_STATUS"
for line in 'notifications: active' 'tmux: on' 'desktop: on (notify-send)' 'terminal: off'; do
	grep -qF "$line" "$TMP_STATUS" || fail "default status lacks [$line]"
done
: >"$NOTIFY_LOG"
report_state "$P0" working default-agent claude s0
report_state "$P0" blocked default-agent claude s0
sleep 0.3
assert_eq "$(count_lines "$NOTIFY_LOG")" 1
assert_contains "$CLIENT_LOG" '◉ default-agent blocked'
! grep -aFq $'\e]9;◉ Agent blocked: default-agent' "$CLIENT_LOG" || fail 'terminal on by default'

# The old options are ignored.
tmux -L "$S" set-option -g @tmux-orchestrator-notify off
tmux -L "$S" set-option -g @tmux-orchestrator-notify-via none
: >"$NOTIFY_LOG"
report_state "$P0" working legacy-agent claude s0
report_state "$P0" blocked legacy-agent claude s0
assert_eq "$(count_lines "$NOTIFY_LOG")" 1
tmux -L "$S" set-option -gu @tmux-orchestrator-notify
tmux -L "$S" set-option -gu @tmux-orchestrator-notify-via

# All channels off is reported explicitly and delivers nothing.
for ch in tmux desktop terminal; do tmux -L "$S" set-option -g "@tmux-orchestrator-notify-$ch" off; done
"$BIN" notify status | grep -q 'notifications: off' || fail 'off status'
: >"$NOTIFY_LOG"
report_state "$P0" working off-agent claude s0
report_state "$P0" blocked off-agent claude s0
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_1_state)" blocked
assert_eq "$(count_lines "$NOTIFY_LOG")" 0
! grep -aFq '◉ off-agent blocked' "$CLIENT_LOG" || fail 'all off still notified'
for ch in tmux desktop terminal; do tmux -L "$S" set-option -gu "@tmux-orchestrator-notify-$ch"; done

# Without a desktop command the desktop channel is silent and tmux still delivers.
NODESK="/tmp/tmux-orchestrator-nodesktop-$$"
mkdir -p "$NODESK"
for cmd in tmux date basename dirname tr head sed; do
	command -v "$cmd" >/dev/null 2>&1 && ln -s "$(command -v "$cmd")" "$NODESK/$cmd"
done
: >"$NOTIFY_LOG"
env PATH="$NODESK" TMUX_BIN="$NODESK/tmux" /bin/bash "$BIN" report --pane "$P0" --kind claude --event UserPromptSubmit --name fallback-agent --session-id s0
env PATH="$NODESK" TMUX_BIN="$NODESK/tmux" /bin/bash "$BIN" report --pane "$P0" --kind claude --event PermissionRequest --name fallback-agent --session-id s0
assert_eq "$(count_lines "$NOTIFY_LOG")" 0
grep -aFq '◉ fallback-agent blocked' "$CLIENT_LOG" || fail 'tmux did not deliver without desktop'
env PATH="$NODESK" TMUX_BIN="$NODESK/tmux" /bin/bash "$BIN" notify status >"$TMP_STATUS"
grep -qF 'desktop: on (unavailable)' "$TMP_STATUS" || fail 'status hid missing desktop command'
rm -rf "$NODESK"

# Desktop off never calls the desktop command.
tmux -L "$S" set-option -g @tmux-orchestrator-notify-desktop off
: >"$NOTIFY_LOG"
report_state "$P0" working tmux-only claude s0
report_state "$P0" blocked tmux-only claude s0
assert_eq "$(count_lines "$NOTIFY_LOG")" 0
assert_contains "$CLIENT_LOG" '◉ tmux-only blocked'

# Terminal only: an OSC 9 sequence to the client's terminal and nothing else.
tmux -L "$S" set-option -g @tmux-orchestrator-notify-tmux off
tmux -L "$S" set-option -g @tmux-orchestrator-notify-terminal on
: >"$NOTIFY_LOG"
report_state "$P0" working term-agent claude s0
report_state "$P0" blocked term-agent claude s0
sleep 0.3
assert_eq "$(count_lines "$NOTIFY_LOG")" 0
assert_contains "$CLIENT_LOG" $'\e]9;◉ Agent blocked: term-agent\a'
! grep -aFq '◉ term-agent blocked' "$CLIENT_LOG" || fail 'tmux off still sent a message'

# All three on: each channel delivers.
tmux -L "$S" set-option -gu @tmux-orchestrator-notify-tmux
tmux -L "$S" set-option -gu @tmux-orchestrator-notify-desktop
report_state "$P0" working all-agent claude s0
report_state "$P0" blocked all-agent claude s0
sleep 0.3
assert_eq "$(count_lines "$NOTIFY_LOG")" 1
assert_contains "$CLIENT_LOG" $'\e]9;◉ Agent blocked: all-agent\a'
assert_contains "$CLIENT_LOG" '◉ all-agent blocked'

# An unrecognised value means the channel default.
tmux -L "$S" set-option -g @tmux-orchestrator-notify-terminal yes
"$BIN" notify status | grep -qF 'terminal: off' || fail 'unrecognised value not default'
report_state "$P0" working yes-agent claude s0
report_state "$P0" blocked yes-agent claude s0
sleep 0.3
! grep -aFq $'\e]9;◉ Agent blocked: yes-agent' "$CLIENT_LOG" || fail 'unrecognised value enabled terminal'

# A control-mode client gets no OSC 9 even when it is the most recently active.
tmux -L "$S" set-option -g @tmux-orchestrator-notify-terminal on
CTL_LOG="/tmp/tmux-orchestrator-control-$$.log"
(sleep 3 | tmux -L "$S" -C attach -t alpha >"$CTL_LOG" 2>&1) &
sleep 0.5
report_state "$P0" working control-agent claude s0
report_state "$P0" blocked control-agent claude s0
sleep 0.3
! grep -aFq $'\e]9;' "$CTL_LOG" || fail 'OSC 9 sent to a control-mode client'
assert_contains "$CLIENT_LOG" $'\e]9;◉ Agent blocked: control-agent\a'
rm -f "$CTL_LOG"
tmux -L "$S" set-option -gu @tmux-orchestrator-notify-terminal

# Pause is idempotent and survives a plugin reload.
"$BIN" notify pause >/dev/null
"$BIN" notify pause >/dev/null
"$BIN" notify status | grep -q 'notifications: paused' || fail 'pause idempotence'
"$ROOT/tmux-orchestrator.tmux"
"$BIN" notify status | grep -q 'notifications: paused' || fail 'pause did not survive reload'
"$BIN" notify toggle >/dev/null
"$BIN" notify status | grep -q 'notifications: active' || fail 'toggle did not resume'
"$BIN" notify toggle >/dev/null
"$BIN" notify status | grep -q 'notifications: paused' || fail 'toggle did not pause'
"$BIN" notify resume >/dev/null

# An OpenCode tab counts as viewed only when it is the active tab.
tmux -L "$S" new-window -t alpha -n tabs 'sleep 300'
PT=$(tmux -L "$S" display -p -t alpha:tabs.0 '#{pane_id}')
tmux -L "$S" select-window -t alpha:tabs
"$BIN" tabs --pane "$PT" --active ses_a --tab ses_a idle front --tab ses_b idle back
: >"$NOTIFY_LOG"
"$BIN" report --pane "$PT" --kind opencode --event permission.asked --session-id ses_b
assert_eq "$(count_lines "$NOTIFY_LOG")" 1
sleep 0.3
assert_contains "$CLIENT_LOG" '◉ back blocked'
: >"$NOTIFY_LOG"
"$BIN" report --pane "$PT" --kind opencode --event permission.asked --session-id ses_a
assert_eq "$(count_lines "$NOTIFY_LOG")" 0

# A wait that loads late on a background tab notifies once.
"$BIN" tabs --pane "$PT" --active ses_a --tab ses_a idle front --tab ses_c running late
: >"$NOTIFY_LOG"
"$BIN" tabs --pane "$PT" --active ses_a --tab ses_a idle front --tab ses_c pending late
"$BIN" tabs --pane "$PT" --active ses_a --tab ses_a idle front --tab ses_c pending late
assert_eq "$(count_lines "$NOTIFY_LOG")" 1

kill "$CLIENT_PID" 2>/dev/null || true
CLIENT_PID=
printf 'notification tests passed\n'
