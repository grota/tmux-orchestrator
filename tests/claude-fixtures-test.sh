#!/usr/bin/env bash
# Claude Code hook fixtures exercise the repository's hook entry point.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/tmux-orchestrator"
HOOK="$ROOT/plugins/claude/hooks/report.sh"
FIX="$ROOT/tests/fixtures/claude"
S="tmux-orchestrator-claude-$$"
export TMUX_SOCKET=$S
export CLAUDE_BIN=/bin/true

cleanup() { tmux -L "$S" kill-server 2>/dev/null || true; rm -rf "${FAKE_CLAUDE_DIR:-}"; }
trap cleanup EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }
state() { tmux -L "$S" show-options -pv -t "$P" @agent_state 2>/dev/null || true; }
raw() { tmux -L "$S" show-options -pv -t "$P" @agent_name_raw 2>/dev/null || true; }
count() { tmux -L "$S" show-options -v -t alpha @agent_count 2>/dev/null || true; }

tmux -L "$S" new-session -d -s alpha -n main -x 100 -y 40 'sleep 300'
P=$(tmux -L "$S" display -p -t alpha:main.0 '#{pane_id}')
export TMUX_PANE=$P

"$HOOK" <"$FIX/session-start-title.json"
assert_eq "$(state)" idle
assert_eq "$(raw)" fix-login
assert_eq "$(tmux -L "$S" show-options -pv -t "$P" @agent_kind)" claude
assert_eq "$(tmux -L "$S" show-options -pv -t "$P" @agent_session)" sid-start
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

"$HOOK" <"$FIX/stop-failure.json"
assert_eq "$(state)" error
"$HOOK" <"$FIX/stop.json"
assert_eq "$(state)" error
"$HOOK" <"$FIX/post-tool-failure.json"
assert_eq "$(state)" error

# A subagent Stop must not touch the pane's main-thread state.
"$HOOK" <"$FIX/subagent-stop.json"
assert_eq "$(state)" error
assert_eq "$(tmux -L "$S" show-options -pv -t "$P" @agent_session)" sid-start

# SessionEnd removes the agent and recomputes the session summary.
"$HOOK" <"$FIX/session-end.json"
assert_eq "$(count)" 0
assert_eq "$(tmux -L "$S" show-options -pv -t "$P" @agent_kind 2>/dev/null || true)" ''

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
