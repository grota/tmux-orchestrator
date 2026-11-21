#!/usr/bin/env bash
# Exercise the Codex hook entry point against a private tmux server.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/tmux-orchestrator"
. "$ROOT/tests/helpers.sh"
HOOK="$ROOT/plugins/codex/hooks/report.sh"
S="tmux-orchestrator-codex-$$"
export TMUX_SOCKET=$S
unset TMUX_ORCHESTRATOR_REPORTER
fixture_dir=$(mktemp -d)
export CODEX_HOME=$fixture_dir

trap 'tmux -L "$S" kill-server 2>/dev/null || true; rm -f "$fixture_dir"/{codex,event,ready,session_index.jsonl}; rmdir "$fixture_dir"' EXIT
tmux -L "$S" -f /dev/null new-session -d -s codex -x 100 -y 40 bash --noprofile --norc -i
P=$(tmux -L "$S" display-message -p '#{pane_id}')
export TMUX_PANE=$P
tmux -L "$S" set-option -g @tmux-orchestrator-reporter "$BIN"

# Run a command in a new session and wait for it.
if command -v setsid >/dev/null && setsid -w true 2>/dev/null; then
	DETACH='setsid -w'
else
	DETACH="python3 -c 'import os,sys
pid=os.fork()
if pid==0:
    os.setsid()
    os.execvp(sys.argv[1],sys.argv[1:])
sys.exit(os.waitpid(pid,0)[1]>>8)'"
fi

hook_payload() {
	jq -cn --arg event "$1" --arg id "${2:-first}" --arg tool "${3-}" --arg cwd "${4:-/work/project}" \
		'{hook_event_name: $event, session_id: $id, cwd: $cwd, tool_name: $tool}'
}

send_event() {
	if [[ -z ${TMUX_PANE:-} ]]; then
		hook_payload "$@" | "$HOOK"
		return
	fi
	# An inline hook is a child of the client in the pane.  Codex runs it in
	# its own session, without a controlling terminal.
	hook_payload "$@" >"$fixture_dir/event"
	: >"$fixture_dir/ready"
	tmux -L "$S" send-keys -t "$P" -l "$(printf '%s %q < %q; printf ready > %q' "$DETACH" "$HOOK" "$fixture_dir/event" "$fixture_dir/ready")"
	tmux -L "$S" send-keys -t "$P" Enter
	for _ in $(seq 1 40); do
		[[ -s $fixture_dir/ready ]] && return 0
		sleep 0.05
	done
	printf 'FAIL: inline hook did not finish\n' >&2
	return 1
}

assert_eq() {
	if [[ $1 != "$2" ]]; then
		printf 'FAIL: expected [%s], got [%s]\n' "$2" "$1" >&2
		exit 1
	fi
}

send_event SessionStart
assert_eq "$(opt "$P" @agent_1_state)" idle
assert_eq "$(opt "$P" @agent_1_kind)" codex
assert_eq "$(opt "$P" @agent_1_name_raw)" project
send_event UserPromptSubmit
assert_eq "$(opt "$P" @agent_1_state)" working
send_event PermissionRequest first Bash
assert_eq "$(opt "$P" @agent_1_state)" blocked
assert_eq "$(opt "$P" @agent_1_event)" codex:PermissionRequest:Bash
send_event PostToolUse first Bash
assert_eq "$(opt "$P" @agent_1_state)" working
send_event PreToolUse first request_user_input
assert_eq "$(opt "$P" @agent_1_state)" blocked
send_event PostToolUse first request_user_input
assert_eq "$(opt "$P" @agent_1_state)" working
send_event SubagentStop
assert_eq "$(opt "$P" @agent_1_state)" working
send_event Stop
assert_eq "$(opt "$P" @agent_1_state)" done
send_event UserPromptSubmit
send_event Interrupt
assert_eq "$(opt "$P" @agent_1_state)" idle

send_event SessionStart second '' '/another/working directory'
send_event SessionEnd first
send_event Stop first
send_event PostToolUse first Bash
assert_eq "$(opt "$P" @agent_1_sid)" second
assert_eq "$(opt "$P" @agent_1_state)" idle
assert_eq "$(opt "$P" @agent_1_name_raw)" 'working directory'
assert_eq "$(tmux -L "$S" show-options -v -t codex @agent_count)" 1

send_event SessionEnd second
send_event SessionEnd second
send_event Stop second
assert_eq "$(opt "$P" @agent_1_sid)" ''
assert_eq "$(tmux -L "$S" show-options -v -t codex @agent_count)" 0

assert_eq "$(printf 'invalid JSON\n' | "$HOOK")" ''
assert_eq "$(TMUX_PANE='' send_event UserPromptSubmit)" ''
assert_eq "$(opt "$P" @agent_1_sid)" ''

# Daemon hooks have no TMUX_PANE. Both clients can use the same cwd.
cp "$(command -v sleep)" "$fixture_dir/codex"
first=01a1f9f8-24b3-7bb1-8fcd-27bd33378e44
second=01a1f9f8-2520-7273-a959-1a1b8f9f5624
alpha=$(tmux -L "$S" new-window -dP -F '#{pane_id}' "$fixture_dir/codex" 300)
beta=$(tmux -L "$S" new-window -dP -F '#{pane_id}' "$fixture_dir/codex" 300)
tmux -L "$S" select-pane -t "$alpha" -T "${first:0:29}... ⠙ Running | project"
tmux -L "$S" select-pane -t "$beta" -T "$second"
unset TMUX_PANE

jq -cn --arg id "$first" '{id:$id,thread_name:"Alpha thread"}' >"$CODEX_HOME/session_index.jsonl"
send_event UserPromptSubmit "$first"
assert_eq "$(opt "$alpha" @agent_1_sid)" "$first"
assert_eq "$(opt "$alpha" @agent_1_state)" working
assert_eq "$(opt "$alpha" @agent_1_name_raw)" 'Alpha thread'
assert_eq "$(opt "$beta" @agent_1_sid)" ''
# An auto-started daemon may have inherited alpha's pane variables.
hook_payload UserPromptSubmit "$second" | TMUX_PANE="$alpha" "$HOOK"
assert_eq "$(opt "$beta" @agent_1_sid)" "$second"
assert_eq "$(opt "$beta" @agent_1_name_raw)" project
assert_eq "$(opt "$alpha" @agent_1_sid)" "$first"
send_event Stop "$first"
assert_eq "$(opt "$alpha" @agent_1_state)" done
assert_eq "$(opt "$beta" @agent_1_state)" working

# Codex puts "Action Required" before the title items while it asks.
tmux -L "$S" select-pane -t "$alpha" -T "[ ! ] Action Required | ${first:0:29}... | Alpha thread | project"
send_event PermissionRequest "$first" Bash
assert_eq "$(opt "$alpha" @agent_1_state)" blocked
tmux -L "$S" select-pane -t "$alpha" -T "${first:0:29}... | Alpha thread | project"
send_event PostToolUse "$first" Bash
send_event Stop "$first"
assert_eq "$(opt "$alpha" @agent_1_state)" done

jq -cn --arg id "$first" '{id:$id,thread_name:"Renamed alpha"}' >>"$CODEX_HOME/session_index.jsonl"
for _ in $(seq 1 30); do
	[[ $(opt "$alpha" @agent_1_name_raw) == 'Renamed alpha' ]] && break
	sleep 0.1
done
assert_eq "$(opt "$alpha" @agent_1_name_raw)" 'Renamed alpha'
assert_eq "$(opt "$alpha" @agent_1_state)" done
assert_eq "$(opt "$beta" @agent_1_name_raw)" project

tmux -L "$S" select-pane -t "$beta" -T "${first:0:29}... | project"
send_event UserPromptSubmit "$first"
assert_eq "$(opt "$alpha" @agent_1_state)" done
assert_eq "$(opt "$beta" @agent_1_sid)" "$second"
tmux -L "$S" select-pane -t "$beta" -T "project"
send_event SessionEnd "$second"
assert_eq "$(opt "$beta" @agent_1_sid)" ''

# A daemon can keep a thread loaded after its client exits to the shell.
shell_pane=$(tmux -L "$S" new-window -dP -F '#{pane_id}' bash --noprofile --norc -i)
tmux -L "$S" send-keys -t "$shell_pane" -l "$(printf '%q ' "$fixture_dir/codex" 300)"
tmux -L "$S" send-keys -t "$shell_pane" Enter
for _ in $(seq 1 30); do
	[[ $(tmux -L "$S" display-message -p -t "$shell_pane" '#{pane_current_command}') == codex ]] && break
	sleep 0.05
done
tmux -L "$S" select-pane -t "$alpha" -T project
tmux -L "$S" select-pane -t "$shell_pane" -T "$first"
send_event UserPromptSubmit "$first"
assert_eq "$(opt "$shell_pane" @agent_1_sid)" "$first"
tmux -L "$S" send-keys -t "$shell_pane" C-c
for _ in $(seq 1 30); do
	[[ -z $(opt "$shell_pane" @agent_1_sid) ]] && break
	sleep 0.1
done
assert_eq "$(opt "$shell_pane" @agent_1_sid)" ''

# A daemon started by a client can run its hooks below that client's pane.
# The title still names the pane.
tmux -L "$S" select-pane -t "$beta" -T "$second"
TMUX_PANE=$P send_event UserPromptSubmit "$second"
assert_eq "$(opt "$beta" @agent_1_sid)" "$second"
assert_eq "$(opt "$P" @agent_1_sid)" ''

# Ending and restarting a thread within a second leaves one watcher.
report_codex() {
	"$BIN" report --protocol 1 --pane "$alpha" --kind codex --event "$1" --session-id "$2" --cwd /work/project
}
for id in one two three; do
	report_codex SessionStart "$id"
	report_codex SessionEnd "$id"
done
report_codex SessionStart four
sleep 2.5
assert_eq "$(pgrep -fc "watch-codex $alpha ")" 1

printf 'Codex hook tests passed\n'
