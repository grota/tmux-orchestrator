#!/usr/bin/env bash
# A Codex pane is tracked from launch, before its first prompt (SPEC.md D23).
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/tmux-orchestrator"
. "$ROOT/tests/helpers.sh"
HOOK="$ROOT/plugins/codex/hooks/report.sh"
S="tmux-orchestrator-codex-launch-$$"
export TMUX_SOCKET=$S
unset TMUX_ORCHESTRATOR_REPORTER TMUX_PANE
TMP=$(mktemp -d)
export CODEX_HOME=$TMP/home
mkdir -p "$CODEX_HOME" "$TMP/bin" "$TMP/work/launched"
trap 'tmux -L "$S" kill-server 2>/dev/null || true; rm -rf "$TMP"' EXIT

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

# A program named codex that sets the terminal title, as the Codex client does
# at launch, then waits.  Each line read redraws the title.  tmux names a
# script after its interpreter, so the interpreter is a copy of bash named codex.
cp "$(command -v bash)" "$TMP/bin/codex"
cat >"$TMP/client.sh" <<'EOF'
printf '\033]2;%s\033\\' "${PWD##*/}"
while read -r line; do
	printf '\033]2;%s %s\033\\' "$line" "${PWD##*/}"
done
EOF

tmux -L "$S" -f /dev/null new-session -d -s main -x 120 -y 40 -c "$TMP/work" bash --noprofile --norc -i
tmux -L "$S" set-option -g @tmux-orchestrator-opencode-auto-install off
# The early codex runs in a shell, so the pane outlives it.
EARLY=$(tmux -L "$S" new-window -d -P -F '#{pane_id}' -c "$TMP/work/launched" bash --noprofile --norc -i)
tmux -L "$S" send-keys -t "$EARLY" "$(printf '%q ' "$TMP/bin/codex" --noprofile --norc "$TMP/client.sh")" Enter
sleep 0.3
TMUX_SOCKET=$S TMUX_BIN=tmux bash "$ROOT/tmux-orchestrator.tmux"

wait_opt() {
	local pane=$1 name=$2 want=$3
	for _ in $(seq 1 50); do
		[[ $(opt "$pane" "$name") == "$want" ]] && return 0
		sleep 0.1
	done
	fail "$name of $pane is [$(opt "$pane" "$name")], expected [$want]"
}

# The plugin load registers a codex that was already running.
wait_opt "$EARLY" @agent_1_kind codex
wait_opt "$EARLY" @agent_1_state idle
[[ $(opt "$EARLY" @agent_1_name_raw) == launched ]] || fail 'early codex name'

# A new codex is tracked when it sets its title, without any hook.
P=$(tmux -L "$S" new-window -d -P -F '#{pane_id}' -c "$TMP/work" "$TMP/bin/codex" --noprofile --norc "$TMP/client.sh")
wait_opt "$P" @agent_n 1
[[ $(opt "$P" @agent_1_kind) == codex ]] || fail 'launch kind'
[[ $(opt "$P" @agent_1_state) == idle ]] || fail 'launch state'
[[ -z $(opt "$P" @agent_1_sid) ]] || fail 'launch has a thread ID'
[[ $(opt "$P" @agent_1_name_raw) == work ]] || fail 'launch name'
[[ $(opt "$P" @agent_1_event) == codex:Launch ]] || fail 'launch event'
since=$(opt "$P" @agent_1_since)

# Title updates of a tracked codex change nothing.
sleep 1.1
tmux -L "$S" send-keys -t "$P" 'spin' Enter
sleep 0.5
[[ $(opt "$P" @agent_n) == 1 && $(opt "$P" @agent_1_since) == "$since" ]] || fail 'title update changed the row'

# A title from another program registers nothing.
SHELL_PANE=$(tmux -L "$S" display-message -p -t main '#{pane_id}')
tmux -L "$S" send-keys -t "$SHELL_PANE" "printf '\\033]2;other\\033\\\\'" Enter
sleep 0.5
[[ -z $(opt "$SHELL_PANE" @agent_n) ]] || fail 'a shell title registered an agent'

# The first prompt's hooks take the row over.
event() {
	jq -cn --arg event "$1" --arg id "$2" --arg cwd "$TMP/work" \
		'{hook_event_name: $event, session_id: $id, cwd: $cwd, tool_name: ""}' |
		TMUX_PANE=$3 "$HOOK"
}
SID=01a209a6-df71-7f52-baa4-de26d0000001
tmux -L "$S" send-keys -t "$P" "$SID" Enter
sleep 0.3
event SessionStart "$SID" "$P"
event UserPromptSubmit "$SID" "$P"
[[ $(opt "$P" @agent_n) == 1 ]] || fail 'thread added a second row'
[[ $(opt "$P" @agent_1_sid) == "$SID" ]] || fail 'thread did not take the row over'
[[ $(opt "$P" @agent_1_state) == working ]] || fail 'prompt state'

# Exiting codex removes the row and leaves the pane at its shell.
tmux -L "$S" send-keys -t "$EARLY" C-d
wait_opt "$EARLY" @agent_n ''
[[ $(tmux -L "$S" display -p -t "$EARLY" '#{pane_current_command}') == bash ]] || fail 'the early pane did not survive'

# Unloading the plugin removes the hook.
"$BIN" cleanup >/dev/null 2>&1 || true
if tmux -L "$S" show-hooks -gw | grep -Fq 'pane-title-changed[90]'; then
	fail 'pane-title-changed hook remains after cleanup'
fi

printf 'codex launch test: ok\n'
