#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/beacon-lifecycle.XXXXXX")"
    TEST_OUTPUT="$TEST_ROOT/beacon-support"
    TEST_STAGE_ROOT="$TEST_ROOT/staging"
    TEST_LIFECYCLE_LOG="$TEST_ROOT/lifecycle.log"
    mkdir -p "$TEST_STAGE_ROOT"
}

teardown() {
    rm -rf "$TEST_ROOT"
}

assert_single_cleanup() {
    [ "$(wc -l < "$TEST_LIFECYCLE_LOG" | tr -d ' ')" -eq 1 ]
    [ "$(cat "$TEST_LIFECYCLE_LOG")" = "phase=cleanup" ]
}

assert_staging_is_empty() {
    [ -z "$(find "$TEST_STAGE_ROOT" -mindepth 1 -print -quit)" ]
}

@test "successful collection records exactly one cleanup and preserves status zero" {
    run env TMPDIR="$TEST_STAGE_ROOT" "$REPO_ROOT/bin/beacon" collect \
        --output "$TEST_OUTPUT" --lifecycle-log "$TEST_LIFECYCLE_LOG"
    [ "$status" -eq 0 ]
    [ -f "$TEST_OUTPUT/MANIFEST.sha256" ]
    assert_single_cleanup
    assert_staging_is_empty
}

@test "simulated failure publishes no bundle and cleanup preserves status 70" {
    run env TMPDIR="$TEST_STAGE_ROOT" "$REPO_ROOT/bin/beacon" collect \
        --scenario failure --output "$TEST_OUTPUT" \
        --lifecycle-log "$TEST_LIFECYCLE_LOG"
    [ "$status" -eq 70 ]
    [[ "$output" == *"Simulated collection failure before publication."* ]]
    [ ! -e "$TEST_OUTPUT" ]
    assert_single_cleanup
    assert_staging_is_empty
}

@test "TERM interruption publishes no bundle and cleanup preserves status 143" {
    stdout_file="$TEST_ROOT/stdout"
    stderr_file="$TEST_ROOT/stderr"

    env TMPDIR="$TEST_STAGE_ROOT" "$REPO_ROOT/bin/beacon" collect \
        --scenario interrupt --output "$TEST_OUTPUT" \
        --lifecycle-log "$TEST_LIFECYCLE_LOG" \
        > "$stdout_file" 2> "$stderr_file" &
    beacon_pid=$!

    ready=no
    for _ in {1..100}; do
        if grep -Fq 'state=waiting_for_signal' "$stdout_file"; then
            ready=yes
            break
        fi
        sleep 0.05
    done
    [ "$ready" = yes ]

    kill -TERM "$beacon_pid"
    signal_status=0
    wait "$beacon_pid" || signal_status=$?

    [ "$signal_status" -eq 143 ]
    [ ! -e "$TEST_OUTPUT" ]
    assert_single_cleanup
    assert_staging_is_empty
}

@test "dry-run non-interactive automation neither prompts nor writes state" {
    run env TMPDIR="$TEST_STAGE_ROOT" "$REPO_ROOT/bin/beacon" collect \
        --dry-run --non-interactive --output "$TEST_OUTPUT" \
        --lifecycle-log "$TEST_LIFECYCLE_LOG" < /dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"dry_run=true"* ]]
    [[ "$output" != *"?"* ]]
    [ ! -e "$TEST_OUTPUT" ]
    [ ! -e "$TEST_LIFECYCLE_LOG" ]
    assert_staging_is_empty
}

@test "invalid scenarios are usage errors and do not start collection" {
    run "$REPO_ROOT/bin/beacon" collect --scenario unknown --output "$TEST_OUTPUT"
    [ "$status" -eq 2 ]
    [ ! -e "$TEST_OUTPUT" ]
    assert_staging_is_empty
}

@test "cleanup evidence failure does not replace successful application status" {
    run "$REPO_ROOT/bin/beacon" collect --output "$TEST_OUTPUT" \
        --lifecycle-log "$TEST_ROOT/missing/lifecycle.log"
    [ "$status" -eq 0 ]
    [ -f "$TEST_OUTPUT/MANIFEST.sha256" ]
    [[ "$output" == *"cleanup hook 'beacon_cleanup' failed; preserving status 0"* ]]
}

@test "redaction handles token-like values paths and malformed fixture records" {
    hostile_workspace="$TEST_ROOT/hostile-workspace"
    cp -R "$REPO_ROOT/fixtures/workspace" "$hostile_workspace"
    printf '%s\n' \
        'SERVICE_TOKEN=Bearer.fake-token.abc123' \
        'PATH_SECRET=/Users/example/private/session' \
        'MALFORMED_FIXTURE_RECORD' \
        'LITERAL_VALUE=$(touch should-never-exist)' \
        >> "$hostile_workspace/config/app.env"
    printf '%s\n' \
        'auth=Bearer.fake-token.abc123' \
        'session_path=/Users/example/private/session' \
        'malformed-reference demo-token-123' \
        >> "$hostile_workspace/logs/app.log"

    run "$REPO_ROOT/bin/beacon" collect --workspace "$hostile_workspace" \
        --output "$TEST_OUTPUT"
    [ "$status" -eq 0 ]
    run "$REPO_ROOT/bin/beacon" verify --workspace "$hostile_workspace" \
        --output "$TEST_OUTPUT"
    [ "$status" -eq 0 ]
    ! grep -R -F 'Bearer.fake-token.abc123' "$TEST_OUTPUT"
    ! grep -R -F '/Users/example/private/session' "$TEST_OUTPUT"
    ! grep -R -F 'demo-token-123' "$TEST_OUTPUT"
    [ ! -e "$REPO_ROOT/should-never-exist" ]
}
