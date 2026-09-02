#!/usr/bin/env bats

load ../../tests/test_helper.sh

setup() {
    setup_test_tmpdir
    source "$BASE_BASH_DIR/std/lib_std.sh"
    declare -a setup_args=()
    base_init setup_args --source "$BASE_BASH_DIR/list/tests/lib_list.bats" --
    source "$BASE_BASH_DIR/list/lib_list.sh"
}

create_script() {
    local script_path="$1"
    local content source_line init_lines
    content="$(cat)"
    source_line="source \"$BASE_BASH_DIR/std/lib_std.sh\""
    if [[ "$content" == *"$source_line"* ]]; then
        init_lines=$'declare -a base_bash_libs_test_args=()\nbase_init base_bash_libs_test_args -- "$@"\nset -- "${base_bash_libs_test_args[@]}"'
        content="${content/"$source_line"/"$source_line"$'\n'"$init_lines"}"
    fi
    printf '%s\n' "$content" > "$script_path"
    chmod +x "$script_path"
}

@test "lib_list can be sourced more than once" {
    source "$BASE_BASH_DIR/list/lib_list.sh"

    [ "$(type -t base_list_append)" = "function" ]
}

@test "lib_list fails clearly when sourced without stdlib" {
    bats_run bash -c 'source "$1"; rc=$?; printf "source-rc=%s\n" "$rc"; exit "$rc"' bash "$BASE_BASH_DIR/list/lib_list.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"lib_list.sh requires lib_std.sh to be sourced first"* ]]
    [[ "$output" == *"source-rc=1"* ]]
    [[ "$output" != *"command not found"* ]]
}

@test "lib_list requires the stdlib loaded marker" {
    bats_run bash -c 'base_std_log_error() { :; }; base_std_log_debug() { :; }; source "$1"; rc=$?; printf "source-rc=%s\n" "$rc"; exit "$rc"' bash "$BASE_BASH_DIR/list/lib_list.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"lib_list.sh requires lib_std.sh to be sourced first"* ]]
    [[ "$output" == *"source-rc=1"* ]]
}

@test "list APIs reject missing arguments under every caller option combination" {
    local function_name mode

    for mode in off e u p eu ep up eup; do
        for function_name in \
            base_list_append \
            base_list_prepend \
            base_list_remove \
            base_list_contains \
            base_list_unique \
            base_list_length; do
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
                exit $?
            ' bash "$mode" "$BASE_BASH_DIR/std/lib_std.sh" "$BASE_BASH_DIR/list/lib_list.sh" "$function_name"

            if [[ "$function_name" == base_list_append || "$function_name" == base_list_prepend ]]; then
                [ "$status" -eq 2 ]
            else
                [ "$status" -eq 1 ]
            fi
            [[ "$output" != *"unbound variable"* ]]
        done
    done
}

@test "base_list_append and base_list_prepend mutate caller arrays in place" {
    local -a values=("middle")

    base_list_append values "tail one" ""
    base_list_prepend values "head"

    [ "${#values[@]}" -eq 4 ]
    [ "${values[0]}" = "head" ]
    [ "${values[1]}" = "middle" ]
    [ "${values[2]}" = "tail one" ]
    [ "${values[3]}" = "" ]
}

@test "base_list_remove deletes all matching values and preserves order" {
    local -a values=("alpha" "beta" "alpha" "" "gamma")

    base_list_remove values "alpha"

    [ "${#values[@]}" -eq 3 ]
    [ "${values[0]}" = "beta" ]
    [ "${values[1]}" = "" ]
    [ "${values[2]}" = "gamma" ]

    base_list_remove values ""

    [ "${#values[@]}" -eq 2 ]
    [ "${values[0]}" = "beta" ]
    [ "${values[1]}" = "gamma" ]
}

@test "base_list_contains checks membership without printing" {
    local -a values=("alpha" "beta gamma" "")
    local stdout_file="$TEST_TMPDIR/list-contains.out"

    base_list_contains "beta gamma" values >"$stdout_file"
    base_list_contains "" values >>"$stdout_file"

    if base_list_contains "delta" values; then
        return 1
    fi
    [ ! -s "$stdout_file" ]
}

@test "base_list_unique stores deduplicated values in a named result array" {
    local -a values=("alpha" "beta" "alpha" "" "beta" "")
    local -a unique=()

    base_list_unique unique values

    [ "${#unique[@]}" -eq 3 ]
    [ "${unique[0]}" = "alpha" ]
    [ "${unique[1]}" = "beta" ]
    [ "${unique[2]}" = "" ]
}

@test "list result helpers reject source aliases before mutation" {
    local -a values=("alpha" "alpha" "beta")
    local rc

    if base_list_unique values values 2>/dev/null; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "${#values[@]}" -eq 3 ]
    [ "${values[0]}" = "alpha" ]
    [ "${values[1]}" = "alpha" ]
    [ "${values[2]}" = "beta" ]

    if base_list_length values values 2>/dev/null; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "${#values[@]}" -eq 3 ]
    [ "${values[0]}" = "alpha" ]
    [ "${values[1]}" = "alpha" ]
    [ "${values[2]}" = "beta" ]
}

@test "list helpers reject exact internal holder names before locals or mutation" {
    local -r __base_bash_libs_list_array_name=actual
    local -a actual=(keep)
    local -ar __base_bash_libs_list_current=(alpha beta)
    local -a result=(saved)
    local count=saved
    local stderr_file="$TEST_TMPDIR/list-internal-holder.err"
    local rc

    if base_list_append __base_bash_libs_list_array_name new 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "${actual[*]}" = "keep" ]

    if base_list_contains alpha __base_bash_libs_list_current 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]

    if base_list_unique result __base_bash_libs_list_current 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "${result[*]}" = "saved" ]

    if base_list_length count __base_bash_libs_list_current 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "$count" = "saved" ]
    [ "${__base_bash_libs_list_current[*]}" = "alpha beta" ]
    [[ "$(cat "$stderr_file")" == *"uses the reserved '__' internal namespace"* ]]
    [[ "$(cat "$stderr_file")" != *"readonly variable"* ]]
}

@test "base_list_length stores the array length in a named variable" {
    local -a values=("alpha" "beta gamma" "")
    local count=""

    base_list_length count values

    [ "$count" = "3" ]
}

@test "list helpers handle declared-empty arrays under nounset" {
    local script="$TEST_TMPDIR/list-empty-nounset.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
set -u
source "$BASE_BASH_DIR/std/lib_std.sh"
source "$BASE_BASH_DIR/list/lib_list.sh"
declare -a values=()
declare -a unique=(old)
base_list_prepend values head
base_list_remove values head
base_list_contains missing values && exit 10
base_list_unique unique values
count=invalid
base_list_length count values
[[ -z "\${values[*]-}" ]]
[[ -z "\${unique[*]-}" ]]
[[ "\$count" == 0 ]]
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
}

@test "list mutators reject readonly output variables" {
    local -a values=("alpha")
    local stderr_file="$TEST_TMPDIR/list-readonly.err"
    local rc

    readonly values
    if base_list_append values beta 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 1 ]
    [ "${values[*]}" = "alpha" ]
    [[ "$(cat "$stderr_file")" == *"result variable 'values' is readonly"* ]]
}

@test "list helpers reject invalid variable names without echoing values" {
    local script="$TEST_TMPDIR/list-invalid-vars.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$BASE_BASH_DIR/std/lib_std.sh"
source "$BASE_BASH_DIR/list/lib_list.sh"
secret="not-valid"
base_list_append "\$secret" "value"
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"base_std_assert_variable_name expects valid Bash variable names"* ]]
    [[ "$output" != *"not-valid"* ]]
}

@test "list helpers reject non-indexed arrays" {
    local script="$TEST_TMPDIR/list-non-indexed.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$BASE_BASH_DIR/std/lib_std.sh"
source "$BASE_BASH_DIR/list/lib_list.sh"
values="alpha"
base_list_append values "beta"
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"must be an indexed array declared by the caller"* ]]

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$BASE_BASH_DIR/std/lib_std.sh"
source "$BASE_BASH_DIR/list/lib_list.sh"
declare -A values=([alpha]="one")
base_list_contains "one" values
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"must be an indexed array declared by the caller"* ]]

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$BASE_BASH_DIR/std/lib_std.sh"
source "$BASE_BASH_DIR/list/lib_list.sh"
declare -a values=("alpha")
base_list_unique unique values
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"must be an indexed array declared by the caller"* ]]
}
