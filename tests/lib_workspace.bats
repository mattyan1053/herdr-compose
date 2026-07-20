#!/usr/bin/env bats
# workspace_cwd resolution from the herdr context JSON and the list fallback.

load helpers

setup() {
  common_setup
}

@test "workspace_cwd reads workspace_cwd from the context JSON" {
  export HERDR_PLUGIN_CONTEXT_JSON='{"workspace_cwd":"/home/u/proj"}'
  runlib 'workspace_cwd ws1'
  [ "$status" -eq 0 ]
  [ "$output" = "/home/u/proj" ]
}

@test "workspace_cwd tries alternate spellings" {
  export HERDR_PLUGIN_CONTEXT_JSON='{"nested":{"worktree":{"checkout_path":"/wt/x"}}}'
  runlib 'workspace_cwd ws1'
  [ "$status" -eq 0 ]
  [ "$output" = "/wt/x" ]
}

@test "workspace_cwd falls back to herdr workspace list" {
  unset HERDR_PLUGIN_CONTEXT_JSON
  stub herdr 'echo '\''{"workspace_id":"ws9","workspace_cwd":"/from/list"}'\'''
  runlib 'workspace_cwd ws9'
  [ "$status" -eq 0 ]
  [ "$output" = "/from/list" ]
}

@test "workspace_cwd is empty when nothing resolves" {
  unset HERDR_PLUGIN_CONTEXT_JSON
  stub herdr 'exit 0'
  runlib 'workspace_cwd ws-unknown'
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
