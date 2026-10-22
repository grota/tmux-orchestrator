#!/usr/bin/env bash
# OpenCode install/uninstall and tmux cleanup rollback tests.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/tmux-orchestrator"
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

"$BIN" install --home "$HOME_TMP" >/dev/null
PLUGIN="$HOME_TMP/.config/opencode/plugins/tmux-orchestrator.js"
[[ -f $PLUGIN ]] || fail 'installed plugin missing'
grep -Fq "\"$ROOT/bin/tmux-orchestrator\"" "$PLUGIN" || fail 'reporter path not substituted'
! grep -Fq '__REPORTER__' "$PLUGIN" || fail 'placeholder remains'
assert_eq "$(cat "$CONFIG")" "$BEFORE"

# The installed plugin resolves the absolute reporter and loads in OpenCode v2.
tmux -L "$S" new-session -d -s installed -n main 'sleep 300'
P=$(tmux -L "$S" display -p -t installed:main.0 '#{pane_id}')
PLUGIN="$PLUGIN" TMUX_PANE="$P" TMUX_SOCKET="$S" node --input-type=module -e '
const { pathToFileURL } = await import("node:url");
const { default: plugin } = await import(pathToFileURL(process.env.PLUGIN).href);
const events = [{ type: "session.created", properties: { info: { id: "s", title: "installed-agent" } } }];
const setup = await plugin.setup({ event: { async *subscribe() { for (const event of events) yield event; } } });
await new Promise((resolve) => setTimeout(resolve, 250));
setup();
'
assert_eq "$(tmux -L "$S" show-options -pv -t "$P" @agent_state)" idle
assert_eq "$(tmux -L "$S" show-options -pv -t "$P" @agent_name_raw)" installed-agent

"$BIN" uninstall --home "$HOME_TMP" >/dev/null
[[ ! -e $PLUGIN ]] || fail 'plugin still installed'
assert_eq "$(cat "$CONFIG")" "$BEFORE"

# Cleanup leaves other plugin hooks alone and removes only ours.
tmux -L "$S" new-session -d -s alpha -n main -x 100 -y 40 'sleep 300'
P=$(tmux -L "$S" display -p -t alpha:main.0 '#{pane_id}')
"$ROOT/tmux-orchestrator.tmux"
tmux -L "$S" set-hook -g 'after-select-pane[91]' 'display-message other-plugin'
"$BIN" report --pane "$P" --state working --name agent --kind claude --session-id s0
[[ $(tmux -L "$S" show-options -pv -t "$P" @agent_state) == working ]] || fail 'setup state'
"$BIN" cleanup
assert_eq "$(tmux -L "$S" show-options -pv -t "$P" @agent_state 2>/dev/null || true)" ''
assert_eq "$(tmux -L "$S" show-options -v -t alpha @agent_count 2>/dev/null || true)" ''
tmux -L "$S" show-hooks -g | grep -Fq 'after-select-pane[90]' && fail 'our hook remains'
tmux -L "$S" show-hooks -g | grep -Fq 'after-select-pane[91]' || fail 'other hook removed'
tmux -L "$S" show-hooks -gw | grep -Fq 'pane-exited[90]' && fail 'pane hook remains'
tmux -L "$S" show-hooks -gw | grep -Fq 'pane-died[90]' && fail 'dead pane hook remains'
assert_eq "$(tmux -L "$S" show-options -gv side-status)" off

printf 'install and cleanup tests passed\n'
