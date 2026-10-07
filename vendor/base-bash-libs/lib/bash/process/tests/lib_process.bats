#!/usr/bin/env bats

load ../../tests/test_helper.sh

setup() {
    setup_test_tmpdir
    export TEST_TMPDIR
    source "$BASE_BASH_DIR/std/lib_std.sh"
    declare -a setup_args=()
    base_init setup_args --source "$BASE_BASH_DIR/process/tests/lib_process.bats" --
    base_std_import process/lib_process.sh
}

@test "process module requires the stdlib" {
    run bash -c 'source "$1"' bash "$BASE_BASH_DIR/process/lib_process.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"lib_process.sh requires lib_std.sh"* ]]
}

@test "base_process_owner_alive accepts a directly parented guardian" {
    owner_pid="$BASHPID"

    (
        base_process_owner_alive "$owner_pid" "$BASHPID"
    )
}

@test "base_process_owner_alive rejects a non-parent relationship" {
    run base_process_owner_alive 99999999 "$BASHPID"
    [ "$status" -eq 1 ]
}

@test "base_process_owner_alive rejects a vanished guardian" {
    run base_process_owner_alive "$BASHPID" 99999999
    [ "$status" -eq 1 ]
}

@test "base_process_owner_alive reports malformed calls as usage errors" {
    run base_process_owner_alive 123
    [ "$status" -eq 2 ]
    [[ "$output" == *"expected <owner_pid> <guardian_pid>"* ]]

    run base_process_owner_alive 0 12
    [ "$status" -eq 2 ]
    [[ "$output" == *"PIDs must be positive integers"* ]]
}

@test "owner guardian removes its channel before invoking cleanup" {
    local workspace="$TEST_TMPDIR/guardian-workspace"
    local guardian_pid="" guardian_fd="" reason_file="$TEST_TMPDIR/reason"

    mkdir "$workspace"
    mkfifo "$workspace/control"
    cleanup_guardian() {
        printf '%s\n' "$1" > "$reason_file"
        [ ! -e "$2/control" ]
        [ ! -e "$2/ready" ]
    }

    __base_bash_libs_process_start_owner_guardian__ \
        guardian_pid guardian_fd "$BASHPID" "$workspace/control" "$workspace/ready" \
        cleanup_guardian
    [ -e "$workspace/ready" ]

    __base_bash_libs_process_stop_owner_guardian__ "$guardian_pid" "$guardian_fd"
    [ "$(<"$reason_file")" = stop ]
    [ ! -e "$workspace/control" ]
    [ ! -e "$workspace/ready" ]
}

@test "owner guardian cleans up after its owner is killed" {
    local workspace="$TEST_TMPDIR/killed-owner-workspace"
    local owner_pid guardian_pid_file="$TEST_TMPDIR/guardian-pid"
    local probe

    (
        local guardian_pid="" guardian_fd=""
        mkdir "$workspace"
        mkfifo "$workspace/control"
        __base_bash_libs_process_start_owner_guardian__ \
            guardian_pid guardian_fd "$BASHPID" "$workspace/control" "$workspace/ready" \
            __base_bash_libs_process_test_cleanup__ "$workspace"
        printf '%s\n' "$guardian_pid" > "$guardian_pid_file"
        kill -KILL "$BASHPID"
    ) &
    owner_pid=$!

    for ((probe = 0; probe < 300; probe++)); do
        [ -e "$workspace/ready" ] && break
        /bin/sleep 0.01
    done
    wait "$owner_pid" 2> /dev/null || true
    for ((probe = 0; probe < 300; probe++)); do
        [ ! -e "$workspace" ] && break
        /bin/sleep 0.01
    done
    [ ! -e "$workspace" ]
}

__base_bash_libs_process_test_cleanup__() {
    local workspace="${2-}"
    rmdir -- "$workspace" 2> /dev/null || true
}
