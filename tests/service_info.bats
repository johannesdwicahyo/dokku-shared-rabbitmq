#!/usr/bin/env bats
load test_helper

setup() {
  setup_plugin_env
  source "$REPO_ROOT/config"
  source "$REPO_ROOT/functions"
}

@test "service_list lists tenants alphabetically and skips _internal" {
  mkdir -p "$PLUGIN_DATA_ROOT/zeta" "$PLUGIN_DATA_ROOT/alpha" "$PLUGIN_DATA_ROOT/_rabbitmqdata"
  run service_list
  [[ "$status" -eq 0 ]]
  lines=()
  while IFS= read -r l; do lines+=("$l"); done <<< "$output"
  [[ "${lines[0]}" == "alpha" ]]
  [[ "${lines[1]}" == "zeta" ]]
  for l in "${lines[@]}"; do
    [[ "$l" != "_rabbitmqdata" ]] || { echo "_rabbitmqdata leaked into list"; return 1; }
  done
}

@test "validate_name accepts good names and rejects bad ones" {
  run validate_name "demo"; [[ "$status" -eq 0 ]]
  run validate_name "a1-b_c"; [[ "$status" -eq 0 ]]
  run validate_name "BadName"; [[ "$status" -ne 0 ]]
  run validate_name ""; [[ "$status" -ne 0 ]]
  run validate_name "with spaces"; [[ "$status" -ne 0 ]]
}
