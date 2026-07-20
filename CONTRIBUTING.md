# Contributing to herdr-compose

Thanks for your interest in improving herdr-compose. It's a small, pure-Bash
herdr plugin, so the contribution loop is fast.

## Project layout

| Path                     | What it is                                             |
| ------------------------ | ------------------------------------------------------ |
| `herdr-plugin.toml`      | Plugin manifest: actions, events, the `ps` pane        |
| `scripts/lib.sh`         | Shared helpers (status, project names, GC, in-flight)  |
| `scripts/action.sh`      | `[[actions]]` entry point (toggle/up/start/stop/down…) |
| `scripts/event.sh`       | `[[events]]` entry point (focus, worktree lifecycle)   |
| `scripts/open-ps.sh`     | Launches the `ps` popup pane                            |
| `scripts/tui.sh`         | The interactive `fzf`-based `ps` popup                  |
| `tests/`                 | `bats` tests with `docker`/`herdr` stubs                |

## Prerequisites

- `bash`, `jq`
- [`shellcheck`](https://www.shellcheck.net/)
- [`bats`](https://github.com/bats-core/bats-core)

No Docker daemon is needed to run the tests — they stub `docker` and `herdr`.

## Development loop

```bash
shellcheck -x --severity=warning scripts/*.sh   # lint
bats tests/                                       # test
```

Both run in CI on every pull request; keep them green.

### Local install

Point herdr at your working tree so changes take effect without publishing:

```bash
herdr plugin link /path/to/herdr-compose
```

## Writing tests

Tests live in `tests/*.bats` and use the helpers in `tests/helpers.bash`:

- `common_setup` — per-test PATH sandbox, state dir, and a silent `herdr` stub.
- `stub <name> <body…>` — drop a recording stub onto PATH. Recorded calls land
  in `$CALLS`; read them with `calls`.
- `runlib '<snippet>'` — source `lib.sh` in a subshell and run a snippet, so
  the library's `set -euo pipefail` never leaks into bats.

The stubs replay canned `docker compose ps`/`config` output, so you can test the
parsing and control flow without a daemon. See `tests/lib_compose.bats` and
`tests/lib_gc.bats` for the pattern.

## Conventions

- **Portability.** The `ps` popup keys are modifier-free single letters on
  purpose (macOS Option/Alt and many SSH/phone terminals mangle Meta keys).
  Keep new UI keys in that scheme.
- **No repo-side config.** Everything is derived from the workspace cwd and
  Docker's compose labels; don't add requirements to users' repositories.
- **Keep both READMEs in sync.** `README.md` (English) and `README_ja.md`
  (Japanese) document the same behaviour — update both.
- **Field-name probing.** herdr context/payload JSON keys are matched
  defensively against a few spellings in `lib.sh`; follow that pattern rather
  than hard-coding a single key.

## Releases

A push to `main` publishes a GitHub release for the `version` in
`herdr-plugin.toml` (via `.github/workflows/release.yml`), but only if a release
for that tag doesn't already exist. Bump the version in the same PR as a
user-facing change so the merge cuts the release.

## License

By contributing you agree that your contributions are licensed under the
[MIT License](LICENSE).
