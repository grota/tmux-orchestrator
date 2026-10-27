#!/usr/bin/env bash
# Claude Code hook fixtures exercise the repository's hook entry point.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/tmux-orchestrator"
HOOK=${HOOK:-$ROOT/plugins/claude/hooks/report.sh}
unset TMUX_ORCHESTRATOR_REPORTER
FIX="$ROOT/tests/fixtures/claude"
S="tmux-orchestrator-claude-$$"
export TMUX_SOCKET=$S
export CLAUDE_BIN=/bin/true

cleanup() { tmux -L "$S" kill-server 2>/dev/null || true; rm -rf "${FAKE_CLAUDE_DIR:-}"; }
trap cleanup EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }
state() { tmux -L "$S" show-options -pv -t "$P" @agent_1_state 2>/dev/null || true; }
raw() { tmux -L "$S" show-options -pv -t "$P" @agent_1_name_raw 2>/dev/null || true; }
count() { tmux -L "$S" show-options -v -t alpha @agent_count 2>/dev/null || true; }

tmux -L "$S" -f /dev/null new-session -d -s alpha -n main -x 100 -y 40 'sleep 300'
P=$(tmux -L "$S" display -p -t alpha:main.0 '#{pane_id}')
export TMUX_PANE=$P

# With no published reporter and none on PATH, the hook exits quietly.
PATH=/usr/bin:/bin "$HOOK" <"$FIX/session-start-title.json" || fail 'hook failed without a reporter'
assert_eq "$(state)" ''

# The hook finds the reporter through the option the tmux plugin publishes.
tmux -L "$S" set-option -g @tmux-orchestrator-reporter "$BIN"

"$HOOK" <"$FIX/session-start-title.json"
assert_eq "$(state)" idle
assert_eq "$(raw)" fix-login
assert_eq "$(tmux -L "$S" show-options -pv -t "$P" @agent_1_kind)" claude
assert_eq "$(tmux -L "$S" show-options -pv -t "$P" @agent_1_sid)" sid-start
assert_eq "$(count)" 1

"$HOOK" <"$FIX/prompt-title.json"
assert_eq "$(state)" working
assert_eq "$(raw)" fix-login-v2

"$HOOK" <"$FIX/pre-tool.json"
assert_eq "$(state)" working
"$HOOK" <"$FIX/post-tool.json"
assert_eq "$(state)" working
"$HOOK" <"$FIX/permission.json"
assert_eq "$(state)" blocked
"$HOOK" <"$FIX/stop.json"
assert_eq "$(state)" done

# Tools that wait for the user block; MCP input forms block until answered.
"$HOOK" <"$FIX/prompt-title.json"
"$HOOK" <"$FIX/ask-user.json"
assert_eq "$(state)" blocked
"$HOOK" <"$FIX/post-tool.json"
assert_eq "$(state)" working
"$HOOK" <"$FIX/exit-plan.json"
assert_eq "$(state)" blocked
"$HOOK" <"$FIX/post-tool.json"
"$HOOK" <"$FIX/elicitation.json"
assert_eq "$(state)" blocked
"$HOOK" <"$FIX/elicitation-result.json"
assert_eq "$(state)" working

# A subagent's permission request blocks the main agent without taking its ID.
"$HOOK" <"$FIX/subagent-permission.json"
assert_eq "$(state)" blocked
assert_eq "$(tmux -L "$S" show-options -pv -t "$P" @agent_1_sid)" sid-start

# Other subagents' tool calls do not hide the wait; the waiting one's own
# tool call or end does.
"$HOOK" <"$FIX/subagent-other-tool.json"
assert_eq "$(state)" blocked
"$HOOK" <"$FIX/subagent-post-tool.json"
assert_eq "$(state)" working
"$HOOK" <"$FIX/subagent-permission.json"
"$HOOK" <"$FIX/subagent-other-tool.json"
"$HOOK" <"$FIX/subagent-stop-hook.json"
assert_eq "$(state)" working
assert_eq "$(tmux -L "$S" show-options -pv -t "$P" @agent_1_waiters 2>/dev/null || true)" ''

# An approved tool that fails ends that subagent's wait too.
"$HOOK" <"$FIX/subagent-permission.json"
"$HOOK" <"$FIX/subagent-tool-failure.json"
"$HOOK" <"$FIX/subagent-other-tool.json"
assert_eq "$(state)" working

# A prompt starts interrupt detection on the session's status.
REG_DIR=$(mktemp -d)
mkdir -p "$REG_DIR/sessions"
printf '{"pid":1,"sessionId":"sid-start","status":"busy"}\n' >"$REG_DIR/sessions/1.json"
printf '{"hook_event_name":"UserPromptSubmit","session_id":"sid-start","cwd":"/tmp/project","session_title":"fix-login-v2"}\n' |
	CLAUDE_CONFIG_DIR="$REG_DIR" TMUX_ORCHESTRATOR_WATCH_TICK=0.2 "$HOOK"
assert_eq "$(state)" working
printf '{"pid":1,"sessionId":"sid-start","status":"idle"}\n' >"$REG_DIR/sessions/1.json"
for _ in $(seq 1 30); do [[ $(state) == idle ]] && break; sleep 0.1; done
assert_eq "$(state)" idle
assert_eq "$(tmux -L "$S" show-options -pv -t "$P" @agent_1_event)" claude:Interrupted
rm -rf "$REG_DIR"

"$HOOK" <"$FIX/prompt-title.json"
"$HOOK" <"$FIX/stop-failure.json"
assert_eq "$(state)" error
assert_eq "$(tmux -L "$S" show-options -pv -t "$P" @agent_1_event)" claude:StopFailure:rate_limit
"$HOOK" <"$FIX/stop.json"
assert_eq "$(state)" error
"$HOOK" <"$FIX/post-tool-failure.json"
assert_eq "$(state)" error

# A subagent Stop must not touch the pane's main-thread state.
"$HOOK" <"$FIX/subagent-stop.json"
assert_eq "$(state)" error
assert_eq "$(tmux -L "$S" show-options -pv -t "$P" @agent_1_sid)" sid-start

# SessionEnd removes the agent and recomputes the session summary.
"$HOOK" <"$FIX/session-end.json"
assert_eq "$(count)" 0
assert_eq "$(tmux -L "$S" show-options -pv -t "$P" @agent_1_kind 2>/dev/null || true)" ''

# Missing session_title falls back to the working-directory basename.
"$HOOK" <"$FIX/session-start-fallback.json"
assert_eq "$(state)" idle
assert_eq "$(raw)" fallback-project

# Synchronous name refresh accepts the documented claude --json array shape.
FAKE_CLAUDE_DIR=$(mktemp -d)
cat >"$FAKE_CLAUDE_DIR/claude" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' '[{"sessionId":"sid-fallback","name":"from-json"}]'
EOS
chmod +x "$FAKE_CLAUDE_DIR/claude"
export CLAUDE_BIN="$FAKE_CLAUDE_DIR/claude"

# SessionStart triggers a non-blocking refresh through tmux run-shell -b.
"$HOOK" <"$FIX/session-start-fallback.json"
sleep 0.8
assert_eq "$(raw)" from-json

"$BIN" refresh-name --pane "$P" --session-id sid-fallback --claude-bin "$FAKE_CLAUDE_DIR/claude"
assert_eq "$(raw)" from-json

printf 'claude fixture tests passed\n'
