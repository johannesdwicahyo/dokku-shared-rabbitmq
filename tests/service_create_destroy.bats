#!/usr/bin/env bats
load test_helper

setup() {
  setup_plugin_env
  source "$REPO_ROOT/config"
  source "$REPO_ROOT/functions"
  # Pretend the container is already running so ensure_shared_container short-circuits.
  stub_response docker 'dokku-shared-rabbitmq'
}

@test "service_create writes metadata files with a 32-char password" {
  service_create "demo"
  [[ -f "$PLUGIN_DATA_ROOT/demo/PASSWORD" ]]
  [[ -f "$PLUGIN_DATA_ROOT/demo/LINKS" ]]
  pw="$(<"$PLUGIN_DATA_ROOT/demo/PASSWORD")"
  [[ "${#pw}" -eq 32 ]]
}

@test "service_create issues add_vhost, add_user, scoped set_permissions in order" {
  service_create "demo"
  calls=()
  while IFS= read -r line; do calls+=("$line"); done < <(grep '^docker exec' "$STUB_LOG")
  [[ "${calls[0]}" == *"add_vhost demo"* ]]
  [[ "${calls[1]}" == *"add_user demo "* ]]
  [[ "${calls[2]}" == *'set_permissions -p demo demo .* .* .*'* ]]
}

@test "service_create refuses an existing tenant" {
  service_create "demo"
  run service_create "demo"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"already exists"* ]]
}

@test "service_create rejects invalid name" {
  run service_create "BadName"; [[ "$status" -ne 0 ]]
  run service_create ""; [[ "$status" -ne 0 ]]
  run service_create "with spaces"; [[ "$status" -ne 0 ]]
}

@test "service_dsn includes user, password, host, port, vhost" {
  service_create "demo"
  run service_dsn "demo"
  [[ "$status" -eq 0 ]]
  pw="$(<"$PLUGIN_DATA_ROOT/demo/PASSWORD")"
  [[ "$output" == "amqp://demo:${pw}@dokku-shared-rabbitmq:5672/demo" ]]
}

@test "service_destroy issues delete_user + delete_vhost and removes the data dir" {
  service_create "demo"
  : >"$STUB_LOG"
  service_destroy "demo"
  [[ ! -d "$PLUGIN_DATA_ROOT/demo" ]]
  run grep -c 'docker exec.*delete_user demo' "$STUB_LOG"
  [[ "$output" -ge 1 ]]
  run grep -c 'docker exec.*delete_vhost demo' "$STUB_LOG"
  [[ "$output" -ge 1 ]]
}

@test "service_destroy errors when tenant is missing" {
  run service_destroy "ghost"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"does not exist"* ]]
}
