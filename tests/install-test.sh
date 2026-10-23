#!/usr/bin/env bash
# OpenCode install/uninstall and tmux cleanup rollback tests.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/tmux-orchestrator"
. "$ROOT/tests/helpers.sh"
S="tmux-orchestrator-install-$$"
export TMUX_SOCKET=$S
HOME_TMP=$(mktemp -d)
CONFIG="$HOME_TMP/.config/opencode/opencode.json"
mkdir -p "$(dirname "$CONFIG")"
printf '{"theme":"keep-me"}\n' >"$CONFIG"
BEFORE=$(cat "$CONFIG")

cleanup() { tmux -L "$S" kill-server 2>/dev/null || true; rm -rf "$HOME_TMP"; }
trap cleanup EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }

# An earlier server plugin file is removed by the installer.
LEGACY="$HOME_TMP/.config/opencode/plugins/tmux-orchestrator.js"
mkdir -p "$(dirname "$LEGACY")"
printf 'old\n' >"$LEGACY"
"$BIN" install --home "$HOME_TMP" >/dev/null
PLUGIN="$HOME_TMP/.config/opencode/plugins/tmux-orchestrator/tui.js"
[[ -f $PLUGIN ]] || fail 'installed plugin missing'
[[ ! -e $LEGACY ]] || fail 'legacy server plugin not removed'
grep -Fq "\"$ROOT/bin/tmux-orchestrator\"" "$PLUGIN" || fail 'reporter path not substituted'
! grep -Fq '__REPORTER__' "$PLUGIN" || fail 'placeholder remains'
assert_eq "$(cat "$CONFIG")" "$BEFORE"

# The installed TUI plugin reaches the absolute reporter with a fake TUI.
tmux -L "$S" new-session -d -s installed -n main 'sleep 300'
P=$(tmux -L "$S" display -p -t installed:main.0 '#{pane_id}')
PLUGIN="$PLUGIN" TMUX_PANE="$P" TMUX_SOCKET="$S" TMUX_ORCHESTRATOR_SOCKET_DIR="$HOME_TMP/sockets" node --input-type=module -e '
const { pathToFileURL } = await import("node:url");
const { default: plugin } = await import(pathToFileURL(process.env.PLUGIN).href);
const api = {
  ui: {
    tabs: { enabled: () => true, list: () => [{ sessionID: "ses_i", title: "installed-agent", active: true }], focus: () => true },
    router: { current: () => ({ type: "home" }), navigate: () => {} },
  },
  data: {
    listen: () => () => {},
    session: { root: (id) => id, get: () => undefined, status: () => "running", permission: { list: () => [] }, form: { list: () => [] } },
  },
};
const dispose = plugin.setup(api);
await new Promise((resolve) => setTimeout(resolve, 600));
process.exit(0);
'
assert_eq "$(tmux -L "$S" show-options -pv -t "$P" @agent_1_state)" working
assert_eq "$(tmux -L "$S" show-options -pv -t "$P" @agent_1_name_raw)" installed-agent
assert_eq "$(tmux -L "$S" show-options -pv -t "$P" @agent_socket)" "$HOME_TMP/sockets/${P#%}.sock"

"$BIN" uninstall --home "$HOME_TMP" >/dev/null
[[ ! -e $PLUGIN ]] || fail 'plugin still installed'
[[ ! -e $(dirname "$PLUGIN") ]] || fail 'plugin directory left behind'
assert_eq "$(cat "$CONFIG")" "$BEFORE"

# Cleanup leaves other plugin hooks alone and removes only ours.
tmux -L "$S" new-session -d -s alpha -n main -x 100 -y 40 'sleep 300'
P=$(tmux -L "$S" display -p -t alpha:main.0 '#{pane_id}')
"$ROOT/tmux-orchestrator.tmux"
tmux -L "$S" set-hook -g 'after-select-pane[91]' 'display-message other-plugin'
report_state "$P" working agent claude s0
[[ $(tmux -L "$S" show-options -pv -t "$P" @agent_1_state) == working ]] || fail 'setup state'
"$BIN" cleanup
assert_eq "$(tmux -L "$S" show-options -pv -t "$P" @agent_1_state 2>/dev/null || true)" ''
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_count 2>/dev/null || true)" ''
tmux -L "$S" show-hooks -g | grep -Fq 'after-select-pane[90]' && fail 'our hook remains'
tmux -L "$S" show-hooks -g | grep -Fq 'after-select-pane[91]' || fail 'other hook removed'
tmux -L "$S" show-hooks -gw | grep -Fq 'pane-exited[90]' && fail 'pane hook remains'
tmux -L "$S" show-hooks -gw | grep -Fq 'pane-died[90]' && fail 'dead pane hook remains'
assert_eq "$(tmux -L "$S" show-options -gv side-status)" off

printf 'install and cleanup tests passed\n'
