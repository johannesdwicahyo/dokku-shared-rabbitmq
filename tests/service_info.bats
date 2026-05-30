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

@test "service_info prints all fields including quota default" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  : >"$PLUGIN_DATA_ROOT/demo/LINKS"
  stub_response docker $'7\n13'
  run service_info "demo"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"name=demo"* ]]
  [[ "$output" == *"user=demo"* ]]
  [[ "$output" == *"vhost=demo"* ]]
  [[ "$output" == *"host=dokku-shared-rabbitmq"* ]]
  [[ "$output" == *"port=5672"* ]]
  [[ "$output" == *"messages=20"* ]]
  [[ "$output" == *"quota_msgs=10000"* ]]
  [[ "$output" == *"read_only=false"* ]]
}

@test "service_info reports read_only=true when marker is present" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  : >"$PLUGIN_DATA_ROOT/demo/LINKS"
  : >"$PLUGIN_DATA_ROOT/demo/QUOTA_VIOLATED"
  stub_response docker ''
  run service_info "demo"
  [[ "$output" == *"read_only=true"* ]]
}

@test "service_info reports linked apps as csv" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  printf 'app1\napp2\n' >"$PLUGIN_DATA_ROOT/demo/LINKS"
  stub_response docker ''
  run service_info "demo"
  [[ "$output" == *"linked_apps=app1,app2"* ]]
}

@test "service_info errors when tenant is missing" {
  run service_info "ghost"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"does not exist"* ]]
}

@test "service_export errors with stretch-goal message and non-zero exit" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  run service_export "demo"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"v0.2 stretch goal"* ]]
}

@test "service_import errors with stretch-goal message and non-zero exit" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  run service_import "demo"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"not implemented in v0.1.0"* ]]
}
