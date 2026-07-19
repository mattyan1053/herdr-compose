#!/usr/bin/env bash
# Entry point for [[events]] — dispatches on HERDR_PLUGIN_EVENT.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=lib.sh
source ./lib.sh

event="${HERDR_PLUGIN_EVENT:-}"
payload="${HERDR_PLUGIN_EVENT_JSON:-}"
[[ -n "$payload" ]] || payload='{}'

payload_first() {
  jq -r "[.. | objects | ($1) | strings] | first // empty" <<<"$payload" 2>/dev/null || true
}

case "$event" in
  workspace.created | workspace.focused | worktree.created | worktree.opened)
    ws=$(payload_first '.workspace_id? // .id?')
    [[ -n "$ws" ]] || ws="${HERDR_WORKSPACE_ID:-}"
    [[ -n "$ws" ]] || exit 0
    dir=$(workspace_cwd "$ws")
    [[ -n "$dir" && -d "$dir" ]] || exit 0
    # Focus fires often; skip the (slow) `compose config` name resolution there.
    if [[ "$event" != "workspace.focused" ]]; then
      cache_project_name "$dir"
    fi
    report_status "$ws" "$dir"
    gc_throttled
    ;;
  worktree.removed)
    # The checkout directory is already gone at this point — tear down by the
    # project name cached while the worktree was alive.
    dir=$(payload_first '.path? // .worktree_path? // .checkout_path?')
    [[ -n "$dir" ]] || exit 0
    name=$(cached_project_name "$dir")
    [[ -n "$name" ]] || exit 0
    docker compose -p "$name" down --volumes --remove-orphans >/dev/null 2>&1 || true
    rm -f "$(state_dir)/projects/$(path_key "$dir")"
    # Belt and suspenders: sweep anything else that leaked.
    compose_gc
    ;;
esac
