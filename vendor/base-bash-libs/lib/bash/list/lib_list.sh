# shellcheck shell=bash
#
# lib_list.sh - Bash helpers for caller-owned indexed arrays.
#

[[ -n "${BASE_BASH_LIBS_LIST_LOADED:-}" ]] && return 0
if [[ "${BASE_BASH_LIBS_STDLIB_LOADED:-}" != "1" ]]; then
    printf '%s\n' "Error: lib_list.sh requires lib_std.sh to be sourced first." >&2
    return 1 2> /dev/null || exit 1
fi
readonly BASE_BASH_LIBS_LIST_LOADED=1

__base_bash_libs_list_equals_exact__() {
    local __base_bash_libs_list_left="${1-}" __base_bash_libs_list_right="${2-}"
    local __base_bash_libs_list_restore_nocasematch=0 __base_bash_libs_list_status=1

    if shopt -q nocasematch; then
        __base_bash_libs_list_restore_nocasematch=1
        shopt -u nocasematch
    fi
    if [[ "$__base_bash_libs_list_left" == "$__base_bash_libs_list_right" ]]; then
        __base_bash_libs_list_status=0
    else
        __base_bash_libs_list_status=1
    fi
    if ((__base_bash_libs_list_restore_nocasematch)); then
        shopt -s nocasematch
    fi
    return "$__base_bash_libs_list_status"
}

__base_bash_libs_list_assert_distinct_names__() {
    local __base_bash_libs_list_operation="${1-}" __base_bash_libs_list_result_name="${2-}" __base_bash_libs_list_source_name="${3-}"

    if [[ "$__base_bash_libs_list_result_name" == "$__base_bash_libs_list_source_name" ]]; then
        base_std_log_error -l base_bash_libs.list \
            "$__base_bash_libs_list_operation: result and source variables must be distinct; '$__base_bash_libs_list_result_name' was provided for both."
        return 1
    fi
    return 0
}

base_list_append() {
    if (($# < 2)); then
        base_std_log_error -l base_bash_libs.list \
            "base_list_append: usage: base_list_append <array_name> <value> [value...]"
        return 2
    fi
    __base_bash_libs_std_validate_variable_names__ base_list_append "${1-}" || return 2
    local __base_bash_libs_list_array_name="$1"
    local -a __base_bash_libs_list_values=()

    __base_bash_libs_std_validate_array_kind__ base_list_append a "$__base_bash_libs_list_array_name" || return 2
    __base_bash_libs_std_assert_writable_output__ base_list_append "$__base_bash_libs_list_array_name" indexed-array || return 2
    shift
    __base_bash_libs_list_values=("$@")
    eval "$__base_bash_libs_list_array_name+=(\"\${__base_bash_libs_list_values[@]}\")"
}

base_list_prepend() {
    if (($# < 2)); then
        base_std_log_error -l base_bash_libs.list \
            "base_list_prepend: usage: base_list_prepend <array_name> <value> [value...]"
        return 2
    fi
    __base_bash_libs_std_validate_variable_names__ base_list_prepend "${1-}" || return 2
    local __base_bash_libs_list_array_name="$1"
    local -a __base_bash_libs_list_values=() __base_bash_libs_list_current=() __base_bash_libs_list_combined=()

    __base_bash_libs_std_validate_array_kind__ base_list_prepend a "$__base_bash_libs_list_array_name" || return 2
    __base_bash_libs_std_assert_writable_output__ base_list_prepend "$__base_bash_libs_list_array_name" indexed-array || return 2
    shift
    __base_bash_libs_list_values=("$@")
    eval "if [[ -n \"\${${__base_bash_libs_list_array_name}[@]+set}\" ]]; then __base_bash_libs_list_current=(\"\${${__base_bash_libs_list_array_name}[@]}\"); fi"
    __base_bash_libs_list_combined=("${__base_bash_libs_list_values[@]+"${__base_bash_libs_list_values[@]}"}" "${__base_bash_libs_list_current[@]+"${__base_bash_libs_list_current[@]}"}")
    if ((${#__base_bash_libs_list_combined[@]} > 0)); then
        eval "$__base_bash_libs_list_array_name=(\"\${__base_bash_libs_list_combined[@]}\")"
    else
        eval "$__base_bash_libs_list_array_name=()"
    fi
}

#
# Removes every exact match from a caller-owned indexed array in place.
#
base_list_remove() {
    if (($# != 2)); then
        base_std_log_error -l base_bash_libs.list \
            "base_list_remove: usage: base_list_remove <array_name> <value>"
        return 2
    fi
    __base_bash_libs_std_validate_variable_names__ base_list_remove "${1-}" || return 2
    local __base_bash_libs_list_array_name="$1" __base_bash_libs_list_needle="$2" __base_bash_libs_list_item
    local -a __base_bash_libs_list_current=() __base_bash_libs_list_filtered=()

    __base_bash_libs_std_validate_array_kind__ base_list_remove a "$__base_bash_libs_list_array_name" || return 2
    __base_bash_libs_std_assert_writable_output__ base_list_remove "$__base_bash_libs_list_array_name" indexed-array || return 2

    eval "if [[ -n \"\${${__base_bash_libs_list_array_name}[@]+set}\" ]]; then __base_bash_libs_list_current=(\"\${${__base_bash_libs_list_array_name}[@]}\"); fi"
    for __base_bash_libs_list_item in "${__base_bash_libs_list_current[@]+"${__base_bash_libs_list_current[@]}"}"; do
        __base_bash_libs_list_equals_exact__ \
            "$__base_bash_libs_list_item" "$__base_bash_libs_list_needle" && continue
        __base_bash_libs_list_filtered+=("$__base_bash_libs_list_item")
    done

    if ((${#__base_bash_libs_list_filtered[@]} > 0)); then
        eval "$__base_bash_libs_list_array_name=(\"\${__base_bash_libs_list_filtered[@]}\")"
    else
        eval "$__base_bash_libs_list_array_name=()"
    fi
}

base_list_contains() {
    if (($# != 2)); then
        base_std_log_error -l base_bash_libs.list \
            "base_list_contains: usage: base_list_contains <value> <array_name>"
        return 2
    fi
    __base_bash_libs_std_validate_variable_names__ base_list_contains "${2-}" || return 2
    local __base_bash_libs_list_needle="$1" __base_bash_libs_list_array_name="$2" __base_bash_libs_list_item
    local -a __base_bash_libs_list_current=()

    __base_bash_libs_std_validate_array_kind__ base_list_contains a "$__base_bash_libs_list_array_name" || return 2

    eval "if [[ -n \"\${${__base_bash_libs_list_array_name}[@]+set}\" ]]; then __base_bash_libs_list_current=(\"\${${__base_bash_libs_list_array_name}[@]}\"); fi"
    for __base_bash_libs_list_item in "${__base_bash_libs_list_current[@]+"${__base_bash_libs_list_current[@]}"}"; do
        __base_bash_libs_list_equals_exact__ \
            "$__base_bash_libs_list_item" "$__base_bash_libs_list_needle" && return 0
    done

    return 1
}

base_list_unique() {
    if (($# != 2)); then
        base_std_log_error -l base_bash_libs.list \
            "base_list_unique: usage: base_list_unique <result_array> <source_array>"
        return 2
    fi
    __base_bash_libs_std_validate_variable_names__ base_list_unique "${1-}" "${2-}" || return 2
    local __base_bash_libs_list_result_name="$1" __base_bash_libs_list_array_name="$2" __base_bash_libs_list_item __base_bash_libs_list_key
    local -a __base_bash_libs_list_current=() __base_bash_libs_list_unique=()
    local -A __base_bash_libs_list_seen=()

    __base_bash_libs_list_assert_distinct_names__ base_list_unique "$__base_bash_libs_list_result_name" "$__base_bash_libs_list_array_name" || return 2
    __base_bash_libs_std_validate_array_kind__ base_list_unique a "$__base_bash_libs_list_result_name" "$__base_bash_libs_list_array_name" || return 2
    __base_bash_libs_std_assert_writable_output__ base_list_unique "$__base_bash_libs_list_result_name" indexed-array || return 2

    eval "if [[ -n \"\${${__base_bash_libs_list_array_name}[@]+set}\" ]]; then __base_bash_libs_list_current=(\"\${${__base_bash_libs_list_array_name}[@]}\"); fi"
    for __base_bash_libs_list_item in "${__base_bash_libs_list_current[@]+"${__base_bash_libs_list_current[@]}"}"; do
        __base_bash_libs_list_key="v:$__base_bash_libs_list_item"
        [[ -n "${__base_bash_libs_list_seen[$__base_bash_libs_list_key]+set}" ]] && continue
        __base_bash_libs_list_seen["$__base_bash_libs_list_key"]=1
        __base_bash_libs_list_unique+=("$__base_bash_libs_list_item")
    done

    if ((${#__base_bash_libs_list_unique[@]} > 0)); then
        eval "$__base_bash_libs_list_result_name=(\"\${__base_bash_libs_list_unique[@]}\")"
    else
        eval "$__base_bash_libs_list_result_name=()"
    fi
}

base_list_length() {
    if (($# != 2)); then
        base_std_log_error -l base_bash_libs.list \
            "base_list_length: usage: base_list_length <result_variable> <source_array>"
        return 2
    fi
    __base_bash_libs_std_validate_variable_names__ base_list_length "${1-}" "${2-}" || return 2
    local __base_bash_libs_list_result_name="$1" __base_bash_libs_list_array_name="$2"
    local __base_bash_libs_list_count=0
    local -a __base_bash_libs_list_current=()

    __base_bash_libs_list_assert_distinct_names__ base_list_length "$__base_bash_libs_list_result_name" "$__base_bash_libs_list_array_name" || return 2
    __base_bash_libs_std_validate_array_kind__ base_list_length a "$__base_bash_libs_list_array_name" || return 2
    __base_bash_libs_std_assert_writable_output__ base_list_length "$__base_bash_libs_list_result_name" integer || return 2

    eval "if [[ -n \"\${${__base_bash_libs_list_array_name}[@]+set}\" ]]; then __base_bash_libs_list_current=(\"\${${__base_bash_libs_list_array_name}[@]}\"); fi"
    # shellcheck disable=SC2199 # The + expansion safely detects Bash 4.2 empty arrays under nounset.
    if [[ -n "${__base_bash_libs_list_current[@]+set}" ]]; then
        __base_bash_libs_list_count="${#__base_bash_libs_list_current[@]}"
    fi
    printf -v "$__base_bash_libs_list_result_name" '%s' "$__base_bash_libs_list_count"
}
