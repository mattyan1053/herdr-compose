#!/usr/bin/env bats
# Orphan GC: a project is torn down when its working_dir is gone, or the dir
# survives but none of its compose files do. Live projects are left alone.
# A `docker` stub feeds `docker ps -a` the label rows and records every
# `docker compose ... down` so we can assert what got reaped.

load helpers

setup() {
  common_setup
  DOWN="$BATS_TEST_TMPDIR/down.log"
}

# gc_stub <label-rows> — `docker ps -a` prints <label-rows> (tab-separated:
# project<TAB>working_dir<TAB>config_files); `docker compose -p X down` records X.
gc_stub() {
  local rows="$1"
  cat > "$STUB_DIR/docker" <<EOF
#!/usr/bin/env bash
if [ "\$1" = ps ]; then
  cat <<'ROWS'
$rows
ROWS
  exit 0
fi
if [ "\$1" = compose ]; then
  # capture the project passed via -p
  prev=""
  for a in "\$@"; do
    [ "\$prev" = -p ] && echo "\$a" >> "$DOWN"
    prev="\$a"
  done
fi
exit 0
EOF
  chmod +x "$STUB_DIR/docker"
}

reaped() { cat "$DOWN" 2>/dev/null || true; }

@test "gc reaps a project whose working_dir is gone" {
  gc_stub "deadproj	/gone/worktree	/gone/worktree/compose.yml"
  runlib "compose_gc"
  [ "$status" -eq 0 ]
  [ "$(reaped)" = "deadproj" ]
}

@test "gc keeps a project whose dir and compose file both survive" {
  local d="$BATS_TEST_TMPDIR/live"
  mkdir -p "$d"
  touch "$d/compose.yml"
  gc_stub "liveproj	$d	$d/compose.yml"
  runlib "compose_gc"
  [ "$status" -eq 0 ]
  [ -z "$(reaped)" ]
}

@test "gc reaps a project whose dir survives but compose files are gone" {
  local d="$BATS_TEST_TMPDIR/halfdead"
  mkdir -p "$d"   # dir exists, but the config file does not
  gc_stub "halfproj	$d	$d/compose.yml"
  runlib "compose_gc"
  [ "$status" -eq 0 ]
  [ "$(reaped)" = "halfproj" ]
}

@test "gc skips a non-compose container (all labels empty)" {
  # docker emits empty labels for containers with no compose project.
  gc_stub "			"
  runlib "compose_gc"
  [ "$status" -eq 0 ]
  [ -z "$(reaped)" ]
}

@test "gc_throttled runs the first time then suppresses within the window" {
  gc_stub "deadproj	/gone/worktree	/gone/worktree/compose.yml"
  # First call sweeps; second within 10 min must not.
  runlib "gc_throttled; echo ---; gc_throttled"
  [ "$status" -eq 0 ]
  # Only one teardown recorded despite two calls.
  [ "$(reaped)" = "deadproj" ]
}
