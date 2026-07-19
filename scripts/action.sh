#!/usr/bin/env bash
# Entry point for [[actions]] — argv[1] carries the action id.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=lib.sh
source ./lib.sh

action="${1:-${HERDR_PLUGIN_ACTION_ID:-}}"
action="${action##*.}" # tolerate fully-qualified ids like "compose.up"

# gc needs no workspace context — handle it before resolution.
if [[ "$action" == "gc" ]]; then
  compose_gc
  exit 0
fi

ws="${HERDR_WORKSPACE_ID:-}"
if [[ -z "$ws" ]]; then
  echo "herdr-compose: no workspace context" >&2
  exit 1
fi

dir=$(workspace_cwd "$ws")
if [[ -z "$dir" || ! -d "$dir" ]]; then
  echo "herdr-compose: could not resolve workspace directory for $ws" >&2
  exit 1
fi

run_compose() { (cd "$dir" && docker compose "$@"); }

case "$action" in
  up)    run_compose up -d ;;
  start) run_compose start ;;
  stop)  run_compose stop ;;
  down)  run_compose down ;;
  toggle)
    if ! counts=$(compose_counts "$dir"); then
      echo "herdr-compose: no compose project in $dir" >&2
      exit 1
    fi
    running=${counts%%$'\t'*}
    total=${counts##*$'\t'}
    if (( running > 0 )); then
      run_compose stop
    elif (( total > 0 )); then
      run_compose start
    else
      run_compose up -d
    fi
    ;;
  refresh) ;; # report below is the whole job
  *)
    echo "herdr-compose: unknown action '$action'" >&2
    exit 1
    ;;
esac

cache_project_name "$dir"
report_status "$ws" "$dir"
