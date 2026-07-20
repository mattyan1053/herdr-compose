#!/usr/bin/env bats
# Pure helpers in lib.sh: path_key, compose file discovery, in-flight markers.

load helpers

setup() {
  common_setup
}

# ── path_key ─────────────────────────────────────────────────────────────────

@test "path_key flattens slashes to underscores" {
  runlib 'path_key /home/user/proj'
  [ "$status" -eq 0 ]
  [ "$output" = "_home_user_proj" ]
}

# ── has_compose_file ─────────────────────────────────────────────────────────

@test "has_compose_file finds each supported filename" {
  local f
  for f in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
    local d="$BATS_TEST_TMPDIR/proj-$f"
    mkdir -p "$d"
    touch "$d/$f"
    runlib "has_compose_file '$d'"
    [ "$status" -eq 0 ]
  done
}

@test "has_compose_file fails on a directory without compose files" {
  mkdir -p "$BATS_TEST_TMPDIR/empty"
  runlib "has_compose_file '$BATS_TEST_TMPDIR/empty'"
  [ "$status" -ne 0 ]
}

# ── compose_config_present ───────────────────────────────────────────────────

@test "compose_config_present: empty label counts as present" {
  runlib "compose_config_present ''"
  [ "$status" -eq 0 ]
}

@test "compose_config_present: one surviving file out of several is enough" {
  touch "$BATS_TEST_TMPDIR/alive.yml"
  runlib "compose_config_present '/gone/a.yml,$BATS_TEST_TMPDIR/alive.yml'"
  [ "$status" -eq 0 ]
}

@test "compose_config_present: all files gone means absent" {
  runlib "compose_config_present '/gone/a.yml,/gone/b.yml'"
  [ "$status" -ne 0 ]
}

# ── in-flight markers ────────────────────────────────────────────────────────

@test "inflight_op returns the marked operation" {
  runlib 'mark_inflight /some/dir up; inflight_op /some/dir'
  [ "$status" -eq 0 ]
  [ "$output" = "up" ]
}

@test "inflight_op fails when nothing is marked" {
  runlib 'inflight_op /some/dir'
  [ "$status" -ne 0 ]
}

@test "clear_inflight removes the marker" {
  runlib 'mark_inflight /some/dir up; clear_inflight /some/dir; inflight_op /some/dir'
  [ "$status" -ne 0 ]
}

@test "inflight_op ignores and removes a stale (>30 min) marker" {
  runlib 'mark_inflight /some/dir up
    printf "%s up\n" "$(( $(date +%s) - 1801 ))" > "$(inflight_file /some/dir)"
    inflight_op /some/dir'
  [ "$status" -ne 0 ]
  runlib 'test -f "$(inflight_file /some/dir)"'
  [ "$status" -ne 0 ]
}

@test "inflight_op ignores a corrupt marker" {
  runlib 'printf "garbage\n" > "$(inflight_file /some/dir)"; inflight_op /some/dir'
  [ "$status" -ne 0 ]
}
