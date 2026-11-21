#!/usr/bin/env bash
# Forward Codex hook events without producing model context or decisions.
set -u
exec >/dev/null 2>&1

command -v jq >/dev/null || exit 0

fields=()
while IFS= read -r -d '' field; do
	fields+=("$field")
done < <(jq -j '[.hook_event_name, .session_id, .cwd, .tool_name] |
	map((strings // "") + "\u0000") | add')
((${#fields[@]} == 4)) || exit 0
event=${fields[0]} sid=${fields[1]} cwd=${fields[2]} tool=${fields[3]}
[[ -n $sid ]] || exit 0

case "$event" in
SessionStart | UserPromptSubmit | PreToolUse | PostToolUse | PermissionRequest | Stop | Interrupt | SessionEnd) ;;
*) exit 0 ;;
esac

tmux_cmd=("${TMUX_BIN:-tmux}")
[[ -n ${TMUX_SOCKET:-} ]] && tmux_cmd+=(-L "$TMUX_SOCKET")

# An auto-started daemon can inherit the first client's pane variables.
# Codex runs a hook in its own session, without a controlling terminal, so
# only an inline hook has an ancestor (the client) on the pane's terminal.
pane_owns_hook() {
	local pane_tty pid=$$ parent tty
	pane_tty=$("${tmux_cmd[@]}" display-message -p -t "$pane" '#{pane_tty}') || return 1
	pane_tty=${pane_tty#/dev/}
	[[ -n $pane_tty ]] || return 1
	while [[ $pid =~ ^[0-9]+$ ]] && ((pid > 1)); do
		read -r parent tty < <(ps -o ppid= -o tty= -p "$pid") || return 1
		[[ $tty == "$pane_tty" ]] && return 0
		pid=$parent
	done
	return 1
}

# Match the ID emitted by the client as a title item. Codex 0.171 shortens
# title items to 29 characters plus three dots, and puts "Action Required"
# before them while it waits for an approval.
find_daemon_pane() {
	local shortened="${sid:0:29}..." found='' candidate command stored_id title
	local separator=$'\x1f'
	while IFS="$separator" read -r candidate command stored_id title; do
		if [[ $event == SessionEnd ]]; then
			[[ $stored_id == "$sid" ]] || continue
		else
			[[ $command == codex ]] || continue
			case "$title" in
			*"$sid"* | *"$shortened"*) ;;
			*) continue ;;
			esac
		fi
		[[ -z $found ]] || return 2
		found=$candidate
	done < <("${tmux_cmd[@]}" list-panes -a -F "#{pane_id}${separator}#{pane_current_command}${separator}#{@agent_1_sid}${separator}#{pane_title}")
	[[ -n $found ]] || return 1
	printf '%s\n' "$found"
}

# The title names the pane even when a daemon inherited another pane's
# variables.  Without a title match, the hook's own pane is the fallback.
pane='' result=1 titled=0
if [[ $sid =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
	titled=1
	pane=$(find_daemon_pane)
	result=$?
fi
if [[ $result == 1 ]]; then
	pane=${TMUX_PANE:-}
	if [[ ! $pane =~ ^%[0-9]+$ ]] || ! pane_owns_hook; then
		pane=''
		# A new client may still be drawing its first title when the prompt arrives.
		if [[ $titled == 1 && $event == UserPromptSubmit ]]; then
			sleep 0.1
			pane=$(find_daemon_pane)
		fi
	fi
fi
[[ $pane =~ ^%[0-9]+$ ]] || exit 0

reporter=${TMUX_ORCHESTRATOR_REPORTER:-}
if [[ ! -x $reporter ]]; then
	reporter=$("${tmux_cmd[@]}" show-options -gv @tmux-orchestrator-reporter || true)
fi
[[ -x $reporter ]] || reporter=$(command -v tmux-orchestrator || true)
[[ -n $reporter ]] || exit 0

"$reporter" report --protocol 1 --pane "$pane" --kind codex \
	--event "$event" --session-id "$sid" --cwd "$cwd" --detail "$tool" || true
