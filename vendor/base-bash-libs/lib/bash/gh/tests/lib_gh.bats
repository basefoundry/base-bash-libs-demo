#!/usr/bin/env bats

load ../../tests/test_helper.sh

setup() {
    setup_test_tmpdir
    export TEST_TMPDIR
    mkdir -p "$TEST_TMPDIR/bin"
    PATH="$TEST_TMPDIR/bin:$BASE_TEST_ORIG_PATH"
    source "$BASE_BASH_DIR/std/lib_std.sh"
    declare -a setup_args=()
    base_init setup_args --source "$BASE_BASH_DIR/gh/tests/lib_gh.bats" --
    source "$BASE_BASH_DIR/gh/lib_gh.sh"
}

create_fake_gh() {
    local script="$TEST_TMPDIR/bin/gh"

    cat > "$script"
    chmod +x "$script"
}

create_fake_git() {
    local script="$TEST_TMPDIR/bin/git"

    cat > "$script"
    chmod +x "$script"
}

# Deterministic retry seams. Individual tests configure the fixture globals or
# replace one seam for a narrower assertion. No retry test needs wall-clock
# sleeps or a live GitHub process.
install_gh_api_retry_fixture() {
    TEST_GH_API_CLOCK=0
    TEST_GH_API_EPOCH=2000000000
    TEST_GH_API_ATTEMPT_DURATION=0
    TEST_GH_API_SUCCESS_AFTER=2
    TEST_GH_API_FAILURE_STATUS=1
    TEST_GH_API_FAILURE_STDOUT=""
    TEST_GH_API_FAILURE_STDERR=$'Get "https://api.github.test/repos/owner/repo": read tcp 127.0.0.1:443->127.0.0.2:1234: read: connection reset by peer\n'
    TEST_GH_API_SUCCESS_STDOUT=$'ok\n'
    TEST_GH_API_SUCCESS_STDERR=""
    TEST_GH_API_OBSERVATION_DIR="$TEST_TMPDIR/gh-api-observations"
    mkdir -p "$TEST_GH_API_OBSERVATION_DIR"
    TEST_GH_API_ATTEMPT_COUNT_FILE="$TEST_GH_API_OBSERVATION_DIR/attempt-count"
    TEST_GH_API_SLEEP_CALLS_FILE="$TEST_GH_API_OBSERVATION_DIR/sleep-calls"
    TEST_GH_API_TIMEOUT_CALLS_FILE="$TEST_GH_API_OBSERVATION_DIR/timeout-calls"
    TEST_GH_API_TIMEOUT_PATHS_FILE="$TEST_GH_API_OBSERVATION_DIR/timeout-paths"
    TEST_GH_API_JITTER_CALLS_FILE="$TEST_GH_API_OBSERVATION_DIR/jitter-calls"
    TEST_GH_API_CAPTURE_MODE_FILE="$TEST_GH_API_OBSERVATION_DIR/capture-mode"
    TEST_GH_API_FIRST_ARG_FILE="$TEST_GH_API_OBSERVATION_DIR/first-api-arg"
    printf '0' > "$TEST_GH_API_ATTEMPT_COUNT_FILE"
    : > "$TEST_GH_API_SLEEP_CALLS_FILE"
    : > "$TEST_GH_API_TIMEOUT_CALLS_FILE"
    : > "$TEST_GH_API_TIMEOUT_PATHS_FILE"
    : > "$TEST_GH_API_JITTER_CALLS_FILE"
    : > "$TEST_GH_API_CAPTURE_MODE_FILE"
    : > "$TEST_GH_API_FIRST_ARG_FILE"

    gh() { return 0; }
    __base_bash_libs_gh_api_monotonic_seconds__() {
        printf -v "$1" '%s' "$TEST_GH_API_CLOCK"
    }
    __base_bash_libs_gh_api_epoch_seconds__() {
        printf -v "$1" '%s' "$TEST_GH_API_EPOCH"
    }
    __base_bash_libs_gh_api_jitter_seconds__() {
        local result_name="$1" cap="$2" delay=0
        gh_api_append_observation "$TEST_GH_API_JITTER_CALLS_FILE" "$cap"
        ((cap == 0)) || delay=$(((cap + 1) / 2))
        printf -v "$result_name" '%s' "$delay"
    }
    __base_bash_libs_gh_api_sleep__() {
        gh_api_append_observation "$TEST_GH_API_SLEEP_CALLS_FILE" "$1"
        TEST_GH_API_CLOCK=$((TEST_GH_API_CLOCK + $1))
    }
    __base_bash_libs_gh_api_attempt__() {
        local attempt_timeout="$1" attempt_timeout_path="$2"
        local stdout_file="$4" stderr_file="$5" attempt_count=0
        local fixture_arg fixture_include=0 fixture_stdout fixture_stderr

        for fixture_arg in "${@:6}"; do
            case "$fixture_arg" in
                --include | -i) fixture_include=1 ;;
            esac
        done

        IFS= read -r attempt_count < "$TEST_GH_API_ATTEMPT_COUNT_FILE"
        attempt_count=$((attempt_count + 1))
        printf '%s' "$attempt_count" > "$TEST_GH_API_ATTEMPT_COUNT_FILE"
        gh_api_append_observation "$TEST_GH_API_TIMEOUT_CALLS_FILE" "$attempt_timeout"
        gh_api_append_observation "$TEST_GH_API_TIMEOUT_PATHS_FILE" \
            "${attempt_timeout_path:-empty}"
        printf '%s' "${6-}" > "$TEST_GH_API_FIRST_ARG_FILE"
        TEST_GH_API_CLOCK=$((TEST_GH_API_CLOCK + TEST_GH_API_ATTEMPT_DURATION))
        : > "$stdout_file"
        : > "$stderr_file"
        if ((attempt_count >= TEST_GH_API_SUCCESS_AFTER)); then
            fixture_stdout="$TEST_GH_API_SUCCESS_STDOUT"
            fixture_stderr="$TEST_GH_API_SUCCESS_STDERR"
        else
            fixture_stdout="$TEST_GH_API_FAILURE_STDOUT"
            fixture_stderr="$TEST_GH_API_FAILURE_STDERR"
        fi
        if ((fixture_include)) && [[ -n "$fixture_stdout" && "$fixture_stdout" != HTTP/* ]]; then
            printf 'HTTP/2.0 200 OK\r\n\r\n' > "$stdout_file"
        fi
        printf '%s' "$fixture_stdout" >> "$stdout_file"
        printf '%s' "$fixture_stderr" > "$stderr_file"
        ((attempt_count >= TEST_GH_API_SUCCESS_AFTER)) && return 0
        return "$TEST_GH_API_FAILURE_STATUS"
    }
}

gh_api_append_observation() {
    local observation_file="$1" observation_value="$2"

    [[ ! -s "$observation_file" ]] || printf ',' >> "$observation_file"
    printf '%s' "$observation_value" >> "$observation_file"
}

gh_api_retry_observed() {
    local observation_file

    case "$1" in
        attempts) observation_file="$TEST_GH_API_ATTEMPT_COUNT_FILE" ;;
        capture-mode) observation_file="$TEST_GH_API_CAPTURE_MODE_FILE" ;;
        first-arg) observation_file="$TEST_GH_API_FIRST_ARG_FILE" ;;
        jitter) observation_file="$TEST_GH_API_JITTER_CALLS_FILE" ;;
        sleeps) observation_file="$TEST_GH_API_SLEEP_CALLS_FILE" ;;
        timeout-paths) observation_file="$TEST_GH_API_TIMEOUT_PATHS_FILE" ;;
        timeouts) observation_file="$TEST_GH_API_TIMEOUT_CALLS_FILE" ;;
        *) return 1 ;;
    esac
    command cat -- "$observation_file"
}

@test "lib_gh can be sourced more than once" {
    source "$BASE_BASH_DIR/gh/lib_gh.sh"

    [ "$(type -t base_gh_run)" = "function" ]
}

@test "lib_gh fails clearly when sourced without stdlib" {
    bats_run bash -c 'source "$1"; rc=$?; printf "source-rc=%s\n" "$rc"; exit "$rc"' bash "$BASE_BASH_DIR/gh/lib_gh.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"lib_gh.sh requires lib_std.sh to be sourced first"* ]]
    [[ "$output" == *"source-rc=1"* ]]
    [[ "$output" != *"command not found"* ]]
}

@test "GitHub required-argument APIs return usage errors under every caller option combination" {
    local function_name mode

    for mode in off e u p eu ep up eup; do
        for function_name in \
            base_gh_report_command_failure \
            base_gh_repo_from_remote_url \
            base_gh_infer_repo_from_origin \
            base_gh_repo_default_branch; do
            bats_run "$BASH" -c '
                mode="$1"
                case "$mode" in *e*) set -e ;; esac
                case "$mode" in *u*) set -u ;; esac
                case "$mode" in *p*) set -o pipefail ;; esac
                source "$2"
                declare -a app_args=()
                base_init app_args --
                source "$3"
                "$4"
                rc=$?
                exit "$rc"
            ' bash "$mode" "$BASE_BASH_DIR/std/lib_std.sh" "$BASE_BASH_DIR/gh/lib_gh.sh" "$function_name"

            [ "$status" -eq 2 ]
            [[ "$output" == *"Usage:"* ]]
            [[ "$output" != *"unbound variable"* ]]
        done
    done
}

@test "GitHub optional forms reject excess arguments and invalid values" {
    capture_command base_gh_require_cli one two
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage: base_gh_require_cli [install_hint]"* ]]

    capture_command base_gh_auth_status_diagnostics one two
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage: base_gh_auth_status_diagnostics [login_hint]"* ]]

    capture_command base_gh_infer_repo_from_origin repo result --required
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage: base_gh_infer_repo_from_origin <repo_dir> <result_variable_name> [--optional]"* ]]

    capture_command base_gh_report_command_failure invalid issue list
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage: base_gh_report_command_failure <status> [gh args...]"* ]]

    capture_command base_gh_report_command_failure 0 issue list
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage: base_gh_report_command_failure <status> [gh args...]"* ]]

    capture_command base_gh_report_command_failure 256 issue list
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage: base_gh_report_command_failure <status> [gh args...]"* ]]
}

@test "GitHub sensitive controls fail closed before executing or echoing malformed arguments" {
    local secret="parser-canary with spaces"
    local unicode_label=$'unicode-label-canary\xe2\x80\xa8\xe2\x80\xae'
    local invocation_file="$TEST_TMPDIR/parser-invoked"

    create_fake_gh <<'EOF'
#!/usr/bin/env bash
printf 'invoked\n' > "${TEST_TMPDIR:?}/parser-invoked"
exit 0
EOF

    capture_command base_gh_run --sensitive "--opaque=$secret" -- issue list
    [ "$status" -eq 2 ]
    [[ "$output" == *"protected diagnostic controls must end with --"* ]]
    [[ "$output" != *"$secret"* ]]

    capture_command base_gh_api_with_retry --safe-display "safe API operation" -- repos/owner/repo
    [ "$status" -eq 2 ]
    [[ "$output" == *"--safe-display is valid only with --sensitive"* ]]

    capture_command base_gh_run --sensitive --safe-display "--token=$secret" -- issue list
    [ "$status" -eq 2 ]
    [[ "$output" == *"one non-empty printable ASCII label"* ]]
    [[ "$output" != *"$secret"* ]]

    capture_command base_gh_run --sensitive --safe-display "-H$secret" -- issue list
    [ "$status" -eq 2 ]
    [[ "$output" == *"one non-empty printable ASCII label"* ]]
    [[ "$output" != *"$secret"* ]]

    capture_command base_gh_api_with_retry --sensitive --safe-display "-fsecret=$secret" -- repos/owner/repo
    [ "$status" -eq 2 ]
    [[ "$output" == *"one non-empty printable ASCII label"* ]]
    [[ "$output" != *"$secret"* ]]

    capture_command base_gh_run --sensitive --safe-display "$unicode_label" -- issue list
    [ "$status" -eq 2 ]
    [[ "$output" == *"one non-empty printable ASCII label"* ]]
    [[ "$output" != *"unicode-label-canary"* ]]

    capture_command base_gh_report_command_failure --sensitive 77 issue list
    [ "$status" -eq 2 ]
    [[ "$output" == *"protected diagnostic controls must end with --"* ]]

    capture_command base_gh_report_command_failure --sensitive -- "status=$secret" issue list
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage: base_gh_report_command_failure"* ]]
    [[ "$output" != *"$secret"* ]]

    capture_command base_gh_run --sensitive --safe-display $'unsafe\nparser-secret' -- issue list
    [ "$status" -eq 2 ]
    [[ "$output" == *"one non-empty printable ASCII label"* ]]
    [[ "$output" != *"parser-secret"* ]]
    [ ! -e "$invocation_file" ]
}

@test "GitHub diagnostics are independent of and preserve caller IFS" {
    local output_file="$TEST_TMPDIR/auth-diagnostics.out"
    local rc

    create_fake_gh <<'EOF'
#!/usr/bin/env bash
printf 'first diagnostic\nsecond diagnostic\n' >&2
exit 4
EOF

    IFS=:
    if base_gh_auth_status_diagnostics >"$output_file" 2>&1; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 1 ]
    [ "$IFS" = ":" ]
    [[ "$(cat "$output_file")" == *"gh auth status: first diagnostic"* ]]
    [[ "$(cat "$output_file")" == *"gh auth status: second diagnostic"* ]]
}

@test "base_gh_run preserves command status under every caller option combination" {
    local mode

    create_fake_gh <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
    printf 'not logged in\n' >&2
    exit 1
fi
printf 'command failed\n' >&2
exit 7
EOF

    for mode in off e u p eu ep up eup; do
        bats_run "$BASH" -c '
            mode="$1"
            case "$mode" in *e*) set -e ;; esac
            case "$mode" in *u*) set -u ;; esac
            case "$mode" in *p*) set -o pipefail ;; esac
            source "$2"
            declare -a app_args=()
            base_init app_args --
            source "$3"
            PATH="$4:$PATH"
            base_gh_run issue list
            rc=$?
            exit "$rc"
        ' bash "$mode" "$BASE_BASH_DIR/std/lib_std.sh" "$BASE_BASH_DIR/gh/lib_gh.sh" "$TEST_TMPDIR/bin"

        [ "$status" -eq 7 ]
        [[ "$output" == *"GitHub command failed: gh issue list"* ]]
        [[ "$output" != *"unbound variable"* ]]

        bats_run "$BASH" -c '
            mode="$1"
            case "$mode" in *e*) set -e ;; esac
            case "$mode" in *u*) set -u ;; esac
            case "$mode" in *p*) set -o pipefail ;; esac
            source "$2"
            declare -a app_args=()
            base_init app_args --
            source "$3"
            PATH="$4:$PATH"
            base_gh_run --sensitive --safe-display "strict protected operation" -- issue list
            rc=$?
            exit "$rc"
        ' bash "$mode" "$BASE_BASH_DIR/std/lib_std.sh" "$BASE_BASH_DIR/gh/lib_gh.sh" "$TEST_TMPDIR/bin"

        [ "$status" -eq 7 ]
        [[ "$output" == *"strict protected operation [sensitive GitHub operation; arguments hidden]"* ]]
        [[ "$output" == *"(exit 7)"* ]]
        [[ "$output" != *"gh auth status: not logged in"* ]]
        [[ "$output" != *"unbound variable"* ]]
    done
}

@test "base_gh_require_cli succeeds when gh is on PATH" {
    create_fake_gh <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

    capture_command base_gh_require_cli

    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "GitHub pass-by-name helpers reject readonly result variables" {
    local repo="sentinel"
    local stderr_file="$TEST_TMPDIR/gh-readonly-output.err"
    local rc

    readonly repo
    if base_gh_repo_from_remote_url "https://github.com/owner/project.git" repo 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 2 ]
    [ "$repo" = "sentinel" ]
    [[ "$(cat "$stderr_file")" == *"result variable 'repo' is readonly"* ]]
}

@test "GitHub result helpers reject exact internal holder names before locals or mutation" {
    local -r __base_bash_libs_gh_result_name=parsed
    local -r __base_bash_libs_gh_infer_result_name=inferred
    local -r __base_bash_libs_gh_repo_result_name=defaulted
    local parsed="keep-parsed" inferred="keep-inferred" defaulted="keep-defaulted"
    local stderr_file="$TEST_TMPDIR/gh-internal-holder.err"
    local rc

    if base_gh_repo_from_remote_url "https://github.com/owner/project.git" __base_bash_libs_gh_result_name 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 2 ]
    [ "$parsed" = "keep-parsed" ]

    if base_gh_infer_repo_from_origin . __base_bash_libs_gh_infer_result_name --optional 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 2 ]
    [ "$inferred" = "keep-inferred" ]

    if base_gh_repo_default_branch owner/project __base_bash_libs_gh_repo_result_name 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 2 ]
    [ "$defaulted" = "keep-defaulted" ]
    [[ "$(cat "$stderr_file")" == *"uses the reserved '__' internal namespace"* ]]
    [[ "$(cat "$stderr_file")" != *"readonly variable"* ]]
}

@test "base_gh_require_cli reports missing gh with caller hint" {
    mkdir -p "$TEST_TMPDIR/no-gh-bin"

    bats_run "$BASH" -c '
        source "$1"
        declare -a app_args=()
        base_init app_args --
        source "$2"
        PATH="$3"
        base_gh_require_cli "$4"
    ' bash "$BASE_BASH_DIR/std/lib_std.sh" "$BASE_BASH_DIR/gh/lib_gh.sh" "$TEST_TMPDIR/no-gh-bin" "Install GitHub CLI and retry."

    [ "$status" -eq 1 ]
    [[ "$output" == *"Required command 'gh' was not found on PATH."* ]]
    [[ "$output" == *"Install GitHub CLI and retry."* ]]
}

@test "base_gh_auth_status_diagnostics reports bounded auth output and hint" {
    create_fake_gh <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then
    printf 'auth failed\n' >&2
    printf 'run login\n' >&2
    exit 4
fi
exit 0
EOF

    capture_command base_gh_auth_status_diagnostics "Run a custom login command."

    [ "$status" -eq 1 ]
    [[ "$output" == *"gh auth status: auth failed"* ]]
    [[ "$output" == *"gh auth status: run login"* ]]
    [[ "$output" == *"Run a custom login command."* ]]
}

@test "base_gh_run passes through successful gh output" {
    create_fake_gh <<'EOF'
#!/usr/bin/env bash
printf 'gh args:'
printf ' <%s>' "$@"
printf '\n'
EOF

    capture_command base_gh_run issue list --repo owner/repo

    [ "$status" -eq 0 ]
    [[ "$output" == *"gh args: <issue> <list> <--repo> <owner/repo>"* ]]
}

@test "base_gh_run reports command failure and auth diagnostics" {
    create_fake_gh <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then
    printf 'not logged in\n' >&2
    exit 1
fi
printf 'command failed\n' >&2
exit 7
EOF

    capture_command base_gh_run issue create --title Example

    [ "$status" -eq 7 ]
    [[ "$output" == *"command failed"* ]]
    [[ "$output" == *"GitHub command failed: gh issue create --title Example"* ]]
    [[ "$output" == *"gh auth status: not logged in"* ]]
    [[ "$output" == *"Run 'gh auth login -h github.com' and retry."* ]]
}

@test "base_gh_run sensitive diagnostics hide every argv form and nested auth output from all log sinks" {
    local secret="gh-run-canary with spaces"
    local primary_log="$TEST_TMPDIR/gh-run-sensitive.log"
    local received_args="$TEST_TMPDIR/gh-run-sensitive.args"
    local primary_content

    export GH_TEST_SECRET="$secret"
    BASE_BASH_LIBS_PRIMARY_LOG="$primary_log"
    create_fake_gh <<'EOF'
#!/usr/bin/env bash
if [[ "${1-}" == "auth" && "${2-}" == "status" ]]; then
    printf 'auth diagnostic exposed %s\n' "${GH_TEST_SECRET:?}" >&2
    exit 4
fi
printf '<%s>\n' "$@" > "${TEST_TMPDIR:?}/gh-run-sensitive.args"
exit 73
EOF

    capture_command base_gh_run --sensitive --safe-display "create protected issue" -- \
        api graphql \
        "spaced value $secret" \
        "--option=$secret" \
        --header "Authorization: Bearer $secret" \
        "https://user:$secret@github.example.test/resource" \
        --field "token=$secret"

    [ "$status" -eq 73 ]
    [[ "$output" == *"create protected issue [sensitive GitHub operation; arguments hidden]"* ]]
    [[ "$output" == *"GitHub command failed:"* ]]
    [[ "$output" == *"(exit 73)"* ]]
    [[ "$output" == *"raw auth diagnostics hidden"* ]]
    [[ "$output" == *"Run 'gh auth login -h github.com' and retry."* ]]
    [[ "$output" != *"$secret"* ]]
    [[ "$(cat "$received_args")" == *"$secret"* ]]

    primary_content="$(cat "$primary_log")"
    [[ "$primary_content" == *"create protected issue"* ]]
    [[ "$primary_content" == *"(exit 73)"* ]]
    [[ "$primary_content" == *"raw auth diagnostics hidden"* ]]
    [[ "$primary_content" != *"$secret"* ]]
}

@test "base_gh_run locks sensitive diagnostics against a dynamically scoped gh function" {
    local secret="dynamic-scope-gh-canary"

    gh() {
        if [[ "${1-}" == "auth" && "${2-}" == "status" ]]; then
            printf 'auth diagnostic exposed %s\n' "$secret" >&2
            return 4
        fi
        __base_bash_libs_gh_run_sensitive=0
        __base_bash_libs_gh_run_safe_display=""
        return 67
    }

    capture_command base_gh_run --sensitive --safe-display "protected function call" -- \
        api graphql --header "Authorization: Bearer $secret"
    unset -f gh

    [ "$status" -eq 67 ]
    [[ "$output" == *"protected function call [sensitive GitHub operation; arguments hidden]"* ]]
    [[ "$output" == *"(exit 67)"* ]]
    [[ "$output" == *"raw auth diagnostics hidden"* ]]
    [[ "$output" != *"$secret"* ]]
}

@test "base_gh_report_command_failure accepts control-first sensitive reporting through status 255" {
    local secret="public-reporter-canary"

    export GH_TEST_SECRET="$secret"
    create_fake_gh <<'EOF'
#!/usr/bin/env bash
if [[ "${1-}" == "auth" && "${2-}" == "status" ]]; then
    printf 'auth diagnostic exposed %s\n' "${GH_TEST_SECRET:?}" >&2
    exit 4
fi
exit 99
EOF

    capture_command base_gh_report_command_failure \
        --sensitive --safe-display "publish protected release" -- \
        255 api repos/owner/repo --header "Authorization: Bearer $secret"

    [ "$status" -eq 255 ]
    [[ "$output" == *"publish protected release [sensitive GitHub operation; arguments hidden]"* ]]
    [[ "$output" == *"(exit 255)"* ]]
    [[ "$output" == *"raw auth diagnostics hidden"* ]]
    [[ "$output" != *"$secret"* ]]
    [[ "$output" != *"--header"* ]]
}

@test "base_gh_run reports command failure under set -e" {
    local script="$TEST_TMPDIR/gh-run-set-e.sh"

    create_fake_gh <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then
    printf 'not logged in\n' >&2
    exit 1
fi
printf 'command failed\n' >&2
exit 7
EOF
    cat > "$script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$BASE_BASH_DIR/std/lib_std.sh"
declare -a app_args=()
base_init app_args --source "\${BASH_SOURCE[0]}" -- "\$@"
source "$BASE_BASH_DIR/gh/lib_gh.sh"
PATH="$TEST_TMPDIR/bin:$BASE_TEST_ORIG_PATH"
base_gh_run issue create --title Example
printf 'after\n'
EOF
    chmod +x "$script"

    bats_run bash "$script"

    [ "$status" -eq 7 ]
    [[ "$output" == *"command failed"* ]]
    [[ "$output" == *"GitHub command failed: gh issue create --title Example"* ]]
    [[ "$output" == *"gh auth status: not logged in"* ]]
    [[ "$output" != *"after"* ]]
}

@test "base_gh_run quotes arguments when reporting command failure" {
    create_fake_gh <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then
    exit 0
fi
exit 7
EOF

    bats_run base_gh_run issue create --title "Example Title" --body "body value"

    [ "$status" -eq 7 ]
    [[ "$output" == *"GitHub command failed: gh issue create --title Example\\ Title --body body\\ value"* ]]
    [[ "$output" == *"(exit 7)"* ]]
    [[ "$output" != *"GitHub command failed: gh issue create --title Example Title --body body value"* ]]
}

@test "base_gh_run returns 1 with an error when gh is not on PATH" {
    mkdir -p "$TEST_TMPDIR/no-gh-bin"

    bats_run "$BASH" -c '
        source "$1"
        declare -a app_args=()
        base_init app_args --
        source "$2"
        PATH="$3"
        base_gh_run issue list
    ' bash "$BASE_BASH_DIR/std/lib_std.sh" "$BASE_BASH_DIR/gh/lib_gh.sh" "$TEST_TMPDIR/no-gh-bin"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Required command 'gh' was not found on PATH."* ]]
    [[ "$output" != *"GitHub command failed"* ]]
    [[ "$output" != *"gh auth status"* ]]
}

@test "base_gh_repo_from_remote_url parses supported GitHub remotes" {
    local repo

    base_gh_repo_from_remote_url "git@github.com:owner/repo.git" repo
    [ "$repo" = "owner/repo" ]

    base_gh_repo_from_remote_url "git@github.com:owner/repo" repo
    [ "$repo" = "owner/repo" ]

    base_gh_repo_from_remote_url "ssh://git@github.com/owner/repo.git" repo
    [ "$repo" = "owner/repo" ]

    base_gh_repo_from_remote_url "https://github.com/owner/repo.git" repo
    [ "$repo" = "owner/repo" ]

    base_gh_repo_from_remote_url "https://github.com/owner/repo" repo
    [ "$repo" = "owner/repo" ]
}

@test "base_gh_repo_from_remote_url supports shadowing-prone output variable names" {
    local result_var=""
    local parsed_repo=""

    base_gh_repo_from_remote_url "https://github.com/owner/repo.git" result_var
    base_gh_repo_from_remote_url "git@github.com:other/project.git" parsed_repo

    [ "$result_var" = "owner/repo" ]
    [ "$parsed_repo" = "other/project" ]
}

@test "base_gh_repo_from_remote_url rejects non-GitHub and malformed remotes" {
    local repo="sentinel"

    bats_run base_gh_repo_from_remote_url "https://example.com/owner/repo.git" repo

    [ "$status" -eq 2 ]
    [ "$repo" = "sentinel" ]

    bats_run base_gh_repo_from_remote_url "https://github.com/owner" repo

    [ "$status" -eq 2 ]
    [ "$repo" = "sentinel" ]

    bats_run base_gh_repo_from_remote_url "ssh://git@github.com//repo.git" repo

    [ "$status" -eq 2 ]
    [ "$repo" = "sentinel" ]

    bats_run base_gh_repo_from_remote_url "https://github.com/owner/repo?query=1" repo

    [ "$status" -eq 2 ]
    [ "$repo" = "sentinel" ]
}

@test "base_gh_infer_repo_from_origin reads origin through git -C" {
    local repo_dir="$TEST_TMPDIR/repo"
    local repo=""

    init_git_repo "$repo_dir"
    git -C "$repo_dir" remote add origin "git@github.com:owner/repo.git"

    base_gh_infer_repo_from_origin "$repo_dir" repo

    [ "$repo" = "owner/repo" ]
}

@test "base_gh_infer_repo_from_origin supports inferred_repo as the result variable name" {
    local repo_dir="$TEST_TMPDIR/repo"
    local inferred_repo=""

    init_git_repo "$repo_dir"
    git -C "$repo_dir" remote add origin "git@github.com:owner/repo.git"

    base_gh_infer_repo_from_origin "$repo_dir" inferred_repo

    [ "$inferred_repo" = "owner/repo" ]
}

@test "base_gh_infer_repo_from_origin supports remote_url as the result variable name" {
    local repo_dir="$TEST_TMPDIR/repo"
    local remote_url=""

    init_git_repo "$repo_dir"
    git -C "$repo_dir" remote add origin "git@github.com:owner/repo.git"

    base_gh_infer_repo_from_origin "$repo_dir" remote_url

    [ "$remote_url" = "owner/repo" ]
}

@test "base_gh_infer_repo_from_origin supports its former internal parsed name as the result variable" {
    local repo_dir="$TEST_TMPDIR/repo"
    local gh_infer_parsed_repo=""

    init_git_repo "$repo_dir"
    git -C "$repo_dir" remote add origin "git@github.com:owner/repo.git"

    base_gh_infer_repo_from_origin "$repo_dir" gh_infer_parsed_repo

    [ "$gh_infer_parsed_repo" = "owner/repo" ]
}

@test "base_gh_infer_repo_from_origin returns empty success for non-GitHub remotes when optional" {
    local repo_dir="$TEST_TMPDIR/repo"
    local repo="sentinel"

    init_git_repo "$repo_dir"
    git -C "$repo_dir" remote add origin "https://example.com/owner/repo.git"

    base_gh_infer_repo_from_origin "$repo_dir" repo --optional

    [ "$repo" = "" ]
}

@test "base_gh_infer_repo_from_origin logs non-optional inference failures" {
    local repo_dir="$TEST_TMPDIR/repo"
    local repo="sentinel"

    init_git_repo "$repo_dir"
    git -C "$repo_dir" remote add origin "https://example.com/owner/repo.git"

    bats_run base_gh_infer_repo_from_origin "$repo_dir" repo

    [ "$status" -eq 1 ]
    [ "$repo" = "sentinel" ]
    [[ "$output" == *"Could not infer GitHub repository from '$repo_dir' origin remote."* ]]
}

@test "base_gh_repo_default_branch reads GitHub repository default branch" {
    local branch=""

    create_fake_gh <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "repo" && "$2" == "view" ]]; then
    printf 'develop\n'
    exit 0
fi
exit 99
EOF

    base_gh_repo_default_branch "owner/repo" branch

    [ "$branch" = "develop" ]
}

@test "base_gh_repo_default_branch supports default_branch as the result variable name" {
    local default_branch=""

    create_fake_gh <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "repo" && "$2" == "view" ]]; then
    printf 'develop\n'
    exit 0
fi
exit 99
EOF

    base_gh_repo_default_branch "owner/repo" default_branch

    [ "$default_branch" = "develop" ]
}

@test "base_gh_repo_default_branch supports remote_default_branch as the result variable name" {
    local remote_default_branch=""

    create_fake_gh <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "repo" && "$2" == "view" ]]; then
    printf 'develop\n'
    exit 0
fi
exit 99
EOF

    base_gh_repo_default_branch "owner/repo" remote_default_branch

    [ "$remote_default_branch" = "develop" ]
}

@test "base_gh_repo_default_branch supports status as the result variable name" {
    local status=""

    create_fake_gh <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "repo" && "$2" == "view" ]]; then
    printf 'develop\n'
    exit 0
fi
exit 99
EOF

    base_gh_repo_default_branch "owner/repo" status

    [ "$status" = "develop" ]
}

@test "base_gh_api_with_retry rejects malformed controls before execution without echoing values" {
    local secret="retry-control-canary"
    local invocation_file="$TEST_TMPDIR/gh-api-control-invoked"

    gh() {
        printf 'invoked\n' > "$invocation_file"
    }

    capture_command base_gh_api_with_retry --retry-policy "$secret" -- repos/owner/repo
    [ "$status" -eq 2 ]
    [[ "$output" != *"$secret"* ]]

    capture_command base_gh_api_with_retry --max-attempts 0 -- repos/owner/repo
    [ "$status" -eq 2 ]
    capture_command base_gh_api_with_retry --max-attempts 2 --max-attempts 3 -- repos/owner/repo
    [ "$status" -eq 2 ]
    capture_command base_gh_api_with_retry --base-delay-seconds 5 --max-delay-seconds 4 -- repos/owner/repo
    [ "$status" -eq 2 ]
    capture_command base_gh_api_with_retry --attempt-timeout-seconds 601 -- repos/owner/repo
    [ "$status" -eq 2 ]
    capture_command base_gh_api_with_retry --max-elapsed-seconds 3601 -- repos/owner/repo
    [ "$status" -eq 2 ]
    capture_command base_gh_api_with_retry --retry-policy read-only repos/owner/repo
    [ "$status" -eq 2 ]
    capture_command base_gh_api_with_retry --safe-display "safe operation" -- repos/owner/repo
    [ "$status" -eq 2 ]
    [ ! -e "$invocation_file" ]
}

@test "base_gh_api_with_retry ignores retired retry environment variables" {
    install_gh_api_retry_fixture
    export BASE_GH_API_MAX_ATTEMPTS=1
    export BASE_GH_API_RETRY_DELAY_SECONDS=59

    capture_command base_gh_api_with_retry repos/owner/repo

    [ "$status" -eq 0 ]
    [ "$(gh_api_retry_observed attempts)" -eq 2 ]
    [ "$(gh_api_retry_observed first-arg)" = "--include" ]
    [ "$(gh_api_retry_observed sleeps)" = "1" ]
    [[ "$output" == *"ok"* ]]
}

@test "base_gh_api_with_retry does not collide with unrelated readonly caller names" {
    local -r gh_api_capture_workspace="caller-workspace"
    local -r gh_api_hook_result="caller-hook"
    local -r gh_api_metadata_epoch="caller-epoch"

    install_gh_api_retry_fixture
    TEST_GH_API_FAILURE_STDOUT=$'HTTP/2.0 429 Too Many Requests\r\nX-RateLimit-Remaining: 0\r\nX-RateLimit-Reset: 2000000001\r\n\r\nbody\n'
    TEST_GH_API_FAILURE_STDERR=""

    capture_command base_gh_api_with_retry --max-attempts 2 \
        --max-elapsed-seconds 30 --max-delay-seconds 10 -- repos/owner/repo

    [ "$status" -eq 0 ]
    [ "$(gh_api_retry_observed attempts)" -eq 2 ]
    [ "$gh_api_capture_workspace" = "caller-workspace" ]
    [ "$gh_api_hook_result" = "caller-hook" ]
    [ "$gh_api_metadata_epoch" = "caller-epoch" ]
}

@test "GitHub API argv classification matches gh pflag value and cluster forms" {
    local method include stdin_backed file_backed graphql ambiguous

    __base_bash_libs_gh_api_classify_argv__ method include stdin_backed file_backed graphql ambiguous \
        repos/owner/repo -iXGET
    [ "$method" = "GET" ]
    [ "$include" -eq 1 ]
    [ "$ambiguous" -eq 0 ]

    __base_bash_libs_gh_api_classify_argv__ method include stdin_backed file_backed graphql ambiguous \
        repos/owner/repo --allow-escape-sequences
    [ "$method" = "GET" ]
    [ "$ambiguous" -eq 0 ]

    __base_bash_libs_gh_api_classify_argv__ method include stdin_backed file_backed graphql ambiguous \
        repos/owner/repo --include=TRUE --paginate=0
    [ "$include" -eq 1 ]
    [ "$ambiguous" -eq 0 ]

    __base_bash_libs_gh_api_classify_argv__ method include stdin_backed file_backed graphql ambiguous \
        -XiGET repos/owner/repo
    [ "$method" = "IGET" ]
    [ "$include" -eq 0 ]

    __base_bash_libs_gh_api_classify_argv__ method include stdin_backed file_backed graphql ambiguous \
        repos/owner/repo -ifkey=value
    [ "$method" = "POST" ]
    [ "$include" -eq 1 ]

    __base_bash_libs_gh_api_classify_argv__ method include stdin_backed file_backed graphql ambiguous \
        -fi repos/owner/repo
    [ "$method" = "POST" ]
    [ "$include" -eq 0 ]

    __base_bash_libs_gh_api_classify_argv__ method include stdin_backed file_backed graphql ambiguous \
        --method --include repos/owner/repo
    [ "$method" = "--INCLUDE" ]
    [ "$include" -eq 0 ]

    __base_bash_libs_gh_api_classify_argv__ method include stdin_backed file_backed graphql ambiguous \
        --input --include repos/owner/repo
    [ "$method" = "POST" ]
    [ "$include" -eq 0 ]
    [ "$file_backed" -eq 1 ]

    __base_bash_libs_gh_api_classify_argv__ method include stdin_backed file_backed graphql ambiguous \
        repos/owner/repo --method GET -XGET
    [ "$method" = "UNKNOWN" ]
    [ "$ambiguous" -eq 1 ]

    __base_bash_libs_gh_api_classify_argv__ method include stdin_backed file_backed graphql ambiguous \
        graphql --raw-field query=@-
    [ "$graphql" -eq 1 ]
    [ "$stdin_backed" -eq 0 ]
}

@test "base_gh_api_with_retry defaults to reads and requires replay-safe attestation for mutations and files" {
    install_gh_api_retry_fixture
    capture_command base_gh_api_with_retry repos/owner/repo
    [ "$status" -eq 0 ]
    [ "$(gh_api_retry_observed attempts)" -eq 2 ]

    install_gh_api_retry_fixture
    capture_command base_gh_api_with_retry repos/owner/repo --method POST
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]
    [[ "$output" == *"outcome may be unknown"* ]]

    install_gh_api_retry_fixture
    capture_command base_gh_api_with_retry repos/owner/repo -f key=value
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]

    install_gh_api_retry_fixture
    capture_command base_gh_api_with_retry graphql
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]

    install_gh_api_retry_fixture
    capture_command base_gh_api_with_retry --retry-policy never -- repos/owner/repo
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]

    install_gh_api_retry_fixture
    capture_command base_gh_api_with_retry repos/owner/repo --future-gh-flag
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]

    install_gh_api_retry_fixture
    capture_command base_gh_api_with_retry repos/owner/repo --input "$TEST_TMPDIR/stable.json"
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]

    install_gh_api_retry_fixture
    capture_command base_gh_api_with_retry --retry-policy replay-safe -- \
        repos/owner/repo --input "$TEST_TMPDIR/stable.json"
    [ "$status" -eq 0 ]
    [ "$(gh_api_retry_observed attempts)" -eq 2 ]
}

@test "base_gh_api_with_retry never retries stdin-backed requests even with replay-safe attestation" {
    local stdin_link="$TEST_TMPDIR/stdin-link" fifo_path="$TEST_TMPDIR/request.fifo"

    install_gh_api_retry_fixture
    capture_command base_gh_api_with_retry --retry-policy replay-safe -- repos/owner/repo --input -
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]
    [[ "$output" == *"may consume stdin"* ]]

    install_gh_api_retry_fixture
    capture_command base_gh_api_with_retry --retry-policy replay-safe -- repos/owner/repo -F payload=@-
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]

    install_gh_api_retry_fixture
    capture_command base_gh_api_with_retry --retry-policy replay-safe -- \
        repos/owner/repo -F payload=literal=@-
    [ "$status" -eq 0 ]
    [ "$(gh_api_retry_observed attempts)" -eq 2 ]

    install_gh_api_retry_fixture
    capture_command base_gh_api_with_retry --retry-policy replay-safe -- repos/owner/repo -f payload=@-
    [ "$status" -eq 0 ]
    [ "$(gh_api_retry_observed attempts)" -eq 2 ]

    ln -s /dev/stdin "$stdin_link"
    install_gh_api_retry_fixture
    if capture_command base_gh_api_with_retry --retry-policy replay-safe -- \
        repos/owner/repo --input "$stdin_link"; then
        :
    fi
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]

    install_gh_api_retry_fixture
    if capture_command base_gh_api_with_retry --retry-policy replay-safe -- \
        repos/owner/repo --input /dev/null; then
        :
    fi
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]

    mkfifo "$fifo_path"
    install_gh_api_retry_fixture
    if capture_command base_gh_api_with_retry --retry-policy replay-safe -- \
        repos/owner/repo --input "$fifo_path"; then
        :
    fi
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]
}

@test "base_gh_api_with_retry recognizes only the bounded transient HTTP and transport allowlists" {
    local code

    for code in 408 425 429 500 502 503 504; do
        install_gh_api_retry_fixture
        TEST_GH_API_FAILURE_STDOUT="HTTP/2 $code"$'\r\n\r\n'
        TEST_GH_API_FAILURE_STDERR=$'gh: response body text is not retry authority\n'
        capture_command base_gh_api_with_retry \
            --base-delay-seconds 0 --max-delay-seconds 120 -- \
            repos/owner/repo --include
        [ "$status" -eq 0 ]
        [ "$(gh_api_retry_observed attempts)" -eq 2 ]
    done

    install_gh_api_retry_fixture
    TEST_GH_API_FAILURE_STATUS=255
    TEST_GH_API_FAILURE_STDERR=$'Get "https://api.github.test/repos/owner/repo": dial tcp 127.0.0.1:443: connect: connection refused\n'
    capture_command base_gh_api_with_retry --base-delay-seconds 0 --max-delay-seconds 1 -- repos/owner/repo
    [ "$status" -eq 0 ]
    [ "$(gh_api_retry_observed attempts)" -eq 2 ]

    install_gh_api_retry_fixture
    TEST_GH_API_FAILURE_STDERR=$'error connecting to github.example.test\ncheck your internet connection or https://githubstatus.com\n'
    capture_command base_gh_api_with_retry --base-delay-seconds 0 --max-delay-seconds 1 -- repos/owner/repo
    [ "$status" -eq 0 ]
    [ "$(gh_api_retry_observed attempts)" -eq 2 ]

    for failure_text in \
        'gh: attacker body says connection reset by peer (HTTP 422)' \
        'Get "https://api.github.test/repos/owner/repo": tls: failed to verify certificate: x509: unknown authority' \
        $'Get "https://api.github.test/repos/owner/repo": read tcp a: read: connection reset by peer\ndebug trace'; do
        install_gh_api_retry_fixture
        TEST_GH_API_SUCCESS_AFTER=99
        TEST_GH_API_FAILURE_STDERR="$failure_text"$'\n'
        capture_command base_gh_api_with_retry repos/owner/repo
        [ "$status" -eq 1 ]
        [ "$(gh_api_retry_observed attempts)" -eq 1 ]
    done

    install_gh_api_retry_fixture
    TEST_GH_API_FAILURE_STATUS=124
    TEST_GH_API_FAILURE_STDERR=""
    capture_command base_gh_api_with_retry --base-delay-seconds 0 --max-delay-seconds 1 -- repos/owner/repo
    [ "$status" -eq 0 ]
    [ "$(gh_api_retry_observed attempts)" -eq 2 ]
}

@test "base_gh_api_with_retry injects structured status for ordinary reads and strips it exactly" {
    install_gh_api_retry_fixture
    TEST_GH_API_FAILURE_STDOUT=$'HTTP/2.0 503 Service Unavailable\r\nRetry-After: 0\r\n\r\nintermediate body\n'
    TEST_GH_API_FAILURE_STDERR=$'gh: service unavailable (HTTP 503)\n'
    TEST_GH_API_SUCCESS_STDOUT=$'HTTP/2.0 200 OK\r\nContent-Type: application/octet-stream\r\n\r\nfinal body\n'

    capture_command base_gh_api_with_retry \
        --base-delay-seconds 0 --max-delay-seconds 1 -- repos/owner/repo

    [ "$status" -eq 0 ]
    [ "$(gh_api_retry_observed attempts)" -eq 2 ]
    [[ "$output" == *"final body"* ]]
    [[ "$output" != *"HTTP/2.0 200"* ]]
    [[ "$output" != *"intermediate body"* ]]

    install_gh_api_retry_fixture
    TEST_GH_API_SUCCESS_AFTER=1
    TEST_GH_API_SUCCESS_STDOUT=$'HTTP/2.0 200 OK\r\nX-Test: café\r\n\r\nbyte-exact body'
    capture_command base_gh_api_with_retry repos/owner/repo
    [ "$status" -eq 0 ]
    [ "$output" = "byte-exact body" ]
}

@test "base_gh_api_with_retry rejects decorated or forced-terminal response metadata" {
    install_gh_api_retry_fixture
    TEST_GH_API_SUCCESS_AFTER=99
    TEST_GH_API_FAILURE_STDOUT=$'HTTP/2.0 503 Service Unavailable\r\n\033[1;34mRetry-After\033[0m: 0\r\n\r\nbody\n'
    capture_command base_gh_api_with_retry repos/owner/repo
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]

    install_gh_api_retry_fixture
    TEST_GH_API_SUCCESS_AFTER=99
    TEST_GH_API_FAILURE_STDOUT=$'HTTP/2.0 503 Service Unavailable\r\nRetry-After: 0\r\n\r\nbody\n'
    CLICOLOR_FORCE=1 capture_command base_gh_api_with_retry repos/owner/repo --include
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]
}

@test "base_gh_api_with_retry does not retry auth cancellation certificate or gh usage failures" {
    local failure_status failure_text

    for failure_status in 2 4; do
        install_gh_api_retry_fixture
        TEST_GH_API_FAILURE_STATUS="$failure_status"
        TEST_GH_API_FAILURE_STDERR=$'gh: Service Unavailable (HTTP 503)\n'
        capture_command base_gh_api_with_retry repos/owner/repo
        [ "$status" -eq "$failure_status" ]
        [ "$(gh_api_retry_observed attempts)" -eq 1 ]
    done

    for failure_text in \
        'gh: Bad credentials (HTTP 401)' \
        'gh: request canceled by user' \
        'gh: x509: certificate signed by unknown authority' \
        'gh: jq: error: invalid expression'; do
        install_gh_api_retry_fixture
        TEST_GH_API_FAILURE_STDERR="$failure_text"$'\n'
        capture_command base_gh_api_with_retry repos/owner/repo
        [ "$status" -eq 1 ]
        [ "$(gh_api_retry_observed attempts)" -eq 1 ]
    done
}

@test "base_gh_api_with_retry preserves signal-derived statuses without retrying transient evidence" {
    local signal_status

    for signal_status in 130 137 143; do
        install_gh_api_retry_fixture
        TEST_GH_API_SUCCESS_AFTER=99
        TEST_GH_API_FAILURE_STATUS="$signal_status"
        TEST_GH_API_FAILURE_STDOUT=$'HTTP/2 503\r\n\r\n'
        TEST_GH_API_FAILURE_STDERR=$'gh: response body text\n'
        if capture_command base_gh_api_with_retry repos/owner/repo --include; then
            :
        fi
        [ "$status" -eq "$signal_status" ]
        [ "$(gh_api_retry_observed attempts)" -eq 1 ]
        [ "$(gh_api_retry_observed sleeps)" = "" ]
    done
}

@test "base_gh_api_with_retry restores and re-delivers custom signal traps after cleanup" {
    local trap_marker="$TEST_TMPDIR/gh-api-caller-term-trap"
    local before_trap after_trap rc=0

    install_gh_api_retry_fixture
    __base_bash_libs_gh_api_sleep__() {
        kill -TERM "$BASHPID"
        return 1
    }
    trap 'printf caller-term > "$trap_marker"' TERM
    before_trap="$(trap -p TERM)"

    base_gh_api_with_retry --max-attempts 2 --base-delay-seconds 0 \
        --max-delay-seconds 1 -- repos/owner/repo >/dev/null 2>/dev/null || rc=$?
    after_trap="$(trap -p TERM)"
    trap - TERM

    [ "$rc" -eq 143 ]
    [ "$(cat "$trap_marker")" = "caller-term" ]
    [ "$after_trap" = "$before_trap" ]
    [ -z "$(find "$TEST_TMPDIR" -type f -name 'stdout' -print -quit)" ]
}

@test "base_gh_api_with_retry honors an explicitly ignored caller signal" {
    local before_trap after_trap rc=0

    install_gh_api_retry_fixture
    __base_bash_libs_gh_api_sleep__() {
        kill -TERM "$BASHPID"
        return 0
    }
    trap '' TERM
    before_trap="$(trap -p TERM)"

    base_gh_api_with_retry --max-attempts 2 --base-delay-seconds 0 \
        --max-delay-seconds 1 -- repos/owner/repo >/dev/null 2>/dev/null || rc=$?
    after_trap="$(trap -p TERM)"
    trap - TERM

    [ "$rc" -eq 0 ]
    [ "$(gh_api_retry_observed attempts)" -eq 2 ]
    [ "$after_trap" = "$before_trap" ]
}

@test "base_gh_api_with_retry uses structured include headers and rejects body and metadata spoofing" {
    install_gh_api_retry_fixture
    TEST_GH_API_FAILURE_STDOUT=$'HTTP/2 503\r\nRetry-After: 0\r\n\r\n{"message":"busy"}\n'
    TEST_GH_API_FAILURE_STDERR=$'gh: Service Unavailable (HTTP 503)\n'
    if capture_command base_gh_api_with_retry --base-delay-seconds 0 --max-delay-seconds 1 -- \
        repos/owner/repo --include; then
        :
    fi
    [ "$status" -eq 0 ]
    [ "$(gh_api_retry_observed attempts)" -eq 2 ]

    install_gh_api_retry_fixture
    TEST_GH_API_FAILURE_STDOUT=$'HTTP/2 503\nRetry-After: 0\nbody without a header terminator\n'
    TEST_GH_API_FAILURE_STDERR=$'ordinary failure\n'
    if capture_command base_gh_api_with_retry --base-delay-seconds 0 --max-delay-seconds 1 -- \
        repos/owner/repo --include; then
        :
    fi
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]

    install_gh_api_retry_fixture
    TEST_GH_API_FAILURE_STDOUT=$'HTTP/2 200\r\nContent-Type: application/json\r\n\r\nHTTP/2 503\nRetry-After: 0\n'
    TEST_GH_API_FAILURE_STDERR=$'ordinary failure\n'
    if capture_command base_gh_api_with_retry --base-delay-seconds 0 --max-delay-seconds 1 -- \
        repos/owner/repo --include; then
        :
    fi
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]

    install_gh_api_retry_fixture
    TEST_GH_API_FAILURE_STDOUT=$'{"errors":[{"message":"HTTP/2 503 Retry-After: 0"}]}\n'
    TEST_GH_API_FAILURE_STDERR=$'gh: Service Unavailable (HTTP 503)\n'
    if capture_command base_gh_api_with_retry repos/owner/repo; then
        :
    fi
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]

    install_gh_api_retry_fixture
    local oversized_status="HTTP/2 503 " padding
    printf -v padding '%*s' 70000 ""
    oversized_status+="${padding// /x}"
    TEST_GH_API_FAILURE_STDOUT="$oversized_status"$'\n\n'
    TEST_GH_API_FAILURE_STDERR=$'ordinary failure\n'
    if capture_command base_gh_api_with_retry --base-delay-seconds 0 --max-delay-seconds 1 -- \
        repos/owner/repo --include; then
        :
    fi
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]

    install_gh_api_retry_fixture
    TEST_GH_API_FAILURE_STDOUT=$'HTTP/2 200\r\nX-RateLimit-Remaining: 0\r\nRetry-After: 0\r\n\r\n'
    TEST_GH_API_FAILURE_STDERR=$'gh: jq: error: invalid expression\n'
    if capture_command base_gh_api_with_retry --base-delay-seconds 0 --max-delay-seconds 120 -- \
        repos/owner/repo --include; then
        :
    fi
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]
}

@test "GitHub API response parsing fails closed on NUL metadata but preserves NUL response bodies" {
    local response_file="$TEST_TMPDIR/nul-response.bin"
    local replay_file="$TEST_TMPDIR/nul-replay.bin"
    local expected_file="$TEST_TMPDIR/nul-expected.bin"
    local header_status retry_after remaining reset invalid header_bytes

    printf 'HTTP/2.0 503 Service Unavailable\r\nRetry-After: 0\000spoof\r\n\r\nbody\n' > \
        "$response_file"
    __base_bash_libs_gh_api_parse_headers__ "$response_file" header_status retry_after \
        remaining reset invalid header_bytes
    [ "$header_status" = "" ]
    [ "$retry_after" = "" ]
    [ "$invalid" -eq 1 ]
    [ "$header_bytes" -eq 0 ]

    printf 'HTTP/2.0 200 OK\r\nContent-Type: application/octet-stream\r\n\r\nbody\000bytes\n' > \
        "$response_file"
    printf 'body\000bytes\n' > "$expected_file"
    __base_bash_libs_gh_api_parse_headers__ "$response_file" header_status retry_after \
        remaining reset invalid header_bytes
    [ "$header_status" = "200" ]
    [ "$invalid" -eq 0 ]
    [ "$header_bytes" -gt 0 ]
    __base_bash_libs_gh_api_replay_file__ "$response_file" "$header_bytes" > "$replay_file"
    cmp "$expected_file" "$replay_file"
}

@test "base_gh_api_with_retry withholds NUL-bearing response metadata without retrying" {
    install_gh_api_retry_fixture
    TEST_GH_API_SUCCESS_AFTER=99
    __base_bash_libs_gh_api_attempt__() {
        local stdout_file="$4" stderr_file="$5" attempt_count=0

        IFS= read -r attempt_count < "$TEST_GH_API_ATTEMPT_COUNT_FILE"
        attempt_count=$((attempt_count + 1))
        printf '%s' "$attempt_count" > "$TEST_GH_API_ATTEMPT_COUNT_FILE"
        printf 'HTTP/2.0 503 Service Unavailable\r\nRetry-After: 0\000spoof\r\n\r\nsecret-body\n' > \
            "$stdout_file"
        : > "$stderr_file"
        return 1
    }

    capture_command base_gh_api_with_retry --base-delay-seconds 0 \
        --max-delay-seconds 1 -- repos/owner/repo

    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]
    [ "$(gh_api_retry_observed sleeps)" = "" ]
    [[ "$output" == *"stdout was withheld"* ]]
    [[ "$output" != *"secret-body"* ]]
}

@test "base_gh_api_with_retry rejects malformed and conflicting delay metadata without sleeping" {
    local response
    local -a malformed_responses=(
        $'HTTP/2.0 503 Service Unavailable\r\nRetry-After: abc\r\n\r\nbody\n'
        $'HTTP/2.0 503 Service Unavailable\r\nRetry-After: -1\r\n\r\nbody\n'
        $'HTTP/2.0 503 Service Unavailable\r\nRetry-After: 1.5\r\n\r\nbody\n'
        $'HTTP/2.0 503 Service Unavailable\r\nRetry-After: 99999999999\r\n\r\nbody\n'
        $'HTTP/2.0 503 Service Unavailable\r\nRetry-After: 1\r\nRetry-After: 2\r\n\r\nbody\n'
        $'HTTP/2.0 403 Forbidden\r\nX-RateLimit-Remaining: 0\r\nX-RateLimit-Reset: invalid\r\n\r\nbody\n'
    )

    for response in "${malformed_responses[@]}"; do
        install_gh_api_retry_fixture
        TEST_GH_API_SUCCESS_AFTER=99
        TEST_GH_API_FAILURE_STDOUT="$response"
        TEST_GH_API_FAILURE_STDERR=""

        capture_command base_gh_api_with_retry --max-attempts 3 \
            --max-elapsed-seconds 30 --base-delay-seconds 0 \
            --max-delay-seconds 10 -- repos/owner/repo

        [ "$status" -eq 1 ]
        [ "$(gh_api_retry_observed attempts)" -eq 1 ]
        [ "$(gh_api_retry_observed sleeps)" = "" ]
    done
}

@test "base_gh_api_with_retry rejects a NUL-suffixed transport diagnostic" {
    install_gh_api_retry_fixture
    TEST_GH_API_SUCCESS_AFTER=99
    __base_bash_libs_gh_api_attempt__() {
        local stdout_file="$4" stderr_file="$5" attempt_count=0

        IFS= read -r attempt_count < "$TEST_GH_API_ATTEMPT_COUNT_FILE"
        attempt_count=$((attempt_count + 1))
        printf '%s' "$attempt_count" > "$TEST_GH_API_ATTEMPT_COUNT_FILE"
        : > "$stdout_file"
        printf 'Get "https://api.github.test/repos/owner/repo": read tcp 127.0.0.1:443->127.0.0.2:1234: read: connection reset by peer\000attacker\n' > \
            "$stderr_file"
        return 1
    }

    capture_command base_gh_api_with_retry --base-delay-seconds 0 \
        --max-delay-seconds 1 -- repos/owner/repo

    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]
    [ "$(gh_api_retry_observed sleeps)" = "" ]
}

@test "GitHub API stderr size bound is enforced before content scanning" {
    local stderr_file="$TEST_TMPDIR/oversized-stderr"
    local tr_marker="$TEST_TMPDIR/tr-invoked" padding
    local stderr_status transport invalid rate

    cat > "$TEST_TMPDIR/bin/tr" <<'EOF'
#!/usr/bin/env bash
: > "${TEST_GH_TR_MARKER:?}"
exit 91
EOF
    chmod +x "$TEST_TMPDIR/bin/tr"
    TEST_GH_TR_MARKER="$tr_marker"
    export TEST_GH_TR_MARKER
    printf -v padding '%*s' 16387 ''
    printf '%s' "${padding// /x}" > "$stderr_file"

    __base_bash_libs_gh_api_parse_stderr__ "$stderr_file" stderr_status transport invalid rate

    [ "$stderr_status" = "" ]
    [ "$transport" -eq 0 ]
    [ "$invalid" -eq 1 ]
    [ ! -e "$tr_marker" ]
}

@test "base_gh_api_with_retry requires structured rate evidence and rejects stderr fallback text" {
    install_gh_api_retry_fixture
    TEST_GH_API_FAILURE_STDERR=$'gh: Forbidden (HTTP 403)\n'
    capture_command base_gh_api_with_retry repos/owner/repo
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]

    install_gh_api_retry_fixture
    TEST_GH_API_FAILURE_STDOUT=$'HTTP/2 403\r\nX-RateLimit-Remaining: 0\r\nRetry-After: 0\r\n\r\n'
    TEST_GH_API_FAILURE_STDERR=$'gh: Forbidden (HTTP 403)\n'
    capture_command base_gh_api_with_retry --base-delay-seconds 0 --max-delay-seconds 120 -- \
        repos/owner/repo --include
    [ "$status" -eq 0 ]
    [ "$(gh_api_retry_observed attempts)" -eq 2 ]

    install_gh_api_retry_fixture
    TEST_GH_API_FAILURE_STDERR=$'gh: You have exceeded a secondary rate limit. Please wait. (HTTP 403)\n'
    if capture_command base_gh_api_with_retry --max-delay-seconds 120 -- repos/owner/repo; then
        :
    fi
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]
    [ "$(gh_api_retry_observed sleeps)" = "" ]
}

@test "base_gh_api_with_retry honors server minimum delays without jitter or downward clamping" {
    install_gh_api_retry_fixture
    TEST_GH_API_FAILURE_STDOUT=$'HTTP/2 503\r\nRetry-After: 7\r\n\r\n'
    capture_command base_gh_api_with_retry --max-delay-seconds 10 -- repos/owner/repo --include
    [ "$status" -eq 0 ]
    [ "$(gh_api_retry_observed sleeps)" = "7" ]
    [ "$(gh_api_retry_observed jitter)" = "" ]

    install_gh_api_retry_fixture
    TEST_GH_API_EPOCH=100
    TEST_GH_API_FAILURE_STDOUT=$'HTTP/2 429\r\nX-RateLimit-Remaining: 0\r\nX-RateLimit-Reset: 107\r\n\r\n'
    TEST_GH_API_FAILURE_STDERR=$'gh: rate limited (HTTP 429)\n'
    capture_command base_gh_api_with_retry --max-delay-seconds 10 -- repos/owner/repo --include
    [ "$status" -eq 0 ]
    [ "$(gh_api_retry_observed sleeps)" = "7" ]

    install_gh_api_retry_fixture
    TEST_GH_API_FAILURE_STDOUT=$'HTTP/2 503\r\nRetry-After: 11\r\n\r\n'
    capture_command base_gh_api_with_retry --max-delay-seconds 10 -- repos/owner/repo --include
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]
    [ "$(gh_api_retry_observed sleeps)" = "" ]

    install_gh_api_retry_fixture
    TEST_GH_API_EPOCH=100
    TEST_GH_API_FAILURE_STDOUT=$'HTTP/2 429\r\nRetry-After: 5\r\nX-RateLimit-Remaining: 0\r\nX-RateLimit-Reset: 109\r\n\r\n'
    TEST_GH_API_FAILURE_STDERR=$'gh: rate limited (HTTP 429)\n'
    capture_command base_gh_api_with_retry --max-delay-seconds 10 -- repos/owner/repo --include
    [ "$status" -eq 0 ]
    [ "$(gh_api_retry_observed sleeps)" = "9" ]
    [ "$(gh_api_retry_observed jitter)" = "" ]
}

@test "base_gh_api_with_retry applies equal jitter and exponential rate waits without delay headers" {
    install_gh_api_retry_fixture
    TEST_GH_API_SUCCESS_AFTER=4
    capture_command base_gh_api_with_retry --max-attempts 4 --base-delay-seconds 2 \
        --max-delay-seconds 5 -- repos/owner/repo
    [ "$status" -eq 0 ]
    [ "$(gh_api_retry_observed jitter)" = "2,4,5" ]
    [ "$(gh_api_retry_observed sleeps)" = "1,2,3" ]

    install_gh_api_retry_fixture
    TEST_GH_API_SUCCESS_AFTER=4
    TEST_GH_API_FAILURE_STDOUT=$'HTTP/2 429\r\n\r\n'
    TEST_GH_API_FAILURE_STDERR=$'gh: response body text\n'
    capture_command base_gh_api_with_retry --max-attempts 4 --max-elapsed-seconds 3600 \
        --max-delay-seconds 120 -- repos/owner/repo --include
    [ "$status" -eq 0 ]
    [ "$(gh_api_retry_observed sleeps)" = "60,120,120" ]
    [ "$(gh_api_retry_observed jitter)" = "" ]
}

@test "GitHub API equal jitter seam always stays within its inclusive half-cap range" {
    local cap delay lower iteration

    for cap in 0 1 2 3 4 31 120 300; do
        lower=$(((cap + 1) / 2))
        for ((iteration = 0; iteration < 25; iteration++)); do
            __base_bash_libs_gh_api_jitter_seconds__ delay "$cap"
            ((delay >= lower))
            ((delay <= cap))
        done
    done
}

@test "base_gh_api_with_retry uses the shared TERM-KILL timeout supervisor contract" {
    install_gh_api_retry_fixture
    TEST_GH_API_SUCCESS_AFTER=3

    capture_command base_gh_api_with_retry --max-attempts 3 --base-delay-seconds 0 \
        --max-delay-seconds 1 -- repos/owner/repo

    [ "$status" -eq 0 ]
    [ "$(gh_api_retry_observed attempts)" -eq 3 ]
    # Detection happens once before the retry loop. The attempt seam records
    # the same verified backend path for every attempt; an empty value means
    # the Bash clock fallback was selected on this host.
    local timeout_path
    IFS=',' read -r -a timeout_paths <<< "$(gh_api_retry_observed timeout-paths)"
    [ "${#timeout_paths[@]}" -eq 3 ]
    for timeout_path in "${timeout_paths[@]}"; do
        case "$timeout_path" in
            empty | */timeout | */gtimeout) ;;
            *) return 1 ;;
        esac
    done
}

@test "base_gh_api_with_retry bounds each timeout by the remaining total budget" {
    install_gh_api_retry_fixture
    TEST_GH_API_ATTEMPT_DURATION=3
    capture_command base_gh_api_with_retry --max-attempts 2 --max-elapsed-seconds 7 \
        --attempt-timeout-seconds 5 --base-delay-seconds 0 --max-delay-seconds 1 -- \
        repos/owner/repo
    [ "$status" -eq 0 ]
    [ "$(gh_api_retry_observed timeouts)" = "5,4" ]
    [ "$(gh_api_retry_observed sleeps)" = "0" ]

    install_gh_api_retry_fixture
    TEST_GH_API_ATTEMPT_DURATION=3
    capture_command base_gh_api_with_retry --max-attempts 2 --max-elapsed-seconds 3 \
        --attempt-timeout-seconds 5 --base-delay-seconds 0 --max-delay-seconds 1 -- \
        repos/owner/repo
    [ "$status" -eq 1 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]
    [ "$(gh_api_retry_observed timeouts)" = "3" ]
    [ "$(gh_api_retry_observed sleeps)" = "" ]

    install_gh_api_retry_fixture
    TEST_GH_API_FAILURE_STATUS=124
    TEST_GH_API_ATTEMPT_DURATION=1
    __base_bash_libs_gh_api_sleep__() {
        gh_api_append_observation "$TEST_GH_API_SLEEP_CALLS_FILE" "$1"
        TEST_GH_API_CLOCK=$((TEST_GH_API_CLOCK + 1))
    }
    capture_command base_gh_api_with_retry --max-attempts 2 --max-elapsed-seconds 2 \
        --attempt-timeout-seconds 2 --base-delay-seconds 0 --max-delay-seconds 1 -- \
        repos/owner/repo
    [ "$status" -eq 124 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]
    [ "$(gh_api_retry_observed timeouts)" = "2" ]
}

@test "base_gh_api_with_retry preserves the last gh status when clock sleep or jitter seams fail" {
    local clock_reads=0

    install_gh_api_retry_fixture
    TEST_GH_API_FAILURE_STATUS=73
    __base_bash_libs_gh_api_monotonic_seconds__() {
        clock_reads=$((clock_reads + 1))
        ((clock_reads == 4)) && return 1
        printf -v "$1" '%s' "$TEST_GH_API_CLOCK"
    }
    capture_command base_gh_api_with_retry --max-attempts 3 --base-delay-seconds 0 \
        --max-delay-seconds 1 -- repos/owner/repo
    [ "$status" -eq 73 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]

    install_gh_api_retry_fixture
    TEST_GH_API_FAILURE_STATUS=74
    __base_bash_libs_gh_api_sleep__() { return 1; }
    capture_command base_gh_api_with_retry repos/owner/repo
    [ "$status" -eq 74 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]

    install_gh_api_retry_fixture
    TEST_GH_API_FAILURE_STATUS=75
    __base_bash_libs_gh_api_jitter_seconds__() { return 1; }
    capture_command base_gh_api_with_retry repos/owner/repo
    [ "$status" -eq 75 ]
    [ "$(gh_api_retry_observed attempts)" -eq 1 ]
}

@test "base_gh_api_with_retry replays final binary channels exactly and cleans mode-0600 captures" {
    local actual_stdout="$TEST_TMPDIR/actual.stdout" actual_stderr="$TEST_TMPDIR/actual.stderr"
    local expected_stdout="$TEST_TMPDIR/expected.stdout" expected_stderr="$TEST_TMPDIR/expected.stderr"
    local capture_dir="$TEST_TMPDIR/captures" rc

    install_gh_api_retry_fixture
    mkdir -p "$capture_dir"
    TMPDIR="$capture_dir"
    gh() { return 0; }
    __base_bash_libs_gh_api_monotonic_seconds__() { printf -v "$1" '%s' 0; }
    __base_bash_libs_gh_api_attempt__() {
        local stdout_file="$4" stderr_file="$5"
        local capture_mode
        if capture_mode="$(stat -f '%Lp' "$stdout_file" 2>/dev/null)"; then
            printf '%s' "$capture_mode" > "$TEST_GH_API_CAPTURE_MODE_FILE"
        else
            capture_mode="$(stat -c '%a' "$stdout_file")"
            printf '%s' "$capture_mode" > "$TEST_GH_API_CAPTURE_MODE_FILE"
        fi
        printf 'HTTP/2.0 200 OK\r\n\r\nout\0value\n\n' > "$stdout_file"
        printf 'err\0value' > "$stderr_file"
        return 0
    }

    if base_gh_api_with_retry --sensitive --safe-display "binary API read" -- \
        repos/owner/repo > "$actual_stdout" 2> "$actual_stderr"; then
        rc=0
    else
        rc=$?
    fi
    printf 'out\0value\n\n' > "$expected_stdout"
    printf 'err\0value' > "$expected_stderr"

    [ "$rc" -eq 0 ]
    [ "$(gh_api_retry_observed capture-mode)" = "600" ]
    cmp "$expected_stdout" "$actual_stdout"
    cmp "$expected_stderr" "$actual_stderr"
    [ -z "$(find "$capture_dir" -type f -print -quit)" ]

    __base_bash_libs_gh_api_attempt__() {
        local stdout_file="$4" stderr_file="$5"
        printf 'HTTP/2.0 400 Bad Request\r\n\r\nfailed-out\0value\n\n' > "$stdout_file"
        printf 'failed-err\0value' > "$stderr_file"
        return 73
    }
    base_std_log_warn() { printf 'warn:%s\n' "${*: -1}" >> "$TEST_TMPDIR/separate.log"; }
    base_std_log_error() { printf 'error:%s\n' "${*: -1}" >> "$TEST_TMPDIR/separate.log"; }
    if base_gh_api_with_retry repos/owner/repo > "$actual_stdout" 2> "$actual_stderr"; then
        rc=0
    else
        rc=$?
    fi
    printf 'failed-out\0value\n\n' > "$expected_stdout"
    printf 'failed-err\0value' > "$expected_stderr"

    [ "$rc" -eq 73 ]
    cmp "$expected_stdout" "$actual_stdout"
    cmp "$expected_stderr" "$actual_stderr"
    [ -z "$(find "$capture_dir" -type f -print -quit)" ]
}

@test "GitHub API capture guardian completes workspace cleanup before normal shutdown returns" {
    local workspace="" guardian_pid="" guardian_fd=""

    base_std_make_temp_dir --keep workspace base-bash-libs-gh-api
    chmod 700 "$workspace"
    mkfifo "$workspace/guardian"
    chmod 600 "$workspace/guardian"
    __base_bash_libs_gh_api_start_capture_guardian__ guardian_pid guardian_fd "$BASHPID" \
        "$workspace"
    : > "$workspace/stdout"
    : > "$workspace/stderr"
    chmod 600 "$workspace/stdout" "$workspace/stderr"
    /bin/sleep 1.2
    [ -d "$workspace" ]

    __base_bash_libs_gh_api_stop_capture_guardian__ "$guardian_pid" "$guardian_fd"

    [ ! -e "$workspace" ]
}

@test "GitHub API capture guardian removes its workspace after owner SIGKILL" {
    local workspace="$TEST_TMPDIR/guardian-owner-workspace"
    local ready_file="$TEST_TMPDIR/guardian-owner-ready"
    local child_pid_file="$TEST_TMPDIR/guardian-owner-child"
    local owner_pid child_pid probe rc=0 workspace_removed=0 child_alive=0

    (
        local guardian_pid="" guardian_fd=""

        mkdir "$workspace"
        chmod 700 "$workspace"
        mkfifo "$workspace/guardian"
        chmod 600 "$workspace/guardian"
        __base_bash_libs_gh_api_start_capture_guardian__ guardian_pid guardian_fd "$BASHPID" \
            "$workspace" || exit 91
        : > "$workspace/stdout"
        : > "$workspace/stderr"
        chmod 600 "$workspace/stdout" "$workspace/stderr"
        /bin/sleep 30 &
        printf '%s\n' "$!" > "$child_pid_file"
        : > "$ready_file"
        kill -KILL "$BASHPID"
    ) &
    owner_pid=$!
    for ((probe = 0; probe < 200; probe++)); do
        [[ -e "$ready_file" ]] && break
        /bin/sleep 0.01
    done
    [[ -e "$ready_file" ]] || {
        kill -KILL "$owner_pid" 2>/dev/null || true
        wait "$owner_pid" 2>/dev/null || true
        return 1
    }
    wait "$owner_pid" 2>/dev/null || rc=$?
    [ "$rc" -eq 137 ]
    IFS= read -r child_pid < "$child_pid_file"
    for ((probe = 0; probe < 200; probe++)); do
        [[ ! -e "$workspace" ]] && break
        /bin/sleep 0.01
    done
    [[ ! -e "$workspace" ]] && workspace_removed=1
    kill -0 "$child_pid" 2>/dev/null && child_alive=1
    kill -KILL "$child_pid" 2>/dev/null || true

    [ "$workspace_removed" -eq 1 ]
    [ "$child_alive" -eq 1 ]
}

@test "base_gh_api_with_retry reports broken-pipe replay failure and still cleans captures" {
    local script="$TEST_TMPDIR/gh-api-epipe.sh"
    local capture_dir="$TEST_TMPDIR/epipe-captures"
    local status_file="$TEST_TMPDIR/epipe-status"

    mkdir -p "$capture_dir"
    cat > "$script" <<'EOF'
#!/usr/bin/env bash
source "$1"
declare -a app_args=()
base_init app_args --
source "$2"
TMPDIR="$3"
STATUS_FILE="$4"
gh() { return 0; }
__base_bash_libs_gh_api_attempt__() {
    local stdout_file="$4" stderr_file="$5" index
    : > "$stderr_file"
    printf 'HTTP/2.0 200 OK\r\n\r\n' > "$stdout_file"
    for ((index = 0; index < 4096; index++)); do
        printf '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n'
    done >> "$stdout_file"
    return 0
}
set -o pipefail
base_gh_api_with_retry repos/owner/repo 2>/dev/null | head -n 0 >/dev/null
pipeline_status=$?
set +o pipefail
printf '%s' "$pipeline_status" > "$STATUS_FILE"
exit 0
EOF
    chmod +x "$script"

    bats_run "$BASH" "$script" \
        "$BASE_BASH_DIR/std/lib_std.sh" "$BASE_BASH_DIR/gh/lib_gh.sh" \
        "$capture_dir" "$status_file"

    [ "$status" -eq 0 ]
    [ "$(cat "$status_file")" -ne 0 ]
    [ -z "$(find "$capture_dir" -type f -print -quit)" ]
}

@test "base_gh_api_with_retry preserves caller EXIT trap and cleans captures after managed command exit" {
    local script="$TEST_TMPDIR/gh-api-abrupt-exit.sh"
    local capture_dir="$TEST_TMPDIR/abrupt-captures"
    local trap_marker="$TEST_TMPDIR/caller-exit-trap-ran"
    local status_file="$TEST_TMPDIR/abrupt-status"

    mkdir -p "$capture_dir"
    cat > "$script" <<'EOF'
#!/usr/bin/env bash
set -u
source "$1"
declare -a app_args=()
base_init app_args --
source "$2"
TMPDIR="$3"
TRAP_MARKER="$4"
STATUS_FILE="$5"
trap 'printf preserved > "$TRAP_MARKER"' EXIT
gh() { exit 77; }
base_gh_api_with_retry repos/owner/repo >/dev/null 2>/dev/null
printf '%s' "$?" > "$STATUS_FILE"
exit 0
EOF
    chmod +x "$script"

    bats_run "$BASH" "$script" \
        "$BASE_BASH_DIR/std/lib_std.sh" "$BASE_BASH_DIR/gh/lib_gh.sh" \
        "$capture_dir" "$trap_marker" "$status_file"

    [ "$status" -eq 0 ]
    [ "$(cat "$status_file")" = "77" ]
    [ "$(cat "$trap_marker")" = "preserved" ]
    [ -z "$(find "$capture_dir" -type f -print -quit)" ]
}

@test "base_gh_api_with_retry removes sensitive captures when terminated during retry backoff" {
    local capture_dir="$TEST_TMPDIR/signal-captures"
    local sleep_pid_file="$TEST_TMPDIR/retry-sleep.pid" ready_file="$TEST_TMPDIR/retry-sleep.ready"
    local call_pid sleep_pid rc=0 probe start_time

    mkdir -p "$capture_dir"
    TMPDIR="$capture_dir"
    gh() { return 0; }
    __base_bash_libs_gh_api_monotonic_seconds__() { printf -v "$1" '%s' 0; }
    __base_bash_libs_gh_api_jitter_seconds__() { printf -v "$1" '%s' 2; }
    __base_bash_libs_gh_api_attempt__() {
        local stdout_file="$4" stderr_file="$5"
        printf 'HTTP/2.0 503 Service Unavailable\r\n\r\nsecret=signal-canary\n' > "$stdout_file"
        printf 'transient transport context\n' > "$stderr_file"
        return 75
    }
    __base_bash_libs_gh_api_sleep__() {
        /bin/sleep 30 &
        printf '%s\n' "$!" > "$sleep_pid_file"
        : > "$ready_file"
        wait "$!"
    }

    start_time=$SECONDS
    base_gh_api_with_retry --max-attempts 2 --max-delay-seconds 2 -- \
        repos/owner/repo >/dev/null 2>/dev/null &
    call_pid=$!
    for ((probe = 0; probe < 100; probe++)); do
        [[ -e "$ready_file" ]] && break
        /bin/sleep 0.01
    done
    [[ -e "$ready_file" && -s "$sleep_pid_file" ]] || {
        kill -KILL "$call_pid" 2>/dev/null || true
        wait "$call_pid" 2>/dev/null || true
        return 1
    }
    IFS= read -r sleep_pid < "$sleep_pid_file"
    kill -TERM "$call_pid"
    if wait "$call_pid"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 143 ]
    [ "$((SECONDS - start_time))" -le 3 ]
    ! kill -0 "$sleep_pid" 2>/dev/null
    [ -z "$(find "$capture_dir" -type f -print -quit)" ]
}

@test "base_gh_api_with_retry protected failures hide captured output argv and persistent-log canaries" {
    local secret="gh-api-retry-secret-canary"
    local primary_log="$TEST_TMPDIR/gh-api-sensitive.log"
    local primary_content

    install_gh_api_retry_fixture
    TEST_GH_API_SUCCESS_AFTER=99
    TEST_GH_API_FAILURE_STATUS=29
    TEST_GH_API_FAILURE_STDOUT=$'HTTP/2 503\r\n\r\n'"captured=$secret"$'\n'
    TEST_GH_API_FAILURE_STDERR="gh: captured=$secret"$'\n'
    BASE_BASH_LIBS_PRIMARY_LOG="$primary_log"

    if capture_command base_gh_api_with_retry --sensitive --safe-display "rotate deployment key" \
        --retry-policy replay-safe \
        --max-attempts 2 --base-delay-seconds 0 --max-delay-seconds 1 -- \
        repos/owner/repo --include --header "Authorization: Bearer $secret" \
        --raw-field "token=$secret"; then
        :
    fi

    [ "$status" -eq 29 ]
    [ "$(gh_api_retry_observed attempts)" -eq 2 ]
    [[ "$output" == *"rotate deployment key [sensitive GitHub operation; arguments hidden]"* ]]
    [[ "$output" == *"captured output hidden"* ]]
    [[ "$output" != *"$secret"* ]]
    primary_content="$(cat "$primary_log")"
    [[ "$primary_content" != *"$secret"* ]]
}

@test "base_gh_api_with_retry final diagnostics report safe method HTTP attempt elapsed and budget context" {
    install_gh_api_retry_fixture
    TEST_GH_API_SUCCESS_AFTER=99
    TEST_GH_API_FAILURE_STATUS=255
    TEST_GH_API_FAILURE_STDOUT=$'HTTP/2 503\r\n\r\n'
    TEST_GH_API_FAILURE_STDERR=$'gh: response body text\n'

    if capture_command base_gh_api_with_retry --sensitive --safe-display "publish deployment" \
        --retry-policy replay-safe --max-attempts 1 -- \
        repos/owner/repo --include --method POST; then
        :
    fi

    [ "$status" -eq 255 ]
    [[ "$output" == *"publish deployment [sensitive GitHub operation; arguments hidden]"* ]]
    [[ "$output" == *"method=POST"* || "$output" == *"method POST"* ]]
    [[ "$output" == *"HTTP 503"* || "$output" == *"http=503"* ]]
    [[ "$output" == *"attempt 1 of 1"* || "$output" == *"attempt=1/1"* ]]
    [[ "$output" == *"elapsed"* ]]
    [[ "$output" == *"budget"* ]]
}

@test "base_gh_api_with_retry preserves final statuses 1 2 4 124 and 255 without a final sleep" {
    local expected_status

    for expected_status in 1 2 4 124 255; do
        install_gh_api_retry_fixture
        TEST_GH_API_SUCCESS_AFTER=99
        TEST_GH_API_FAILURE_STATUS="$expected_status"
        if capture_command base_gh_api_with_retry --max-attempts 1 -- repos/owner/repo; then
            :
        fi
        [ "$status" -eq "$expected_status" ]
        [ "$(gh_api_retry_observed attempts)" -eq 1 ]
        [ "$(gh_api_retry_observed sleeps)" = "" ]
    done
}

@test "base_gh_api_with_retry captures failures under set -e" {
    local script="$TEST_TMPDIR/gh-api-set-e.sh"

    create_fake_gh <<'EOF'
#!/usr/bin/env bash
printf 'gh: Not Found (HTTP 404)\n' >&2
exit 4
EOF
    cat > "$script" <<EOF
#!/usr/bin/env bash
set -e
source "$BASE_BASH_DIR/std/lib_std.sh"
declare -a app_args=()
base_init app_args --source "\${BASH_SOURCE[0]}" -- "\$@"
source "$BASE_BASH_DIR/gh/lib_gh.sh"
PATH="$TEST_TMPDIR/bin:$PATH"
base_gh_api_with_retry repos/owner/missing
printf 'after\n'
EOF
    chmod +x "$script"

    bats_run bash "$script"

    [ "$status" -eq 4 ]
    [[ "$output" == *"Not Found"* ]]
    [[ "$output" != *"after"* ]]
}

@test "base_gh_api_with_retry works under noclobber and preserves that caller option" {
    create_fake_gh <<'EOF'
#!/usr/bin/env bash
include=0
for arg in "$@"; do
    [[ "$arg" == --include ]] && include=1
done
((include == 0)) || printf 'HTTP/2.0 200 OK\r\n\r\n'
printf 'noclobber-body\n'
EOF

    bats_run "$BASH" -c '
        source "$1"
        declare -a app_args=()
        base_init app_args --
        source "$2"
        set -C
        value="$(base_gh_api_with_retry --max-attempts 1 -- repos/owner/repo)" || exit $?
        [[ -o noclobber ]] || exit 91
        printf "value=%s\nnoclobber=on\n" "$value"
    ' bash "$BASE_BASH_DIR/std/lib_std.sh" "$BASE_BASH_DIR/gh/lib_gh.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"value=noclobber-body"* ]]
    [[ "$output" == *"noclobber=on"* ]]
    [[ "$output" != *"cannot overwrite existing file"* ]]
}
