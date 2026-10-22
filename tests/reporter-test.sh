#!/usr/bin/env bash
# Reporter tests.  Uses a throwaway tmux socket and no network.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/tmux-orchestrator"
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

"$BIN" report --pane "$P0" --state idle --name alpha-one --kind claude --session-id s0
"$BIN" report --pane "$P0" --state working --name alpha-one --kind claude --session-id s0
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_state)" working
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_kind)" claude
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_session)" s0

"$BIN" report --pane "$P1" --state blocked --name alpha-two --kind opencode --session-id s1
"$BIN" report --pane "$P2" --state done --name alpha-three --kind claude --session-id s2
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_count)" 3
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_rollup)" blocked

# Error is sticky across a completion without new activity.
"$BIN" report --pane "$P0" --state error --name alpha-one --kind claude --session-id s0
"$BIN" report --pane "$P0" --state done --name alpha-one --kind claude --session-id s0
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_state)" error
"$BIN" report --pane "$P0" --state working --name alpha-one --kind claude --session-id s0
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_state)" working

# Hostile names are stored escaped for the format and raw for notifications.
"$BIN" report --pane "$P1" --state working --name $'evil#[fg=red]\nline' --kind claude --session-id s1
assert_eq "$(tmux -L "$S" show-options -pv -t "$P1" @agent_name_raw)" 'evil#[fg=red] line'
assert_eq "$(tmux -L "$S" show-options -pv -t "$P1" @agent_name)" 'evil##[fg=red] line'

# Repeated identical events do not duplicate state or counts.
"$BIN" report --pane "$P2" --state done --name alpha-three --kind claude --session-id s2
"$BIN" report --pane "$P2" --state done --name alpha-three --kind claude --session-id s2
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_count)" 3

# Removal recomputes the summary and is idempotent.
"$BIN" remove --pane "$P2"
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_count)" 2
if tmux -L "$S" show-options -pv -t "$P2" @agent_state >/dev/null 2>&1; then
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
tmux -L "$S" set-option -p -t "$P2" @agent_kind claude
tmux -L "$S" set-option -p -t "$P2" @agent_name p2
"$BIN" reconcile
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_count)" 3
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_rollup)" working

# Focus clears only the active pane's done state.
tmux -L "$S" set-option -p -t "$P0" @agent_state done
tmux -L "$S" set-option -p -t "$P1" @agent_state done
tmux -L "$S" set-option -p -t "$P2" @agent_state done
(env -u TMUX TERM=xterm-256color timeout 5 script -qefc "tmux -L $S attach -t alpha" /tmp/tmux-orchestrator-focus-$$.log >/dev/null 2>&1) &
CLIENT_PID=$!
sleep 0.5
CLIENT_NAME=$(tmux -L "$S" list-clients -F '#{client_name}' | head -1)
[[ -n $CLIENT_NAME ]] || fail "no attached client"
tmux -L "$S" select-window -t alpha:main
tmux -L "$S" select-pane -t "$P0"
ACTIVE=$(tmux -L "$S" display -p -c "$CLIENT_NAME" '#{pane_id}')
assert_eq "$ACTIVE" "$P0"
"$BIN" focus
assert_eq "$(tmux -L "$S" show-options -pv -t "$P0" @agent_state)" idle
assert_eq "$(tmux -L "$S" show-options -pv -t "$P1" @agent_state)" done
assert_eq "$(tmux -L "$S" show-options -pv -t "$P2" @agent_state)" done
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
"$BIN" report --pane "$PE" --state working --name ephemeral --kind claude --session-id se
tmux -L "$S" kill-pane -t "$PE"
"$BIN" reconcile
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_count)" 3

# A dead pane with remain-on-exit keeps its options until gc removes them.
tmux -L "$S" new-window -t alpha -n gc 'sleep 300'
PG=$(tmux -L "$S" display -p -t alpha:gc.0 '#{pane_id}')
tmux -L "$S" set-option -w -t alpha:gc remain-on-exit on
"$BIN" report --pane "$PG" --state working --name dead-agent --kind claude --session-id sg
tmux -L "$S" respawn-pane -k -t "$PG" 'true'
sleep 0.4
assert_eq "$(tmux -L "$S" display -p -t "$PG" '#{pane_dead}')" 1
"$BIN" gc
assert_eq "$(tmux -L "$S" show-options -pv -t "$PG" @agent_state 2>/dev/null || true)" ''
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_count)" 3

printf 'reporter tests passed\n'
