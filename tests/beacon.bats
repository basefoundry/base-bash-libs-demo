#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/beacon-test.XXXXXX")"
    TEST_OUTPUT="$TEST_ROOT/beacon bundle"
}

teardown() {
    rm -rf "$TEST_ROOT"
}

@test "selection rejects linked files, linked parents and special files" {
    mkdir -p "$TEST_ROOT/workspace/config" "$TEST_ROOT/outside"
    printf 'synthetic-marker\n' > "$TEST_ROOT/outside/app.env"
    ln -s "$TEST_ROOT/outside/app.env" "$TEST_ROOT/workspace/config/app.env"
    run "$REPO_ROOT/bin/beacon" collect --workspace "$TEST_ROOT/workspace" --output "$TEST_OUTPUT"
    [ "$status" -eq 1 ]
    [ ! -e "$TEST_OUTPUT" ]
    rm "$TEST_ROOT/workspace/config/app.env"
    rmdir "$TEST_ROOT/workspace/config"
    ln -s "$TEST_ROOT/outside" "$TEST_ROOT/workspace/config"
    run "$REPO_ROOT/bin/beacon" plan --workspace "$TEST_ROOT/workspace"
    [ "$status" -eq 1 ]
    rm "$TEST_ROOT/workspace/config"
    mkdir "$TEST_ROOT/workspace/config"
    mkfifo "$TEST_ROOT/workspace/config/app.env"
    run "$REPO_ROOT/bin/beacon" collect --workspace "$TEST_ROOT/workspace" --output "$TEST_OUTPUT"
    [ "$status" -eq 1 ]
    [ ! -e "$TEST_OUTPUT" ]
}

@test "verification rejects linked parents, dangling links and special files" {
    "$REPO_ROOT/bin/beacon" collect --quiet --output "$TEST_OUTPUT"
    mv "$TEST_OUTPUT/files" "$TEST_ROOT/payload"
    ln -s "$TEST_ROOT/payload" "$TEST_OUTPUT/files"
    run "$REPO_ROOT/bin/beacon" verify --output "$TEST_OUTPUT"
    [ "$status" -eq 1 ]
    [[ "$output" != *verified=true* ]]
    rm "$TEST_OUTPUT/files"
    mv "$TEST_ROOT/payload" "$TEST_OUTPUT/files"
    ln -s "$TEST_ROOT/missing" "$TEST_OUTPUT/extra"
    run "$REPO_ROOT/bin/beacon" verify --output "$TEST_OUTPUT"
    [ "$status" -eq 1 ]
    rm "$TEST_OUTPUT/extra"
    mkfifo "$TEST_OUTPUT/extra"
    run "$REPO_ROOT/bin/beacon" verify --output "$TEST_OUTPUT"
    [ "$status" -eq 1 ]
}

@test "help exposes the flagship commands" {
    run "$REPO_ROOT/bin/beacon" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"status"* ]]
    [[ "$output" == *"plan"* ]]
    [[ "$output" == *"collect"* ]]
    [[ "$output" == *"verify"* ]]
}

@test "status reports immutable release identity" {
    run "$REPO_ROOT/bin/beacon" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"framework_version=2.0.0"* ]]
    [[ "$output" == *"framework_commit=b4243765726c133499feeabdc50154f99c0fec12"* ]]
    [[ "$output" == *"framework_dirty_state=clean"* ]]
    [[ "$output" == *"framework_provenance=release-artifact"* ]]
}

@test "plan lists only relative supported inputs" {
    run "$REPO_ROOT/bin/beacon" plan --output "$TEST_OUTPUT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"include=config/app.env"* ]]
    [[ "$output" == *"include=logs/app.log"* ]]
    [[ "$output" == *"include=system/info.txt"* ]]
    [[ "$output" != *"include=$REPO_ROOT"* ]]
}

@test "dry-run collection writes nothing" {
    run "$REPO_ROOT/bin/beacon" collect --dry-run --output "$TEST_OUTPUT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dry_run=true"* ]]
    [ ! -e "$TEST_OUTPUT" ]
}

@test "collection redacts secrets and verifies its manifest" {
    run "$REPO_ROOT/bin/beacon" collect --output "$TEST_OUTPUT"
    [ "$status" -eq 0 ]
    [ -f "$TEST_OUTPUT/MANIFEST.sha256" ]

    run "$REPO_ROOT/bin/beacon" verify --output "$TEST_OUTPUT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"verified=true"* ]]
    ! grep -R -F "demo-token-123" "$TEST_OUTPUT"
    ! grep -R -F "demo-password-456" "$TEST_OUTPUT"
    grep -R -F "[REDACTED]" "$TEST_OUTPUT"
    ! grep -R -F "$REPO_ROOT" "$TEST_OUTPUT"
}

@test "repeated collections are deterministic" {
    second_output="$TEST_ROOT/second bundle"
    run "$REPO_ROOT/bin/beacon" collect --quiet --output "$TEST_OUTPUT"
    [ "$status" -eq 0 ]
    run "$REPO_ROOT/bin/beacon" collect --quiet --output "$second_output"
    [ "$status" -eq 0 ]
    diff -r "$TEST_OUTPUT" "$second_output"
}

@test "verification rejects a tampered file" {
    run "$REPO_ROOT/bin/beacon" collect --quiet --output "$TEST_OUTPUT"
    [ "$status" -eq 0 ]
    printf 'tampered\n' >> "$TEST_OUTPUT/files/system/info.txt"
    run "$REPO_ROOT/bin/beacon" verify --output "$TEST_OUTPUT"
    [ "$status" -ne 0 ]
}

@test "existing output is never overwritten" {
    mkdir -p "$TEST_OUTPUT"
    printf 'preserve\n' > "$TEST_OUTPUT/existing.txt"
    run "$REPO_ROOT/bin/beacon" collect --output "$TEST_OUTPUT"
    [ "$status" -ne 0 ]
    [ "$(cat "$TEST_OUTPUT/existing.txt")" = "preserve" ]
}

@test "framework resolution supports spaces and a symlink" {
    mkdir -p "$TEST_ROOT/framework path"
    ln -s "$REPO_ROOT/vendor/base-bash-libs/lib/bash" \
        "$TEST_ROOT/framework path/library link"
    run env BASE_BASH_LIBS_DIR="$TEST_ROOT/framework path/library link" \
        "$REPO_ROOT/bin/beacon" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"framework_version=2.0.0"* ]]
}
