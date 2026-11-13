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
# -p prints the notification ID, 7 unless FAKE_ID says otherwise.
[[ " $* " == *' -p '* ]] && printf '%s\n' "${FAKE_ID:-7}"
# FAKE_BEFORE_CLICK runs before the answer, as if something happened meanwhile.
# The pause lets the reporter store the ID first.
[[ -n ${FAKE_BEFORE_CLICK:-} ]] && sleep 0.3 && eval "$FAKE_BEFORE_CLICK"
# FAKE_CLICK=1 answers like a click on the notification.
[[ ${FAKE_CLICK:-} == 1 ]] && printf 'default\n'
exit 0
EOS
chmod +x "$FAKE/notify-send"
export NOTIFY_LOG TMUX_ORCHESTRATOR_NOTIFY_SYNC=1
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

tmux -L "$S" -f /dev/null new-session -d -s alpha -n main -x 120 -y 40 'sleep 300'
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

# No tmux client at all: the desktop channel still works.
report_state "$P0" working fix-login claude s0
report_state "$P0" blocked fix-login claude s0
assert_eq "$(count_lines "$NOTIFY_LOG")" 1
assert_contains "$NOTIFY_LOG" '◉ Agent blocked: fix-login'

# Hostile names are sanitized in both channels; kind and location are absent.
: >"$NOTIFY_LOG"
report_state "$P0" working $'evil#[fg=red]\nline' claude s0
report_state "$P0" blocked $'evil#[fg=red]\nline' claude s0
assert_contains "$NOTIFY_LOG" '◉ Agent blocked: evil#[fg=red] line'
! grep -q 'claude\|s0' "$NOTIFY_LOG" || fail 'notification leaked kind or location'

# A client viewing the agent suppresses every channel.
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

# A client on another pane gets the desktop notification and no tmux message.
tmux -L "$S" select-pane -t "$P1"
: >"$NOTIFY_LOG"
report_state "$P0" working fix-login claude s0
report_state "$P0" blocked fix-login claude s0
assert_contains "$NOTIFY_LOG" '◉ Agent blocked: fix-login'
sleep 0.3
! grep -aFq '◉ fix-login blocked' "$CLIENT_LOG" || fail 'tmux message sent'

# With two clients, the one viewing suppresses the notification.
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

# A new done notifies once.
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

# error notifies.
tmux -L "$S" select-window -t alpha:main
tmux -L "$S" select-pane -t "$P1"
: >"$NOTIFY_LOG"
report_state "$P0" working fix-login claude s0
report_state "$P0" error fix-login claude s0
assert_contains "$NOTIFY_LOG" '× Agent error: fix-login'

# Pause suppresses every channel but keeps state.
"$BIN" notify pause
"$BIN" notify status | grep -q 'notifications: paused' || fail 'pause status'
: >"$NOTIFY_LOG"
report_state "$P0" working fix-login claude s0
report_state "$P0" blocked fix-login claude s0
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_1_state)" blocked
assert_eq "$(count_lines "$NOTIFY_LOG")" 0

"$BIN" notify resume
"$BIN" notify status | grep -q 'notifications: active' || fail 'resume status'
report_state "$P0" working fix-login claude s0
report_state "$P0" blocked fix-login claude s0
assert_eq "$(count_lines "$NOTIFY_LOG")" 1

# Defaults: desktop on, terminal off, and no tmux channel.
"$BIN" notify status >"$TMP_STATUS"
for line in 'notifications: active' 'desktop: on (notify-send)' 'terminal: off'; do
	grep -qF "$line" "$TMP_STATUS" || fail "default status lacks [$line]"
done
! grep -qF 'tmux:' "$TMP_STATUS" || fail 'status lists a tmux channel'
: >"$NOTIFY_LOG"
report_state "$P0" working default-agent claude s0
report_state "$P0" blocked default-agent claude s0
sleep 0.3
assert_eq "$(count_lines "$NOTIFY_LOG")" 1
! grep -aFq '◉ default-agent blocked' "$CLIENT_LOG" || fail 'tmux message sent'
! grep -aFq $'\e]9;◉ Agent blocked: default-agent' "$CLIENT_LOG" || fail 'terminal on by default'


# All channels off is reported explicitly and delivers nothing.
for ch in desktop terminal; do tmux -L "$S" set-option -g "@tmux-orchestrator-notify-$ch" off; done
"$BIN" notify status | grep -q 'notifications: off' || fail 'off status'
: >"$NOTIFY_LOG"
report_state "$P0" working off-agent claude s0
report_state "$P0" blocked off-agent claude s0
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_1_state)" blocked
assert_eq "$(count_lines "$NOTIFY_LOG")" 0
! grep -aFq '◉ off-agent blocked' "$CLIENT_LOG" || fail 'all off still notified'
for ch in desktop terminal; do tmux -L "$S" set-option -gu "@tmux-orchestrator-notify-$ch"; done

# Without a desktop command the desktop channel is silent.
NODESK="/tmp/tmux-orchestrator-nodesktop-$$"
mkdir -p "$NODESK"
for cmd in tmux date basename dirname tr head sed; do
	command -v "$cmd" >/dev/null 2>&1 && ln -s "$(command -v "$cmd")" "$NODESK/$cmd"
done
: >"$NOTIFY_LOG"
env PATH="$NODESK" TMUX_BIN="$NODESK/tmux" /bin/bash "$BIN" report --pane "$P0" --kind claude --event UserPromptSubmit --name fallback-agent --session-id s0
env PATH="$NODESK" TMUX_BIN="$NODESK/tmux" /bin/bash "$BIN" report --pane "$P0" --kind claude --event PermissionRequest --name fallback-agent --session-id s0
assert_eq "$(count_lines "$NOTIFY_LOG")" 0
env PATH="$NODESK" TMUX_BIN="$NODESK/tmux" /bin/bash "$BIN" notify status >"$TMP_STATUS"
grep -qF 'desktop: on (unavailable)' "$TMP_STATUS" || fail 'status hid missing desktop command'
rm -rf "$NODESK"

# Desktop off never calls the desktop command.
tmux -L "$S" set-option -g @tmux-orchestrator-notify-desktop off
: >"$NOTIFY_LOG"
report_state "$P0" working desk-off claude s0
report_state "$P0" blocked desk-off claude s0
assert_eq "$(count_lines "$NOTIFY_LOG")" 0

# Terminal only: an OSC 9 sequence to the client's terminal and nothing else.
tmux -L "$S" set-option -g @tmux-orchestrator-notify-terminal on
: >"$NOTIFY_LOG"
report_state "$P0" working term-agent claude s0
report_state "$P0" blocked term-agent claude s0
sleep 0.3
assert_eq "$(count_lines "$NOTIFY_LOG")" 0
assert_contains "$CLIENT_LOG" $'\e]9;◉ Agent blocked: term-agent\a'
! grep -aFq '◉ term-agent blocked' "$CLIENT_LOG" || fail 'tmux message sent'

# Both on: each channel delivers.
tmux -L "$S" set-option -gu @tmux-orchestrator-notify-desktop
report_state "$P0" working all-agent claude s0
report_state "$P0" blocked all-agent claude s0
sleep 0.3
assert_eq "$(count_lines "$NOTIFY_LOG")" 1
assert_contains "$CLIENT_LOG" $'\e]9;◉ Agent blocked: all-agent\a'

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
: >"$NOTIFY_LOG"
"$BIN" report --pane "$PT" --kind opencode --event permission.asked --session-id ses_a
assert_eq "$(count_lines "$NOTIFY_LOG")" 0

# A wait that loads late on a background tab notifies once.
"$BIN" tabs --pane "$PT" --active ses_a --tab ses_a idle front --tab ses_c running late
: >"$NOTIFY_LOG"
"$BIN" tabs --pane "$PT" --active ses_a --tab ses_a idle front --tab ses_c pending late
"$BIN" tabs --pane "$PT" --active ses_a --tab ses_a idle front --tab ses_c pending late
assert_eq "$(count_lines "$NOTIFY_LOG")" 1

# Clicking a desktop notification brings a client to the agent and runs the
# notify command.  The client already in the agent's session wins over a more
# recently active client elsewhere.
CMD_LOG="$FAKE/command.log"
tmux -L "$S" set-option -g @tmux-orchestrator-raise-command \
	"printf '%s|%s|%s|%s\\n' \"\$TMUX_ORCHESTRATOR_PANE\" \"\$TMUX_ORCHESTRATOR_SESSION\" \"\$TMUX_ORCHESTRATOR_CLIENT\" \"\$TMUX_ORCHESTRATOR_CLIENT_TTY\" >$CMD_LOG"
(env -u TMUX TERM=xterm-256color timeout 60 script -qefc "tmux -L $S attach -t beta" "$CLIENT_LOG.3" >/dev/null 2>&1) &
CLIENT3_PID=$!
for _ in $(seq 1 30); do
	[[ $(tmux -L "$S" list-clients -F '#{client_session}' | grep -c '^beta$' || true) == 1 ]] && break
	sleep 0.1
done
# The client of SESSION with a terminal, and FORMAT read for client NAME.
tty_client() { tmux -L "$S" list-clients -f '#{!=:#{client_control_mode},1}' -F '#{client_session} #{client_name}' | awk -v s="$1" '$1 == s { print $2 }'; }
client_fmt() { tmux -L "$S" list-clients -F "#{client_name} $2" | awk -v c="$1" '$1 == c { print $2 }'; }
ALPHA_CLIENT=$(tty_client alpha)
BETA_CLIENT=$(tty_client beta)
tmux -L "$S" select-window -t alpha:tabs
: >"$NOTIFY_LOG"
FAKE_CLICK=1 report_state "$P0" working fix-login claude s0
FAKE_CLICK=1 report_state "$P0" blocked fix-login claude s0
assert_contains "$NOTIFY_LOG" '-A default=Focus'
assert_eq "$(client_fmt "$ALPHA_CLIENT" '#{pane_id}')" "$P0"
assert_eq "$(client_fmt "$BETA_CLIENT" '#{session_name}')" beta
assert_eq "$(cat "$CMD_LOG")" "$P0|alpha|$ALPHA_CLIENT|$ALPHA_CLIENT"

# Without a click nothing moves and the command does not run.
rm -f "$CMD_LOG"
tmux -L "$S" select-pane -t "$P1"
report_state "$P0" working fix-login claude s0
report_state "$P0" blocked fix-login claude s0
assert_eq "$(client_fmt "$ALPHA_CLIENT" '#{pane_id}')" "$P1"
[[ ! -e $CMD_LOG ]] || fail 'notify command ran without a click'

# Each notification asks for its ID; the agent's open one is replaced, and
# the option is cleared once its notification is gone.
assert_contains "$NOTIFY_LOG" '-p -t 5000 -A default=Focus'
! grep -aFq -- ' -r ' "$NOTIFY_LOG" || fail 'replaced without an open notification'
assert_eq "$(opt "$P0" @agent_notify_s0)" ''
tmux -L "$S" set-option -p -t "$P0" @agent_notify_s0 '42 open'
: >"$NOTIFY_LOG"
report_state "$P0" working fix-login claude s0
report_state "$P0" blocked fix-login claude s0
assert_contains "$NOTIFY_LOG" '-r 42'
assert_eq "$(opt "$P0" @agent_notify_s0)" ''

# A click reaching a waiter whose notification a newer one replaced is left
# to the newer waiter: nothing moves, and the newer one's ID stays.
FAKE_BEFORE_CLICK="tmux -L $S set-option -p -t $P0 @agent_notify_s0 '7 newer'" \
	FAKE_CLICK=1 report_state "$P0" working fix-login claude s0
FAKE_BEFORE_CLICK="tmux -L $S set-option -p -t $P0 @agent_notify_s0 '7 newer'" \
	FAKE_CLICK=1 report_state "$P0" blocked fix-login claude s0
assert_eq "$(client_fmt "$ALPHA_CLIENT" '#{pane_id}')" "$P1"
[[ ! -e $CMD_LOG ]] || fail 'replaced notification acted on a click'
assert_eq "$(opt "$P0" @agent_notify_s0)" '7 newer'
tmux -L "$S" set-option -pu -t "$P0" @agent_notify_s0

# @tmux-orchestrator-notify-timeout sets how long the notification stays open;
# anything but a positive whole number means 5 seconds.
for pair in 12:12000 soon:5000 0:5000; do
	tmux -L "$S" set-option -g @tmux-orchestrator-notify-timeout "${pair%%:*}"
	: >"$NOTIFY_LOG"
	report_state "$P0" working fix-login claude s0
	report_state "$P0" blocked fix-login claude s0
	assert_contains "$NOTIFY_LOG" "-t ${pair#*:} "
done
tmux -L "$S" set-option -gu @tmux-orchestrator-notify-timeout

# focus-agent picks the client showing the agent's window over the others.
"$BIN" focus-agent --pane "$PB"
assert_eq "$(cut -d'|' -f3 "$CMD_LOG")" "$BETA_CLIENT"
assert_eq "$(client_fmt "$ALPHA_CLIENT" '#{session_name}')" alpha
kill "$CLIENT3_PID" 2>/dev/null || true
tmux -L "$S" set-option -gu @tmux-orchestrator-raise-command

kill "$CLIENT_PID" 2>/dev/null || true
CLIENT_PID=

# With focus-events on, a client whose terminal window lost focus does not
# see its pane: the agent notifies and a done state stays until focus returns.
# The fifo feeds the client's terminal the focus-out and focus-in reports.
# Loading the plugin turned focus-events on, and status reports it.
assert_eq "$(tmux -L "$S" show-options -gv focus-events)" on
"$BIN" notify status | grep -qx 'focus-events: on' || fail 'status hid focus-events'
FOCUS_FIFO="$FAKE/focus.fifo"
mkfifo "$FOCUS_FIFO"
(env -u TMUX TERM=xterm-256color timeout 60 script -qefc "tmux -L $S attach -t alpha" /dev/null <"$FOCUS_FIFO" >/dev/null 2>&1) &
CLIENT_PID=$!
exec 7>"$FOCUS_FIFO"
for _ in $(seq 1 30); do
	[[ $(tmux -L "$S" list-clients -F '#{client_flags}' | grep -c focused || true) == 1 ]] && break
	sleep 0.1
done
tmux -L "$S" select-window -t alpha:main
tmux -L "$S" select-pane -t "$P0"
: >"$NOTIFY_LOG"
report_state "$P0" working fix-login claude s0
report_state "$P0" blocked fix-login claude s0
assert_eq "$(count_lines "$NOTIFY_LOG")" 0
printf '\033[O' >&7
for _ in $(seq 1 30); do
	[[ $(tmux -L "$S" list-clients -F '#{client_flags}' | grep -c focused || true) == 0 ]] && break
	sleep 0.1
done
report_state "$P0" working fix-login claude s0
report_state "$P0" done fix-login claude s0
assert_eq "$(count_lines "$NOTIFY_LOG")" 1
assert_contains "$NOTIFY_LOG" '✓ Agent done: fix-login'
"$BIN" focus
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_1_state)" done
printf '\033[I' >&7
for _ in $(seq 1 30); do
	[[ $(tmux -L "$S" show-options -pv -t "$P0" @agent_1_state) == idle ]] && break
	sleep 0.1
done
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_1_state)" idle
exec 7>&-

# Opting out keeps focus-events as it was, warns, and status says so.
tmux -L "$S" set-option -g focus-events off
tmux -L "$S" set-option -g @tmux-orchestrator-focus-events off
"$ROOT/tmux-orchestrator.tmux"
assert_eq "$(tmux -L "$S" show-options -gv focus-events)" off
"$BIN" notify status | grep -qF 'focus-events: off' || fail 'status hid focus-events off'
tmux -L "$S" set-option -gu @tmux-orchestrator-focus-events
kill "$CLIENT_PID" 2>/dev/null || true
CLIENT_PID=
printf 'notification tests passed\n'
