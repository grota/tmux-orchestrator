#!/usr/bin/env bash
# Raise the niri window of the terminal that runs the tmux client a
# notification click or the attention key brought to an agent.  Use it as
# @tmux-orchestrator-raise-command.
#
# The window is the one whose process is an ancestor of the client.  When that
# process owns several windows (Ghostty, kitty and foot servers do), the
# client's terminal gets a unique title for a moment so its window can be
# found, and then gets its old title back.
set -u
cpid=${TMUX_ORCHESTRATOR_CLIENT_PID:-}
tty=${TMUX_ORCHESTRATOR_CLIENT_TTY:-}
[[ -n $cpid ]] || exit 0
command -v niri >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || exit 0

windows=$(niri msg --json windows) || exit 0
pid=$cpid ids=''
while [[ $pid =~ ^[0-9]+$ ]] && ((pid > 1)); do
	ids=$(jq -r --argjson p "$pid" '[.[] | select(.pid == $p) | .id] | join(" ")' <<<"$windows")
	[[ -n $ids ]] && break
	pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
done
[[ -n $ids ]] || exit 0
read -r -a ids <<<"$ids"
id=${ids[0]}

if ((${#ids[@]} > 1)) && [[ -w $tty ]]; then
	mark="tmux-orchestrator-$$-$RANDOM"
	printf '\033]2;%s\007' "$mark" >"$tty"
	found=''
	for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
		sleep 0.05
		found=$(niri msg --json windows | jq -r --arg m "$mark" 'first(.[] | select(.title == $m) | .id) // empty')
		[[ -n $found ]] && break
	done
	if [[ -n $found ]]; then
		id=$found
		title=$(jq -r --argjson i "$id" 'first(.[] | select(.id == $i) | .title) // ""' <<<"$windows")
	else
		title=''
	fi
	printf '\033]2;%s\007' "$title" >"$tty"
fi

niri msg action focus-window --id "$id" >/dev/null
