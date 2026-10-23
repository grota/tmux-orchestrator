#!/usr/bin/env bash
# Claude Code adapter: reads a hook payload on stdin and forwards it to the
# shared reporter as an agent event (ADR-0005).  The reporter is resolved from
# the repository checkout that contains this plugin; CLAUDE_PLUGIN_ROOT is
# intentionally not used for the repository root because the plugin lives one
# directory below it.
set -u
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd || true)
reporter=${TMUX_ORCHESTRATOR_REPORTER:-$root/bin/tmux-orchestrator}
if [[ ! -x $reporter ]]; then
	reporter=$(command -v tmux-orchestrator 2>/dev/null || true)
fi
[[ -n $reporter && -n ${TMUX_PANE:-} ]] || exit 0
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
if [[ -n $agent_id ]]; then
	case "$event" in
	SessionStart | Stop | StopFailure | SessionEnd) exit 0 ;;
	esac
	sid=''
fi

args=(report --pane "$TMUX_PANE" --kind claude --event "$event")
[[ -n $detail ]] && args+=(--detail "$detail")
[[ -n $sid ]] && args+=(--session-id "$sid")
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
