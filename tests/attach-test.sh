#!/usr/bin/env bash
# Claude Code background sessions shown in a pane with `claude attach`.  Fake
# `ps` and `claude` binaries stand in for the process table and the session
# list; tmux is real, on a throwaway socket.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/tmux-orchestrator"
S="tmux-orchestrator-attach-$$"
export TMUX_SOCKET=$S
FAKE=$(mktemp -d)
export FAKE_PS="$FAKE/ps.txt" FAKE_AGENTS="$FAKE/agents.json" NOTIFY_LOG="$FAKE/notify.log"

cleanup() {
	kill "${CLIENT_PID:-}" 2>/dev/null || true
	tmux -L "$S" kill-server 2>/dev/null || true
	rm -rf "$FAKE"
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }

cat >"$FAKE/ps" <<'EOS'
#!/bin/sh
cat "$FAKE_PS"
EOS
cat >"$FAKE/claude" <<'EOS'
#!/bin/sh
cat "$FAKE_AGENTS"
EOS
cat >"$FAKE/notify-send" <<'EOS'
#!/bin/sh
printf '%s\n' "$*" >>"$NOTIFY_LOG"
EOS
# The panes run a process named claude, as a real viewer does.
mkdir -p "$FAKE/viewer"
ln -s "$(command -v sleep)" "$FAKE/viewer/claude"
chmod +x "$FAKE/ps" "$FAKE/claude" "$FAKE/notify-send"
export PATH="$FAKE:$PATH"
: >"$NOTIFY_LOG"

SID=f7ca13fb-cca9-405d-9476-1e13f8c6c841
OTHER=9bed2b17-0000-4000-8000-000000000000
cat >"$FAKE_AGENTS" <<EOF
[
  {"id": "f7ca13fb", "kind": "background", "sessionId": "$SID", "name": "Agent title wrap settings", "state": "blocked"},
  {"id": "9bed2b17", "kind": "background", "sessionId": "$OTHER", "name": "Agent docs pass", "state": "working"},
  {"id": null, "kind": "interactive", "sessionId": "cafe0000-0000-4000-8000-000000000000", "name": "local", "state": null}
]
EOF

tmux -L "$S" new-session -d -s alpha -n main -x 120 -y 40 "$FAKE/viewer/claude 300"
tmux -L "$S" set-option -g @tmux-orchestrator-opencode-auto-install off
tmux -L "$S" split-window -t alpha:main -d "$FAKE/viewer/claude 300"
"$ROOT/tmux-orchestrator.tmux"
P0=$(tmux -L "$S" display -p -t alpha:main.0 '#{pane_id}')
P1=$(tmux -L "$S" display -p -t alpha:main.1 '#{pane_id}')
PID0=$(tmux -L "$S" display -p -t "$P0" '#{pane_pid}')
PID1=$(tmux -L "$S" display -p -t "$P1" '#{pane_pid}')
opt() { tmux -L "$S" show-options -pv -t "$1" "$2" 2>/dev/null || true; }
# Write the fake process table: "pid ppid stat args" per line.
procs() { printf '%s\n' "$@" >"$FAKE_PS"; }
# A background hook, as the Claude adapter forwards it without TMUX_PANE.
hook() {
	env -u TMUX_PANE TMUX_ORCHESTRATOR_REPORTER="$BIN" bash "$ROOT/plugins/claude/hooks/report.sh" <<<"$1"
}

# The viewer is found after options, and the event reaches its pane only.
procs "900 $PID0 Sl+ claude --settings {\"a\":1} attach f7ca13fb" "901 $PID1 S sleep 300"
hook "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SID\",\"cwd\":\"/tmp\",\"session_title\":\"bg agent\"}"
assert_eq "$(opt "$P0" @agent_1_state)" working
assert_eq "$(opt "$P0" @agent_1_sid)" "$SID"
assert_eq "$(opt "$P0" @agent_attached)" "$SID"
assert_eq "$(opt "$P1" @agent_n)" ''

# A subagent waiting for the user blocks the attached agent: Claude Code sends
# its hooks with the main session's ID.
hook "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"$SID\",\"agent_id\":\"sub-1\",\"cwd\":\"/tmp\"}"
assert_eq "$(opt "$P0" @agent_1_state)" blocked
assert_eq "$(opt "$P0" @agent_1_sid)" "$SID"
hook "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"$SID\",\"agent_id\":\"sub-1\",\"cwd\":\"/tmp\"}"
assert_eq "$(opt "$P0" @agent_1_state)" working
: >"$NOTIFY_LOG"

# A hook without a session id, or from a session nobody shows, changes nothing.
hook '{"hook_event_name":"Stop","cwd":"/tmp"}'
hook "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"$OTHER\",\"cwd\":\"/tmp\"}"
assert_eq "$(opt "$P1" @agent_n)" ''
assert_eq "$(opt "$P0" @agent_1_sid)" "$SID"
assert_eq "$(wc -l <"$NOTIFY_LOG" | tr -d ' ')" 0

# Part of the name resolves; an ambiguous part resolves to nothing.
procs "900 $PID0 Sl+ claude attach title WRAP"
hook "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SID\",\"cwd\":\"/tmp\"}"
assert_eq "$(opt "$P0" @agent_1_state)" done
procs "900 $PID0 Sl+ claude attach agent"
hook "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SID\",\"cwd\":\"/tmp\"}"
assert_eq "$(opt "$P0" @agent_n)" ''

# A suspended viewer does not show its session: the next hook drops it and
# sends no notification.
procs "900 $PID0 Sl+ claude attach f7ca13fb"
hook "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SID\",\"cwd\":\"/tmp\"}"
assert_eq "$(opt "$P0" @agent_1_state)" working
procs "900 $PID0 T claude attach f7ca13fb"
: >"$NOTIFY_LOG"
hook "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"$SID\",\"cwd\":\"/tmp\"}"
assert_eq "$(opt "$P0" @agent_n)" ''
assert_eq "$(wc -l <"$NOTIFY_LOG" | tr -d ' ')" 0

# Selecting a pane that just attached adds the session with Claude's state.
# Discovery checks the panes clients view, so attach one.
(env -u TMUX TERM=xterm-256color timeout 6 script -qefc "stty rows 40 cols 120; tmux -L $S attach -t alpha" /dev/null >/dev/null 2>&1) &
CLIENT_PID=$!
sleep 0.8
procs "900 $PID1 Sl+ /home/u/.local/bin/claude attach f7ca13fb"
tmux -L "$S" select-pane -t "$P1"
"$BIN" focus
assert_eq "$(opt "$P1" @agent_1_state)" blocked
assert_eq "$(opt "$P1" @agent_1_name_raw)" 'Agent title wrap settings'
assert_eq "$(opt "$P1" @agent_attached)" "$SID"

# Going back to the agent view removes it on the next selection.
procs "900 $PID1 Sl+ claude agents"
"$BIN" focus
assert_eq "$(opt "$P1" @agent_n)" ''
assert_eq "$(opt "$P1" @agent_attached)" ''

# An ordinary Claude agent is never removed by the attach check, and an
# ordinary event clears a stale attached marker.
"$BIN" report --pane "$P0" --kind claude --event UserPromptSubmit --name local --session-id cafe
"$BIN" focus
assert_eq "$(opt "$P0" @agent_1_state)" working
tmux -L "$S" set-option -p -t "$P0" @agent_attached stale
"$BIN" report --pane "$P0" --kind claude --event Stop --session-id cafe
assert_eq "$(opt "$P0" @agent_attached)" ''
assert_eq "$(opt "$P0" @agent_1_state)" done

printf 'attach tests passed\n'
