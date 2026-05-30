#!/usr/bin/env bats
load test_helper

# Verifies every subcommand accepts the Dokku 0.38 invocation convention:
# $1 is "shared-rabbitmq:<cmd>" and user args start at $2. Scripts `shift`
# this prefix off before reading positional args.

setup() {
  setup_plugin_env
}

@test "create rejects empty name and points at the right cmd" {
  run "$REPO_ROOT/subcommands/create" "shared-rabbitmq:create"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"shared-rabbitmq:create"* ]]
}

@test "create with a name provisions and prints the DSN" {
  stub_response docker 'dokku-shared-rabbitmq'
  run "$REPO_ROOT/subcommands/create" "shared-rabbitmq:create" "demo"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "amqp://demo:"*"@dokku-shared-rabbitmq:5672/demo" ]]
}

@test "destroy requires -f and treats positional 1 as the tenant name" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  run "$REPO_ROOT/subcommands/destroy" "shared-rabbitmq:destroy" "demo"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"refusing to destroy"* ]]
}

@test "destroy -f removes the tenant" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  : >"$PLUGIN_DATA_ROOT/demo/LINKS"
  run "$REPO_ROOT/subcommands/destroy" "shared-rabbitmq:destroy" "demo" "-f"
  [[ "$status" -eq 0 ]]
  [[ ! -d "$PLUGIN_DATA_ROOT/demo" ]]
}

@test "list runs cleanly with no tenants" {
  run "$REPO_ROOT/subcommands/list" "shared-rabbitmq:list"
  [[ "$status" -eq 0 ]]
}

@test "link sets RABBITMQ_URL on the app" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  : >"$PLUGIN_DATA_ROOT/demo/LINKS"
  run "$REPO_ROOT/subcommands/link" "shared-rabbitmq:link" "demo" "myapp"
  [[ "$status" -eq 0 ]]
  run grep -c 'dokku config:set --no-restart myapp RABBITMQ_URL=amqp://demo:pw@' "$STUB_LOG"
  [[ "$output" -ge 1 ]]
}

@test "link errors without an app arg" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  : >"$PLUGIN_DATA_ROOT/demo/LINKS"
  run "$REPO_ROOT/subcommands/link" "shared-rabbitmq:link" "demo"
  [[ "$status" -ne 0 ]]
}

@test "unlink unsets RABBITMQ_URL on the app" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  printf 'myapp\n' >"$PLUGIN_DATA_ROOT/demo/LINKS"
  run "$REPO_ROOT/subcommands/unlink" "shared-rabbitmq:unlink" "demo" "myapp"
  [[ "$status" -eq 0 ]]
  run grep -c 'dokku config:unset --no-restart myapp RABBITMQ_URL' "$STUB_LOG"
  [[ "$output" -ge 1 ]]
}

@test "info errors when tenant is missing" {
  run "$REPO_ROOT/subcommands/info" "shared-rabbitmq:info" "ghost"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"does not exist"* ]]
}

@test "info prints human-readable fields for an existing tenant" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  : >"$PLUGIN_DATA_ROOT/demo/LINKS"
  stub_response docker $'3\n4'
  run "$REPO_ROOT/subcommands/info" "shared-rabbitmq:info" "demo"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Name:"*"demo"* ]]
  [[ "$output" == *"Vhost:"*"demo"* ]]
  [[ "$output" == *"Messages:"*"7"* ]]
}

@test "set-quota parses the positional message count" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  run "$REPO_ROOT/subcommands/set-quota" "shared-rabbitmq:set-quota" "demo" "500"
  [[ "$status" -eq 0 ]]
  [[ "$(<"$PLUGIN_DATA_ROOT/demo/QUOTA_MSGS")" == "500" ]]
}

@test "set-quota errors without a count" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  run "$REPO_ROOT/subcommands/set-quota" "shared-rabbitmq:set-quota" "demo"
  [[ "$status" -ne 0 ]]
}

@test "unset-quota clears the override" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  printf '500' >"$PLUGIN_DATA_ROOT/demo/QUOTA_MSGS"
  run "$REPO_ROOT/subcommands/unset-quota" "shared-rabbitmq:unset-quota" "demo"
  [[ "$status" -eq 0 ]]
  [[ ! -f "$PLUGIN_DATA_ROOT/demo/QUOTA_MSGS" ]]
}

@test "check-quotas sweeps all tenants and flips the over-cap one" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  : >"$PLUGIN_DATA_ROOT/demo/LINKS"
  printf '10' >"$PLUGIN_DATA_ROOT/demo/QUOTA_MSGS"
  stub_response docker $'40'   # tenant_usage for demo
  stub_response docker ''      # set_permissions
  run "$REPO_ROOT/subcommands/check-quotas" "shared-rabbitmq:check-quotas"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"flipped"* ]]
  [[ -f "$PLUGIN_DATA_ROOT/demo/QUOTA_VIOLATED" ]]
}

@test "connect --print-only prints the docker exec command and the vhost" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  run "$REPO_ROOT/subcommands/connect" "shared-rabbitmq:connect" "demo" "--print-only"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"docker exec -it dokku-shared-rabbitmq bash"* ]]
  [[ "$output" == *"demo"* ]]
}

@test "connect errors when tenant is missing" {
  run "$REPO_ROOT/subcommands/connect" "shared-rabbitmq:connect" "ghost" "--print-only"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"does not exist"* ]]
}

@test "export errors with stretch-goal message and non-zero exit" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  run "$REPO_ROOT/subcommands/export" "shared-rabbitmq:export" "demo"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"v0.2 stretch goal"* ]]
}

@test "import errors with stretch-goal message and non-zero exit" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  run "$REPO_ROOT/subcommands/import" "shared-rabbitmq:import" "demo"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"not implemented in v0.1.0"* ]]
}

@test "commands dispatcher routes unknown subcommand to error" {
  run "$REPO_ROOT/commands" "shared-rabbitmq:does-not-exist"
  [[ "$status" -ne 0 ]]
}
