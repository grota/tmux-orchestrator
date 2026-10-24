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

PLUGINS="$HOME_TMP/.config/opencode/plugins"
DEST="$PLUGINS/tmux-orchestrator"
mkdir -p "$PLUGINS"

# The installer links the adapter and leaves other plugin files alone.
printf 'mine\n' >"$PLUGINS/tmux-orchestrator.js"
"$BIN" install opencode --home "$HOME_TMP" >/dev/null
[[ -L $DEST ]] || fail 'adapter is not a link'
assert_eq "$(readlink "$DEST")" "$ROOT/plugins/opencode"
assert_eq "$(cat "$PLUGINS/tmux-orchestrator.js")" mine
assert_eq "$(cat "$CONFIG")" "$BEFORE"
"$BIN" install --home "$HOME_TMP" >/dev/null
assert_eq "$(readlink "$DEST")" "$ROOT/plugins/opencode"

# Paths this project did not create are left alone.
rm "$DEST"
mkdir "$DEST"
printf 'someone else\n' >"$DEST/index.js"
"$BIN" install opencode --home "$HOME_TMP" 2>/dev/null
[[ -d $DEST && ! -L $DEST && -f $DEST/index.js ]] || fail 'foreign directory replaced'
"$BIN" uninstall opencode --home "$HOME_TMP" 2>/dev/null
[[ -f $DEST/index.js ]] || fail 'foreign directory removed'
rm -r "$DEST"
ln -s /somewhere/else "$DEST"
"$BIN" install opencode --home "$HOME_TMP" 2>/dev/null
assert_eq "$(readlink "$DEST")" /somewhere/else
rm "$DEST"

# The linked adapter reaches the reporter the tmux plugin publishes.
"$BIN" install opencode --home "$HOME_TMP" >/dev/null
tmux -L "$S" -f /dev/null new-session -d -s installed -n main 'sleep 300'
tmux -L "$S" set-option -g @tmux-orchestrator-reporter "$BIN"
P=$(tmux -L "$S" display -p -t installed:main.0 '#{pane_id}')
PLUGIN="$DEST/tui.js" TMUX_PANE="$P" TMUX_SOCKET="$S" TMUX_ORCHESTRATOR_SOCKET_DIR="$HOME_TMP/sockets" node --input-type=module -e '
const { pathToFileURL } = await import("node:url");
const { default: plugin } = await import(pathToFileURL(process.env.PLUGIN).href);
const api = {
  ui: {
    tabs: { enabled: () => true, list: () => [{ sessionID: "ses_i", title: "installed-agent", active: true, busy: true, attention: false }], focus: () => true },
    router: { current: () => ({ type: "home" }), navigate: () => {} },
  },
  data: {
    listen: () => () => {},
    session: { root: (id) => id, get: () => undefined, status: () => "running", permission: { list: () => [] }, form: { list: () => [] } },
  },
};
plugin.setup(api);
await new Promise((resolve) => setTimeout(resolve, 600));
process.exit(0);
'
assert_eq "$(tmux -L "$S" show-options -pv -t "$P" @agent_1_state)" working
assert_eq "$(tmux -L "$S" show-options -pv -t "$P" @agent_1_name_raw)" installed-agent

"$BIN" uninstall opencode --home "$HOME_TMP" >/dev/null
[[ ! -e $DEST && ! -L $DEST ]] || fail 'adapter link still installed'
assert_eq "$(cat "$CONFIG")" "$BEFORE"

# By default each plugin load links the adapter to the loaded copy, but only
# when OpenCode is detected.
COPY="$HOME_TMP/second-copy"
mkdir -p "$COPY"
cp -R "$ROOT/tmux-orchestrator.tmux" "$ROOT/bin" "$ROOT/lib" "$ROOT/plugins" "$COPY/"
NOPATH="$HOME_TMP/nopath"
STUBPATH="$HOME_TMP/stubpath"
mkdir -p "$NOPATH" "$STUBPATH"
for cmd in bash tmux dirname cat ln rm mkdir readlink; do
	ln -s "$(command -v "$cmd")" "$NOPATH/$cmd"
	ln -s "$(command -v "$cmd")" "$STUBPATH/$cmd"
done
printf '#!/bin/sh\n' >"$STUBPATH/opencode"
chmod +x "$STUBPATH/opencode"

# Detected through the config directory.
HOME=$HOME_TMP PATH=$NOPATH "$ROOT/tmux-orchestrator.tmux"
assert_eq "$(readlink "$DEST")" "$ROOT/plugins/opencode"
HOME=$HOME_TMP PATH=$NOPATH "$COPY/tmux-orchestrator.tmux"
assert_eq "$(readlink "$DEST")" "$COPY/plugins/opencode"
assert_eq "$(tmux -L "$S" show-options -gv @tmux-orchestrator-reporter)" "$COPY/bin/tmux-orchestrator"

# Off leaves an existing link as it is.
tmux -L "$S" set-option -g @tmux-orchestrator-opencode-auto-install off
HOME=$HOME_TMP PATH=$NOPATH "$ROOT/tmux-orchestrator.tmux"
assert_eq "$(readlink "$DEST")" "$COPY/plugins/opencode"
tmux -L "$S" set-option -gu @tmux-orchestrator-opencode-auto-install
"$BIN" uninstall opencode --home "$HOME_TMP" >/dev/null

# Detected through opencode on PATH, without a config directory.
BARE="$HOME_TMP/bare-home"
mkdir -p "$BARE"
HOME=$BARE PATH=$STUBPATH "$ROOT/tmux-orchestrator.tmux"
assert_eq "$(readlink "$BARE/.config/opencode/plugins/tmux-orchestrator")" "$ROOT/plugins/opencode"
rm -rf "$BARE"

# Not detected: nothing is created.
mkdir -p "$BARE"
HOME=$BARE PATH=$NOPATH "$ROOT/tmux-orchestrator.tmux"
[[ ! -e $BARE/.config ]] || fail 'OpenCode directory created without OpenCode'
rm -rf "$BARE"

# Cleanup leaves other plugin hooks alone and removes only ours.
tmux -L "$S" new-session -d -s alpha -n main -x 100 -y 40 'sleep 300'
P=$(tmux -L "$S" display -p -t alpha:main.0 '#{pane_id}')
HOME=$HOME_TMP "$ROOT/tmux-orchestrator.tmux"
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
