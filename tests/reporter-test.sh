#!/usr/bin/env bash
# Reporter tests.  Uses a throwaway tmux socket and no network.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/tmux-orchestrator"
. "$ROOT/tests/helpers.sh"
S="tmux-orchestrator-reporter-$$"
export TMUX_SOCKET=$S

cleanup() {
	tmux -L "$S" kill-server 2>/dev/null || true
}
trap cleanup EXIT

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

assert_eq() {
	[[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"
}

tmux -L "$S" new-session -d -s alpha -n main -x 120 -y 40 'sleep 300'
tmux -L "$S" new-window -t alpha -n second 'sleep 300'
tmux -L "$S" split-window -t alpha:main -d 'sleep 300' 
P0=$(tmux -L "$S" display -p -t alpha:main.0 '#{pane_id}')
P1=$(tmux -L "$S" display -p -t alpha:main.1 '#{pane_id}')
P2=$(tmux -L "$S" display -p -t alpha:second.0 '#{pane_id}')

report_state "$P0" idle alpha-one claude s0
report_state "$P0" working alpha-one claude s0
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_1_state)" working
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_1_kind)" claude
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_1_sid)" s0

report_state "$P1" blocked alpha-two opencode s1
report_state "$P2" done alpha-three claude s2
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_count)" 3
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_rollup)" blocked

# Error is sticky across a completion without new activity.
report_state "$P0" error alpha-one claude s0
"$BIN" report --pane "$P0" --kind claude --event Stop --session-id s0
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_1_state)" error
report_state "$P0" working alpha-one claude s0
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_1_state)" working

# Hostile names are stored escaped for the format and raw for notifications.
report_state "$P1" working $'evil#[fg=red]\nline' claude s1
assert_eq "$(tmux -L "$S" show-options -pv -t "$P1" @agent_1_name_raw)" 'evil#[fg=red] line'
assert_eq "$(tmux -L "$S" show-options -pv -t "$P1" @agent_1_name)" 'evil##[fg=red] line'

# Repeated identical events do not duplicate state or counts.
report_state "$P2" done alpha-three claude s2
report_state "$P2" done alpha-three claude s2
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_count)" 3

# Removal recomputes the summary and is idempotent.
"$BIN" remove --pane "$P2"
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_count)" 2
if tmux -L "$S" show-options -pv -t "$P2" @agent_1_state >/dev/null 2>&1; then
	fail "agent state still present after removal"
fi
"$BIN" remove --pane "$P2"

# Reconcile repairs a deliberately wrong summary.
tmux -L "$S" set-option -t alpha @agent_count 99
tmux -L "$S" set-option -t alpha @agent_rollup idle
"$BIN" reconcile
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_count)" 2
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_rollup)" working

# A marked pane without a state is presented as unknown and still counted.
tmux -L "$S" set-option -p -t "$P2" @agent_n 1
tmux -L "$S" set-option -p -t "$P2" @agent_1_kind claude
tmux -L "$S" set-option -p -t "$P2" @agent_1_name p2
"$BIN" reconcile
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_count)" 3
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_rollup)" working

# Focus clears only the active pane's done state.
(env -u TMUX TERM=xterm-256color timeout 5 script -qefc "tmux -L $S attach -t alpha" /tmp/tmux-orchestrator-focus-$$.log >/dev/null 2>&1) &
CLIENT_PID=$!
sleep 0.5
CLIENT_NAME=$(tmux -L "$S" list-clients -F '#{client_name}' | head -1)
[[ -n $CLIENT_NAME ]] || fail "no attached client"
tmux -L "$S" select-window -t alpha:main
tmux -L "$S" select-pane -t "$P0"
sleep 0.3
tmux -L "$S" set-option -p -t "$P0" @agent_1_state done
tmux -L "$S" set-option -p -t "$P1" @agent_1_state done
tmux -L "$S" set-option -p -t "$P2" @agent_1_state done
ACTIVE=$(tmux -L "$S" display -p -c "$CLIENT_NAME" '#{pane_id}')
assert_eq "$ACTIVE" "$P0"
"$BIN" focus
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_1_state)" idle
assert_eq "$(tmux -L "$S" show-options -pv -t "$P1" @agent_1_state)" done
assert_eq "$(tmux -L "$S" show-options -pv -t "$P2" @agent_1_state)" done

# The agent-row click path selects the target pane and clears its done state.
tmux -L "$S" select-window -t alpha:second
tmux -L "$S" select-pane -t "$P2"
"$BIN" select "$P1"
ACTIVE=$(tmux -L "$S" display -p -c "$CLIENT_NAME" '#{pane_id}')
assert_eq "$ACTIVE" "$P1"
assert_eq "$(tmux -L "$S" show-options -pv -t "$P1" @agent_1_state)" idle
kill "$CLIENT_PID" 2>/dev/null || true

# Toggle persists off across a reload and restores the configured side.
"$BIN" toggle
assert_eq "$(tmux -L "$S" show-options -gv @tmux-orchestrator-enabled)" 0
assert_eq "$(tmux -L "$S" show-options -gv side-status)" off
TMUX_SOCKET=$S "$ROOT/tmux-orchestrator.tmux"
assert_eq "$(tmux -L "$S" show-options -gv side-status)" off
"$BIN" toggle
assert_eq "$(tmux -L "$S" show-options -gv @tmux-orchestrator-enabled)" 1
assert_eq "$(tmux -L "$S" show-options -gv side-status)" left

# A killed pane's options disappear and the summary can be recomputed.
tmux -L "$S" new-window -t alpha -n ephemeral 'sleep 300'
PE=$(tmux -L "$S" display -p -t alpha:ephemeral.0 '#{pane_id}')
report_state "$PE" working ephemeral claude se
tmux -L "$S" kill-pane -t "$PE"
"$BIN" reconcile
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_count)" 3

# A dead pane with remain-on-exit keeps its options until gc removes them.
tmux -L "$S" new-window -t alpha -n gc 'sleep 300'
PG=$(tmux -L "$S" display -p -t alpha:gc.0 '#{pane_id}')
tmux -L "$S" set-option -w -t alpha:gc remain-on-exit on
report_state "$PG" working dead-agent claude sg
tmux -L "$S" respawn-pane -k -t "$PG" 'true'
sleep 0.4
assert_eq "$(tmux -L "$S" display -p -t "$PG" '#{pane_dead}')" 1
"$BIN" gc
assert_eq "$(tmux -L "$S" show-options -pv -t "$PG" @agent_1_state 2>/dev/null || true)" ''
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_count)" 3

# A Claude interrupt is read from the transcript (ADR-0006).
export TMUX_ORCHESTRATOR_WATCH_TICK=0.2
TR_DIR=$(mktemp -d)
TR="$TR_DIR/session.jsonl"
printf '{"type":"user","message":{"content":"start"}}\n' >"$TR"
watchers() { pgrep -f "watch-interrupt --pane $P0 --transcript $TR" | wc -l | tr -d ' '; }
wait_watchers() {
	local i
	for i in $(seq 1 40); do
		[[ $(watchers) == "$1" ]] && return 0
		sleep 0.1
	done
	fail "expected $1 interrupt watchers, found $(watchers)"
}
wait_state() {
	local i
	for i in $(seq 1 25); do
		[[ $(opt "$P0" @agent_1_state) == "$1" ]] && return 0
		sleep 0.2
	done
	return 1
}
"$BIN" report --pane "$P0" --kind claude --event UserPromptSubmit --session-id s0 --transcript "$TR"
assert_eq "$(opt "$P0" @agent_1_state)" working
wait_watchers 1
# A subagent's interrupt, and a line still being written, change nothing.
printf '{"type":"user","isSidechain":true,"message":{"content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}\n' >>"$TR"
printf '{"type":"user","isSidechain":false,"message":{"content":[{"type":"text","text":"[Request interrupted' >>"$TR"
sleep 0.8
assert_eq "$(opt "$P0" @agent_1_state)" working
printf ' by user for tool use]"}]}}\n' >>"$TR"
wait_state idle || fail 'interrupt not detected'
assert_eq "$(opt "$P0" @agent_1_event)" claude:Interrupted
wait_watchers 0

# A new prompt retires the previous watcher; Stop ends the current one.
"$BIN" report --pane "$P0" --kind claude --event UserPromptSubmit --session-id s0 --transcript "$TR"
"$BIN" report --pane "$P0" --kind claude --event UserPromptSubmit --session-id s0 --transcript "$TR"
wait_watchers 1
"$BIN" report --pane "$P0" --kind claude --event Stop --session-id s0
wait_watchers 0
assert_eq "$(opt "$P0" @agent_1_state)" done

# A watcher gives up after the idle limit without transcript growth.
TMUX_ORCHESTRATOR_WATCH_IDLE=1 "$BIN" report --pane "$P0" --kind claude --event UserPromptSubmit --session-id s0 --transcript "$TR"
wait_watchers 1
wait_watchers 0
assert_eq "$(opt "$P0" @agent_1_state)" working
rm -rf "$TR_DIR"
unset TMUX_ORCHESTRATOR_WATCH_TICK

# The last agent event is recorded with its detail.
"$BIN" report --pane "$P0" --kind claude --event StopFailure --detail rate_limit --session-id s0
assert_eq "$(opt "$P0" @agent_1_event)" claude:StopFailure:rate_limit
assert_eq "$(opt "$P0" @agent_1_state)" error

# An OpenCode pane hosts one agent per tab, in tab order.
tmux -L "$S" new-window -t alpha -n tabs 'sleep 300'
PT=$(tmux -L "$S" display -p -t alpha:tabs.0 '#{pane_id}')
"$BIN" tabs --pane "$PT" --active ses_b --tab ses_a running api --tab ses_b idle docs --tab ses_c pending 'web app'
assert_eq "$(opt "$PT" @agent_n)" 3
assert_eq "$(opt "$PT" @agent_1_name)" api
assert_eq "$(opt "$PT" @agent_1_state)" working
assert_eq "$(opt "$PT" @agent_2_state)" idle
assert_eq "$(opt "$PT" @agent_3_state)" blocked
assert_eq "$(opt "$PT" @agent_3_name)" 'web app'
assert_eq "$(opt "$PT" @agent_active)" 2
assert_eq "$(opt "$PT" @agent_pane_rollup)" blocked

# Events find their tab by agent session ID.
"$BIN" report --pane "$PT" --kind opencode --event session.execution.succeeded --session-id ses_a
assert_eq "$(opt "$PT" @agent_1_state)" done
"$BIN" report --pane "$PT" --kind opencode --event session.execution.started --session-id ses_b
assert_eq "$(opt "$PT" @agent_2_state)" working

# Closing the middle tab keeps the others in order with their state.
"$BIN" tabs --pane "$PT" --active ses_c --tab ses_a running api --tab ses_c pending 'web app'
assert_eq "$(opt "$PT" @agent_n)" 2
assert_eq "$(opt "$PT" @agent_1_sid)" ses_a
assert_eq "$(opt "$PT" @agent_1_state)" done
assert_eq "$(opt "$PT" @agent_2_sid)" ses_c
assert_eq "$(opt "$PT" @agent_2_state)" blocked
assert_eq "$(opt "$PT" @agent_3_sid)" ''
assert_eq "$(opt "$PT" @agent_active)" 2

# Focusing a done tab inside the TUI clears it.
"$BIN" tabs --pane "$PT" --active ses_a --tab ses_a running api --tab ses_c pending 'web app'
assert_eq "$(opt "$PT" @agent_1_state)" idle
assert_eq "$(opt "$PT" @agent_1_event)" opencode:tab.focused

# A renamed tab keeps its state.
"$BIN" report --pane "$PT" --kind opencode --event session.renamed --session-id ses_a --name 'api v2'
assert_eq "$(opt "$PT" @agent_1_name_raw)" 'api v2'
assert_eq "$(opt "$PT" @agent_1_state)" idle

# Agents past the ninth roll up into the overflow fields.
TABS=()
for i in 1 2 3 4 5 6 7 8 9 10 11; do
	TABS+=(--tab "ses_$i" idle "tab-$i")
done
TABS[42]=pending
"$BIN" tabs --pane "$PT" --active ses_1 "${TABS[@]}"
assert_eq "$(opt "$PT" @agent_n)" 11
assert_eq "$(opt "$PT" @agent_more_n)" 2
assert_eq "$(opt "$PT" @agent_more_state)" blocked
assert_eq "$(opt "$PT" @agent_11_state)" blocked
"$BIN" tabs --pane "$PT" --active ses_1 "${TABS[@]:0:36}"
assert_eq "$(opt "$PT" @agent_n)" 9
assert_eq "$(opt "$PT" @agent_more_n)" ''
assert_eq "$(opt "$PT" @agent_10_sid)" ''

# Selecting a tab row asks the pane's TUI to focus that tab over its socket.
SOCK_DIR=$(mktemp -d)
SOCK="$SOCK_DIR/focus.sock"
FOCUS_LOG="$SOCK_DIR/focus.log"
python3 -I -c '
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sys.argv[1]); s.listen(1); s.settimeout(5)
c, _ = s.accept()
open(sys.argv[2], "w").write(c.recv(256).decode())
' "$SOCK" "$FOCUS_LOG" &
LISTENER=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -S $SOCK ]] && break; sleep 0.1; done
"$BIN" register --pane "$PT" --socket "$SOCK"
"$BIN" select "$PT:3"
wait "$LISTENER" || true
assert_eq "$(cat "$FOCUS_LOG")" 'focus ses_3'
"$BIN" select "$PT:+"
rm -rf "$SOCK_DIR"

# A whole pane is removed when its TUI exits.
"$BIN" remove --pane "$PT"
assert_eq "$(opt "$PT" @agent_n)" ''
assert_eq "$(opt "$PT" @agent_1_sid)" ''
assert_eq "$(opt "$PT" @agent_socket)" ''

# A Claude session that ends removes its agent.
"$BIN" report --pane "$P0" --kind claude --event SessionEnd --session-id s0
assert_eq "$(opt "$P0" @agent_n)" ''

# Options left by the older single-agent layout are cleared by reconcile.
tmux -L "$S" set-option -p -t "$P0" @agent_kind claude
tmux -L "$S" set-option -p -t "$P0" @agent_state working
"$BIN" reconcile
assert_eq "$(opt "$P0" @agent_kind)" ''
assert_eq "$(opt "$P0" @agent_state)" ''

# Legacy options are also cleared beside current slots, and a pane-level
# @agent_rollup no longer shadows the session rollup on session rows.
report_state "$P0" blocked alpha-one claude s0
report_state "$P1" working alpha-two claude s1
tmux -L "$S" set-option -p -t "$P1" @agent_rollup working
tmux -L "$S" set-option -p -t "$P1" @agent_kind claude
"$BIN" reconcile
assert_eq "$(opt "$P1" @agent_kind)" ''
assert_eq "$(tmux -L "$S" show-options -pqv -t "$P1" @agent_rollup)" ''
assert_eq "$(opt "$P1" @agent_1_state)" working
tmux -L "$S" select-window -t alpha:main
tmux -L "$S" select-pane -t "$P1"
assert_eq "$(tmux -L "$S" display -p -t "$P1" '#{@agent_rollup}')" blocked

# cleanup leaves no agent option of either layout.
report_state "$P0" working alpha-one claude s0
tmux -L "$S" set-option -p -t "$P1" @agent_session old
"$BIN" cleanup
LEFT=$(for p in $(tmux -L "$S" list-panes -a -F '#{pane_id}'); do tmux -L "$S" show-options -p -t "$p"; done | grep -c '^@agent_' || true)
assert_eq "$LEFT" 0
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_count 2>/dev/null || true)" ''

printf 'reporter tests passed\n'
