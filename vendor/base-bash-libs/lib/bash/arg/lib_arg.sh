# shellcheck shell=bash
#
# lib_arg.sh - Bash helpers for conservative option parsing.
#

[[ -n "${BASE_BASH_LIBS_ARG_LOADED:-}" ]] && return 0
if [[ "${BASE_BASH_LIBS_STDLIB_LOADED:-}" != "1" ]]; then
    printf '%s\n' "Error: lib_arg.sh requires lib_std.sh to be sourced first." >&2
    return 1 2> /dev/null || exit 1
fi
readonly BASE_BASH_LIBS_ARG_LOADED=1

__base_bash_libs_arg_set_assoc_value__() {
    local __base_bash_libs_arg_assoc_name="$1" __base_bash_libs_arg_assoc_key="$2" __base_bash_libs_arg_assoc_value="$3"

    # The variable name is validated before callers reach this helper.
    # shellcheck disable=SC1087
    printf -v "$__base_bash_libs_arg_assoc_name[$__base_bash_libs_arg_assoc_key]" '%s' "$__base_bash_libs_arg_assoc_value"
}

__base_bash_libs_arg_assert_distinct_names__() {
    local -a __base_bash_libs_arg_distinct_names=("$@")
    local __base_bash_libs_arg_left_index __base_bash_libs_arg_right_index

    for ((__base_bash_libs_arg_left_index = 0; __base_bash_libs_arg_left_index < ${#__base_bash_libs_arg_distinct_names[@]}; __base_bash_libs_arg_left_index++)); do
        for ((__base_bash_libs_arg_right_index = __base_bash_libs_arg_left_index + 1;  \
        __base_bash_libs_arg_right_index < ${#__base_bash_libs_arg_distinct_names[@]};  \
        __base_bash_libs_arg_right_index++)); do
            if [[ "${__base_bash_libs_arg_distinct_names[__base_bash_libs_arg_left_index]}" == "${__base_bash_libs_arg_distinct_names[__base_bash_libs_arg_right_index]}" ]]; then
                base_std_log_error -l base_bash_libs.arg \
                    "base_arg_parse: caller-owned variables must be distinct; '${__base_bash_libs_arg_distinct_names[__base_bash_libs_arg_left_index]}' was provided more than once."
                return 1
            fi
        done
    done
    return 0
}

__base_bash_libs_arg_preflight_repeatable_names__() {
    (($# == 1)) || return 0
    [[ "${1-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 0
    eval "if [[ -n \"\${${1}[@]+set}\" ]]; then set -- \"\${${1}[@]}\"; else set --; fi"

    while (($#)); do
        if [[ "${1#*|}" == repeatable\|* ]]; then
            __base_bash_libs_std_assert_public_variable_names__ base_arg_parse "${1%%|*}" || return 1
        fi
        shift
    done
    return 0
}

__base_bash_libs_arg_parse_specs__() {
    local __base_bash_libs_arg_specs_name="$1"
    local __base_bash_libs_arg_token_kind_name="$2" __base_bash_libs_arg_token_name_name="$3"
    local __base_bash_libs_arg_repeatable_names_name="${4-}"
    local __base_bash_libs_arg_options_name="${5-}" __base_bash_libs_arg_positionals_name="${6-}" __base_bash_libs_arg_caller_specs_name="${7-}"
    local -a __base_bash_libs_arg_specs=() __base_bash_libs_arg_tokens=()
    local __base_bash_libs_arg_spec __base_bash_libs_arg_remainder __base_bash_libs_arg_name __base_bash_libs_arg_kind __base_bash_libs_arg_tokens_part __base_bash_libs_arg_token
    local __base_bash_libs_arg_name_re='^[A-Za-z_][A-Za-z0-9_]*$'
    local __base_bash_libs_arg_token_re='^--?[[:alnum:]_][[:alnum:]_-]*$'
    local -A __base_bash_libs_arg_seen_names=() __base_bash_libs_arg_seen_tokens=()

    eval "if [[ -n \"\${${__base_bash_libs_arg_specs_name}[@]+set}\" ]]; then __base_bash_libs_arg_specs=(\"\${${__base_bash_libs_arg_specs_name}[@]}\"); fi"

    for __base_bash_libs_arg_spec in "${__base_bash_libs_arg_specs[@]+"${__base_bash_libs_arg_specs[@]}"}"; do
        __base_bash_libs_arg_name="${__base_bash_libs_arg_spec%%|*}"
        __base_bash_libs_arg_remainder="${__base_bash_libs_arg_spec#*|}"
        __base_bash_libs_arg_kind="${__base_bash_libs_arg_remainder%%|*}"
        __base_bash_libs_arg_tokens_part="${__base_bash_libs_arg_remainder#*|}"

        if [[ "$__base_bash_libs_arg_spec" == "$__base_bash_libs_arg_remainder" || "$__base_bash_libs_arg_remainder" == "$__base_bash_libs_arg_tokens_part" ||
            -z "$__base_bash_libs_arg_name" || -z "$__base_bash_libs_arg_kind" || -z "$__base_bash_libs_arg_tokens_part" ]]; then
            base_std_log_error -l base_bash_libs.arg "base_arg_parse: malformed option spec '$__base_bash_libs_arg_spec'."
            return 2
        fi
        if ! [[ "$__base_bash_libs_arg_name" =~ $__base_bash_libs_arg_name_re ]]; then
            base_std_log_error -l base_bash_libs.arg "base_arg_parse: option spec '$__base_bash_libs_arg_spec' name must be a valid Bash identifier."
            return 2
        fi
        if [[ -n "${__base_bash_libs_arg_seen_names[$__base_bash_libs_arg_name]+set}" ]]; then
            base_std_log_error -l base_bash_libs.arg "base_arg_parse: option spec name '$__base_bash_libs_arg_name' is duplicated."
            return 2
        fi
        __base_bash_libs_arg_seen_names["$__base_bash_libs_arg_name"]=1

        if [[ "$__base_bash_libs_arg_kind" != "flag" && "$__base_bash_libs_arg_kind" != "value" &&
            "$__base_bash_libs_arg_kind" != "repeatable" ]]; then
            base_std_log_error -l base_bash_libs.arg "base_arg_parse: option spec '$__base_bash_libs_arg_name' must use kind 'flag', 'value', or 'repeatable'."
            return 2
        fi

        if [[ "$__base_bash_libs_arg_kind" == "repeatable" ]]; then
            if [[ -z "$__base_bash_libs_arg_repeatable_names_name" ]]; then
                base_std_log_error -l base_bash_libs.arg "base_arg_parse: repeatable option spec '$__base_bash_libs_arg_name' requires an output array contract."
                return 2
            fi
            __base_bash_libs_std_assert_public_variable_names__ base_arg_parse "$__base_bash_libs_arg_name" || return 1
            __base_bash_libs_arg_assert_distinct_names__ \
                "$__base_bash_libs_arg_options_name" "$__base_bash_libs_arg_positionals_name" "$__base_bash_libs_arg_caller_specs_name" "$__base_bash_libs_arg_name" || return 1
            if ! __base_bash_libs_std_declares_array_kind__ "$__base_bash_libs_arg_name" "a"; then
                base_std_log_error -l base_bash_libs.arg "base_arg_parse: repeatable option '$__base_bash_libs_arg_name' requires a caller-declared indexed array."
                return 2
            fi
            __base_bash_libs_std_assert_writable_output__ base_arg_parse "$__base_bash_libs_arg_name" || return 1
            eval "$__base_bash_libs_arg_repeatable_names_name+=(\"\$__base_bash_libs_arg_name\")"
        fi

        if [[ "$__base_bash_libs_arg_tokens_part" == "|"* || "$__base_bash_libs_arg_tokens_part" == *"|" ||
            "$__base_bash_libs_arg_tokens_part" == *"||"* ]]; then
            base_std_log_error -l base_bash_libs.arg "base_arg_parse: option spec '$__base_bash_libs_arg_spec' contains an empty option token."
            return 2
        fi
        IFS='|' read -r -a __base_bash_libs_arg_tokens <<< "$__base_bash_libs_arg_tokens_part"
        for __base_bash_libs_arg_token in "${__base_bash_libs_arg_tokens[@]+"${__base_bash_libs_arg_tokens[@]}"}"; do
            if ! [[ "$__base_bash_libs_arg_token" =~ $__base_bash_libs_arg_token_re ]] || [[ "$__base_bash_libs_arg_token" == *"="* ]]; then
                base_std_log_error -l base_bash_libs.arg "base_arg_parse: option spec '$__base_bash_libs_arg_spec' has invalid option token '$__base_bash_libs_arg_token'."
                return 2
            fi
            if [[ -n "${__base_bash_libs_arg_seen_tokens[$__base_bash_libs_arg_token]+set}" ]]; then
                base_std_log_error -l base_bash_libs.arg "base_arg_parse: option token '$__base_bash_libs_arg_token' is duplicated."
                return 2
            fi
            __base_bash_libs_arg_seen_tokens["$__base_bash_libs_arg_token"]=1
            __base_bash_libs_arg_set_assoc_value__ "$__base_bash_libs_arg_token_kind_name" "$__base_bash_libs_arg_token" "$__base_bash_libs_arg_kind"
            __base_bash_libs_arg_set_assoc_value__ "$__base_bash_libs_arg_token_name_name" "$__base_bash_libs_arg_token" "$__base_bash_libs_arg_name"
        done
    done

    return 0
}

#
# base_arg_parse - Parses simple flags and value options into caller-owned variables.
#
# Spec entries use: name|kind|token[|token...]
#   - name: valid Bash identifier used as the associative-array key
#   - kind: "flag", "value", or "repeatable"
#   - token: exact option token, such as --verbose or -v
#
# Repeatable values are published to the caller-declared indexed array whose
# name is used as the spec name, while the options result records occurrence
# with a value of "1".
#
# Usage:
#   declare -A options=()
#   declare -a positionals=()
#   specs=("verbose|flag|--verbose|-v" "output|value|--output|-o")
#   base_arg_parse options positionals specs -- "$@"
#
base_arg_parse() {
    if (($# < 4)) || [[ "${4-}" != "--" ]]; then
        base_std_log_error -l base_bash_libs.arg "base_arg_parse: usage: base_arg_parse <options_assoc> <positionals_array> <specs_array> -- [args...]"
        return 2
    fi
    __base_bash_libs_std_assert_public_variable_names__ base_arg_parse "${1-}" "${2-}" "${3-}" || return 1
    __base_bash_libs_arg_preflight_repeatable_names__ "$3" || return 1

    local __base_bash_libs_arg_options_name="$1" __base_bash_libs_arg_positionals_name="$2" __base_bash_libs_arg_specs_name="$3"
    local __base_bash_libs_arg_current __base_bash_libs_arg_option_token __base_bash_libs_arg_option_value __base_bash_libs_arg_option_name __base_bash_libs_arg_option_kind
    local __base_bash_libs_arg_repeatable_name __base_bash_libs_arg_repeatable_index __base_bash_libs_arg_repeatable_value
    local -a __base_bash_libs_arg_positionals=() __base_bash_libs_arg_repeatable_names=() __base_bash_libs_arg_repeatable_values=()
    local -a __base_bash_libs_arg_publish_values=()
    local -A __base_bash_libs_arg_options=() __base_bash_libs_arg_token_kind=() __base_bash_libs_arg_token_name=()
    local __base_bash_libs_arg_parse_options=1

    base_std_assert_variable_name "$__base_bash_libs_arg_options_name" "$__base_bash_libs_arg_positionals_name" "$__base_bash_libs_arg_specs_name"
    __base_bash_libs_arg_assert_distinct_names__ "$__base_bash_libs_arg_options_name" "$__base_bash_libs_arg_positionals_name" "$__base_bash_libs_arg_specs_name" || return 1
    base_std_assert_associative_array "$__base_bash_libs_arg_options_name"
    base_std_assert_indexed_array "$__base_bash_libs_arg_positionals_name" "$__base_bash_libs_arg_specs_name"
    __base_bash_libs_std_assert_writable_output__ base_arg_parse "$__base_bash_libs_arg_options_name" || return 1
    __base_bash_libs_std_assert_writable_output__ base_arg_parse "$__base_bash_libs_arg_positionals_name" || return 1

    __base_bash_libs_arg_parse_specs__ "$__base_bash_libs_arg_specs_name" __base_bash_libs_arg_token_kind __base_bash_libs_arg_token_name __base_bash_libs_arg_repeatable_names \
        "$__base_bash_libs_arg_options_name" "$__base_bash_libs_arg_positionals_name" "$__base_bash_libs_arg_specs_name" || return $?

    shift 4

    while (($# > 0)); do
        __base_bash_libs_arg_current="$1"
        shift

        if ((__base_bash_libs_arg_parse_options)) && [[ "$__base_bash_libs_arg_current" == "--" ]]; then
            __base_bash_libs_arg_parse_options=0
            continue
        fi

        if ((__base_bash_libs_arg_parse_options)) && [[ "$__base_bash_libs_arg_current" == --*=* ]]; then
            __base_bash_libs_arg_option_token="${__base_bash_libs_arg_current%%=*}"
            __base_bash_libs_arg_option_value="${__base_bash_libs_arg_current#*=}"
            __base_bash_libs_arg_option_kind="${__base_bash_libs_arg_token_kind[$__base_bash_libs_arg_option_token]-}"
            __base_bash_libs_arg_option_name="${__base_bash_libs_arg_token_name[$__base_bash_libs_arg_option_token]-}"

            if [[ -z "$__base_bash_libs_arg_option_kind" ]]; then
                base_std_log_error -l base_bash_libs.arg "base_arg_parse: unknown option '$__base_bash_libs_arg_option_token'."
                return 2
            fi
            if [[ "$__base_bash_libs_arg_option_kind" != "value" && "$__base_bash_libs_arg_option_kind" != "repeatable" ]]; then
                base_std_log_error -l base_bash_libs.arg "base_arg_parse: option '$__base_bash_libs_arg_option_token' does not accept a value."
                return 2
            fi

            if [[ "$__base_bash_libs_arg_option_kind" == "repeatable" ]]; then
                __base_bash_libs_arg_repeatable_values+=("$__base_bash_libs_arg_option_name" "$__base_bash_libs_arg_option_value")
                __base_bash_libs_arg_set_assoc_value__ __base_bash_libs_arg_options "$__base_bash_libs_arg_option_name" "1"
            else
                __base_bash_libs_arg_set_assoc_value__ __base_bash_libs_arg_options "$__base_bash_libs_arg_option_name" "$__base_bash_libs_arg_option_value"
            fi
            continue
        fi

        if ((__base_bash_libs_arg_parse_options)) && [[ "$__base_bash_libs_arg_current" == -* && "$__base_bash_libs_arg_current" != "-" ]]; then
            __base_bash_libs_arg_option_token="$__base_bash_libs_arg_current"
            __base_bash_libs_arg_option_kind="${__base_bash_libs_arg_token_kind[$__base_bash_libs_arg_option_token]-}"
            __base_bash_libs_arg_option_name="${__base_bash_libs_arg_token_name[$__base_bash_libs_arg_option_token]-}"

            if [[ -z "$__base_bash_libs_arg_option_kind" ]]; then
                base_std_log_error -l base_bash_libs.arg "base_arg_parse: unknown option '$__base_bash_libs_arg_option_token'."
                return 2
            fi

            if [[ "$__base_bash_libs_arg_option_kind" == "flag" ]]; then
                __base_bash_libs_arg_set_assoc_value__ __base_bash_libs_arg_options "$__base_bash_libs_arg_option_name" "1"
                continue
            fi

            if (($# == 0)); then
                base_std_log_error -l base_bash_libs.arg "base_arg_parse: option '$__base_bash_libs_arg_option_token' requires a value."
                return 2
            fi
            if [[ -n "${1-}" ]]; then
                if [[ -n "${__base_bash_libs_arg_token_kind[$1]+set}" ]]; then
                    base_std_log_error -l base_bash_libs.arg "base_arg_parse: option '$__base_bash_libs_arg_option_token' requires a value before option '$1'."
                    return 2
                fi
            fi

            __base_bash_libs_arg_option_value="$1"
            shift
            if [[ "$__base_bash_libs_arg_option_kind" == "repeatable" ]]; then
                __base_bash_libs_arg_repeatable_values+=("$__base_bash_libs_arg_option_name" "$__base_bash_libs_arg_option_value")
                __base_bash_libs_arg_set_assoc_value__ __base_bash_libs_arg_options "$__base_bash_libs_arg_option_name" "1"
            else
                __base_bash_libs_arg_set_assoc_value__ __base_bash_libs_arg_options "$__base_bash_libs_arg_option_name" "$__base_bash_libs_arg_option_value"
            fi
            continue
        fi

        __base_bash_libs_arg_positionals+=("$__base_bash_libs_arg_current")
    done

    eval "$__base_bash_libs_arg_options_name=()"
    # shellcheck disable=SC2199 # The + expansion safely detects Bash 4.2 empty arrays under nounset.
    if [[ -n "${__base_bash_libs_arg_options[@]+set}" ]]; then
        for __base_bash_libs_arg_option_name in "${!__base_bash_libs_arg_options[@]}"; do
            __base_bash_libs_arg_set_assoc_value__ "$__base_bash_libs_arg_options_name" "$__base_bash_libs_arg_option_name" "${__base_bash_libs_arg_options[$__base_bash_libs_arg_option_name]}"
        done
    fi
    if ((${#__base_bash_libs_arg_positionals[@]} > 0)); then
        eval "$__base_bash_libs_arg_positionals_name=(\"\${__base_bash_libs_arg_positionals[@]}\")"
    else
        eval "$__base_bash_libs_arg_positionals_name=()"
    fi

    for __base_bash_libs_arg_repeatable_name in "${__base_bash_libs_arg_repeatable_names[@]+"${__base_bash_libs_arg_repeatable_names[@]}"}"; do
        __base_bash_libs_arg_publish_values=()
        # shellcheck disable=SC2199 # The + expansion safely detects Bash 4.2 empty arrays under nounset.
        if [[ -n "${__base_bash_libs_arg_repeatable_values[@]+set}" ]]; then
            for ((__base_bash_libs_arg_repeatable_index = 0;  \
            __base_bash_libs_arg_repeatable_index < ${#__base_bash_libs_arg_repeatable_values[@]};  \
            __base_bash_libs_arg_repeatable_index += 2)); do
                if [[ "${__base_bash_libs_arg_repeatable_values[__base_bash_libs_arg_repeatable_index]}" == "$__base_bash_libs_arg_repeatable_name" ]]; then
                    __base_bash_libs_arg_repeatable_value="${__base_bash_libs_arg_repeatable_values[__base_bash_libs_arg_repeatable_index + 1]}"
                    __base_bash_libs_arg_publish_values+=("$__base_bash_libs_arg_repeatable_value")
                fi
            done
        fi
        if ((${#__base_bash_libs_arg_publish_values[@]} > 0)); then
            eval "$__base_bash_libs_arg_repeatable_name=(\"\${__base_bash_libs_arg_publish_values[@]}\")"
        else
            eval "$__base_bash_libs_arg_repeatable_name=()"
        fi
    done
    return 0
}
