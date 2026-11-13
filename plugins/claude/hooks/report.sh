#!/usr/bin/env bash
# Claude Code adapter: reads a hook payload on stdin and forwards it to the
# shared reporter as an agent event (SPEC.md D5).  Claude Code installs only this
# plugin's directory, so the reporter is found through the tmux server the
# agent runs in (SPEC.md D7): an explicit override, the option the tmux plugin
# publishes, then PATH.
set -u
reporter=${TMUX_ORCHESTRATOR_REPORTER:-}
if [[ -z $reporter ]]; then
	tmux_cmd=(tmux)
	[[ -n ${TMUX_SOCKET:-} ]] && tmux_cmd+=(-L "$TMUX_SOCKET")
	reporter=$("${tmux_cmd[@]}" show-options -gv @tmux-orchestrator-reporter 2>/dev/null || true)
fi
[[ -n $reporter && -x $reporter ]] || reporter=$(command -v tmux-orchestrator 2>/dev/null || true)
[[ -n $reporter ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

fields=()
while IFS= read -r -d '' field; do
	fields+=("$field")
done < <(jq -j '[
	.hook_event_name // .event // "",
	.session_id // .sessionId // "",
	.cwd // "",
	.session_title // "",
	.agent_id // "",
	.tool_name // "",
	.error // "",
	(.tool_response.backgroundTaskId? // .tool_response.taskId? // .tool_use_id // ""),
	(.tool_input.run_in_background? // false),
	has("background_tasks"),
	([.background_tasks[]? | select(.status == "running" and (.type == "shell" or .type == "monitor")) | .id] | join(" ")),
	(if .hook_event_name == "UserPromptSubmit" and (.prompt | type) == "string" and (.prompt | startswith("<task-notification>"))
	 then (.prompt | [(capture("<task-id>(?<id>[^<]+)</task-id>").id // ""), (capture("<status>(?<s>[^<]+)</status>").s // "")] | join(" "))
	 else "" end)
] | map(tostring + "\u0000") | add' 2>/dev/null)
((${#fields[@]} == 12)) || exit 0
event=${fields[0]} sid=${fields[1]} cwd=${fields[2]} title=${fields[3]}
agent_id=${fields[4]} tool=${fields[5]} error=${fields[6]}
task_id=${fields[7]} background=${fields[8]}
has_tasks=${fields[9]} running=${fields[10]}
read -r notified notified_status <<<"${fields[11]}"
[[ -n $event ]] || exit 0

# A background task: Bash with run_in_background, or a Monitor, which always
# runs in the background.  Its end arrives as a task notification prompt, and
# the Stop hooks list the tasks still running (SPEC.md D11).
task=''
if [[ $event == PostToolUse && -n $task_id ]]; then
	case "$tool:$background" in
	Bash:true | Monitor:*) task=$task_id ;;
	esac
fi

case "$event" in
PreToolUse) detail=$tool ;;
StopFailure) detail=$error ;;
*) detail='' ;;
esac

# Claude Code sends subagent hooks with the main session's ID, which still
# finds the pane showing a background session.
hook_sid=$sid

# Subagent activity and waits count toward the main agent, but a subagent's
# lifecycle never starts, completes or ends it, and its session ID is not ours.
# Its end only means it no longer waits for the user.
if [[ -n $agent_id ]]; then
	case "$event" in
	SessionStart | StopFailure | SessionEnd) exit 0 ;;
	Stop) event=SubagentStop ;;
	esac
	sid=''
fi

# A background session runs outside tmux; the reporter finds the pane that
# shows it with `claude attach`.
if [[ -n ${TMUX_PANE:-} ]]; then
	args=(report --protocol 1 --pane "$TMUX_PANE" --kind claude --event "$event")
else
	[[ -n $hook_sid ]] || exit 0
	args=(report --protocol 1 --background --background-session "$hook_sid" --kind claude --event "$event")
fi
[[ -n $detail ]] && args+=(--detail "$detail")
[[ -n $sid ]] && args+=(--session-id "$sid")
[[ -n $agent_id ]] && args+=(--agent "$agent_id")
[[ -n $cwd ]] && args+=(--cwd "$cwd")
[[ -n $task ]] && args+=(--task "$task")
[[ ($event == Stop || $event == SubagentStop) && $has_tasks == true ]] && args+=(--tasks "$running")
if [[ $event == UserPromptSubmit && -z $agent_id && -n ${notified:-} ]]; then
	case "${notified_status:-}" in
	completed | failed | killed) args+=(--task-done "$notified") ;;
	esac
fi
case "$event" in
SessionStart | UserPromptSubmit)
	# A supplied title is authoritative; only look one up when it is absent.
	if [[ -n $title ]]; then
		args+=(--name "$title")
	else
		args+=(--refresh)
	fi
	;;
esac
exec "$reporter" "${args[@]}"
