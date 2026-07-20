# Shared setup for herdr-compose bats tests.
#
# The scripts under test shell out to `docker` and `herdr`; tests point PATH at
# a per-test stub directory and write small recording stubs there instead of
# touching a real daemon. State goes to a per-test HERDR_PLUGIN_STATE_DIR.

common_setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  LIB="$REPO_ROOT/scripts/lib.sh"
  STUB_DIR="$BATS_TEST_TMPDIR/stub-bin"
  CALLS="$BATS_TEST_TMPDIR/calls.log"
  mkdir -p "$STUB_DIR"
  export PATH="$STUB_DIR:$PATH"
  export HERDR_PLUGIN_STATE_DIR="$BATS_TEST_TMPDIR/state"
  # lib.sh falls back to `herdr` on PATH; default to a silent success stub so
  # report_* helpers never hang or fail a test by accident.
  stub herdr 'exit 0'
}

# stub <name> <body…> — drop an executable stub into the stub dir.
# The body sees the recorded arguments as "$@" and CALLS in the environment.
stub() {
  local name="$1"
  shift
  {
    printf '#!/usr/bin/env bash\n'
    printf 'echo "%s $*" >> "%s"\n' "$name" "$CALLS"
    printf '%s\n' "$@"
  } > "$STUB_DIR/$name"
  chmod +x "$STUB_DIR/$name"
}

# runlib <snippet> — run a snippet in a fresh bash with lib.sh sourced.
# Sourcing in a subprocess keeps lib.sh's `set -euo pipefail` away from bats.
runlib() {
  run bash -c "source '$LIB'; $1"
}

# calls — print the recorded stub invocations (empty if none).
calls() {
  cat "$CALLS" 2>/dev/null || true
}
