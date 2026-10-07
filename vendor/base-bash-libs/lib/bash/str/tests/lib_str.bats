#!/usr/bin/env bats

load ../../tests/test_helper.sh

setup() {
    setup_test_tmpdir
    source "$BASE_BASH_DIR/std/lib_std.sh"
    declare -a setup_args=()
    base_init setup_args --source "$BASE_BASH_DIR/str/tests/lib_str.bats" --
    source "$BASE_BASH_DIR/str/lib_str.sh"
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

@test "lib_str can be sourced more than once" {
    source "$BASE_BASH_DIR/str/lib_str.sh"

    [ "$(type -t base_str_trim)" = "function" ]
}

@test "lib_str fails clearly when sourced without stdlib" {
    bats_run bash -c 'source "$1"; rc=$?; printf "source-rc=%s\n" "$rc"; exit "$rc"' bash "$BASE_BASH_DIR/str/lib_str.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"lib_str.sh requires lib_std.sh to be sourced first"* ]]
    [[ "$output" == *"source-rc=1"* ]]
    [[ "$output" != *"command not found"* ]]
}

@test "lib_str requires the stdlib loaded marker" {
    bats_run bash -c 'base_std_log_error() { :; }; base_std_log_debug() { :; }; source "$1"; rc=$?; printf "source-rc=%s\n" "$rc"; exit "$rc"' bash "$BASE_BASH_DIR/str/lib_str.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"lib_str.sh requires lib_std.sh to be sourced first"* ]]
    [[ "$output" == *"source-rc=1"* ]]
}

@test "string APIs reject missing arguments under every caller option combination" {
    local function_name mode

    for mode in off e u p eu ep up eup; do
        for function_name in \
            base_str_lower \
            base_str_upper \
            base_str_ltrim \
            base_str_rtrim \
            base_str_trim \
            base_str_contains \
            base_str_starts_with \
            base_str_ends_with \
            base_str_split \
            base_str_join; do
            bats_run "$BASH" -c '
                mode="$1"
                case "$mode" in *e*) set -e ;; esac
                case "$mode" in *u*) set -u ;; esac
                case "$mode" in *p*) set -o pipefail ;; esac
                source "$2"
                declare -a app_args=()
                base_init app_args --
                source "$3"
                if "$4"; then status=0; else status=$?; fi
                printf "after\n"
                exit "$status"
            ' bash "$mode" "$BASE_BASH_DIR/std/lib_std.sh" "$BASE_BASH_DIR/str/lib_str.sh" "$function_name"

            [ "$status" -eq 2 ]
            [[ "$output" != *"unbound variable"* ]]
            [[ "$output" == *"after"* ]]
        done
    done
}

@test "string case helpers transform text without changing other characters" {
    local value="Alpha BETA 123!?"
    local stdout_file="$TEST_TMPDIR/case.stdout"

    base_str_lower value >"$stdout_file"

    [ "$value" = "alpha beta 123!?" ]
    [ ! -s "$stdout_file" ]

    base_str_upper value >"$stdout_file"

    [ "$value" = "ALPHA BETA 123!?" ]
    [ ! -s "$stdout_file" ]
}

@test "string trim helpers remove leading and trailing whitespace" {
    local value=$' \t  hello world  \t '
    local left=$' \t  hello world  \t '
    local right=$' \t  hello world  \t '
    local stdout_file="$TEST_TMPDIR/trim.stdout"

    base_str_trim value >"$stdout_file"
    base_str_ltrim left >"$stdout_file"
    base_str_rtrim right >"$stdout_file"

    [ "$value" = "hello world" ]
    [ "$left" = $'hello world  \t ' ]
    [ "$right" = $' \t  hello world' ]
    [ ! -s "$stdout_file" ]
}

@test "shared TSV field escaping preserves ordinary values and encodes delimiters" {
    local value=$'ordinary\\value\twith-tab\nwith-newline\rwith-carriage'
    local escaped expected

    escaped="$(__base_bash_libs_str_escape_tsv_field__ "$value")"
    expected=$'ordinary\\\\value\\twith-tab\\nwith-newline\\rwith-carriage'

    [ "$escaped" = "$expected" ]
}

@test "string mutators reject readonly output variables" {
    local value="Alpha"
    local stderr_file="$TEST_TMPDIR/string-readonly.err"
    local rc

    readonly value
    if base_str_lower value 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 2 ]
    [ "$value" = "Alpha" ]
    [[ "$(cat "$stderr_file")" == *"result variable 'value' is readonly"* ]]
}

@test "string mutators reject typed outputs before coercing caller data" {
    local stderr_file="$TEST_TMPDIR/string-typed-output.err"
    local rc
    local -i integer_value=42
    local -u uppercase_value=MiXeD

    if base_str_lower integer_value 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 2 ]
    [ "$integer_value" -eq 42 ]
    [[ "$(<"$stderr_file")" == *"attributes incompatible with the scalar output contract"* ]]

    if base_str_lower uppercase_value 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 2 ]
    [ "$uppercase_value" = MIXED ]
}

@test "string split rejects indexed-array outputs with coercing attributes" {
    local stderr_file="$TEST_TMPDIR/string-array-output.err"
    local rc
    local -au fields=(sentinel)

    if base_str_split fields "one:two" : 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 2 ]
    [ "${fields[0]}" = SENTINEL ]
    [ "${#fields[@]}" -eq 1 ]
    [[ "$(<"$stderr_file")" == *"attributes incompatible with the indexed-array output contract"* ]]
}

@test "array output contracts distinguish indexed from associative arrays with nocasematch" {
    local stderr_file="$TEST_TMPDIR/string-associative-output.err"
    local rc
    local -A fields=([keep]=sentinel)
    shopt -s nocasematch

    if base_str_split fields "one:two" : 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    shopt -u nocasematch

    [ "$rc" -eq 2 ]
    [ "${fields[keep]}" = sentinel ]
    [[ "$(<"$stderr_file")" == *"must be a caller-declared indexed array"* ]]
}

@test "readonly string outputs cannot collide with argument-count decimal locals" {
    local candidate

    for candidate in result_name value sign digits normalized; do
        bats_run "$BASH" -c '
            source "$1"
            declare -a app_args=()
            base_init app_args --
            source "$2"
            printf -v "$3" %s MiXeD
            readonly "$3"
            base_str_lower "$3"
            case $? in
                2) ;;
                *) exit 99 ;;
            esac
            printf "value=%s\n" "${!3}"
            exit 2
        ' bash "$BASE_BASH_DIR/std/lib_std.sh" "$BASE_BASH_DIR/str/lib_str.sh" "$candidate"

        [ "$status" -eq 2 ]
        [[ "$output" == *"result variable '$candidate' is readonly"* ]]
        [[ "$output" == *"value=MiXeD"* ]]
        [[ "$output" != *"readonly variable"* ]]
        [[ "$output" != *"local:"* ]]
    done
}

@test "string transform helpers reject invalid variable names" {
    local script="$TEST_TMPDIR/string-transform-invalid.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$BASE_BASH_DIR/std/lib_std.sh"
source "$BASE_BASH_DIR/str/lib_str.sh"
secret="not-valid"
base_str_trim "\$secret"
EOF

    bats_run bash "$script"

    [ "$status" -eq 2 ]
    [[ "$output" == *"base_str_trim: one or more variable names are invalid"* ]]
    [[ "$output" != *"not-valid"* ]]
}

@test "string predicate helpers check contains prefix and suffix" {
    base_str_contains "release-v1.2.3.tar.gz" "v1.2"
    base_str_starts_with "release-v1.2.3.tar.gz" "release-"
    base_str_ends_with "release-v1.2.3.tar.gz" ".tar.gz"

    if base_str_contains "release-v1.2.3.tar.gz" "v2"; then
        return 1
    fi
    if base_str_starts_with "release-v1.2.3.tar.gz" "debug-"; then
        return 1
    fi
    if base_str_ends_with "release-v1.2.3.tar.gz" ".zip"; then
        return 1
    fi
}

@test "string predicates and split remain exact under nocasematch" {
    local -a parts=()

    shopt -s nocasematch
    if base_str_contains "aB" "b"; then
        return 1
    fi
    if base_str_starts_with "aB" "A"; then
        return 1
    fi
    if base_str_ends_with "aB" "b"; then
        return 1
    fi

    base_str_split parts "aB" "b"
    shopt -q nocasematch
    shopt -u nocasematch

    [ "${#parts[@]}" -eq 1 ]
    [ "${parts[0]}" = "aB" ]
}

@test "string predicate helpers reject incorrect argument counts" {
    local script="$TEST_TMPDIR/string-predicate-arity.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$BASE_BASH_DIR/std/lib_std.sh"
source "$BASE_BASH_DIR/str/lib_str.sh"
"\$@"
EOF

    bats_run bash "$script" base_str_contains "needle-only"
    [ "$status" -eq 2 ]
    [[ "$output" == *"base_str_contains: usage"* ]]

    bats_run bash "$script" base_str_starts_with "value" "prefix" "extra"
    [ "$status" -eq 2 ]
    [[ "$output" == *"base_str_starts_with: usage"* ]]

    bats_run bash "$script" base_str_ends_with
    [ "$status" -eq 2 ]
    [[ "$output" == *"base_str_ends_with: usage"* ]]
}

@test "base_str_split stores delimited fields in a named array" {
    local -a parts=()

    base_str_split parts "alpha,beta,,gamma" ","

    [ "${#parts[@]}" -eq 4 ]
    [ "${parts[0]}" = "alpha" ]
    [ "${parts[1]}" = "beta" ]
    [ "${parts[2]}" = "" ]
    [ "${parts[3]}" = "gamma" ]
}

@test "base_str_split preserves a trailing empty field after a trailing separator" {
    local -a parts=()

    base_str_split parts "alpha,beta," ","

    [ "${#parts[@]}" -eq 3 ]
    [ "${parts[0]}" = "alpha" ]
    [ "${parts[1]}" = "beta" ]
    [ "${parts[2]}" = "" ]
}

@test "base_str_split preserves a leading empty field before the first separator" {
    local -a parts=()

    base_str_split parts ",alpha,beta" ","

    [ "${#parts[@]}" -eq 3 ]
    [ "${parts[0]}" = "" ]
    [ "${parts[1]}" = "alpha" ]
    [ "${parts[2]}" = "beta" ]
}

@test "base_str_split can store results in an array named fields" {
    local -a fields=()

    base_str_split fields "alpha:beta:gamma" ":"

    [ "${#fields[@]}" -eq 3 ]
    [ "${fields[0]}" = "alpha" ]
    [ "${fields[1]}" = "beta" ]
    [ "${fields[2]}" = "gamma" ]
}

@test "base_str_split rejects invalid result variable names" {
    local script="$TEST_TMPDIR/str-split-invalid.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$BASE_BASH_DIR/std/lib_std.sh"
source "$BASE_BASH_DIR/str/lib_str.sh"
secret="not-valid"
base_str_split "\$secret" "alpha,beta" ","
EOF

    bats_run bash "$script"

    [ "$status" -eq 2 ]
    [[ "$output" == *"base_str_split: one or more variable names are invalid"* ]]
    [[ "$output" != *"not-valid"* ]]
}

@test "base_str_join writes joined array values to a named result variable" {
    local -a values=("alpha" "beta gamma" "")
    local joined=""

    base_str_join joined "|" values

    [ "$joined" = "alpha|beta gamma|" ]
}

@test "base_str_join supports shadowing-prone result and source array names" {
    local -a values=("alpha" "beta")
    local -a array_name=("left" "right")
    local result_name=""
    local joined=""

    base_str_join result_name "," values
    base_str_join joined "|" array_name

    [ "$result_name" = "alpha,beta" ]
    [ "$joined" = "left|right" ]
}

@test "base_str_join rejects a source alias before mutation" {
    local -a values=("alpha" "beta")
    local rc

    if base_str_join values "," values 2>/dev/null; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 2 ]
    [ "${#values[@]}" -eq 2 ]
    [ "${values[0]}" = "alpha" ]
    [ "${values[1]}" = "beta" ]
}

@test "base_str_join handles a declared-empty array under nounset" {
    local script="$TEST_TMPDIR/str-join-empty-nounset.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
set -u
source "$BASE_BASH_DIR/std/lib_std.sh"
source "$BASE_BASH_DIR/str/lib_str.sh"
declare -a values=()
joined=invalid
base_str_join joined "," values
[[ -z "\$joined" ]]
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
}

@test "base_str_lower rejects reserved internal output names" {
    local __base_bash_libs_str_var_name="Mixed Case"
    local stderr_file="$TEST_TMPDIR/str-reserved-output.err"
    local rc

    if base_str_lower __base_bash_libs_str_var_name 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 2 ]
    [ "$__base_bash_libs_str_var_name" = "Mixed Case" ]
    [[ "$(cat "$stderr_file")" == *"uses the reserved '__' internal namespace"* ]]
}

@test "string helpers reject exact internal holder names before locals or mutation" {
    local -r __base_bash_libs_str_var_name=actual
    local actual="Mixed Case"
    local -r __base_bash_libs_str_join_result_name=joined
    local joined="keep"
    local -a values=(alpha beta)
    local -ar __base_bash_libs_str_join_values=(alpha beta)
    local stderr_file="$TEST_TMPDIR/str-internal-holder.err"
    local rc

    if base_str_lower __base_bash_libs_str_var_name 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 2 ]
    [ "$actual" = "Mixed Case" ]

    if base_str_join __base_bash_libs_str_join_result_name , values 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 2 ]
    [ "$joined" = "keep" ]

    if base_str_join joined , __base_bash_libs_str_join_values 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 2 ]
    [ "$joined" = "keep" ]
    [ "${__base_bash_libs_str_join_values[*]}" = "alpha beta" ]
    [[ "$(cat "$stderr_file")" == *"uses the reserved '__' internal namespace"* ]]
    [[ "$(cat "$stderr_file")" != *"readonly variable"* ]]
}

@test "base_str_join rejects invalid variable names" {
    local script="$TEST_TMPDIR/str-join-invalid-array.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$BASE_BASH_DIR/std/lib_std.sh"
source "$BASE_BASH_DIR/str/lib_str.sh"
secret="not-valid"
base_str_join joined " " "\$secret"
EOF

    bats_run bash "$script"

    [ "$status" -eq 2 ]
    [[ "$output" == *"base_str_join: one or more variable names are invalid"* ]]
    [[ "$output" != *"not-valid"* ]]

    script="$TEST_TMPDIR/str-join-invalid-result.sh"
    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$BASE_BASH_DIR/std/lib_std.sh"
source "$BASE_BASH_DIR/str/lib_str.sh"
declare -a values=("alpha")
secret="not-valid"
base_str_join "\$secret" " " values
EOF

    bats_run bash "$script"

    [ "$status" -eq 2 ]
    [[ "$output" == *"base_str_join: one or more variable names are invalid"* ]]
    [[ "$output" != *"not-valid"* ]]
}

@test "lib_str does not define list membership aliases" {
    [ "$(type -t str_in_array || true)" = "" ]
}

@test "string array helpers reject non-indexed arrays" {
    local script="$TEST_TMPDIR/str-non-indexed.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$BASE_BASH_DIR/std/lib_std.sh"
source "$BASE_BASH_DIR/str/lib_str.sh"
parts=""
base_str_split parts "alpha,beta" ","
EOF

    bats_run bash "$script"

    [ "$status" -eq 2 ]
    [[ "$output" == *"must be a caller-declared indexed array"* ]]

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$BASE_BASH_DIR/std/lib_std.sh"
source "$BASE_BASH_DIR/str/lib_str.sh"
declare -A values=([alpha]="one")
joined=""
base_str_join joined "," values
EOF

    bats_run bash "$script"

    [ "$status" -eq 2 ]
    [[ "$output" == *"must be a caller-declared indexed array"* ]]

}
