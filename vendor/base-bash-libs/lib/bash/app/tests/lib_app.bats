#!/usr/bin/env bats

load ../../tests/test_helper.sh

setup() {
    setup_test_tmpdir
    source "$BASE_BASH_DIR/std/lib_std.sh"
    source "$BASE_BASH_DIR/cli/lib_cli.sh"
    source "$BASE_BASH_DIR/app/lib_app.sh"
    unset APP_TEST_MODE APP_TEST_SECRET
}

declare_test_config() {
    base_app_init demo name=demo
    base_app_config_define demo mode enum enum=dev,prod default=dev env=APP_TEST_MODE
    base_app_config_define demo secret string required=true secret=true env=APP_TEST_SECRET
}

@test "lib_app requires stdlib and loads cli from the package" {
    bats_run "$BASH" -c 'source "$1"' bash "$BASE_BASH_DIR/app/lib_app.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"lib_app.sh requires lib_std.sh"* ]]

    bats_run "$BASH" -c 'source "$1"; source "$2"; type -t base_cli_model_init' bash "$BASE_BASH_DIR/std/lib_std.sh" "$BASE_BASH_DIR/app/lib_app.sh"
    [ "$status" -eq 0 ]
    [ "$output" = function ]
}

@test "configuration precedence and provenance are deterministic" {
    local user_file="$TEST_TMPDIR/user.conf" project_file="$TEST_TMPDIR/project.conf" value source
    declare_test_config
    printf 'mode=dev\n' >"$user_file"
    printf 'mode=prod\n' >"$project_file"
    export APP_TEST_MODE=dev
    base_app_config_set_cli demo secret cli-secret

    base_app_config_load demo --user "$user_file" --project "$project_file" --cli mode=dev
    base_app_config_get demo mode value
    base_app_config_provenance demo mode source
    [ "$value" = dev ]
    [ "$source" = cli ]
    base_app_config_get demo secret value
    [ "$value" = cli-secret ]
}

@test "configuration files are data and reject malformed or unknown records" {
    local config_file="$TEST_TMPDIR/config.conf"
    declare_test_config
    printf 'mode=dev\nnot-a-record\n' >"$config_file"
    bats_run base_app_config_load demo --project "$config_file"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not key=value data"* ]]

    printf 'unknown=value\n' >"$config_file"
    bats_run base_app_config_load demo --project "$config_file"
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown key 'unknown'"* ]]
    ! grep -Eq '(^|[[:space:];])eval([[:space:];]|$)' "$BASE_BASH_DIR/app/lib_app.sh"
}

@test "missing required configuration and explicitly requested files fail clearly" {
    declare_test_config
    bats_run base_app_config_load demo
    [ "$status" -eq 2 ]
    [[ "$output" == *"required configuration 'secret'"* ]]

    bats_run base_app_config_load demo --project "$TEST_TMPDIR/missing.conf"
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not exist"* ]]
}

@test "effective reports redact secrets and retain provenance" {
    declare_test_config
    export APP_TEST_MODE=prod APP_TEST_SECRET=top-secret
    base_app_config_load demo
    bats_run base_app_config_report demo
    [ "$status" -eq 0 ]
    [[ "$output" == *$'mode\tenvironment\tprod'* ]]
    [[ "$output" == *$'secret\tenvironment\t<redacted>'* ]]
    [[ "$output" != *"top-secret"* ]]
}

@test "effective report escapes field delimiters in non-secret values" {
    base_app_init report name=report
    base_app_config_define report message string default='unused'
    base_app_config_set_cli report message $'line\twith\nseparators'
    base_app_config_load report

    bats_run base_app_config_report report

    [ "$status" -eq 0 ]
    [[ "$output" == *$'message\tcli\tline\\twith\\nseparators'* ]]
    [ "$(printf '%s\n' "$output" | awk 'END { print NR }')" -eq 1 ]
}

@test "standard options publish opt-in policy and noninteractive prompts are denied" {
    base_cli_model_init demo name=demo
    base_cli_command demo run "Run"
    base_app_init policy
    base_app_add_standard_options demo run
    base_cli_parse demo -- run --dry-run --non-interactive --color never
    base_app_apply_standard_options policy
    [ "$BASE_BASH_LIBS_APP_DRY_RUN" -eq 1 ]
    [ "$BASE_BASH_LIBS_APP_NONINTERACTIVE" -eq 1 ]
    [ "$BASE_BASH_LIBS_APP_COLOR" = never ]
    ! base_app_should_prompt policy
}

@test "lifecycle hooks run LIFO exactly once and preserve handler status" {
    local events=()
    first_hook() { events+=("$1:$2:first"); }
    second_hook() { events+=("$1:$2:second"); }
    cleanup_hook() { events+=("$1:$2:cleanup"); }
    failing_handler() { return 7; }
    base_app_init lifecycle
    base_app_hook lifecycle fatal first first_hook
    base_app_hook lifecycle fatal second second_hook
    base_app_hook lifecycle cleanup cleanup cleanup_hook

    set +e
    base_app_run lifecycle failing_handler
    status=$?
    set -e
    [ "$status" -eq 7 ]
    [ "${events[*]}" = "fatal:7:second fatal:7:first cleanup:7:cleanup" ]
    set +e
    base_app_run lifecycle failing_handler
    status=$?
    set -e
    [ "$status" -eq 7 ]
}

@test "source is idempotent" {
    source "$BASE_BASH_DIR/app/lib_app.sh"
    [ "$(type -t base_app_run)" = function ]
}
