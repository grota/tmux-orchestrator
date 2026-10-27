#!/usr/bin/env bash
# Renders the sidebar on a throwaway socket with an attached pty client.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/tmux-orchestrator"
. "$ROOT/tests/helpers.sh"
S="tmux-orchestrator-sidebar-$$"
export TMUX_SOCKET=$S
LOG="/tmp/tmux-orchestrator-sidebar-$$.log"

cleanup() {
	kill "${CLIENT_PID:-}" 2>/dev/null || true
	tmux -L "$S" kill-server 2>/dev/null || true
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }
assert_contains() { grep -aFq -- "$2" "$1" || fail "missing [$2] in $1"; }

tmux -L "$S" new-session -d -s alpha -n main -x 120 -y 40 'sleep 300'
# Keep the developer's real OpenCode plugin link untouched.
tmux -L "$S" set-option -g @tmux-orchestrator-opencode-auto-install off
tmux -L "$S" split-window -t alpha:main -d 'sleep 300'
tmux -L "$S" new-window -t alpha -n second 'sleep 300'
tmux -L "$S" split-window -t alpha:second -d 'sleep 300'
tmux -L "$S" split-window -t alpha:second -d 'sleep 300'
tmux -L "$S" new-session -d -s beta -n other -x 120 -y 40 'sleep 300'
tmux -L "$S" new-session -d -s gamma -n empty -x 120 -y 40 'sleep 300'
"$ROOT/tmux-orchestrator.tmux"
"$ROOT/tmux-orchestrator.tmux"
[[ $(tmux -L "$S" show-options -gv @tmux-orchestrator-reporter) == "$ROOT/bin/tmux-orchestrator" ]] || fail 'reporter path not published'
HOOK_COUNT=$(tmux -L "$S" show-hooks -g | grep -c 'after-select-pane\[90\]' || true)
[[ $HOOK_COUNT == 1 ]] || fail "duplicate select-pane hook: $HOOK_COUNT"
tmux -L "$S" show-hooks -gw | grep -Fq 'pane-exited[90]' || fail 'missing pane-exited hook'

P0=$(tmux -L "$S" display -p -t alpha:main.0 '#{pane_id}')
P1=$(tmux -L "$S" display -p -t alpha:main.1 '#{pane_id}')
P2=$(tmux -L "$S" display -p -t alpha:second.0 '#{pane_id}')
P3=$(tmux -L "$S" display -p -t beta:other.0 '#{pane_id}')
P4=$(tmux -L "$S" display -p -t alpha:second.1 '#{pane_id}')
P5=$(tmux -L "$S" display -p -t alpha:second.2 '#{pane_id}')

report_state "$P0" working fix-login claude s0
report_state "$P1" blocked 'x#[fg=red]y' opencode s1
report_state "$P2" done very-long-agent-name-that-should-truncate claude s2
report_state "$P3" error beta-agent opencode s3
report_state "$P5" idle idle-agent claude s4

# Marked but stateless pane must render as unknown, not disappear.
tmux -L "$S" set-option -p -t "$P4" @agent_n 1
tmux -L "$S" set-option -p -t "$P4" @agent_1_kind claude
tmux -L "$S" set-option -p -t "$P4" @agent_1_name stateless
"$BIN" reconcile

# An OpenCode pane with eleven tabs shows nine rows and an overflow row.
PO=$(tmux -L "$S" split-window -t alpha:main -d -P -F '#{pane_id}' 'sleep 300')
TABS=()
for i in 1 2 3 4 5 6 7 8 9 10 11; do
	TABS+=(--tab "ses_$i" idle "tab-$i")
done
TABS[42]=pending
"$BIN" tabs --pane "$PO" --active ses_1 "${TABS[@]}"

(env -u TMUX TERM=xterm-256color timeout 4 script -qefc "stty rows 60 cols 120; tmux -L $S attach -t alpha" "$LOG" >/dev/null 2>&1) &
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
# Session rows count the agents that need the user.
assert_contains "$LOG" '●2'
assert_contains "$LOG" '✓1'
assert_contains "$LOG" '×1'
assert_contains "$LOG" '○'
assert_contains "$LOG" '·'
assert_contains "$LOG" 'tab-2'
assert_contains "$LOG" 'tab-9'
# Each agent shows how long it has been in its state.
[[ $(opt "$P0" @agent_1_since) =~ ^[0-9]+$ ]] || fail 'no time in state'
grep -aEq '[0-9]+s' "$LOG" || fail 'time in state not rendered'
assert_contains "$LOG" '+2 more'
grep -aFq 'tab-11' "$LOG" && fail 'tab past the ninth slot was drawn'

# A tab row click selects its pane; the overflow row selects the pane too.
tmux -L "$S" select-pane -t "$P0"
"$BIN" select "$PO:2"
[[ $(tmux -L "$S" display -p -t alpha '#{pane_id}') == "$PO" ]] || fail 'tab row did not select its pane'
tmux -L "$S" select-pane -t "$P0"
"$BIN" select "$PO:+"
[[ $(tmux -L "$S" display -p -t alpha '#{pane_id}') == "$PO" ]] || fail 'overflow row did not select its pane'
"$BIN" remove --pane "$PO"
tmux -L "$S" kill-pane -t "$PO"

# Session rows keep the default switch-client; agent rows carry their pane ID
# in a user range because tmux's "=" target resolves to the active pane.
KEYS=$(tmux -L "$S" list-keys -T root MouseDown1Status)
FMT=$(tmux -L "$S" show-options -gv side-status-format)
[[ $KEYS == *'switch-client -t='* ]] || fail 'missing default switch-client'
[[ $KEYS == *'select #{mouse_status_range}'* ]] || fail 'missing pane selection'
ROW3=$(tmux -L "$S" show-options -gv @tmux-orchestrator-row-3)
[[ $ROW3 == *'range=user|#{pane_id}:3 '* ]] || fail 'agent rows must carry pane and slot'
[[ $FMT == *'#{E:@tmux-orchestrator-row-9}'* ]] || fail 'slot rows not expanded in the format'
[[ $FMT == *'range=user|#{pane_id}:+'* ]] || fail 'overflow row must carry its pane'
[[ $FMT != *'row-10'* ]] || fail 'more than nine slots generated'
[[ $FMT$ROW3 != *'range=pane|'* ]] || fail 'pane ranges cannot target their pane'

# Exercise the selection path the binding uses, including a split window.
tmux -L "$S" select-window -t alpha:main
tmux -L "$S" select-pane -t "$P1"
"$BIN" select "$P2"
sleep 0.3
[[ $(tmux -L "$S" show-options -pv -t "$P2" @agent_1_state) == idle ]] || fail 'done did not clear on selection'
CLIENT_NAME=$(tmux -L "$S" list-clients -F '#{client_name}' | head -1)
ACTIVE=$(tmux -L "$S" display -p -c "$CLIENT_NAME" '#{pane_id}')
[[ $ACTIVE == "$P2" ]] || fail "pane selection failed: $ACTIVE"

# A session-row click switches the client session.
tmux -L "$S" switch-client -c "$CLIENT_NAME" -t beta
[[ $(tmux -L "$S" display -p -c "$CLIENT_NAME" '#{client_session}') == beta ]] || fail 'session selection failed'
tmux -L "$S" switch-client -c "$CLIENT_NAME" -t alpha

# A native drag width is session-local and survives a state refresh.
tmux -L "$S" set-option -t alpha side-status-width 32
report_state "$P0" working fix-login claude s0
[[ $(tmux -L "$S" show-options -t alpha -v side-status-width) == 32 ]] || fail 'drag width reset by refresh'
tmux -L "$S" set-option -t alpha -u side-status-width

# pane-exited triggers a summary recomputation through the fixed hook.
tmux -L "$S" new-window -t alpha -n transient 'sleep 300'
PT=$(tmux -L "$S" display -p -t alpha:transient.0 '#{pane_id}')
report_state "$PT" working transient claude st
[[ $(tmux -L "$S" show-options -v -t alpha @agent_count) == 6 ]] || fail 'transient count'
tmux -L "$S" respawn-pane -k -t "$PT" 'true'
sleep 0.8
[[ $(tmux -L "$S" show-options -v -t alpha @agent_count) == 5 ]] || fail 'pane-exited did not reconcile'

# remain-on-exit fires pane-died, which gc removes before it can stale the count.
tmux -L "$S" new-window -t alpha -n dead 'sleep 300'
PD=$(tmux -L "$S" display -p -t alpha:dead.0 '#{pane_id}')
tmux -L "$S" set-option -w -t alpha:dead remain-on-exit on
report_state "$PD" working dead claude sd
tmux -L "$S" respawn-pane -k -t "$PD" 'true'
sleep 0.8
[[ $(tmux -L "$S" show-options -pv -t "$PD" @agent_1_state 2>/dev/null || true) == '' ]] || fail 'pane-died left agent state'
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

# The time in state can be hidden without reloading the plugin.
tmux -L "$S" set-option -g @tmux-orchestrator-time off
NOTIME_LOG="/tmp/tmux-orchestrator-sidebar-notime-$$.log"
(env -u TMUX TERM=xterm-256color timeout 3 script -qefc "stty rows 60 cols 120; tmux -L $S attach -t alpha" "$NOTIME_LOG" >/dev/null 2>&1) &
sleep 1
assert_contains "$NOTIME_LOG" 'fix-login'
! grep -aEq '[0-9]+s' "$NOTIME_LOG" || fail 'time in state shown while off'
rm -f "$NOTIME_LOG"
tmux -L "$S" set-option -gu @tmux-orchestrator-time

# Agent rows render through their slot option; render one as plain lines.
row() { tmux -L "$S" display -p -t "$1" "#{E:@tmux-orchestrator-row-${2:-1}}"; }
plain() { sed -E 's/#\[nl\]/\n/g; s/#\[[^]]*\]//g' | sed '/^$/d'; }
lines() { row "$@" | plain | wc -l | tr -d ' '; }
tmux -L "$S" new-window -t alpha -n wrap 'sleep 300'
PW=$(tmux -L "$S" display -p -t alpha:wrap.0 '#{pane_id}')
tmux -L "$S" set-option -g side-status-width 28

# A short name takes one line, followed by the kind line holding the time.
report_state "$PW" working short claude sw
assert_eq "$(lines "$PW")" 2
row "$PW" | grep -Fq 'claude#[align=right]' || fail 'time not on the kind line'
[[ $(row "$PW" | plain | tail -1) =~ ^\ \ claude[0-9]+s\ $ ]] || fail 'kind line layout'

# Wrapping is the default: continuation lines are indented under the name.
report_state "$PW" working "$(printf 'n%.0s' {1..30})" claude sw
assert_eq "$(lines "$PW")" 3
assert_eq "$(row "$PW" | plain | sed -n 2p)" "  nnnnn"
assert_eq "$(row "$PW" | plain | head -1)" "◐ $(printf 'n%.0s' {1..25})"

# More than four lines: four are shown and the last ends in an ellipsis.
report_state "$PW" working "$(printf 'w%.0s' {1..120})" claude sw
assert_eq "$(lines "$PW")" 5
[[ $(row "$PW" | plain | sed -n 4p) == "  $(printf 'w%.0s' {1..25})…" ]] || fail 'fourth line not cut'

# Multibyte names are split by character.
report_state "$PW" working "$(printf 'é%.0s' {1..30})" claude sw
assert_eq "$(row "$PW" | plain | sed -n 2p)" "  ééééé"

# Wrapping follows a width change with no agent event.
tmux -L "$S" set-option -g side-status-width 23
assert_eq "$(row "$PW" | plain | sed -n 2p)" "  $(printf 'é%.0s' {1..10})"
tmux -L "$S" set-option -g side-status-width 28

# A fixed limit, nowrap and an invalid value, all applied live.
report_state "$PW" working refactor-the-login-flow-and-more-words claude sw
tmux -L "$S" set-option -g @tmux-orchestrator-name-max-chars 12
assert_eq "$(row "$PW" | plain | head -1)" "◐ refactor-the…"
assert_eq "$(lines "$PW")" 2
tmux -L "$S" set-option -g @tmux-orchestrator-name-max-chars nowrap
assert_eq "$(row "$PW" | plain | head -1)" "◐ refactor-the-login-flow-a…"
assert_eq "$(lines "$PW")" 2
tmux -L "$S" set-option -g @tmux-orchestrator-name-max-chars banana
assert_eq "$(lines "$PW")" 3
tmux -L "$S" set-option -g @tmux-orchestrator-name-max-chars wrap
assert_eq "$(lines "$PW")" 3
tmux -L "$S" set-option -gu @tmux-orchestrator-name-max-chars

# The focused agent is the active tab of the viewed pane.
"$BIN" tabs --pane "$PW" --active ses_b --tab ses_a idle tab-a --tab ses_b idle tab-b
tmux -L "$S" select-window -t alpha:wrap
tmux -L "$S" select-pane -t "$PW"
# Only the focused agent is emphasised: underlined by default, applied live.
row "$PW" 2 | grep -Fq '#[underscore]' || fail 'focused tab not underlined'
row "$PW" 1 | grep -Fq '#[underscore]' && fail 'background tab underlined'
row "$PW" 2 | grep -Fq '#[bold]' && fail 'focused tab bold by default'
tmux -L "$S" set-option -g @tmux-orchestrator-focus-style bold
row "$PW" 2 | grep -Fq '#[bold]' || fail 'focused tab not bold'
row "$PW" 2 | grep -Fq '#[underscore]' && fail 'bold style underlined'
row "$PW" 1 | grep -Fq '#[bold]' && fail 'background tab bold'
tmux -L "$S" set-option -g @tmux-orchestrator-focus-style none
row "$PW" 2 | grep -Eq '#\[(bold|underscore)\]' && fail 'none style emphasised'
tmux -L "$S" set-option -g @tmux-orchestrator-focus-style banana
row "$PW" 2 | grep -Fq '#[underscore]' || fail 'invalid style not underlined'
tmux -L "$S" set-option -gu @tmux-orchestrator-focus-style
# Every wrapped line of the focused name is emphasised.
"$BIN" tabs --pane "$PW" --active ses_b --tab ses_a idle tab-a --tab ses_b idle "$(printf 'u%.0s' {1..30})"
assert_eq "$(row "$PW" 2 | grep -oF '#[underscore]' | wc -l | tr -d ' ')" 2
"$BIN" remove --pane "$PW"
tmux -L "$S" kill-pane -t "$PW"

# The keys panel is closed by default and toggled by its footer row.
FMT=$(tmux -L "$S" show-options -gv side-status-format)
[[ $FMT == *'#[align=right]#[range=user|keys]? keys'* ]] || fail 'missing keys footer'
tmux -L "$S" display -p "$FMT" | grep -Fq 'prefix O  toggle' && fail 'keys panel open by default'
tmux -L "$S" bind-key N run-shell -b '#{@tmux-orchestrator-reporter} notify pause'
tmux -L "$S" bind-key M run-shell "'$BIN' reconcile #{pane_id}"
tmux -L "$S" bind-key X display-message 'not ours'
"$BIN" select keys
PANEL=$(tmux -L "$S" display -p "$FMT")
for line in 'prefix O  toggle' 'prefix N  notify pause' 'prefix M  reconcile ##{pane_id}'; do
	[[ $PANEL == *"$line"* ]] || fail "keys panel lacks [$line]"
done
[[ $PANEL != *'not ours'* && $PANEL != *MouseDown1Status* ]] || fail 'keys panel lists foreign or fixed bindings'
"$BIN" select keys
tmux -L "$S" display -p "$FMT" | grep -Fq 'prefix N' && fail 'keys panel did not close'
# A binding added after load appears on the next open.
tmux -L "$S" bind-key K run-shell -b '#{@tmux-orchestrator-reporter} gc'
"$BIN" select keys
tmux -L "$S" display -p "$FMT" | grep -Fq 'prefix K  gc' || fail 'new binding not listed'
"$BIN" select keys
tmux -L "$S" unbind-key N
tmux -L "$S" unbind-key M
tmux -L "$S" unbind-key X
tmux -L "$S" unbind-key K

# The toggle key never overwrites a user binding, and a changed key leaves no
# stale toggle behind.
tmux -L "$S" unbind-key O
tmux -L "$S" bind-key O display-message mine
"$ROOT/tmux-orchestrator.tmux"
[[ $(tmux -L "$S" list-keys -T prefix O) == *'display-message mine'* ]] || fail 'user binding overwritten'
"$BIN" select keys
tmux -L "$S" display -p "$FMT" | grep -Fq 'toggle' && fail 'skipped toggle key listed'
"$BIN" select keys
tmux -L "$S" unbind-key O
"$ROOT/tmux-orchestrator.tmux"
[[ $(tmux -L "$S" list-keys -T prefix O) == *' toggle'* ]] || fail 'free toggle key not bound'
tmux -L "$S" set-option -g @tmux-orchestrator-toggle-key S
"$ROOT/tmux-orchestrator.tmux"
[[ $(tmux -L "$S" list-keys -T prefix S) == *' toggle'* ]] || fail 'new toggle key not bound'
tmux -L "$S" list-keys -T prefix O >/dev/null 2>&1 && fail 'old toggle key still bound'
tmux -L "$S" set-option -gu @tmux-orchestrator-toggle-key
"$ROOT/tmux-orchestrator.tmux"

printf 'sidebar tests passed\n'
