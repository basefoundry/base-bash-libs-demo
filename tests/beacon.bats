#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/beacon-test.XXXXXX")"
    TEST_OUTPUT="$TEST_ROOT/beacon bundle"
}

teardown() {
    rm -rf "$TEST_ROOT"
}

@test "verification requires complete unique canonical inventory" {
    "$REPO_ROOT/bin/beacon" collect --quiet --output "$TEST_OUTPUT"
    cp "$TEST_OUTPUT/MANIFEST.sha256" "$TEST_ROOT/original"
    for mutation in empty partial duplicate reversed extra malformed missing unreadable; do
        cp "$TEST_ROOT/original" "$TEST_OUTPUT/MANIFEST.sha256"
        case "$mutation" in
            empty) : > "$TEST_OUTPUT/MANIFEST.sha256" ;;
            partial) head -n 1 "$TEST_ROOT/original" > "$TEST_OUTPUT/MANIFEST.sha256" ;;
            duplicate) cat "$TEST_ROOT/original" >> "$TEST_OUTPUT/MANIFEST.sha256" ;;
            reversed) LC_ALL=C sort -r "$TEST_ROOT/original" > "$TEST_OUTPUT/MANIFEST.sha256" ;;
            extra) printf extra > "$TEST_OUTPUT/extra.txt" ;;
            malformed) printf 'bad\trecord\n' >> "$TEST_OUTPUT/MANIFEST.sha256" ;;
            missing) mv "$TEST_OUTPUT/files/system/info.txt" "$TEST_ROOT/info" ;;
            unreadable) chmod 000 "$TEST_OUTPUT/files/logs/app.log" ;;
        esac
        run "$REPO_ROOT/bin/beacon" verify --output "$TEST_OUTPUT"
        if [[ "$mutation" != unreadable || "$(id -u)" != 0 ]]; then
            [ "$status" -eq 1 ]
            [[ "$output" != *verified=true* ]]
            [ -n "$output" ]
        fi
        case "$mutation" in
            extra) rm "$TEST_OUTPUT/extra.txt" ;;
            missing) mv "$TEST_ROOT/info" "$TEST_OUTPUT/files/system/info.txt" ;;
            unreadable) chmod 644 "$TEST_OUTPUT/files/logs/app.log" ;;
        esac
    done
}

@test "verification accepts partial workspaces but rejects coherent invalid metadata" {
    mkdir -p "$TEST_ROOT/partial/system"
    printf 'synthetic\n' > "$TEST_ROOT/partial/system/info.txt"
    "$REPO_ROOT/bin/beacon" collect --workspace "$TEST_ROOT/partial" --output "$TEST_OUTPUT"
    run "$REPO_ROOT/bin/beacon" verify --workspace "$TEST_ROOT/partial" --output "$TEST_OUTPUT"
    [ "$status" -eq 0 ]
    [[ "$output" == *files=2* ]]
    printf 'selected_files=1\n' >> "$TEST_OUTPUT/README.txt"
    hash="$(shasum -a 256 "$TEST_OUTPUT/README.txt")"
    tail -n 1 "$TEST_OUTPUT/MANIFEST.sha256" > "$TEST_ROOT/last"
    printf '%s\tREADME.txt\n' "${hash%% *}" > "$TEST_OUTPUT/MANIFEST.sha256"
    cat "$TEST_ROOT/last" >> "$TEST_OUTPUT/MANIFEST.sha256"
    run "$REPO_ROOT/bin/beacon" verify --workspace "$TEST_ROOT/partial" --output "$TEST_OUTPUT"
    [ "$status" -eq 1 ]
    [[ "$output" == *metadata* ]]
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
