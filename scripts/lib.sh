#!/usr/bin/env bash
# Shared helpers for herdr-compose. Sourced by action.sh / event.sh.
#
# Plugin runtime commands run with the *plugin directory* as cwd, so every
# docker compose invocation must resolve the workspace directory first.
set -euo pipefail

SOURCE_NAME="herdr-compose"
TOKEN_NAME="compose"

herdr_cli() {
  "${HERDR_BIN_PATH:-herdr}" "$@"
}

state_dir() {
  local d="${HERDR_PLUGIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr-compose}"
  mkdir -p "$d/projects"
  printf '%s' "$d"
}

# ── workspace id → directory ─────────────────────────────────────────────────
# herdr 0.7.x passes the workspace directory as a flat `workspace_cwd` field in
# the context JSON (alongside focused_pane_cwd etc.); other spellings are kept
# as fallbacks. `herdr workspace list` output carries no cwd today, so the
# list-based fallback only helps if a future herdr adds one.
workspace_cwd() {
  local ws="${1:-${HERDR_WORKSPACE_ID:-}}" cwd=""
  if [[ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ]]; then
    cwd=$(jq -r \
      '[.. | objects | (.workspace_cwd? // .cwd? // .working_dir? // .path? // .worktree.checkout_path?) | strings] | first // empty' \
      <<<"$HERDR_PLUGIN_CONTEXT_JSON" 2>/dev/null || true)
  fi
  # Workspace list entries carry no plain cwd, but worktree-backed workspaces
  # expose worktree.checkout_path — enough to make the fallback useful.
  if [[ -z "$cwd" && -n "$ws" ]]; then
    cwd=$(herdr_cli workspace list 2>/dev/null \
      | jq -sr --arg ws "$ws" \
        '[.. | objects | select((.workspace_id? // .id?) == $ws)
          | (.workspace_cwd? // .cwd? // .working_dir? // .path? // .worktree.checkout_path?) | strings] | first // empty' \
      2>/dev/null || true)
  fi
  printf '%s' "$cwd"
}

# ── compose status ───────────────────────────────────────────────────────────
# Prints "<running>\t<total>" for the compose project reachable from $1
# (compose searches ancestor directories itself). Returns 1 when the
# directory has no compose project at all.
compose_counts() {
  local dir="$1" out
  out=$( (cd "$dir" && docker compose ps -a --format json 2>/dev/null) ) || return 1
  # `docker compose ps --format json` emits an array on older v2 releases and
  # NDJSON on newer ones; slurping covers both.
  jq -sr \
    '[.. | objects | select(has("State"))]
     | [([.[] | select(.State == "running")] | length), length] | @tsv' \
    <<<"$out"
}

# Always running/total — the counts distinguish running (⏵ 2/2) from stopped
# (⏸ 0/2) even where the small glyphs are hard to tell apart.
compose_token() {
  local dir="$1" counts running total
  counts=$(compose_counts "$dir") || return 1
  running=${counts%%$'\t'*}
  total=${counts##*$'\t'}
  if (( total == 0 )); then
    printf '⏹ down'
  elif (( running == 0 )); then
    printf '⏸ %d/%d' "$running" "$total"
  else
    printf '⏵ %d/%d' "$running" "$total"
  fi
}

# Heuristic mirror of compose's default file discovery (current dir only) —
# used to distinguish "no compose project" from "project present but broken"
# (e.g. a worktree checkout missing its gitignored .env).
has_compose_file() {
  local d="$1" f
  for f in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
    [[ -f "$d/$f" ]] && return 0
  done
  return 1
}

# Reports the sidebar token for a workspace. An empty value is sent when the
# directory has no compose project — herdr hides unreported tokens, and empty
# is the closest CLI approximation of clearing one (the socket API clears
# with null; revisit if empty strings ever render as stray separators).
report_status() {
  local ws="$1" dir="$2" value
  if ! value=$(compose_token "$dir"); then
    if has_compose_file "$dir"; then value="⚠ error"; else value=""; fi
  fi
  herdr_cli workspace report-metadata "$ws" \
    --source "$SOURCE_NAME" --token "$TOKEN_NAME=$value" >/dev/null 2>&1 || true
}

# Failures inside herdr are otherwise invisible (no toast, log only), so
# surface them in the sidebar; details stay in `herdr plugin log list`.
report_error() {
  herdr_cli workspace report-metadata "$1" \
    --source "$SOURCE_NAME" --token "$TOKEN_NAME=⚠ error" >/dev/null 2>&1 || true
}

# ── project-name cache ───────────────────────────────────────────────────────
# worktree.removed fires *after* the checkout directory is deleted, so
# teardown must run as `docker compose -p <name> down`. The name is cached
# per directory whenever we successfully touch a project.
compose_project_name() {
  local dir="$1" name=""
  name=$( (cd "$dir" && docker compose config --format json 2>/dev/null) \
    | jq -r '.name // empty' 2>/dev/null ) || true
  if [[ -z "$name" ]]; then
    name=$(basename "$dir" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]//g')
  fi
  printf '%s' "$name"
}

path_key() {
  printf '%s' "$1" | tr '/' '_'
}

cache_project_name() {
  local dir="$1"
  compose_project_name "$dir" > "$(state_dir)/projects/$(path_key "$dir")"
}

cached_project_name() {
  local f
  f="$(state_dir)/projects/$(path_key "$1")"
  if [[ -f "$f" ]]; then cat "$f"; fi
}

# ── orphan GC ────────────────────────────────────────────────────────────────
# Worktrees removed outside herdr (plain `git worktree remove`, rm -rf, herdr
# not running) never emit worktree.removed, so their containers leak. Compose
# stamps every container with its project working_dir and config_files labels;
# a project is an orphan when its working_dir is gone, or when the directory
# survives but none of its compose files do — the latter happens when a
# worktree deletion half-fails because containers wrote root-owned files into
# bind mounts (herdr then can't rm the directory and never emits
# worktree.removed). Either way the project cannot be `up`ed again and is
# safe to tear down. Volumes go too (-v): the checkout is gone for good, and
# a later same-name checkout should start fresh. External volumes are never
# removed by compose, so shared data is safe.
compose_gc() {
  docker ps -a \
    --format '{{.Label "com.docker.compose.project"}}\t{{.Label "com.docker.compose.project.working_dir"}}\t{{.Label "com.docker.compose.project.config_files"}}' \
    2>/dev/null | sort -u | while IFS=$'\t' read -r name wdir cfgs; do
      [[ -n "$name" && -n "$wdir" ]] || continue
      if [[ -d "$wdir" ]] && compose_config_present "$cfgs"; then continue; fi
      docker compose -p "$name" down --volumes --remove-orphans >/dev/null 2>&1 || true
      rm -f "$(state_dir)/projects/$(path_key "$wdir")"
    done
}

# config_files is a comma-separated path list. "Present" when at least one
# listed file still exists; an empty label counts as present so projects
# started in exotic ways (stdin config, very old compose) are never reaped
# while their directory is alive.
compose_config_present() {
  local cfgs="$1" f
  [[ -n "$cfgs" ]] || return 0
  local IFS=','
  for f in $cfgs; do
    [[ -f "$f" ]] && return 0
  done
  return 1
}

# Focus events fire constantly; sweep at most every 10 minutes.
gc_throttled() {
  local stamp now last=0
  stamp="$(state_dir)/gc.last"
  now=$(date +%s)
  if [[ -f "$stamp" ]]; then last=$(<"$stamp"); fi
  (( now - last >= 600 )) || return 0
  printf '%s' "$now" > "$stamp"
  compose_gc
}
