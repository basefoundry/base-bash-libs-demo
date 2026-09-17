#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/beacon-canary-test.XXXXXX")"
    mkdir -p "$TEST_ROOT/candidate/bin" "$TEST_ROOT/temp"
    ln -s "$REPO_ROOT/vendor/base-bash-libs/lib" "$TEST_ROOT/candidate/lib"
    cat > "$TEST_ROOT/candidate/bin/base-bash" <<'SH'
#!/usr/bin/env bash
"$BEACON_REAL_LAUNCHER" "$@" || exit $?
[[ "$2" != "$BEACON_BROKEN_COMMAND" ]] || exit 42
SH
    chmod +x "$TEST_ROOT/candidate/bin/base-bash"
}

teardown() {
    rm -rf "$TEST_ROOT"
}

@test "canary rejects expected output followed by producer failure and cleans temp state" {
    for command in plan collect verify; do
        run env TMPDIR="$TEST_ROOT/temp" BEACON_BROKEN_COMMAND="$command" \
            BEACON_REAL_LAUNCHER="$REPO_ROOT/vendor/base-bash-libs/bin/base-bash" \
            "$REPO_ROOT/tests/candidate-smoke.sh" "$TEST_ROOT/candidate" 2.0.0 \
            b4243765726c133499feeabdc50154f99c0fec12
        [ "$status" -eq 1 ]
        [[ "$output" == *"returned 42"* ]]
        [[ "$output" != *passed.* ]]
        [ -z "$(find "$TEST_ROOT/temp" -mindepth 1 -print -quit)" ]
    done
}

@test "successful full-contract canary cleans temporary state" {
    run env TMPDIR="$TEST_ROOT/temp" "$REPO_ROOT/tests/candidate-smoke.sh" "$REPO_ROOT/vendor/base-bash-libs"
    [ "$status" -eq 0 ]
    [[ "$output" == *passed.* ]]
    [ -z "$(find "$TEST_ROOT/temp" -mindepth 1 -print -quit)" ]
}
