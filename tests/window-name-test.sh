#!/usr/bin/env bash
# Window names show the agent name of the active pane through the global
# automatic-rename-format, and the user's format around it is kept.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/tmux-orchestrator"
. "$ROOT/tests/helpers.sh"
S="tmux-orchestrator-window-name-$$"
export TMUX_SOCKET=$S

cleanup() { tmux -L "$S" kill-server 2>/dev/null || true; }
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }

TOKEN='#{pane_current_command}'
WRAP='#{?@agent_active_name,#{=20:@agent_active_name},#{pane_current_command}}'
DEFAULT='#{?pane_in_mode,[tmux],#{pane_current_command}}#{?pane_dead,[dead],}'

format() { tmux -L "$S" show-options -gwv automatic-rename-format; }
# The window name the current format gives pane $1.
name_of() { tmux -L "$S" display-message -p -t "$1" '#{E:automatic-rename-format}'; }
load() { "$ROOT/tmux-orchestrator.tmux"; }

tmux -L "$S" -f /dev/null new-session -d -s alpha -x 120 -y 40 'sleep 300'
tmux -L "$S" set-option -g @tmux-orchestrator-opencode-auto-install off
tmux -L "$S" split-window -t alpha -d 'sleep 300'
P0=$(tmux -L "$S" display -p -t alpha:0.0 '#{pane_id}')
P1=$(tmux -L "$S" display -p -t alpha:0.1 '#{pane_id}')
assert_eq "$(format)" "$DEFAULT"

# tmux's default: only the command part changes.
load
assert_eq "$(format)" "${DEFAULT//"$TOKEN"/"$WRAP"}"
assert_eq "$(name_of "$P0")" sleep

report_state "$P0" working 'a-very-long-agent-name-here' claude sid-1
assert_eq "$(name_of "$P0")" 'a-very-long-agent-na'
assert_eq "$(name_of "$P1")" sleep

# Copy mode still shows [tmux].
tmux -L "$S" copy-mode -t "$P0"
assert_eq "$(name_of "$P0")" '[tmux]'
tmux -L "$S" send-keys -t "$P0" -X cancel

# A # in the name is shown, not read as a style.
report_state "$P0" working 'fix #[bold]' claude sid-1
assert_eq "$(name_of "$P0")" 'fix ##[bold]'

# The OpenCode tab in front names the window.
"$BIN" report --pane "$P1" --kind opencode --event tab.opened --name docs --session-id ses_a
assert_eq "$(name_of "$P1")" docs

# The agent leaving gives the command back.
"$BIN" report --pane "$P0" --kind claude --event SessionEnd --session-id sid-1
assert_eq "$(name_of "$P0")" sleep

# Reloading does not wrap twice.
load
load
assert_eq "$(format)" "${DEFAULT//"$TOKEN"/"$WRAP"}"

# off gives the user's format back.
tmux -L "$S" set-option -g @tmux-orchestrator-window-name off
load
assert_eq "$(format)" "$DEFAULT"
tmux -L "$S" set-option -gu @tmux-orchestrator-window-name

# A custom format keeps everything around the command.
tmux -L "$S" set-option -gw automatic-rename-format "$TOKEN:#{b:pane_current_path}"
load
assert_eq "$(format)" "$WRAP:#{b:pane_current_path}"

# A format without the command is left alone.
tmux -L "$S" set-option -gw automatic-rename-format '#{b:pane_current_path}'
load
assert_eq "$(format)" '#{b:pane_current_path}'

# An earlier replacement is swapped for the current one.
tmux -L "$S" set-option -gw automatic-rename-format '#{?@old,#{@old},#{pane_current_command}}!'
tmux -L "$S" set-option -g @tmux-orchestrator-window-name-applied '#{?@old,#{@old},#{pane_current_command}}'
load
assert_eq "$(format)" "$WRAP!"

printf 'window-name-test: ok\n'
