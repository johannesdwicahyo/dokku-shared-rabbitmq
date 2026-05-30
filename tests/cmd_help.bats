#!/usr/bin/env bats
load test_helper

setup() {
  setup_plugin_env
}

@test "subcommands/help prints usage with all subcommands" {
  run "$REPO_ROOT/subcommands/help" "shared-rabbitmq:help"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage: dokku shared-rabbitmq:"* ]]
  for cmd in create destroy link unlink list info connect set-quota unset-quota check-quotas export import help; do
    [[ "$output" == *"shared-rabbitmq:$cmd"* ]] || {
      echo "missing command in help output: $cmd"
      return 1
    }
  done
}

@test "commands dispatcher routes :help to subcommands/help" {
  run "$REPO_ROOT/commands" "shared-rabbitmq:help"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage: dokku shared-rabbitmq:"* ]]
}

@test "commands dispatcher routes a known subcommand" {
  run "$REPO_ROOT/commands" "shared-rabbitmq:list"
  [[ "$status" -eq 0 ]]
}

@test "commands dispatcher errors on unknown subcommand" {
  run "$REPO_ROOT/commands" "shared-rabbitmq:does-not-exist"
  [[ "$status" -ne 0 ]]
}

@test "help mentions the vhost-isolation note" {
  run "$REPO_ROOT/subcommands/help" "shared-rabbitmq:help"
  [[ "$output" == *"vhost"* ]]
}
