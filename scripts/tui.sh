#!/usr/bin/env bash
# Interactive `docker compose ps` popup — the [[panes]] entrypoint "ps".
#
# herdr launches this as the pane *program*; it resolves the manifest's relative
# command against the plugin root, while the pane's process cwd is whatever the
# launcher chose. So we can't rely on cwd alone: the launcher passes the target
# workspace directory as $HC_DIR and the plugin root as $HC_PLUGIN_DIR, and we
# cd into $HC_DIR here so every `docker compose` call hits the right project.
#
# The UI is fzf: the service list is the choice list, logs are the --preview,
# and each action is an fzf keybinding that runs a compose command and reloads
# the list. Multi-select (tab) applies service-scoped actions to every marked
# row. Keys are modifier-free single letters (see the header/README) — the most
# portable choice across terminals; Alt and most Ctrl combos are avoided.
#   lowercase = the selection {+1} (marked rows, else the highlighted row):
#     enter/l logs · f follow · r restart · s start · t stop · u up · x rm
#     (rm -sf is the per-service analog of down)
#   UPPERCASE = the whole project (ignores the selection, works on an empty list):
#     R restart · S start · T stop · U up · D down
#   / search · Esc leave search · p preview · Ctrl-L / F5 refresh · q quit
set -uo pipefail

plugin_dir="${HC_PLUGIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
self="$plugin_dir/scripts/tui.sh"
if [[ -n "${HC_DIR:-}" && -d "$HC_DIR" ]]; then cd "$HC_DIR" || exit 1; fi

# ── list mode ────────────────────────────────────────────────────────────────
# Prints one aligned row per service: "<service> <glyph state> <status> <ports>".
# fzf's default whitespace tokenizer makes {1} the service name (never spaced),
# which is exactly what every compose command below wants. Emitted TSV is padded
# by `column -t`. `ps -a` covers stopped/exited containers too.
if [[ "${1:-}" == "--list" ]]; then
  docker compose ps -a --format json 2>/dev/null | jq -sr '
    [.. | objects | select(has("State"))] | sort_by(.Service // .Name) | .[]
    | (.Service // .Name // "?")                              as $svc
    | (.State // "?")                                         as $st
    | (if   $st == "running" then "▶"
       elif $st == "paused"  then "⏸"
       elif ($st|test("exit|dead")) then "✖"
       else "·" end)                                          as $g
    | ([.Publishers[]? | select((.PublishedPort // 0) > 0)
        | "\(.PublishedPort)→\(.TargetPort)"] | unique | join(",")) as $ports
    | [$svc, ($g + " " + $st), (.Status // ""),
       (if $ports == "" then "-" else $ports end)] | @tsv
  ' 2>/dev/null | column -t -s $'\t'
  exit 0
fi

# ── preflight: is there a compose project reachable from here? ────────────────
if ! docker compose ps -a >/dev/null 2>&1; then
  printf 'herdr-compose: no compose project reachable from\n  %s\n\n' "$PWD"
  printf 'このディレクトリ（と祖先）に compose ファイルがありません。\n'
  read -rsn1 -p '何かキーを押すと閉じます…' _ || true
  exit 0
fi

export HC_SELF="$self"

# Key scheme: modifier-free single keys, which are the most portable across
# terminals (macOS Option/Alt and many phone/SSH terminals mangle Meta; bare
# and Shifted letters are raw bytes everyone sends). Convention:
#   lowercase = the selection (marked rows via Tab, else the highlighted row)
#   UPPERCASE = the whole project (ignores the selection; works on an empty list)
# Search is off by default so the letters are commands (lazydocker-style);
# press / to filter, Esc to leave search, q to quit.
header=$'↵/l logs · f follow · r restart · s start · t stop · u up · x rm      SHIFT = whole project (R S T U D)\n/ search · p preview · Ctrl-L refresh · Tab mark · q quit'

# Show any failure and pause, so a bad compose call is not hidden by the reload.
fail='|| { echo; read -rsn1 -p "failed — press any key " _; }'
RL='+reload(bash "$HC_SELF" --list)'

bash "$self" --list | fzf \
  --ansi --layout=reverse --info=inline --no-sort --multi \
  --disabled --prompt 'compose> ' \
  --header-first --header "$header" \
  --preview 'docker compose logs --tail=200 {1} 2>&1 | tail -n 400' \
  --preview-window 'right,55%,border-left,wrap,follow' \
  --bind 'j:down,k:up,p:toggle-preview' \
  --bind 'q:abort' \
  --bind '/:change-prompt(search> )+enable-search' \
  --bind 'esc:change-prompt(compose> )+disable-search' \
  --bind 'ctrl-l:reload(bash "$HC_SELF" --list)' \
  --bind 'f5:reload(bash "$HC_SELF" --list)' \
  --bind 'enter:execute(docker compose logs --tail=2000 {1} 2>&1 | less -R +G)' \
  --bind 'l:execute(docker compose logs --tail=2000 {1} 2>&1 | less -R +G)' \
  --bind 'f:execute(clear; echo "following {1} — Ctrl-C to return"; echo; docker compose logs -f --tail=100 {1})' \
  --bind "r:execute(docker compose restart {+1} $fail)$RL" \
  --bind "s:execute(docker compose start {+1} $fail)$RL" \
  --bind "t:execute(docker compose stop {+1} $fail)$RL" \
  --bind "u:execute(docker compose up -d {+1} $fail)$RL" \
  --bind "x:execute(printf 'rm -sf %s ? [y/N] ' \"{+1}\"; read -r a; [ \"\$a\" = y ] && docker compose rm -sf {+1})$RL" \
  --bind "R:execute(docker compose restart $fail)$RL" \
  --bind "S:execute(docker compose start $fail)$RL" \
  --bind "T:execute(docker compose stop $fail)$RL" \
  --bind "U:execute(docker compose up -d $fail)$RL" \
  --bind "D:execute(printf 'compose down (whole project)? [y/N] '; read -r a; [ \"\$a\" = y ] && docker compose down)$RL" \
  >/dev/null 2>&1 || true
