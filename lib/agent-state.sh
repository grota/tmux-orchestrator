# Agent state module for tmux-orchestrator.  Sourced by the reporter and its
# tests; it performs no tmux or other I/O.  Every agent event's meaning and
# every state rule lives here (ADR-0005).

# Rank used for pane, overflow and session rollups.
agent_rank() {
	case "$1" in
	blocked) printf 5 ;;
	error) printf 4 ;;
	done) printf 3 ;;
	working) printf 2 ;;
	idle) printf 1 ;;
	*) printf 0 ;;
	esac
}

agent_valid_state() {
	case "$1" in
	working | blocked | done | idle | error | unknown) printf '%s' "$1" ;;
	*) printf unknown ;;
	esac
}

# Highest-ranked state of the arguments; prints nothing for no arguments.
agent_rollup() {
	local state best='' best_rank=-1 rank
	for state in "$@"; do
		state=$(agent_valid_state "$state")
		rank=$(agent_rank "$state")
		if ((rank > best_rank)); then
			best_rank=$rank
			best=$state
		fi
	done
	printf '%s' "$best"
}

# Translate an agent event into what it means for the agent:
# prompt, activity, wait, release, complete, fail, interrupt, start, end,
# viewed, set:<state>, or nothing for events that do not affect state.
agent_event_meaning() {
	local kind=$1 event=$2 detail=${3-}
	case "$kind:$event" in
	claude:SessionStart) printf start ;;
	claude:UserPromptSubmit) printf prompt ;;
	claude:PostToolUse | claude:ElicitationResult) printf activity ;;
	claude:PreToolUse)
		case "$detail" in
		AskUserQuestion | ExitPlanMode) printf wait ;;
		*) printf activity ;;
		esac
		;;
	claude:PermissionRequest | claude:Elicitation) printf wait ;;
	claude:Stop) printf complete ;;
	claude:StopFailure) printf fail ;;
	# A subagent that ends, or a tool that fails after its approval, no longer
	# waits for the user.
	claude:SubagentStop | claude:PostToolUseFailure) printf release ;;
	claude:SessionEnd) printf end ;;
	# Made by the reporter from the transcript: Claude Code has no interrupt hook.
	claude:Interrupted) printf interrupt ;;

	opencode:session.execution.started | opencode:permission.replied | \
		opencode:form.replied | opencode:form.cancelled) printf activity ;;
	opencode:permission.asked | opencode:form.created) printf wait ;;
	opencode:session.execution.succeeded) printf complete ;;
	opencode:session.execution.failed) printf fail ;;
	opencode:session.execution.interrupted) printf interrupt ;;
	opencode:tab.opened)
		case "$detail" in
		running) printf set:working ;;
		pending) printf set:blocked ;;
		*) printf set:idle ;;
		esac
		;;
	# A wait that loaded after its tab appeared, as when OpenCode restores a tab.
	opencode:tab.pending) printf wait ;;
	opencode:tab.closed) printf end ;;
	opencode:tab.focused) printf viewed ;;

	tmux:viewed) printf viewed ;;
	esac
}

# agent_waiters WAITERS KIND EVENT DETAIL ACTOR
# The actors (subagent IDs, or main) still waiting for the user after an
# event, from the space-separated WAITERS before it.  A wait adds ACTOR; that
# actor's own activity or end removes it; a new turn or outcome clears all.
agent_waiters() {
	local waiters=${1-} actor=${5:-main} out='' w
	case "$(agent_event_meaning "${2-}" "${3-}" "${4-}")" in
	'') printf '%s' "$waiters" ;;
	wait)
		for w in $waiters; do [[ $w == "$actor" ]] && actor=''; done
		printf '%s' "$waiters${actor:+${waiters:+ }$actor}"
		;;
	activity | release)
		for w in $waiters; do [[ $w == "$actor" ]] || out+="${out:+ }$w"; done
		printf '%s' "$out"
		;;
	esac
}

# agent_transition PREV KIND EVENT [DETAIL] [WAITING]
# Prints "set STATE NOTIFY", "forget", or "ignore".  PREV is empty for an agent
# that is not stored yet.  WAITING is 1 while another actor of the agent still
# waits for the user, which keeps it blocked.  NOTIFY is 1 when the state
# changes into blocked, error, or done.
agent_transition() {
	local prev=${1-} kind=${2-} event=${3-} detail=${4-} waiting=${5-} meaning next notify=0
	[[ -n $prev ]] && prev=$(agent_valid_state "$prev")
	meaning=$(agent_event_meaning "$kind" "$event" "$detail")

	case "$meaning" in
	'')
		printf 'ignore'
		return 0
		;;
	end)
		printf 'forget'
		return 0
		;;
	start) next=idle ;;
	prompt) next=working ;;
	activity)
		next=working
		[[ $prev == blocked && $waiting == 1 ]] && next=blocked
		;;
	release)
		[[ -n $prev ]] || { printf 'ignore'; return 0; }
		next=$prev
		[[ $prev == blocked && $waiting != 1 ]] && next=working
		;;
	wait) next=blocked ;;
	fail) next=error ;;
	interrupt) next=idle ;;
	set:*) next=${meaning#set:} ;;
	complete)
		# A completion only means done after work; an error survives it.
		case "$prev" in
		working | blocked) next=done ;;
		error) next=error ;;
		'') next=idle ;;
		*) next=$prev ;;
		esac
		;;
	viewed)
		case "$prev" in
		done) next=idle ;;
		'') next=idle ;;
		*) next=$prev ;;
		esac
		;;
	esac

	if [[ $next != "$prev" ]]; then
		case "$next" in
		blocked | error | done) notify=1 ;;
		esac
	fi
	printf 'set %s %s' "$next" "$notify"
}
