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

[[ -n $enabled ]] || enabled=1
[[ $side == left || $side == right ]] || side=left
[[ $width =~ ^[0-9]+$ ]] || width=28
((width >= 10)) || width=28
[[ -n $toggle_key ]] || toggle_key=O

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
"${TMUX[@]}" set-option -g side-status-format "$(cat "$CURRENT_DIR/lib/sidebar-format")"

# Keep the default status-bar behaviour (switch-client -t=) and add the
# selection steps that side-status ranges need.  The pane branch also clears a
# done state when the already-active row is clicked.
CLICK="switch-client -t= ; if -F '#{==:#{mouse_status_range},window}' 'select-window -t=' ; if -F '#{==:#{mouse_status_range},pane}' 'select-window -t= ; select-pane -t= ; run-shell -b \"$RUN_FOCUS\"'"
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
