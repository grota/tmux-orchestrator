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
RUN_RENAME="${REPORTER_PREFIX}'$REPORTER' rename-prompt"
# Not named TMUX: assigning an array to it drops tmux's own TMUX variable
# from every command, which then talks to the default server.
TMUX_CMD=("${TMUX_BIN:-tmux}")
if [[ -n ${TMUX_SOCKET:-} ]]; then
	TMUX_CMD+=(-L "$TMUX_SOCKET")
fi

if ! "${TMUX_CMD[@]}" show-options -g side-status >/dev/null 2>&1; then
	"${TMUX_CMD[@]}" display-message "tmux-orchestrator: tmux 3.9 or newer is required (side-status)" >/dev/null 2>&1 || true
	exit 0
fi

enabled=$("${TMUX_CMD[@]}" show-options -gv @tmux-orchestrator-enabled 2>/dev/null || true)
side=$("${TMUX_CMD[@]}" show-options -gv @tmux-orchestrator-side 2>/dev/null || true)
width=$("${TMUX_CMD[@]}" show-options -gv @tmux-orchestrator-width 2>/dev/null || true)
toggle_key=$("${TMUX_CMD[@]}" show-options -gv @tmux-orchestrator-toggle-key 2>/dev/null || true)
opencode_auto=$("${TMUX_CMD[@]}" show-options -gv @tmux-orchestrator-opencode-auto-install 2>/dev/null || true)

[[ -n $enabled ]] || enabled=1
[[ $side == left || $side == right ]] || side=left
[[ $width =~ ^[0-9]+$ ]] || width=28
((width >= 10)) || width=28
[[ -n $toggle_key ]] || toggle_key=O

# Adapters find the reporter of the copy loaded here through this option (ADR-0007).
"${TMUX_CMD[@]}" set-option -g @tmux-orchestrator-reporter "$REPORTER"
# Keep the OpenCode adapter linked to this copy when OpenCode is installed.  The
# server PATH can miss a bin directory added by shell startup files, so the
# config directory OpenCode creates on first run counts too.
if [[ $opencode_auto != off ]] && { command -v opencode >/dev/null 2>&1 || [[ -d $HOME/.config/opencode ]]; }; then
	"$REPORTER" install opencode --quiet >/dev/null 2>&1 || true
fi
"${TMUX_CMD[@]}" set-option -g @tmux-orchestrator-enabled "$enabled"
"${TMUX_CMD[@]}" set-option -g @tmux-orchestrator-side "$side"
"${TMUX_CMD[@]}" set-option -g @tmux-orchestrator-width "$width"
"${TMUX_CMD[@]}" set-option -g @tmux-orchestrator-toggle-key "$toggle_key"

if [[ $enabled == 0 ]]; then
	"${TMUX_CMD[@]}" set-option -g side-status off
else
	"${TMUX_CMD[@]}" set-option -g side-status "$side"
fi
"${TMUX_CMD[@]}" set-option -g side-status-width "$width"

# Assemble the sidebar from lib/sidebar-format: one icon fragment for every
# state, one agent row repeated per slot, and the overflow row (ADR-0004).
while IFS= read -r line; do
	case "$line" in
	slots=*) VISIBLE_SLOTS=${line#slots=} ;;
	name_lines=*) NAME_LINES=${line#name_lines=} ;;
	nw=*) FMT_NW=${line#nw=} ;;
	nw1=*) FMT_NW1=${line#nw1=} ;;
	extra=*) FMT_EXTRA=${line#extra=} ;;
	focus=*) FMT_FOCUS=${line#focus=} ;;
	fixed=*) FMT_FIXED=${line#fixed=} ;;
	nowrap=*) FMT_NOWRAP=${line#nowrap=} ;;
	emph=*) FMT_EMPH=${line#emph=} ;;
	name_first=*) FMT_NAME_FIRST=${line#name_first=} ;;
	name_more=*) FMT_NAME_MORE=${line#name_more=} ;;
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

# Name lines 2 and later skip the name widths already shown, using a prefix
# of this dot string as a regex (ADR-0008).  It covers sidebars up to 500
# columns wide.
dots=$(printf '%*s' $((500 * (NAME_LINES - 1))) '')
"${TMUX_CMD[@]}" set-option -g @tmux-orchestrator-dots "${dots// /.}"

name_more=''
for ((line = 2; line <= NAME_LINES; line++)); do
	cut='/{NW}'
	((line == NAME_LINES)) && cut='/{NW}/…'
	fragment=${FMT_NAME_MORE//\{OFF\}/"#{e|-:#{e|*:{NW},$((line - 1))},{EXTRA}}"}
	name_more+=${fragment//\{CUT\}/"$cut"}
done
agent_row=${FMT_AGENT_ROW/\{NAME_FIRST\}/"$FMT_NAME_FIRST"}
agent_row=${agent_row/\{NAME_MORE\}/"$name_more"}
agent_row=${agent_row//\{EMPH\}/"$FMT_EMPH"}
agent_row=${agent_row//\{NOWRAP\}/"$FMT_NOWRAP"}
agent_row=${agent_row//\{FIXED\}/"$FMT_FIXED"}
agent_row=${agent_row//\{FOCUS\}/"$FMT_FOCUS"}
agent_row=${agent_row//\{NW1\}/"$FMT_NW1"}
agent_row=${agent_row//\{EXTRA\}/"$FMT_EXTRA"}
agent_row=${agent_row//\{NW\}/"$FMT_NW"}

# Each slot's row lives in its own option and the format expands it with E:,
# because nine inline rows exceed tmux's command size limit.  The options hold
# only this static fragment; agent names are still read with single escaping.
agent_rows=''
for ((slot = 1; slot <= VISIBLE_SLOTS; slot++)); do
	"${TMUX_CMD[@]}" set-option -g "@tmux-orchestrator-row-$slot" "$(expand_icons "${agent_row//\{I\}/"$slot"}")"
	agent_rows+="#{E:@tmux-orchestrator-row-$slot}"
done
format=${FMT_LAYOUT/\{AGENT_ROWS\}/"$agent_rows"}
format=${format/\{MORE_ROW\}/"$FMT_MORE_ROW"}
"${TMUX_CMD[@]}" set-option -g side-status-format "$(expand_icons "$format")"

# Session rows keep the default switch-client -t= behaviour.  Agent rows use a
# user range that carries the pane ID: tmux's special mouse target (=) resolves
# to the active pane for side-status pane ranges, so it cannot select the row.
# The reporter receives the ID and executes select-window/select-pane itself.
CLICK="if -F '#{==:#{mouse_status_range},session}' 'switch-client -t=' ; if -F '#{==:#{mouse_status_range},window}' 'switch-client -t= ; select-window -t=' ; if -F '#{&&:#{mouse_status_range},#{!=:#{mouse_status_range},session},#{!=:#{mouse_status_range},window}}' 'run-shell -b \"$RUN_SELECT #{mouse_status_range}\"'"
"${TMUX_CMD[@]}" bind-key -n MouseDown1Status "$CLICK"

# A double click renames: the first click has already switched to the session,
# so a session row renames the current session, like prefix $.  An agent row
# asks the reporter, which renames the agent in Claude Code or OpenCode.
DOUBLE_CLICK="if -F '#{==:#{mouse_status_range},session}' { command-prompt -I '#S' -p 'rename session:' { rename-session -- \"%%%\" } } ; if -F '#{m/r:^%[0-9]+:[0-9]+\$,#{mouse_status_range}}' 'run-shell -b \"$RUN_RENAME #{mouse_status_range} #{client_name}\"'"
"${TMUX_CMD[@]}" bind-key -n DoubleClick1Status "$DOUBLE_CLICK"

# The toggle key never overwrites a user binding.  Our toggle bindings are
# recognised by the reporter's file name, so one left by a moved checkout or
# an earlier toggle key is found and removed too.
is_our_toggle() { [[ $1 == *bin/tmux-orchestrator*' toggle'* ]]; }
while IFS='|' read -r key command; do
	[[ $key != "$toggle_key" ]] && is_our_toggle "$command" && "${TMUX_CMD[@]}" unbind-key -T prefix "$key"
done < <("${TMUX_CMD[@]}" list-keys -T prefix -F '#{key_string}|#{key_command}' 2>/dev/null || true)
existing=$("${TMUX_CMD[@]}" list-keys -T prefix -F '#{key_command}' "$toggle_key" 2>/dev/null || true)
if [[ -z $existing ]] || is_our_toggle "$existing"; then
	"${TMUX_CMD[@]}" bind-key "$toggle_key" run-shell -b "$RUN_TOGGLE"
else
	"${TMUX_CMD[@]}" display-message "tmux-orchestrator: prefix $toggle_key is already bound, so the sidebar toggle key was not bound" >/dev/null 2>&1 || true
fi

# Fixed indexes make reloads idempotent and preserve other plugins' hooks.
"${TMUX_CMD[@]}" set-hook -g 'after-select-pane[90]' "run-shell -b \"$RUN_FOCUS\""
"${TMUX_CMD[@]}" set-hook -g 'after-select-window[90]' "run-shell -b \"$RUN_FOCUS\""
"${TMUX_CMD[@]}" set-hook -g 'client-session-changed[90]' "run-shell -b \"$RUN_FOCUS\""
"${TMUX_CMD[@]}" set-hook -gw 'pane-exited[90]' "run-shell -b \"$RUN_RECONCILE\""
# remain-on-exit keeps a dead pane instead of firing pane-exited.
"${TMUX_CMD[@]}" set-hook -gw 'pane-died[90]' "run-shell -b \"$RUN_GC\""
"${TMUX_CMD[@]}" set-hook -g 'session-closed[90]' "run-shell -b \"$RUN_RECONCILE\""

exit 0
