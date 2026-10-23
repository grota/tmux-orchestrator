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
# activity, wait, complete, fail, interrupt, start, end,
# viewed, set:<state>, or nothing for events that do not affect state.
agent_event_meaning() {
	local kind=$1 event=$2 detail=${3-}
	case "$kind:$event" in
	claude:SessionStart) printf start ;;
	claude:UserPromptSubmit | claude:PostToolUse | claude:ElicitationResult) printf activity ;;
	claude:PreToolUse)
		case "$detail" in
		AskUserQuestion | ExitPlanMode) printf wait ;;
		*) printf activity ;;
		esac
		;;
	claude:PermissionRequest | claude:Elicitation) printf wait ;;
	claude:Stop) printf complete ;;
	claude:StopFailure) printf fail ;;
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
	opencode:tab.closed) printf end ;;
	opencode:tab.focused) printf viewed ;;

	tmux:viewed) printf viewed ;;
	esac
}

# agent_transition PREV KIND EVENT [DETAIL]
# Prints "set STATE NOTIFY", "forget", or "ignore".  PREV is empty for an agent
# that is not stored yet.  NOTIFY is 1 when the state changes into blocked,
# error, or done.
agent_transition() {
	local prev=${1-} kind=${2-} event=${3-} detail=${4-} meaning next notify=0
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
	activity) next=working ;;
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
