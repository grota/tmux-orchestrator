#!/usr/bin/env bash
# TPM entry point.  Everything here is user-level and idempotent on reload.
set -u

CURRENT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPORTER="$CURRENT_DIR/bin/tmux-orchestrator"
if [[ -n ${TMUX_SOCKET:-} ]]; then
	REPORTER_PREFIX="TMUX_SOCKET=$(printf '%q' "$TMUX_SOCKET") "
else
	REPORTER_PREFIX=''
fi
RUN_FOCUS="${REPORTER_PREFIX}'$REPORTER' focus"
RUN_SELECT="${REPORTER_PREFIX}'$REPORTER' select"
RUN_RECONCILE="${REPORTER_PREFIX}'$REPORTER' reconcile"
RUN_GC="${REPORTER_PREFIX}'$REPORTER' gc"
RUN_TOGGLE="${REPORTER_PREFIX}'$REPORTER' toggle"
TMUX=("${TMUX_BIN:-tmux}")
if [[ -n ${TMUX_SOCKET:-} ]]; then
	TMUX+=(-L "$TMUX_SOCKET")
fi

if ! "${TMUX[@]}" show-options -g side-status >/dev/null 2>&1; then
	"${TMUX[@]}" display-message "tmux-orchestrator: tmux 3.9 or newer is required (side-status)" >/dev/null 2>&1 || true
	exit 0
fi

enabled=$("${TMUX[@]}" show-options -gv @tmux-orchestrator-enabled 2>/dev/null || true)
side=$("${TMUX[@]}" show-options -gv @tmux-orchestrator-side 2>/dev/null || true)
width=$("${TMUX[@]}" show-options -gv @tmux-orchestrator-width 2>/dev/null || true)
toggle_key=$("${TMUX[@]}" show-options -gv @tmux-orchestrator-toggle-key 2>/dev/null || true)
opencode=$("${TMUX[@]}" show-options -gv @tmux-orchestrator-opencode 2>/dev/null || true)

[[ -n $enabled ]] || enabled=1
[[ $side == left || $side == right ]] || side=left
[[ $width =~ ^[0-9]+$ ]] || width=28
((width >= 10)) || width=28
[[ -n $toggle_key ]] || toggle_key=O

# Adapters find the reporter of the copy loaded here through this option (ADR-0007).
"${TMUX[@]}" set-option -g @tmux-orchestrator-reporter "$REPORTER"
# Opt-in: keep the OpenCode adapter linked to this copy.
if [[ $opencode == on ]]; then
	"$REPORTER" install opencode --quiet >/dev/null 2>&1 || true
fi
"${TMUX[@]}" set-option -g @tmux-orchestrator-enabled "$enabled"
"${TMUX[@]}" set-option -g @tmux-orchestrator-side "$side"
"${TMUX[@]}" set-option -g @tmux-orchestrator-width "$width"
"${TMUX[@]}" set-option -g @tmux-orchestrator-toggle-key "$toggle_key"

if [[ $enabled == 0 ]]; then
	"${TMUX[@]}" set-option -g side-status off
else
	"${TMUX[@]}" set-option -g side-status "$side"
fi
"${TMUX[@]}" set-option -g side-status-width "$width"

# Assemble the sidebar from lib/sidebar-format: one icon fragment for every
# state, one agent row repeated per slot, and the overflow row (ADR-0004).
VISIBLE_SLOTS=9
while IFS= read -r line; do
	case "$line" in
	icon=*) FMT_ICON=${line#icon=} ;;
	agent_row=*) FMT_AGENT_ROW=${line#agent_row=} ;;
	more_row=*) FMT_MORE_ROW=${line#more_row=} ;;
	layout=*) FMT_LAYOUT=${line#layout=} ;;
	esac
done <"$CURRENT_DIR/lib/sidebar-format"

# Replace every {ICON:option} marker in $1 with the icon fragment for option.
expand_icons() {
	local text=$1 out='' option
	while [[ $text == *'{ICON:'* ]]; do
		out+=${text%%\{ICON:*}
		text=${text#*\{ICON:}
		option=${text%%\}*}
		text=${text#*\}}
		out+=${FMT_ICON//\{STATE\}/"$option"}
	done
	printf '%s' "$out$text"
}

agent_rows=''
for ((slot = 1; slot <= VISIBLE_SLOTS; slot++)); do
	agent_rows+=${FMT_AGENT_ROW//\{I\}/"$slot"}
done
format=${FMT_LAYOUT/\{AGENT_ROWS\}/"$agent_rows"}
format=${format/\{MORE_ROW\}/"$FMT_MORE_ROW"}
"${TMUX[@]}" set-option -g side-status-format "$(expand_icons "$format")"

# Session rows keep the default switch-client -t= behaviour.  Agent rows use a
# user range that carries the pane ID: tmux's special mouse target (=) resolves
# to the active pane for side-status pane ranges, so it cannot select the row.
# The reporter receives the ID and executes select-window/select-pane itself.
CLICK="if -F '#{==:#{mouse_status_range},session}' 'switch-client -t=' ; if -F '#{==:#{mouse_status_range},window}' 'switch-client -t= ; select-window -t=' ; if -F '#{&&:#{mouse_status_range},#{!=:#{mouse_status_range},session},#{!=:#{mouse_status_range},window}}' 'run-shell -b \"$RUN_SELECT #{mouse_status_range}\"'"
"${TMUX[@]}" bind-key -n MouseDown1Status "$CLICK"

"${TMUX[@]}" bind-key "$toggle_key" run-shell -b "$RUN_TOGGLE"

# Fixed indexes make reloads idempotent and preserve other plugins' hooks.
"${TMUX[@]}" set-hook -g 'after-select-pane[90]' "run-shell -b \"$RUN_FOCUS\""
"${TMUX[@]}" set-hook -g 'after-select-window[90]' "run-shell -b \"$RUN_FOCUS\""
"${TMUX[@]}" set-hook -g 'client-session-changed[90]' "run-shell -b \"$RUN_FOCUS\""
"${TMUX[@]}" set-hook -gw 'pane-exited[90]' "run-shell -b \"$RUN_RECONCILE\""
# remain-on-exit keeps a dead pane instead of firing pane-exited.
"${TMUX[@]}" set-hook -gw 'pane-died[90]' "run-shell -b \"$RUN_GC\""
"${TMUX[@]}" set-hook -g 'session-closed[90]' "run-shell -b \"$RUN_RECONCILE\""

exit 0
