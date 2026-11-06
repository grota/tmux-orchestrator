# Shared test helpers.  Sourced after BIN is set.

# Tests never reach the real desktop notifier: silent notify-send and osascript
# come first on PATH.  A test that checks notifications puts its own fake
# before them.
QUIET_BIN="${TMPDIR:-/tmp}/tmux-orchestrator-quiet-bin-$(id -u)"
if [[ ! -x $QUIET_BIN/notify-send ]]; then
	mkdir -p "$QUIET_BIN"
	printf '#!/bin/sh\nexit 0\n' >"$QUIET_BIN/notify-send"
	printf '#!/bin/sh\nexit 0\n' >"$QUIET_BIN/osascript"
	chmod +x "$QUIET_BIN/notify-send" "$QUIET_BIN/osascript"
fi
export PATH="$QUIET_BIN:$PATH"

# report_state PANE STATE NAME KIND SESSION_ID
# Reaches STATE through the agent events of KIND.  done is reached through
# working, because a completion only means done after work.
report_state() {
	local pane=$1 state=$2 name=$3 kind=$4 sid=$5 event
	case "$kind:$state" in
	claude:idle) event=SessionStart ;;
	claude:working) event=UserPromptSubmit ;;
	claude:blocked) event=PermissionRequest ;;
	claude:done) event=Stop ;;
	claude:error) event=StopFailure ;;
	opencode:idle) event=session.execution.interrupted ;;
	opencode:working) event=session.execution.started ;;
	opencode:blocked) event=permission.asked ;;
	opencode:done) event=session.execution.succeeded ;;
	opencode:error) event=session.execution.failed ;;
	*) printf 'report_state: unsupported %s:%s\n' "$kind" "$state" >&2; return 1 ;;
	esac
	if [[ $state == done ]]; then
		report_state "$pane" working "$name" "$kind" "$sid"
	fi
	"$BIN" report --pane "$pane" --kind "$kind" --event "$event" --name "$name" --session-id "$sid"
}

# opt PANE NAME prints a pane option, or nothing when it is unset.
opt() {
	tmux -L "$S" show-options -pv -t "$1" "$2" 2>/dev/null || true
}
