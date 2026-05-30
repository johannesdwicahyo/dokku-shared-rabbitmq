#!/usr/bin/env bats
load test_helper

setup() {
  setup_plugin_env
  source "$REPO_ROOT/config"
  source "$REPO_ROOT/functions"
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  : >"$PLUGIN_DATA_ROOT/demo/LINKS"
}

@test "service_get_quota_msgs returns default when no override" {
  run service_get_quota_msgs "demo"
  [[ "$output" == "10000" ]]
}

@test "service_set_quota writes the override file" {
  service_set_quota "demo" "500"
  [[ "$(<"$PLUGIN_DATA_ROOT/demo/QUOTA_MSGS")" == "500" ]]
}

@test "service_set_quota rejects non-numeric / zero / negative" {
  run service_set_quota "demo" "huge"; [[ "$status" -ne 0 ]]
  run service_set_quota "demo" "0"; [[ "$status" -ne 0 ]]
  run service_set_quota "demo" "-5"; [[ "$status" -ne 0 ]]
  run service_set_quota "demo" ""; [[ "$status" -ne 0 ]]
}

@test "service_unset_quota removes the override file" {
  printf '500' >"$PLUGIN_DATA_ROOT/demo/QUOTA_MSGS"
  service_unset_quota "demo"
  [[ ! -f "$PLUGIN_DATA_ROOT/demo/QUOTA_MSGS" ]]
}

@test "tenant_usage sums message counts across queues" {
  # list_queues output: one message-count per queue line.
  stub_response docker $'12\n30\n8'
  run tenant_usage "demo"
  [[ "$output" == "50" ]]
}

@test "tenant_usage is zero when no queues" {
  stub_response docker ''
  run tenant_usage "demo"
  [[ "$output" == "0" ]]
}

@test "service_check_quota flips read-only when over cap" {
  printf '10' >"$PLUGIN_DATA_ROOT/demo/QUOTA_MSGS"
  stub_response docker $'40'   # tenant_usage -> 40 > 10
  stub_response docker ''      # set_permissions
  run service_check_quota "demo"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"flipped"* ]]
  [[ -f "$PLUGIN_DATA_ROOT/demo/QUOTA_VIOLATED" ]]
  # Revoke = configure/read kept, write empty -> ".* <empty> .*" renders with a
  # double space. -F matches the . and * literally.
  run grep -cF 'set_permissions -p demo demo .*  .*' "$STUB_LOG"
  [[ "$output" -ge 1 ]]
}

@test "service_check_quota releases when back under cap" {
  printf '100' >"$PLUGIN_DATA_ROOT/demo/QUOTA_MSGS"
  : >"$PLUGIN_DATA_ROOT/demo/QUOTA_VIOLATED"
  stub_response docker $'5'    # tenant_usage -> 5 < 100
  stub_response docker ''      # set_permissions
  run service_check_quota "demo"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"released"* ]]
  [[ ! -f "$PLUGIN_DATA_ROOT/demo/QUOTA_VIOLATED" ]]
  # Full grant = ".* .* .*" with single spaces.
  run grep -cF 'set_permissions -p demo demo .* .* .*' "$STUB_LOG"
  [[ "$output" -ge 1 ]]
}

@test "service_check_quota is silent when over cap and already enforced" {
  printf '10' >"$PLUGIN_DATA_ROOT/demo/QUOTA_MSGS"
  : >"$PLUGIN_DATA_ROOT/demo/QUOTA_VIOLATED"
  stub_response docker $'40'
  run service_check_quota "demo"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
  run grep -c 'set_permissions' "$STUB_LOG"
  [[ "$output" == "0" ]]
}

@test "service_check_quota is silent when under cap and not flagged" {
  printf '100' >"$PLUGIN_DATA_ROOT/demo/QUOTA_MSGS"
  stub_response docker $'5'
  run service_check_quota "demo"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}
