#!/usr/bin/env bash
# Agent state module tests.  Pure: no tmux server is started.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../lib/agent-state.sh
. "$ROOT/lib/agent-state.sh"

FAILS=0
check() {
	local expected=$1 got
	shift
	got=$(agent_transition "$@")
	if [[ $got != "$expected" ]]; then
		printf 'FAIL: agent_transition %s -> [%s], expected [%s]\n' "$*" "$got" "$expected" >&2
		FAILS=$((FAILS + 1))
	fi
}

# Claude Code mapping.
check 'set idle 0' '' claude SessionStart
check 'set idle 0' done claude SessionStart
check 'set working 0' idle claude UserPromptSubmit
check 'set working 0' blocked claude PostToolUse
check 'set working 0' idle claude PreToolUse Bash
check 'set blocked 1' working claude PreToolUse AskUserQuestion
check 'set blocked 1' working claude PreToolUse ExitPlanMode
check 'set blocked 1' working claude PermissionRequest
check 'set blocked 1' working claude Elicitation
check 'set working 0' blocked claude ElicitationResult
check 'set done 1' working claude Stop
check 'set error 1' working claude StopFailure rate_limit
check 'forget' working claude SessionEnd
check 'set working 0' working claude PostToolUseFailure
check 'set error 0' error claude PostToolUseFailure
check 'set working 0' blocked claude PostToolUseFailure
check 'set working 0' working claude SubagentStop

# A blocked agent stays blocked while another of its actors still waits.
check 'set blocked 0' blocked claude PostToolUse '' 1
check 'set working 0' blocked claude PostToolUse '' 0
check 'set blocked 0' blocked claude SubagentStop '' 1
check 'set working 0' blocked claude SubagentStop ''
check 'set working 0' blocked claude UserPromptSubmit '' 1
check 'ignore' '' claude SubagentStop
w() {
	local expected=$1 got
	shift
	got=$(agent_waiters "$@")
	[[ $got == "$expected" ]] || { printf 'FAIL: agent_waiters %s -> [%s], expected [%s]\n' "$*" "$got" "$expected" >&2; FAILS=$((FAILS + 1)); }
}
w 'a1' '' claude PermissionRequest '' a1
w 'a1 main' 'a1' claude PreToolUse AskUserQuestion main
w 'a1' 'a1' claude PermissionRequest '' a1
w 'a1' 'a1 a2' claude PostToolUse '' a2
w '' 'a1' claude SubagentStop '' a1
w '' 'a1' claude PostToolUseFailure '' a1
w 'a1' 'a1' claude PostToolUse '' a2
w '' 'a1 a2' claude UserPromptSubmit '' main
w '' 'a1' claude Stop '' main
w 'a1' 'a1' claude Notification idle_prompt main
check 'ignore' working claude Notification permission_prompt

# Live subagents: each appears with its own events and goes with SubagentStop.
sa() {
	local expected=$1 got
	shift
	got=$(agent_subagents "$@")
	[[ $got == "$expected" ]] || { printf 'FAIL: agent_subagents %s -> [%s], expected [%s]\n' "$*" "$got" "$expected" >&2; FAILS=$((FAILS + 1)); }
}
sa 'a1:working:100' '' claude SubagentStart '' a1 100
sa 'a1:working:100 a2:blocked:110' 'a1:working:100' claude PermissionRequest '' a2 110
sa 'a2:blocked:110 a1:blocked:120' 'a1:working:100 a2:blocked:110' claude PreToolUse AskUserQuestion a1 120
sa 'a2:working:130' 'a2:blocked:110' claude PostToolUse '' a2 130
sa 'a2:blocked:110' 'a1:working:100 a2:blocked:110' claude SubagentStop '' a1 120
sa 'a1:working:100' 'a1:working:100' claude Stop '' main 120
sa 'a1:working:100' 'a1:working:100' claude UserPromptSubmit '' main 120
sa '' 'a1:working:100' claude Interrupted '' main 120
sa '' 'a1:working:100' claude SessionStart '' main 120
sa 'a2:working:2000' 'a1:working:100' claude PostToolUse '' a2 2000
sa 'x' 'x' opencode permission.asked '' a1 100
got=$(agent_subagents_summary 'a1:working:1 a2:blocked:2 a3:done:3')
[[ $got == '3 blocked' ]] || { printf 'FAIL: summary [%s]\n' "$got" >&2; FAILS=$((FAILS + 1)); }
got=$(agent_subagents_summary '')
[[ $got == '0 ' ]] || { printf 'FAIL: empty summary [%s]\n' "$got" >&2; FAILS=$((FAILS + 1)); }

# An attached background session takes the state Claude Code reports for it.
check 'set working 0' '' claude Attached working
check 'set blocked 1' '' claude Attached blocked
check 'set done 1' '' claude Attached done
check 'set idle 0' '' claude Attached idle
check 'set error 1' '' claude Attached failed
check 'set error 1' '' claude Attached error
check 'set unknown 0' '' claude Attached whatever

# Claude Code reports no interrupt; the idle prompt changes nothing.
check 'ignore' working claude Notification idle_prompt
check 'set idle 0' working claude Interrupted
check 'set idle 0' blocked claude Interrupted

# OpenCode mapping.
for e in session.execution.started permission.replied form.replied form.cancelled; do
	check 'set working 0' idle opencode "$e"
done
check 'set blocked 1' working opencode permission.asked
check 'set blocked 1' working opencode form.created
check 'set done 1' working opencode session.execution.succeeded
check 'set error 1' working opencode session.execution.failed
check 'set idle 0' working opencode session.execution.interrupted
check 'set idle 0' blocked opencode session.execution.interrupted
check 'ignore' working opencode session.renamed
check 'ignore' working opencode session.text.delta
check 'set working 0' '' opencode tab.opened running
check 'set blocked 1' '' opencode tab.opened pending
check 'set idle 0' '' opencode tab.opened idle
check 'forget' working opencode tab.closed
check 'set blocked 1' working opencode tab.pending
check 'set blocked 1' idle opencode tab.pending
check 'set idle 0' done opencode tab.focused
check 'set working 0' working opencode tab.focused

# Completion depends on prior activity; an error survives it.
check 'set done 1' blocked claude Stop
check 'set idle 0' idle claude Stop
check 'set idle 0' idle opencode session.execution.succeeded
check 'set done 0' done claude Stop
check 'set error 0' error claude Stop
check 'set error 0' error opencode session.execution.succeeded
check 'set idle 0' '' claude Stop

# An error clears on the next activity.
check 'set working 0' error claude UserPromptSubmit
check 'set working 0' error opencode session.execution.started

# Viewing clears done only.
check 'set idle 0' done tmux viewed
check 'set blocked 0' blocked tmux viewed
check 'set error 0' error tmux viewed

# Notify only on a change into an attention state.
check 'set blocked 0' blocked claude PermissionRequest
check 'set error 1' done claude StopFailure

# Unknown or invalid previous states are treated as unknown.
check 'set working 0' bogus claude UserPromptSubmit
check 'set unknown 0' bogus tmux viewed
check 'ignore' working nobody Stop

# Ranking and rollups.
[[ $(agent_rollup working blocked idle) == blocked ]] || { echo 'FAIL: rollup blocked' >&2; FAILS=$((FAILS + 1)); }
[[ $(agent_rollup idle done working) == done ]] || { echo 'FAIL: rollup done' >&2; FAILS=$((FAILS + 1)); }
[[ $(agent_rollup bogus) == unknown ]] || { echo 'FAIL: rollup unknown' >&2; FAILS=$((FAILS + 1)); }
[[ $(agent_rollup) == '' ]] || { echo 'FAIL: empty rollup' >&2; FAILS=$((FAILS + 1)); }

((FAILS == 0)) || exit 1
printf 'agent state tests passed\n'
