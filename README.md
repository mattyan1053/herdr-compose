# herdr-compose

English | [日本語](README_ja.md)

[![CI](https://github.com/mattyan1053/herdr-compose/actions/workflows/ci.yml/badge.svg)](https://github.com/mattyan1053/herdr-compose/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/mattyan1053/herdr-compose?sort=semver)](https://github.com/mattyan1053/herdr-compose/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![herdr ≥ 0.7.4](https://img.shields.io/badge/herdr-%E2%89%A5%200.7.4-6f42c1.svg)](https://herdr.dev)

Docker Compose status and controls for each [herdr](https://herdr.dev) space.

- Shows the compose project state of every space in the sidebar
  (`⏵ 10/10` all running · `⏵ 8/10` partial · `⏸ 0/10` stopped ·
  `⏹ down` no containers · nothing at all when the workspace has no compose
  project). While an action runs the token shows the operation in progress
  (`⏳ up…` / `⏳ stop…`), which matters when `up` sits in an image pull.
- One keypress per space to `toggle` (stop if running, else start / `up -d`),
  plus explicit `up` / `start` / `stop` / `down` actions.
- An interactive `ps` **popup** (`compose.ps`): a live `docker compose ps` of the
  focused space's project, where you pick services and view logs, restart, start,
  stop, `up -d`, or remove them — a small in-space lazydocker scoped to one
  project. See [Interactive popup](#interactive-popup).
- Tears the stack down automatically when a worktree checkout is removed
  (`docker compose -p <project> down`, so it works even though the directory
  is already gone when `worktree.removed` fires).

Everything is derived from the workspace's cwd and Docker's compose labels —
no configuration is required in your repositories, which makes it friendly to
team monorepos you can't (or don't want to) modify.

## Why

Running several AI coding agents in parallel worktrees is easy; running ten
containers *per worktree* is not — ports collide and memory runs out. The
pragmatic answer is to keep implementation parallel but make the running dev
stack exclusive-ish: `stop` frees memory while keeping containers, volumes and
migration state intact, so switching the "live" stack between spaces takes
seconds. This plugin puts that workflow on a keybinding and makes the current
state visible per space.

## Requirements

- herdr ≥ 0.7.4 (the `ps` popup uses `plugin pane open --placement popup`)
- Docker Compose v2
- `bash`, `jq`
- `fzf` — for the interactive `ps` popup only (the status token and the other
  actions work without it)

## Install

```bash
herdr plugin install mattyan1053/herdr-compose
```

or for local development:

```bash
herdr plugin link /path/to/herdr-compose
```

## Configuration

Add the status token to your sidebar rows and bind the actions you want in
`~/.config/herdr/config.toml`:

```toml
[ui.sidebar.spaces]
rows = [
  ["state_icon", "workspace"],
  ["branch", "git_status", "$compose"],
]

[[keys.command]]
key = "prefix+alt+d"
type = "plugin_action"
command = "compose.toggle"

[[keys.command]]
key = "prefix+alt+shift+d"
type = "plugin_action"
command = "compose.down"

[[keys.command]]
key = "prefix+alt+p"
type = "plugin_action"
command = "compose.ps"
```

Actions without a keybinding can be invoked from a shell instead:
`herdr plugin action invoke compose.<action>` runs against the currently
focused workspace. The CLI prints an invocation receipt as JSON and the
action runs asynchronously — the outcome shows up in the sidebar token and
in `herdr plugin log list --plugin compose`.

## Actions

| Action            | Effect                                              |
| ----------------- | --------------------------------------------------- |
| `compose.ps`      | open the interactive `ps` popup (see below)          |
| `compose.toggle`  | running → `stop` · stopped → `start` · none → `up -d` |
| `compose.up`      | `docker compose up -d`                              |
| `compose.start`   | `docker compose start`                              |
| `compose.stop`    | `docker compose stop` (frees memory, keeps state)   |
| `compose.down`    | `docker compose down`                               |
| `compose.refresh` | re-report the sidebar status                        |
| `compose.gc`      | tear down orphaned projects (see below)             |

## Interactive popup

`compose.ps` opens a session-modal popup (via herdr's `plugin pane open
--placement popup`) showing a live `docker compose ps -a` of the focused space's
project. The popup runs in the workspace directory, so it always targets that
space's compose project — no configuration needed.

The keys are modifier-free single letters — the most portable choice across
terminals (macOS Option/Alt and many phone or SSH terminals mangle Meta keys;
bare and Shifted letters are bytes every terminal sends). The convention is
**lowercase = the selection, UPPERCASE = the whole project**:

| Key             | Scope    | Action                                          |
| --------------- | -------- | ----------------------------------------------- |
| `Enter` / `l`   | service  | view logs in a pager (`less`)                   |
| `f`             | service  | follow logs (`logs -f`; `Ctrl-C` returns)       |
| `r`             | service  | `restart`                                       |
| `s`             | service  | `start`                                         |
| `t`             | service  | s`t`op                                          |
| `u`             | service  | `up -d`                                         |
| `x`             | service  | `rm -sf` (remove — the per-service `down`)      |
| `R` `S` `T` `U` | project  | the same, for the whole project                 |
| `D`             | project  | `down` the whole project (confirm)              |
| `/`             | —        | filter the list; `Esc` leaves search            |
| `p`             | —        | toggle the logs preview                         |
| `Ctrl-L` / `F5` | —        | refresh the list                                |
| `Tab`           | —        | mark a row (service actions apply to all marked) |
| `q` / `Ctrl-C`  | —        | close the popup                                 |

Service actions operate on the marked rows (`Tab` to mark several) or, with
nothing marked, the highlighted row. The uppercase (project) keys ignore the
selection, so they work even when the list is empty (nothing running yet).

The list is not a live filter by default so the letters can be commands; press
`/` to filter, `Esc` to return to command mode.

Note on `down`: `docker compose down` is a project-wide operation and takes no
service argument. The per-service analog — stop and remove a single container —
is `x` (`docker compose rm -sf <service>`).

## Orphaned projects

Removing a worktree through herdr triggers an automatic
`docker compose -p <project> down`. But worktrees deleted *outside* herdr
(`git worktree remove` from a shell or an agent, `rm -rf`, herdr not running)
emit no event, so their containers would leak. The `gc` sweep covers that
case: any compose project whose labeled `working_dir` no longer exists on
disk — or whose labeled compose files are all gone even though the directory
survives — can never be `up`ed again, so it is torn down. The second
criterion matters because worktree deletion can half-fail: containers that
write root-owned files into bind mounts leave a directory herdr cannot
delete (and no `worktree.removed` event fires on a failed removal). GC runs
automatically after worktree removals and at most every 10 minutes on
workspace focus, and can be invoked manually as `compose.gc`.

Teardown of a dead checkout uses `down --volumes`: anonymous volumes are
never reattached anyway, and a later checkout of the same branch should start
from a fresh database rather than inherit stale state. Compose never removes
`external: true` volumes, so shared data is safe. The explicit `compose.down`
action keeps standard semantics (volumes survive).

## Troubleshooting

- When an action fails, the space's token turns `⚠ error` and details land in
  `herdr plugin log list --plugin compose` — herdr shows no toast for failed
  plugin actions, so the token and the log are the places to look.
- A common failure in fresh worktree checkouts: gitignored files such as
  `.env` don't exist in the new checkout, so compose refuses to start. Copy
  them over from the main checkout.

## Notes & caveats

- Status refreshes on workspace/worktree lifecycle events (created, focused,
  opened) and after every action. Containers that change state behind herdr's
  back (crash, `docker` run elsewhere) show up on the next focus or
  `compose.refresh` — there is no background watcher yet.
- A first-time `compose.up` that needs to pull images may take a while; run it
  in a pane instead if your images are heavy.
- The context/payload JSON field names (`cwd`, `path`, `workspace_id`, …) are
  probed defensively against a few likely spellings. If your herdr version
  uses different names, `scripts/lib.sh` is the place to look.

## Development

```bash
shellcheck -x --severity=warning scripts/*.sh   # lint
bats tests/                                       # test (no Docker needed)
```

The tests stub `docker` and `herdr`, so they run without a daemon. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the project layout and conventions.

## License

MIT
