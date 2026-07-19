#!/usr/bin/env bash
# Launcher for the `ps` action — opens the interactive compose popup.
#
# herdr actions run a command; this one asks herdr to open the manifest's "ps"
# pane as a session-modal popup. The pane's program (scripts/tui.sh) is resolved
# by herdr against the plugin root, but its docker compose calls must run in the
# *workspace* directory — so we resolve that here and hand it to the popup as
# $HC_DIR, along with the plugin root as $HC_PLUGIN_DIR (tui.sh needs it to find
# itself for fzf reloads). We deliberately do not pass --cwd: matching the proven
# file-viewer pattern keeps herdr's relative-program resolution unambiguous.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
plugin_dir="$(cd .. && pwd)"
# shellcheck source=lib.sh
source ./lib.sh

herdr_bin="${HERDR_BIN_PATH:-herdr}"
ws="${HERDR_WORKSPACE_ID:-}"

env_args=(--env "HC_PLUGIN_DIR=$plugin_dir")
if [[ -n "$ws" ]]; then
  dir="$(workspace_cwd "$ws")"
  if [[ -n "$dir" && -d "$dir" ]]; then
    env_args+=(--env "HC_DIR=$dir")
  fi
fi

exec "$herdr_bin" plugin pane open \
  --plugin compose \
  --entrypoint ps \
  --placement popup \
  --width 90% --height 85% \
  --focus \
  "${env_args[@]}"
