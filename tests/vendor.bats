#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/beacon-vendor-test.XXXXXX")"
    VENDOR_ROOT="$TEST_ROOT/repo"
    mkdir -p "$VENDOR_ROOT/scripts"
    cp "$REPO_ROOT/scripts/verify-vendor" "$VENDOR_ROOT/scripts/verify-vendor"
    cp "$REPO_ROOT/base-bash-libs.lock" "$VENDOR_ROOT/base-bash-libs.lock"
    cp -R "$REPO_ROOT/vendor" "$VENDOR_ROOT/vendor"
}

teardown() {
    rm -rf "$TEST_ROOT"
}

run_verifier() {
    run "$VENDOR_ROOT/scripts/verify-vendor"
}

@test "vendor verification requires an exact regular-file inventory" {
    run_verifier
    [ "$status" -eq 0 ]

    printf 'unlisted\n' > "$VENDOR_ROOT/vendor/base-bash-libs/unlisted.txt"
    run_verifier
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not exactly match"* ]]
}

@test "vendor verification rejects links and special files" {
    printf 'outside\n' > "$TEST_ROOT/outside.txt"
    ln -s "$TEST_ROOT/outside.txt" "$VENDOR_ROOT/vendor/base-bash-libs/unlisted-link"
    run_verifier
    [ "$status" -eq 1 ]
    [[ "$output" == *"symbolic link"* ]]

    rm "$VENDOR_ROOT/vendor/base-bash-libs/unlisted-link"
    mkfifo "$VENDOR_ROOT/vendor/base-bash-libs/unlisted-fifo"
    run_verifier
    [ "$status" -eq 1 ]
    [[ "$output" == *"special file"* ]]
}

@test "vendor verification rejects duplicate and noncanonical manifest paths" {
    head -n 1 "$VENDOR_ROOT/vendor/base-bash-libs/MANIFEST.sha256" \
        > "$TEST_ROOT/duplicate"
    cat "$VENDOR_ROOT/vendor/base-bash-libs/MANIFEST.sha256" "$TEST_ROOT/duplicate" \
        > "$TEST_ROOT/manifest"
    mv "$TEST_ROOT/manifest" "$VENDOR_ROOT/vendor/base-bash-libs/MANIFEST.sha256"
    run_verifier
    [ "$status" -eq 1 ]
    [[ "$output" == *"duplicate paths"* ]]

    cp "$REPO_ROOT/vendor/base-bash-libs/MANIFEST.sha256" \
        "$VENDOR_ROOT/vendor/base-bash-libs/MANIFEST.sha256"
    sed '1s/  VERSION$/  .\/VERSION/' \
        "$VENDOR_ROOT/vendor/base-bash-libs/MANIFEST.sha256" \
        > "$TEST_ROOT/manifest"
    mv "$TEST_ROOT/manifest" "$VENDOR_ROOT/vendor/base-bash-libs/MANIFEST.sha256"
    run_verifier
    [ "$status" -eq 1 ]
    [[ "$output" == *"not canonical"* ]]
}
