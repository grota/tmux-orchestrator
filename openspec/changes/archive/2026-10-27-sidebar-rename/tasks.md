# Tasks

## 1. Rename

- [x] 1.1 Bind `DoubleClick1Status`: a session row opens `command-prompt` with `rename-session -- "%%%"`; an agent row runs `rename-prompt` with the row and client
- [x] 1.2 Add `rename-prompt`: a non-blocking prompt (`-b -l`) prefilled with the escaped name, whose answer goes through `@tmux-orchestrator-rename-*` options to `rename`
- [x] 1.3 Add `rename`: Claude through the registry's messaging socket, confirmed by the registry; OpenCode through the adapter socket, confirmed by `ok`; failures shown with `display-message` and the name unchanged
- [x] 1.4 Answer `rename <sid> <title>` in the OpenCode adapter through `api.client.session.update`
- [x] 1.5 Leave the double-click binding out of the keys panel

## 2. Tests

- [x] 2.1 `tests/rename-test.sh`: fake Claude registry and socket (applied, ignored, missing), fake OpenCode adapter (ok, refused), and a real prompt typed with `send-keys -K`, including quotes, `$`, `~`, `#`, `,`, `;` and `\`
- [x] 2.2 `tests/opencode-plugin.test.js`: rename answered on the socket, success and refusal
- [x] 2.3 `tests/contract/claude-test.sh` and `tests/contract/opencode-test.sh` against the installed agents; verify both pass

## 3. Docs

- [x] 3.1 ADR-0009, README (Sidebar, OpenCode events, Development, Known limitations) and CHANGELOG
