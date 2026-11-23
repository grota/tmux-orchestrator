#!/usr/bin/env bash
# Drives the sidebar with real mouse input: a client attached inside a pane of
# an outer tmux server receives SGR mouse sequences, so tmux itself decides
# which key a click in the side status line becomes.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/tmux-orchestrator"
. "$ROOT/tests/helpers.sh"
S="tmux-orchestrator-mouse-$$"
O="tmux-orchestrator-mouse-outer-$$"
export TMUX_SOCKET=$S

cleanup() {
	tmux -L "$O" kill-server 2>/dev/null || true
	tmux -L "$S" kill-server 2>/dev/null || true
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }

# wait_for CODE: retries the shell code CODE for up to three seconds.
wait_for() {
	local _
	for _ in $(seq 30); do eval "$1" && return 0; sleep 0.1; done
	return 1
}

# row_of TEXT prints the 1-based screen line of the first sidebar line holding TEXT.
row_of() {
	tmux -L "$O" capture-pane -p -t "$O" | grep -nF -- "$1" | head -n 1 | cut -d: -f1
}

# click X Y sends a left click at 1-based column X, line Y.
click() {
	tmux -L "$O" send-keys -t "$O" -l $'\e'"[<0;$1;$2M"$'\e'"[<0;$1;$2m"
}

# double_click X Y sends two clicks inside tmux's double-click time.
double_click() {
	click "$1" "$2"
	sleep 0.05
	click "$1" "$2"
}

tmux -L "$S" -f /dev/null new-session -d -s alpha -x 120 -y 40 'sleep 300'
tmux -L "$S" set-option -g mouse on
tmux -L "$S" set-option -g @tmux-orchestrator-opencode-auto-install off
tmux -L "$S" split-window -t alpha -d 'sleep 300'
"$ROOT/tmux-orchestrator.tmux"
P0=$(tmux -L "$S" display -p -t alpha:0.0 '#{pane_id}')
PA=$(tmux -L "$S" display -p -t alpha:0.1 '#{pane_id}')
report_state "$PA" idle mouse-agent claude ses_mouse

# The status line's own bindings stay tmux's defaults.
[[ $(tmux -L "$S" list-keys -T root MouseDown1Status) == *'switch-client -t ='* ]] || fail 'MouseDown1Status was rebound'
[[ -z $(tmux -L "$S" list-keys -T root DoubleClick1Status 2>/dev/null) ]] || fail 'DoubleClick1Status was bound'

tmux -L "$O" -f /dev/null new-session -d -s "$O" -x 120 -y 40 \
	"env -u TMUX TERM=xterm-256color tmux -L $S attach -t alpha"
wait_for '[[ -n $(row_of mouse-agent) ]]' || fail 'sidebar never showed the agent'
AGENT_ROW=$(row_of mouse-agent)
SESSION_ROW=$(row_of ' alpha ')
[[ -n $SESSION_ROW ]] || fail 'sidebar never showed the session row'

# A click on an agent row focuses its pane.
tmux -L "$S" select-pane -t "$P0"
click 4 "$AGENT_ROW"
wait_for '[[ $(tmux -L "$S" display -p -t alpha "#{pane_id}") == "$PA" ]]' || fail 'agent row click did not focus its pane'
sleep 0.6

# A double click on an agent row opens the agent rename prompt.
double_click 4 "$AGENT_ROW"
wait_for '[[ $(tmux -L "$S" show-options -gqv @tmux-orchestrator-rename-row) == "$PA:1" ]]' || fail 'agent row double click opened no rename prompt'
wait_for '[[ -n $(row_of "rename claude agent:") ]]' || fail 'agent rename prompt not shown'
tmux -L "$O" send-keys -t "$O" C-c
wait_for '[[ -z $(row_of "rename claude agent:") ]]' || fail 'agent rename prompt did not close'
sleep 0.6

# A double click on a session row opens the session rename prompt.
double_click 4 "$SESSION_ROW"
wait_for '[[ -n $(row_of "rename session:") ]]' || fail 'session row double click opened no rename prompt'
tmux -L "$O" send-keys -t "$O" C-c

printf 'mouse tests passed\n'
