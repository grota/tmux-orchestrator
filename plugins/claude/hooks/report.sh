#!/usr/bin/env bash
# Claude Code adapter: reads a hook payload on stdin and forwards it to the
# shared reporter as an agent event (ADR-0005).  Claude Code installs only this
# plugin's directory, so the reporter is found through the tmux server the
# agent runs in (ADR-0007): an explicit override, the option the tmux plugin
# publishes, then PATH.
set -u
[[ -n ${TMUX_PANE:-} ]] || exit 0
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
	.notification_type // "",
	.transcript_path // ""
] | map(tostring + "\u0000") | add' 2>/dev/null)
((${#fields[@]} == 9)) || exit 0
event=${fields[0]} sid=${fields[1]} cwd=${fields[2]} title=${fields[3]}
agent_id=${fields[4]} tool=${fields[5]} error=${fields[6]} ntype=${fields[7]}
transcript=${fields[8]}
[[ -n $event ]] || exit 0

case "$event" in
PreToolUse) detail=$tool ;;
StopFailure) detail=$error ;;
Notification) detail=$ntype ;;
*) detail='' ;;
esac

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

args=(report --protocol 1 --pane "$TMUX_PANE" --kind claude --event "$event")
[[ -n $detail ]] && args+=(--detail "$detail")
[[ -n $sid ]] && args+=(--session-id "$sid")
[[ -n $agent_id ]] && args+=(--agent "$agent_id")
[[ -n $cwd ]] && args+=(--cwd "$cwd")
# A new turn starts the interrupt watcher on the main transcript (ADR-0006).
[[ $event == UserPromptSubmit && -n $transcript ]] && args+=(--transcript "$transcript")
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
