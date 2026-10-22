#!/usr/bin/env bash
# Renders the sidebar on a throwaway socket with an attached pty client.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/tmux-orchestrator"
S="tmux-orchestrator-sidebar-$$"
export TMUX_SOCKET=$S
LOG="/tmp/tmux-orchestrator-sidebar-$$.log"

cleanup() {
	kill "${CLIENT_PID:-}" 2>/dev/null || true
	tmux -L "$S" kill-server 2>/dev/null || true
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_contains() { grep -aFq -- "$2" "$1" || fail "missing [$2] in $1"; }

tmux -L "$S" new-session -d -s alpha -n main -x 120 -y 40 'sleep 300'
tmux -L "$S" split-window -t alpha:main -d 'sleep 300'
tmux -L "$S" new-window -t alpha -n second 'sleep 300'
tmux -L "$S" split-window -t alpha:second -d 'sleep 300'
tmux -L "$S" split-window -t alpha:second -d 'sleep 300'
tmux -L "$S" new-session -d -s beta -n other -x 120 -y 40 'sleep 300'
tmux -L "$S" new-session -d -s gamma -n empty -x 120 -y 40 'sleep 300'
"$ROOT/tmux-orchestrator.tmux"
"$ROOT/tmux-orchestrator.tmux"
HOOK_COUNT=$(tmux -L "$S" show-hooks -g | grep -c 'after-select-pane\[90\]' || true)
[[ $HOOK_COUNT == 1 ]] || fail "duplicate select-pane hook: $HOOK_COUNT"
tmux -L "$S" show-hooks -gw | grep -Fq 'pane-exited[90]' || fail 'missing pane-exited hook'

P0=$(tmux -L "$S" display -p -t alpha:main.0 '#{pane_id}')
P1=$(tmux -L "$S" display -p -t alpha:main.1 '#{pane_id}')
P2=$(tmux -L "$S" display -p -t alpha:second.0 '#{pane_id}')
P3=$(tmux -L "$S" display -p -t beta:other.0 '#{pane_id}')
P4=$(tmux -L "$S" display -p -t alpha:second.1 '#{pane_id}')
P5=$(tmux -L "$S" display -p -t alpha:second.2 '#{pane_id}')

"$BIN" report --pane "$P0" --state working --name fix-login --kind claude --session-id s0
"$BIN" report --pane "$P1" --state blocked --name 'x#[fg=red]y' --kind opencode --session-id s1
"$BIN" report --pane "$P2" --state done --name very-long-agent-name-that-should-truncate --kind claude --session-id s2
"$BIN" report --pane "$P3" --state error --name beta-agent --kind opencode --session-id s3
"$BIN" report --pane "$P5" --state idle --name idle-agent --kind claude --session-id s4

# Marked but stateless pane must render as unknown, not disappear.
tmux -L "$S" set-option -p -t "$P4" @agent_kind claude
tmux -L "$S" set-option -p -t "$P4" @agent_name stateless
"$BIN" reconcile

(env -u TMUX TERM=xterm-256color timeout 4 script -qefc "tmux -L $S attach -t alpha" "$LOG" >/dev/null 2>&1) &
CLIENT_PID=$!
sleep 1

assert_contains "$LOG" 'Sessions'
assert_contains "$LOG" 'Agents'
assert_contains "$LOG" '▸'
assert_contains "$LOG" 'alpha'
assert_contains "$LOG" 'beta'
assert_contains "$LOG" 'fix-login'
assert_contains "$LOG" 'x#[fg=red]y'
assert_contains "$LOG" 'opencode'
assert_contains "$LOG" 'stateless'
assert_contains "$LOG" 'idle-agent'
assert_contains "$LOG" '◐'
assert_contains "$LOG" '●'
assert_contains "$LOG" '×'
assert_contains "$LOG" '✓'
assert_contains "$LOG" '○'
assert_contains "$LOG" '·'
assert_contains "$LOG" '…'

# The binding must preserve the default session switch and add window/pane
# selection for side-status ranges.
KEYS=$(tmux -L "$S" list-keys -T root MouseDown1Status)
[[ $KEYS == *'switch-client -t ='* ]] || fail 'missing default switch-client'
[[ $KEYS == *'select-window -t='* ]] || fail 'missing window selection'
[[ $KEYS == *'select-pane -t='* ]] || fail 'missing pane selection'

# Exercise the selection steps the binding uses, including a split window.
tmux -L "$S" select-window -t alpha:simple 2>/dev/null || true
tmux -L "$S" select-pane -t "$P1"
tmux -L "$S" select-window -t alpha:second
tmux -L "$S" select-pane -t "$P2"
sleep 0.3
[[ $(tmux -L "$S" show-options -pv -t "$P2" @agent_state) == idle ]] || fail 'done did not clear on selection'
CLIENT_NAME=$(tmux -L "$S" list-clients -F '#{client_name}' | head -1)
ACTIVE=$(tmux -L "$S" display -p -c "$CLIENT_NAME" '#{pane_id}')
[[ $ACTIVE == "$P2" ]] || fail "pane selection failed: $ACTIVE"

# A session-row click switches the client session.
tmux -L "$S" switch-client -c "$CLIENT_NAME" -t beta
[[ $(tmux -L "$S" display -p -c "$CLIENT_NAME" '#{client_session}') == beta ]] || fail 'session selection failed'
tmux -L "$S" switch-client -c "$CLIENT_NAME" -t alpha

# A native drag width is session-local and survives a state refresh.
tmux -L "$S" set-option -t alpha side-status-width 32
"$BIN" report --pane "$P0" --state working --name fix-login --kind claude --session-id s0
[[ $(tmux -L "$S" show-options -t alpha -v side-status-width) == 32 ]] || fail 'drag width reset by refresh'
tmux -L "$S" set-option -t alpha -u side-status-width

# pane-exited triggers a summary recomputation through the fixed hook.
tmux -L "$S" new-window -t alpha -n transient 'sleep 300'
PT=$(tmux -L "$S" display -p -t alpha:transient.0 '#{pane_id}')
"$BIN" report --pane "$PT" --state working --name transient --kind claude --session-id st
[[ $(tmux -L "$S" show-options -v -t alpha @agent_count) == 6 ]] || fail 'transient count'
tmux -L "$S" respawn-pane -k -t "$PT" 'true'
sleep 0.8
[[ $(tmux -L "$S" show-options -v -t alpha @agent_count) == 5 ]] || fail 'pane-exited did not reconcile'

# remain-on-exit fires pane-died, which gc removes before it can stale the count.
tmux -L "$S" new-window -t alpha -n dead 'sleep 300'
PD=$(tmux -L "$S" display -p -t alpha:dead.0 '#{pane_id}')
tmux -L "$S" set-option -w -t alpha:dead remain-on-exit on
"$BIN" report --pane "$PD" --state working --name dead --kind claude --session-id sd
tmux -L "$S" respawn-pane -k -t "$PD" 'true'
sleep 0.8
[[ $(tmux -L "$S" show-options -pv -t "$PD" @agent_state 2>/dev/null || true) == '' ]] || fail 'pane-died left agent state'
[[ $(tmux -L "$S" show-options -v -t alpha @agent_count) == 5 ]] || fail 'pane-died did not reconcile'

kill "$CLIENT_PID" 2>/dev/null || true
CLIENT_PID=
sleep 0.2

# Current session with no agents gets a visible empty-state row.
LOG2="/tmp/tmux-orchestrator-sidebar-empty-$$.log"
(env -u TMUX TERM=xterm-256color timeout 3 script -qefc "tmux -L $S attach -t gamma" "$LOG2" >/dev/null 2>&1) &
CLIENT_PID=$!
sleep 0.8
assert_contains "$LOG2" 'no agents in this session'
assert_contains "$LOG2" 'alpha'
kill "$CLIENT_PID" 2>/dev/null || true
CLIENT_PID=

# Configuration and preserved default behaviour.
[[ $(tmux -L "$S" show-options -gv side-status-width) == 28 ]] || fail 'default width'
[[ $(tmux -L "$S" show-options -gv side-status) == left ]] || fail 'default side'

# The configured side is restored by a reload and can be changed.
tmux -L "$S" set-option -g @tmux-orchestrator-side right
"$ROOT/tmux-orchestrator.tmux"
[[ $(tmux -L "$S" show-options -gv side-status) == right ]] || fail 'right side not restored'
tmux -L "$S" set-option -g @tmux-orchestrator-side left
"$ROOT/tmux-orchestrator.tmux"
[[ $(tmux -L "$S" show-options -gv side-status) == left ]] || fail 'left side not restored'

printf 'sidebar tests passed\n'
