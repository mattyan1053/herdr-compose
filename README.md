# herdr-compose

English | [日本語](README_ja.md)

Docker Compose status and controls for each [herdr](https://herdr.dev) space.

- Shows the compose project state of every space in the sidebar
  (`⏵ 10` all running · `⏵ 8/10` partial · `⏸ 10` stopped · `⏹ down` no
  containers · nothing at all when the workspace has no compose project).
- One keypress per space to `toggle` (stop if running, else start / `up -d`),
  plus explicit `up` / `start` / `stop` / `down` actions.
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

- herdr ≥ 0.7.0
- Docker Compose v2
- `bash`, `jq`

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
```

All actions are also available from the workspace action menu, so keybindings
are optional.

## Actions

| Action            | Effect                                              |
| ----------------- | --------------------------------------------------- |
| `compose.toggle`  | running → `stop` · stopped → `start` · none → `up -d` |
| `compose.up`      | `docker compose up -d`                              |
| `compose.start`   | `docker compose start`                              |
| `compose.stop`    | `docker compose stop` (frees memory, keeps state)   |
| `compose.down`    | `docker compose down`                               |
| `compose.refresh` | re-report the sidebar status                        |
| `compose.gc`      | tear down orphaned projects (see below)             |

## Orphaned projects

Removing a worktree through herdr triggers an automatic
`docker compose -p <project> down`. But worktrees deleted *outside* herdr
(`git worktree remove` from a shell or an agent, `rm -rf`, herdr not running)
emit no event, so their containers would leak. The `gc` sweep covers that
case: any compose project whose labeled `working_dir` no longer exists on
disk can never be `up`ed again, so it is torn down. GC runs automatically
after worktree removals and at most every 10 minutes on workspace focus, and
can be invoked manually as `compose.gc`.

Teardown of a dead checkout uses `down --volumes`: anonymous volumes are
never reattached anyway, and a later checkout of the same branch should start
from a fresh database rather than inherit stale state. Compose never removes
`external: true` volumes, so shared data is safe. The explicit `compose.down`
action keeps standard semantics (volumes survive).

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

## License

MIT
