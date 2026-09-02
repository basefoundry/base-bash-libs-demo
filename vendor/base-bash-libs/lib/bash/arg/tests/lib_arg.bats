#!/usr/bin/env bats

load ../../tests/test_helper.sh

setup() {
    setup_test_tmpdir
    source "$BASE_BASH_DIR/std/lib_std.sh"
    declare -a setup_args=()
    base_init setup_args --source "$BASE_BASH_DIR/arg/tests/lib_arg.bats" --
    source "$BASE_BASH_DIR/arg/lib_arg.sh"
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

@test "lib_arg can be sourced more than once" {
    source "$BASE_BASH_DIR/arg/lib_arg.sh"

    [ "$(type -t base_arg_parse)" = "function" ]
}

@test "lib_arg fails clearly when sourced without stdlib" {
    bats_run bash -c 'source "$1"; rc=$?; printf "source-rc=%s\n" "$rc"; exit "$rc"' bash "$BASE_BASH_DIR/arg/lib_arg.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"lib_arg.sh requires lib_std.sh to be sourced first"* ]]
    [[ "$output" == *"source-rc=1"* ]]
    [[ "$output" != *"command not found"* ]]
}

@test "lib_arg requires the stdlib loaded marker" {
    bats_run bash -c 'base_std_log_error() { :; }; base_std_log_debug() { :; }; source "$1"; rc=$?; printf "source-rc=%s\n" "$rc"; exit "$rc"' bash "$BASE_BASH_DIR/arg/lib_arg.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"lib_arg.sh requires lib_std.sh to be sourced first"* ]]
    [[ "$output" == *"source-rc=1"* ]]
}

@test "base_arg_parse returns usage without nounset aborts under every caller option combination" {
    local mode

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
            base_arg_parse
            exit $?
        ' bash "$mode" "$BASE_BASH_DIR/std/lib_std.sh" "$BASE_BASH_DIR/arg/lib_arg.sh"

        [ "$status" -eq 2 ]
        [[ "$output" == *"base_arg_parse: usage:"* ]]
        [[ "$output" != *"unbound variable"* ]]
    done
}

@test "base_arg_parse stores flags values and positionals" {
    local -a specs=(
        "verbose|flag|--verbose|-v"
        "output|value|--output|-o"
    )
    local -A options=()
    local -a positionals=()

    base_arg_parse options positionals specs -- --verbose -o "build result.txt" alpha -- beta gamma

    [ "${options[verbose]}" = "1" ]
    [ "${options[output]}" = "build result.txt" ]
    [ "${#positionals[@]}" -eq 3 ]
    [ "${positionals[0]}" = "alpha" ]
    [ "${positionals[1]}" = "beta" ]
    [ "${positionals[2]}" = "gamma" ]
}

@test "base_arg_parse rejects readonly output arrays before parsing" {
    local script="$TEST_TMPDIR/arg-readonly-output.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$BASE_BASH_DIR/std/lib_std.sh"
source "$BASE_BASH_DIR/arg/lib_arg.sh"
declare -Ar options=()
declare -a positionals=()
declare -a specs=("verbose|flag|--verbose")
base_arg_parse options positionals specs -- --verbose
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"result variable 'options' is readonly"* ]]
}

@test "base_arg_parse supports shadowing-prone caller array names" {
    local -a specs_name=(
        "verbose|flag|--verbose|-v"
        "output|value|--output|-o"
    )
    local -A options_name=()
    local -a positionals_name=()

    base_arg_parse options_name positionals_name specs_name -- -v --output result.txt item

    [ "${options_name[verbose]}" = "1" ]
    [ "${options_name[output]}" = "result.txt" ]
    [ "${#positionals_name[@]}" -eq 1 ]
    [ "${positionals_name[0]}" = "item" ]
}

@test "base_arg_parse rejects reserved internal output names" {
    local -A __base_bash_libs_arg_options=([sentinel]="keep")
    local -a __base_bash_libs_arg_positionals=(sentinel)
    local -a specs_name=("verbose|flag|--verbose|-v")
    local stderr_file="$TEST_TMPDIR/arg-reserved-output.err"
    local rc

    if base_arg_parse __base_bash_libs_arg_options __base_bash_libs_arg_positionals specs_name -- -v 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 1 ]
    [ "${__base_bash_libs_arg_options[sentinel]}" = "keep" ]
    [ "${__base_bash_libs_arg_positionals[0]}" = "sentinel" ]
    [[ "$(cat "$stderr_file")" == *"uses the reserved '__' internal namespace"* ]]
}

@test "base_arg_parse rejects exact internal holder and repeatable names before locals or mutation" {
    local -r __base_bash_libs_arg_options_name=actual_options
    local -A actual_options=([sentinel]="keep")
    local -a positionals=(old)
    local -a specs=("verbose|flag|--verbose")
    local -ar __base_bash_libs_arg_repeatable_name=(saved)
    local -a repeatable_specs=("__base_bash_libs_arg_repeatable_name|repeatable|--include")
    local stderr_file="$TEST_TMPDIR/arg-internal-holder.err"
    local rc

    if base_arg_parse __base_bash_libs_arg_options_name positionals specs -- --verbose 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "${actual_options[sentinel]}" = "keep" ]
    [ "${positionals[0]}" = "old" ]
    [[ "$(cat "$stderr_file")" == *"uses the reserved '__' internal namespace"* ]]
    [[ "$(cat "$stderr_file")" != *"readonly variable"* ]]

    if base_arg_parse actual_options positionals repeatable_specs -- --include new 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "${actual_options[sentinel]}" = "keep" ]
    [ "${positionals[0]}" = "old" ]
    [ "${__base_bash_libs_arg_repeatable_name[0]}" = "saved" ]
    [[ "$(cat "$stderr_file")" == *"uses the reserved '__' internal namespace"* ]]
    [[ "$(cat "$stderr_file")" != *"readonly variable"* ]]
}

@test "base_arg_parse rejects aliases among its primary caller-owned arrays before mutation" {
    local -A options=([existing]="keep")
    local -a positionals=(old)
    local -a specs=("verbose|flag|--verbose|-v")
    local rc

    if base_arg_parse options options specs -- --verbose 2>/dev/null; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "${options[existing]}" = "keep" ]

    if base_arg_parse options positionals options -- --verbose 2>/dev/null; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "${options[existing]}" = "keep" ]
    [ "${positionals[0]}" = "old" ]

    if base_arg_parse options positionals positionals -- --verbose 2>/dev/null; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "${options[existing]}" = "keep" ]
    [ "${positionals[0]}" = "old" ]
    [ "${specs[0]}" = "verbose|flag|--verbose|-v" ]
}

@test "base_arg_parse rejects repeatable-output aliases before mutation" {
    local -A options=([existing]="keep")
    local -a positionals=(old)
    local -a specs=("include|repeatable|--include")
    local -a include=(saved)
    local rc

    if base_arg_parse options include specs -- --include new 2>/dev/null; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "${options[existing]}" = "keep" ]
    [ "${include[0]}" = "saved" ]

    include=("include|repeatable|--include")
    if base_arg_parse options positionals include -- --include new 2>/dev/null; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "${options[existing]}" = "keep" ]
    [ "${positionals[0]}" = "old" ]
    [ "${include[0]}" = "include|repeatable|--include" ]
}

@test "base_arg_parse accepts long option equals values and repeated options" {
    local -a specs=(
        "verbose|flag|--verbose|-v"
        "output|value|--output|-o"
    )
    local -A options=()
    local -a positionals=()

    base_arg_parse options positionals specs -- --output=first.txt --output second.txt -v -v item

    [ "${options[verbose]}" = "1" ]
    [ "${options[output]}" = "second.txt" ]
    [ "${#positionals[@]}" -eq 1 ]
    [ "${positionals[0]}" = "item" ]
}

@test "base_arg_parse accepts -- as a value option value" {
    local -a specs=("output|value|--output|-o")
    local -A options=()
    local -a positionals=()

    base_arg_parse options positionals specs -- --output -- item

    [ "${options[output]}" = "--" ]
    [ "${#positionals[@]}" -eq 1 ]
    [ "${positionals[0]}" = "item" ]
}

@test "base_arg_parse preserves repeatable values in caller-owned arrays" {
    local -a specs=("include|repeatable|--include|-I")
    local -a include=()
    local -A options=()
    local -a positionals=()

    base_arg_parse options positionals specs -- --include first --include=second -I "" item

    [ "${options[include]}" = "1" ]
    [ "${#include[@]}" -eq 3 ]
    [ "${include[0]}" = "first" ]
    [ "${include[1]}" = "second" ]
    [ "${include[2]}" = "" ]
    [ "${positionals[0]}" = "item" ]
}

@test "base_arg_parse clears repeatable arrays when a successful parse has no values" {
    local -a specs=("include|repeatable|--include")
    local -a include=(old)
    local -A options=([include]=old)
    local -a positionals=()

    base_arg_parse options positionals specs -- item

    [ "${#include[@]}" -eq 0 ]
    [ -z "${options[include]+set}" ]
}

@test "base_arg_parse handles declared-empty arrays under nounset" {
    local script="$TEST_TMPDIR/arg-empty-nounset.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
set -u
source "$BASE_BASH_DIR/std/lib_std.sh"
source "$BASE_BASH_DIR/arg/lib_arg.sh"
declare -A options=()
declare -a positionals=()
declare -a specs=()
base_arg_parse options positionals specs --
[[ -z "\${options[*]-}" ]]
[[ -z "\${positionals[*]-}" ]]
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
}

@test "base_arg_parse returns usage status for unknown options" {
    local -a specs=("verbose|flag|--verbose|-v")
    local -A options=()
    local -a positionals=()
    local parse_status=0

    base_arg_parse options positionals specs -- --unknown || parse_status=$?

    [ "$parse_status" -eq 2 ]
}

@test "base_arg_parse preserves caller outputs when an unknown option follows accepted args" {
    local -a specs=("verbose|flag|--verbose|-v")
    local -A options=([existing]="keep")
    local -a positionals=("old")
    local parse_status=0

    base_arg_parse options positionals specs -- --verbose item --unknown || parse_status=$?

    [ "$parse_status" -eq 2 ]
    [ "${options[existing]}" = "keep" ]
    [ -z "${options[verbose]+set}" ]
    [ "${#positionals[@]}" -eq 1 ]
    [ "${positionals[0]}" = "old" ]
}

@test "base_arg_parse returns usage status when option values are missing" {
    local -a specs=("output|value|--output|-o")
    local -A options=()
    local -a positionals=()
    local parse_status=0

    base_arg_parse options positionals specs -- --output || parse_status=$?

    [ "$parse_status" -eq 2 ]
}

@test "base_arg_parse preserves caller outputs when a value option fails late" {
    local -a specs=(
        "verbose|flag|--verbose|-v"
        "output|value|--output|-o"
    )
    local -A options=([existing]="keep")
    local -a positionals=("old")
    local parse_status=0

    base_arg_parse options positionals specs -- --verbose --output || parse_status=$?

    [ "$parse_status" -eq 2 ]
    [ "${options[existing]}" = "keep" ]
    [ -z "${options[verbose]+set}" ]
    [ -z "${options[output]+set}" ]
    [ "${#positionals[@]}" -eq 1 ]
    [ "${positionals[0]}" = "old" ]
}

@test "base_arg_parse rejects registered options as missing option values" {
    local -a specs=(
        "verbose|flag|--verbose|-v"
        "output|value|--output|-o"
    )
    local -A options=()
    local -a positionals=()
    local parse_status=0

    base_arg_parse options positionals specs -- --output --verbose || parse_status=$?

    [ "$parse_status" -eq 2 ]
    [ -z "${options[output]+set}" ]
    [ -z "${options[verbose]+set}" ]
}

@test "base_arg_parse rejects invalid variable names without echoing values" {
    local script="$TEST_TMPDIR/arg-invalid-vars.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$BASE_BASH_DIR/std/lib_std.sh"
source "$BASE_BASH_DIR/arg/lib_arg.sh"
secret="not-valid"
declare -a specs=("verbose|flag|--verbose")
base_arg_parse "\$secret" positionals specs -- --verbose
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"base_std_assert_variable_name expects valid Bash variable names"* ]]
    [[ "$output" != *"not-valid"* ]]
}

@test "base_arg_parse asserts caller-owned array declarations" {
    local script="$TEST_TMPDIR/arg-invalid-array-vars.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$BASE_BASH_DIR/std/lib_std.sh"
source "$BASE_BASH_DIR/arg/lib_arg.sh"
declare -a options=()
declare -a positionals=()
declare -a specs=("verbose|flag|--verbose")
base_arg_parse options positionals specs -- --verbose
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Variable 'options' must be an associative array declared by the caller."* ]]

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$BASE_BASH_DIR/std/lib_std.sh"
source "$BASE_BASH_DIR/arg/lib_arg.sh"
declare -A options=()
positionals=""
declare -a specs=("verbose|flag|--verbose")
base_arg_parse options positionals specs -- --verbose
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Variable 'positionals' must be an indexed array declared by the caller."* ]]
}

@test "base_arg_parse rejects malformed specs" {
    local -a specs=("verbose|maybe|--verbose")
    local -A options=()
    local -a positionals=()
    local parse_status=0

    base_arg_parse options positionals specs -- --verbose || parse_status=$?

    [ "$parse_status" -eq 2 ]
}

@test "base_arg_parse rejects duplicate names and tokens without changing outputs" {
    local -a specs=("first|flag|--first" "second|value|--first")
    local -A options=([existing]=keep)
    local -a positionals=(old)
    local parse_status=0

    base_arg_parse options positionals specs -- --first || parse_status=$?

    [ "$parse_status" -eq 2 ]
    [ "${options[existing]}" = "keep" ]
    [ "${#positionals[@]}" -eq 1 ]
    [ "${positionals[0]}" = "old" ]
}

@test "base_arg_parse rejects unreachable and empty option tokens" {
    local -A options=()
    local -a positionals=()
    local parse_status=0
    local -a specs=("value|value|--value|--")

    base_arg_parse options positionals specs -- --value x || parse_status=$?

    [ "$parse_status" -eq 2 ]

    parse_status=0
    specs=("value|value|--value|")
    base_arg_parse options positionals specs -- --value x || parse_status=$?

    [ "$parse_status" -eq 2 ]
}
