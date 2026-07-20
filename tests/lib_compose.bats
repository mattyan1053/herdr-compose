#!/usr/bin/env bats
# Helpers that shell out to `docker compose`: status counts, the sidebar token,
# and project-name resolution. A `docker` stub replays canned `ps`/`config`
# output so the parsing (NDJSON vs. array, running/total, glyph choice) is
# exercised without a daemon.

load helpers

setup() {
  common_setup
  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK"
}

# docker_ps_stub <json> — install a `docker` stub whose `compose ps` prints
# <json> and whose other subcommands succeed silently.
docker_ps_stub() {
  local json="$1"
  cat > "$STUB_DIR/docker" <<EOF
#!/usr/bin/env bash
echo "docker \$*" >> "$CALLS"
if [ "\$1" = compose ] && printf '%s\n' "\$@" | grep -q '^ps\$'; then
  cat <<'JSON'
$json
JSON
  exit 0
fi
exit 0
EOF
  chmod +x "$STUB_DIR/docker"
}

# ── compose_counts ───────────────────────────────────────────────────────────

@test "compose_counts parses NDJSON (newer compose)" {
  docker_ps_stub '{"Service":"a","State":"running"}
{"Service":"b","State":"exited"}'
  runlib "compose_counts '$WORK'"
  [ "$status" -eq 0 ]
  [ "$output" = $'1\t2' ]
}

@test "compose_counts parses a JSON array (older compose)" {
  docker_ps_stub '[{"Service":"a","State":"running"},{"Service":"b","State":"running"}]'
  runlib "compose_counts '$WORK'"
  [ "$status" -eq 0 ]
  [ "$output" = $'2\t2' ]
}

@test "compose_counts fails when compose ps errors (no project)" {
  cat > "$STUB_DIR/docker" <<EOF
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$STUB_DIR/docker"
  runlib "compose_counts '$WORK'"
  [ "$status" -ne 0 ]
}

# ── compose_token ────────────────────────────────────────────────────────────

@test "compose_token: all running shows the play glyph" {
  docker_ps_stub '{"Service":"a","State":"running"}
{"Service":"b","State":"running"}'
  runlib "compose_token '$WORK'"
  [ "$status" -eq 0 ]
  [ "$output" = "⏵ 2/2" ]
}

@test "compose_token: none running shows the pause glyph" {
  docker_ps_stub '{"Service":"a","State":"exited"}
{"Service":"b","State":"exited"}'
  runlib "compose_token '$WORK'"
  [ "$status" -eq 0 ]
  [ "$output" = "⏸ 0/2" ]
}

@test "compose_token: no containers shows down" {
  docker_ps_stub '[]'
  runlib "compose_token '$WORK'"
  [ "$status" -eq 0 ]
  [ "$output" = "⏹ down" ]
}

# ── compose_project_name / cache ─────────────────────────────────────────────

@test "compose_project_name uses the name from compose config" {
  cat > "$STUB_DIR/docker" <<EOF
#!/usr/bin/env bash
echo "docker \$*" >> "$CALLS"
if [ "\$1" = compose ] && printf '%s\n' "\$@" | grep -q '^config\$'; then
  echo '{"name":"myproj"}'
fi
exit 0
EOF
  chmod +x "$STUB_DIR/docker"
  runlib "compose_project_name '$WORK'"
  [ "$status" -eq 0 ]
  [ "$output" = "myproj" ]
}

@test "compose_project_name falls back to a sanitized basename" {
  # config prints nothing -> fall back to basename, lowercased & stripped.
  stub docker 'exit 0'
  local d="$BATS_TEST_TMPDIR/My.Proj"
  mkdir -p "$d"
  runlib "compose_project_name '$d'"
  [ "$status" -eq 0 ]
  [ "$output" = "myproj" ]
}

@test "cache_project_name then cached_project_name round-trips" {
  stub docker 'exit 0'
  local d="$BATS_TEST_TMPDIR/svc"
  mkdir -p "$d"
  runlib "cache_project_name '$d'; cached_project_name '$d'"
  [ "$status" -eq 0 ]
  [ "$output" = "svc" ]
}

@test "cached_project_name is empty for an unknown directory" {
  runlib "cached_project_name /never/seen"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
