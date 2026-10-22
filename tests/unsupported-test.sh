#!/usr/bin/env bash
# Compatibility gate and missing-dependency degradation.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# A tmux without side-status must produce one warning and make no option calls.
cat >"$TMP/tmux" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_TMUX_LOG:?}"
case " $* " in
  *" show-options -g side-status "*) exit 1 ;;
  *) exit 0 ;;
esac
EOS
chmod +x "$TMP/tmux"
export FAKE_TMUX_LOG="$TMP/calls"
TMUX_BIN="$TMP/tmux" "$ROOT/tmux-orchestrator.tmux"
[[ $(grep -c 'tmux 3.9 or newer' "$FAKE_TMUX_LOG") == 1 ]] || fail 'expected one version warning'
! grep -q ' set-option ' "$FAKE_TMUX_LOG" || fail 'unsupported server was configured'

# Missing tmux must not block a Claude hook.
PATH_SAVE=$PATH
mkdir -p "$TMP/bin"
for cmd in bash dirname cat; do
	command -v "$cmd" >/dev/null 2>&1 && ln -s "$(command -v "$cmd")" "$TMP/bin/$cmd"
done
if PATH="$TMP/bin" TMUX_BIN=/nonexistent "$ROOT/plugins/claude/hooks/report.sh" \
	<"$ROOT/tests/fixtures/claude/session-start-title.json" >/dev/null 2>"$TMP/err"; then
	:
else
	fail 'hook failed when tmux is unavailable'
fi
[[ ! -s $TMP/err ]] || fail "hook wrote an error: $(cat "$TMP/err")"

# Missing jq and tmux also degrades silently.
if PATH="$TMP/bin" TMUX_BIN=/nonexistent "$ROOT/plugins/claude/hooks/report.sh" \
	<"$ROOT/tests/fixtures/claude/session-start-title.json" >/dev/null 2>"$TMP/err2"; then
	:
else
	fail 'hook failed when jq is unavailable'
fi
[[ ! -s $TMP/err2 ]] || fail "hook wrote an error without jq: $(cat "$TMP/err2")"

printf 'unsupported and missing-dependency tests passed\n'
