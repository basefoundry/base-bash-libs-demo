# shellcheck shell=bash
#
# lib_str.sh - Bash library of generic string manipulation functions.
#

[[ -n "${BASE_BASH_LIBS_STR_LOADED:-}" ]] && return 0
if [[ "${BASE_BASH_LIBS_STDLIB_LOADED:-}" != "1" ]]; then
    printf '%s\n' "Error: lib_str.sh requires lib_std.sh to be sourced first." >&2
    return 1 2>/dev/null || exit 1
fi
readonly BASE_BASH_LIBS_STR_LOADED=1

base_str_lower() {
    base_std_assert_arg_count "$#" 1
    __base_bash_libs_std_assert_public_variable_names__ base_str_lower "${1-}" || return 1
    local __base_bash_libs_str_var_name="$1" __base_bash_libs_str_value

    base_std_assert_variable_name "$__base_bash_libs_str_var_name"
    __base_bash_libs_std_assert_writable_output__ base_str_lower "$__base_bash_libs_str_var_name" || return 1
    __base_bash_libs_str_value="${!__base_bash_libs_str_var_name-}"
    printf -v "$__base_bash_libs_str_var_name" '%s' "${__base_bash_libs_str_value,,}"
}

base_str_upper() {
    base_std_assert_arg_count "$#" 1
    __base_bash_libs_std_assert_public_variable_names__ base_str_upper "${1-}" || return 1
    local __base_bash_libs_str_var_name="$1" __base_bash_libs_str_value

    base_std_assert_variable_name "$__base_bash_libs_str_var_name"
    __base_bash_libs_std_assert_writable_output__ base_str_upper "$__base_bash_libs_str_var_name" || return 1
    __base_bash_libs_str_value="${!__base_bash_libs_str_var_name-}"
    printf -v "$__base_bash_libs_str_var_name" '%s' "${__base_bash_libs_str_value^^}"
}

base_str_ltrim() {
    base_std_assert_arg_count "$#" 1
    __base_bash_libs_std_assert_public_variable_names__ base_str_ltrim "${1-}" || return 1
    local __base_bash_libs_str_var_name="$1" __base_bash_libs_str_value

    base_std_assert_variable_name "$__base_bash_libs_str_var_name"
    __base_bash_libs_std_assert_writable_output__ base_str_ltrim "$__base_bash_libs_str_var_name" || return 1
    __base_bash_libs_str_value="${!__base_bash_libs_str_var_name-}"
    __base_bash_libs_str_value="${__base_bash_libs_str_value#"${__base_bash_libs_str_value%%[![:space:]]*}"}"
    printf -v "$__base_bash_libs_str_var_name" '%s' "$__base_bash_libs_str_value"
}

base_str_rtrim() {
    base_std_assert_arg_count "$#" 1
    __base_bash_libs_std_assert_public_variable_names__ base_str_rtrim "${1-}" || return 1
    local __base_bash_libs_str_var_name="$1" __base_bash_libs_str_value

    base_std_assert_variable_name "$__base_bash_libs_str_var_name"
    __base_bash_libs_std_assert_writable_output__ base_str_rtrim "$__base_bash_libs_str_var_name" || return 1
    __base_bash_libs_str_value="${!__base_bash_libs_str_var_name-}"
    __base_bash_libs_str_value="${__base_bash_libs_str_value%"${__base_bash_libs_str_value##*[![:space:]]}"}"
    printf -v "$__base_bash_libs_str_var_name" '%s' "$__base_bash_libs_str_value"
}

base_str_trim() {
    base_std_assert_arg_count "$#" 1
    __base_bash_libs_std_assert_public_variable_names__ base_str_trim "${1-}" || return 1
    base_str_ltrim "$1" || return $?
    base_str_rtrim "$1" || return $?
}

base_str_contains() {
    local value="${1-}" needle="${2-}"

    base_std_assert_arg_count "$#" 2
    [[ "$value" == *"$needle"* ]]
}

base_str_starts_with() {
    local value="${1-}" prefix="${2-}"

    base_std_assert_arg_count "$#" 2
    [[ "$value" == "$prefix"* ]]
}

base_str_ends_with() {
    local value="${1-}" suffix="${2-}"

    base_std_assert_arg_count "$#" 2
    [[ "$value" == *"$suffix" ]]
}

# Splits a value into a caller-owned indexed array. Empty fields are preserved,
# including the final empty field produced by a trailing separator.
base_str_split() {
    base_std_assert_arg_count "$#" 3
    __base_bash_libs_std_assert_public_variable_names__ base_str_split "${1-}" || return 1
    local __base_bash_libs_str_split_result_name="$1" __base_bash_libs_str_split_value="$2" __base_bash_libs_str_split_separator="$3"

    base_std_assert_variable_name "$__base_bash_libs_str_split_result_name"
    __base_bash_libs_std_assert_writable_output__ base_str_split "$__base_bash_libs_str_split_result_name" || return 1
    base_std_assert_indexed_array "$__base_bash_libs_str_split_result_name"

    local -a __base_bash_libs_str_split_fields=()
    local __base_bash_libs_str_split_remainder="$__base_bash_libs_str_split_value"

    if [[ -z "$__base_bash_libs_str_split_separator" ]]; then
        __base_bash_libs_str_split_fields=("$__base_bash_libs_str_split_value")
    else
        while [[ "$__base_bash_libs_str_split_remainder" == *"$__base_bash_libs_str_split_separator"* ]]; do
            __base_bash_libs_str_split_fields+=("${__base_bash_libs_str_split_remainder%%"$__base_bash_libs_str_split_separator"*}")
            __base_bash_libs_str_split_remainder="${__base_bash_libs_str_split_remainder#*"$__base_bash_libs_str_split_separator"}"
        done
        __base_bash_libs_str_split_fields+=("$__base_bash_libs_str_split_remainder")
    fi

    eval "$__base_bash_libs_str_split_result_name=(\"\${__base_bash_libs_str_split_fields[@]}\")"
}

base_str_join() {
    base_std_assert_arg_count "$#" 3
    __base_bash_libs_std_assert_public_variable_names__ base_str_join "${1-}" "${3-}" || return 1
    local __base_bash_libs_str_join_result_name="$1" __base_bash_libs_str_join_separator="$2" __base_bash_libs_str_join_array_name="$3"

    base_std_assert_variable_name "$__base_bash_libs_str_join_result_name" "$__base_bash_libs_str_join_array_name"
    if [[ "$__base_bash_libs_str_join_result_name" == "$__base_bash_libs_str_join_array_name" ]]; then
        base_std_log_error -l base_bash_libs.str \
            "base_str_join: result and source variables must be distinct; '$__base_bash_libs_str_join_result_name' was provided for both."
        return 1
    fi
    __base_bash_libs_std_assert_writable_output__ base_str_join "$__base_bash_libs_str_join_result_name" || return 1
    base_std_assert_indexed_array "$__base_bash_libs_str_join_array_name"

    local __base_bash_libs_str_join_joined="" __base_bash_libs_str_join_value __base_bash_libs_str_join_has_value=0
    local -a __base_bash_libs_str_join_values=()
    eval "if [[ -n \"\${${__base_bash_libs_str_join_array_name}[@]+set}\" ]]; then __base_bash_libs_str_join_values=(\"\${${__base_bash_libs_str_join_array_name}[@]}\"); fi"

    for __base_bash_libs_str_join_value in "${__base_bash_libs_str_join_values[@]+"${__base_bash_libs_str_join_values[@]}"}"; do
        if ((__base_bash_libs_str_join_has_value == 0)); then
            __base_bash_libs_str_join_joined="$__base_bash_libs_str_join_value"
            __base_bash_libs_str_join_has_value=1
        else
            __base_bash_libs_str_join_joined+="$__base_bash_libs_str_join_separator$__base_bash_libs_str_join_value"
        fi
    done

    printf -v "$__base_bash_libs_str_join_result_name" '%s' "$__base_bash_libs_str_join_joined"
}
