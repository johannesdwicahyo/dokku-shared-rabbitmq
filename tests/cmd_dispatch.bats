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
