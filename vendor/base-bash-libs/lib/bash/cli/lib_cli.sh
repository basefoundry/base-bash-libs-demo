# shellcheck shell=bash
#
# lib_cli.sh - Declarative command contracts for Bash applications.
#

[[ -n "${BASE_BASH_LIBS_CLI_LOADED:-}" ]] && return 0
if [[ "${BASE_BASH_LIBS_STDLIB_LOADED:-}" != "1" ]]; then
    printf '%s\n' "Error: lib_cli.sh requires lib_std.sh to be sourced first." >&2
    return 1 2> /dev/null || exit 1
fi
readonly BASE_BASH_LIBS_CLI_LOADED=1

# A model is an identifier in this process, not a caller-owned array. Keeping
# the registry in one associative array avoids nameref/eval dependencies and
# keeps the runtime compatible with Bash 4.2.
declare -gA __base_bash_libs_cli_models=()
declare -gA __base_bash_libs_cli_attrs=()
declare -gA __base_bash_libs_cli_seen=()
# Declaration-time collision indexes. Values are comma-separated command
# paths; paths are validated to exclude commas. This avoids scanning the full
# model registry for every option while retaining the canonical model records
# used by parsing and validation.
declare -gA __base_bash_libs_cli_option_name_index=()
declare -gA __base_bash_libs_cli_option_token_index=()
# Keep the allowlists in one indexed table. Indexed arrays avoid the
# Bash-4.2 associative-subscript parsing differences that affect generated
# applications while preserving a single source of truth for every kind.
declare -ga __base_bash_libs_cli_allowed_attrs=(
    'name,version,description,handler'
    'path,description,handler,aliases'
    'path,name,type,tokens,help,metavar,default,required,enum,validator,conflicts,sensitive,hidden'
    'path,name,help,metavar,default,required,enum,validator,repeatable'
)
declare -ga __base_bash_libs_cli_ancestors=()
declare -ga __base_bash_libs_cli_option_names=()
declare -ga __base_bash_libs_cli_option_paths=()
declare -ga __base_bash_libs_cli_positional_names=()
declare -ga __base_bash_libs_cli_repeat_values=()
declare -ga __base_bash_libs_cli_completion_candidates=()
declare -ga __base_bash_libs_cli_quick_columns=()
declare -g __base_bash_libs_cli_quick_depth=0
declare -ga BASE_BASH_LIBS_CLI_RESULT_POSITIONALS=()
declare -gA BASE_BASH_LIBS_CLI_RESULT_OPTIONS=()
declare -gA BASE_BASH_LIBS_CLI_RESULT_REPEATED=()
declare -gA BASE_BASH_LIBS_CLI_RESULT_REPEATABLE_COUNTS=()
declare -g BASE_BASH_LIBS_CLI_RESULT_MODEL=""
declare -g BASE_BASH_LIBS_CLI_RESULT_COMMAND=""
declare -g BASE_BASH_LIBS_CLI_RESULT_ACTION="run"

__base_bash_libs_cli_error__() {
    printf 'ERROR: %s\n' "$*" >&2
    return 2
}

__base_bash_libs_cli_valid_identifier__() {
    [[ "${1-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ && "${1-}" != __* ]]
}

__base_bash_libs_cli_valid_model__() {
    [[ "${1-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

__base_bash_libs_cli_valid_segment__() {
    [[ "${1-}" == - || "${1-}" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*$ ]]
}

__base_bash_libs_cli_builtin_option_action__() {
    case "${1-}" in
    -h | --help) printf 'help' ;;
    -V | --version) printf 'version' ;;
    *) return 1 ;;
    esac
}

__base_bash_libs_cli_is_builtin_option_token__() {
    __base_bash_libs_cli_builtin_option_action__ "${1-}" > /dev/null
}

__base_bash_libs_cli_valid_path__() {
    local path="${1-}"
    local -a parts=()
    local part

    [[ -z "$path" ]] && return 0
    [[ "$path" != /* && "$path" != */ && "$path" != *'//' && "$path" != *'|' ]] || return 1
    IFS=/ read -r -a parts <<< "$path"
    for part in "${parts[@]+${parts[@]}}"; do
        __base_bash_libs_cli_valid_segment__ "$part" || return 1
    done
}

__base_bash_libs_cli_model_exists__() {
    [[ -n "${__base_bash_libs_cli_models["${1-}|meta|name"]+set}" ]]
}

__base_bash_libs_cli_command_exists__() {
    [[ -n "${__base_bash_libs_cli_models["${1-}|command|exists|${2-}"]+set}" ]]
}

__base_bash_libs_cli_parse_attrs__() {
    local argument key value

    __base_bash_libs_cli_attrs=()
    for argument; do
        [[ "$argument" == *=* ]] || {
            __base_bash_libs_cli_error__ "declaration attribute '$argument' must use key=value syntax."
            return $?
        }
        key="${argument%%=*}"
        value="${argument#*=}"
        [[ "$key" =~ ^[a-z][a-z0-9_-]*$ ]] || {
            __base_bash_libs_cli_error__ "declaration attribute '$key' has an invalid name."
            return $?
        }
        [[ -z "${__base_bash_libs_cli_attrs[$key]+set}" ]] || {
            __base_bash_libs_cli_error__ "declaration attribute '$key' was provided more than once."
            return $?
        }
        __base_bash_libs_cli_attrs["$key"]="$value"
    done
}

__base_bash_libs_cli_kind_has_attr__() {
    local kind="${1-}" key="${2-}" allowed index

    case "$kind" in
    model) index=0 ;;
    command) index=1 ;;
    option) index=2 ;;
    positional) index=3 ;;
    *) return 1 ;;
    esac
    allowed="${__base_bash_libs_cli_allowed_attrs[$index]-}"
    [[ -n "$allowed" ]] || return 1
    case ",$allowed," in
    *,"$key",*) return 0 ;;
    esac
    return 1
}

__base_bash_libs_cli_attr_allowed__() {
    local key="${1-}" kind

    for kind in model command option positional; do
        __base_bash_libs_cli_kind_has_attr__ "$kind" "$key" && return 0
    done
    __base_bash_libs_cli_error__ "unknown declaration attribute '$key'."
    return $?
}

__base_bash_libs_cli_validate_bool__() {
    [[ "${1-}" =~ ^(0|1|true|false|yes|no)$ ]]
}

__base_bash_libs_cli_validate_enum__() {
    local owner="$1" enum_value item default_value matched=0
    local -a enum_values=()
    local -A enum_seen=()

    [[ -n "${__base_bash_libs_cli_attrs[enum]+set}" ]] || return 0
    enum_value="${__base_bash_libs_cli_attrs[enum]}"
    IFS=, read -r -a enum_values <<< "$enum_value"
    ((${#enum_values[@]} > 0)) && [[ "$enum_value" != ,* && "$enum_value" != *, && "$enum_value" != *',,'* ]] || {
        __base_bash_libs_cli_declaration_usage__ "$owner: enum must contain non-empty comma-separated values."
        return 2
    }
    for item in "${enum_values[@]}"; do
        [[ -z "${enum_seen[$item]+set}" ]] || {
            __base_bash_libs_cli_declaration_usage__ "$owner: enum value '$item' was provided more than once."
            return 2
        }
        enum_seen["$item"]=1
    done
    [[ -n "${__base_bash_libs_cli_attrs[default]+set}" ]] || return 0
    default_value="${__base_bash_libs_cli_attrs[default]}"
    for item in "${enum_values[@]}"; do
        [[ "$default_value" == "$item" ]] && matched=1
    done
    ((matched)) || {
        __base_bash_libs_cli_declaration_usage__ "$owner: default must be one of the declared enum values."
        return 2
    }
}

__base_bash_libs_cli_validate_attrs__() {
    local key value

    for key in "${!__base_bash_libs_cli_attrs[@]}"; do
        __base_bash_libs_cli_attr_allowed__ "$key" || return $?
    done
    for key in required sensitive hidden repeatable; do
        if [[ -n "${__base_bash_libs_cli_attrs[$key]+set}" ]]; then
            value="${__base_bash_libs_cli_attrs[$key]}"
            __base_bash_libs_cli_validate_bool__ "$value" || {
                __base_bash_libs_cli_error__ "attribute '$key' must be true, false, 1, 0, yes, or no."
                return $?
            }
        fi
    done
}

__base_bash_libs_cli_restrict_attrs__() {
    local kind="$1" key

    for key in "${!__base_bash_libs_cli_attrs[@]}"; do
        if ! __base_bash_libs_cli_kind_has_attr__ "$kind" "$key"; then
            __base_bash_libs_cli_error__ "attribute '$key' is not valid for this declaration."
            return 2
        fi
    done
}

__base_bash_libs_cli_attr_is_runtime__() {
    case "${1-}" in
    path | name | type | tokens) return 1 ;;
    *) return 0 ;;
    esac
}

__base_bash_libs_cli_ancestors_for__() {
    local path="${1-}"
    local -a parts=()
    local index current=""

    __base_bash_libs_cli_ancestors=("")
    [[ -z "$path" ]] && return 0
    IFS=/ read -r -a parts <<< "$path"
    for index in "${!parts[@]}"; do
        if [[ -z "$current" ]]; then
            current="${parts[index]}"
        else
            current="$current/${parts[index]}"
        fi
        __base_bash_libs_cli_ancestors+=("$current")
    done
}

__base_bash_libs_cli_option_lookup__() {
    local __base_bash_libs_cli_lookup_model="$1" __base_bash_libs_cli_lookup_path="$2"
    local __base_bash_libs_cli_lookup_token="$3" __base_bash_libs_cli_lookup_name_result="$4"
    local __base_bash_libs_cli_lookup_path_result="$5" __base_bash_libs_cli_lookup_type_result="$6"
    local __base_bash_libs_cli_lookup_ancestor __base_bash_libs_cli_lookup_found_name

    printf -v "$__base_bash_libs_cli_lookup_name_result" '%s' ''
    printf -v "$__base_bash_libs_cli_lookup_path_result" '%s' ''
    printf -v "$__base_bash_libs_cli_lookup_type_result" '%s' ''
    __base_bash_libs_cli_ancestors_for__ "$__base_bash_libs_cli_lookup_path"
    for __base_bash_libs_cli_lookup_ancestor in "${__base_bash_libs_cli_ancestors[@]}"; do
        if [[ -n "${__base_bash_libs_cli_models["$__base_bash_libs_cli_lookup_model|option|$__base_bash_libs_cli_lookup_ancestor|token|$__base_bash_libs_cli_lookup_token"]+set}" ]]; then
            __base_bash_libs_cli_lookup_found_name="${__base_bash_libs_cli_models["$__base_bash_libs_cli_lookup_model|option|$__base_bash_libs_cli_lookup_ancestor|token|$__base_bash_libs_cli_lookup_token"]}"
            printf -v "$__base_bash_libs_cli_lookup_name_result" '%s' "$__base_bash_libs_cli_lookup_found_name"
            printf -v "$__base_bash_libs_cli_lookup_path_result" '%s' "$__base_bash_libs_cli_lookup_ancestor"
            printf -v "$__base_bash_libs_cli_lookup_type_result" '%s' \
                "${__base_bash_libs_cli_models["$__base_bash_libs_cli_lookup_model|option|$__base_bash_libs_cli_lookup_ancestor|meta|$__base_bash_libs_cli_lookup_found_name|type"]}"
            return 0
        fi
    done
    return 1
}

__base_bash_libs_cli_option_meta__() {
    local model="$1" path="$2" name="$3" field="$4"
    printf '%s' "${__base_bash_libs_cli_models["$model|option|$path|meta|$name|$field"]-}"
}

__base_bash_libs_cli_positional_meta__() {
    local model="$1" path="$2" name="$3" field="$4"
    printf '%s' "${__base_bash_libs_cli_models["$model|positional|$path|meta|$name|$field"]-}"
}

__base_bash_libs_cli_command_child__() {
    local model="$1" path="$2" name="$3"
    printf '%s' "${__base_bash_libs_cli_models["$model|command|child|$path|$name"]-}"
}

__base_bash_libs_cli_set_option__() {
    local name="$1" value="$2"
    BASE_BASH_LIBS_CLI_RESULT_OPTIONS["$name"]="$value"
}

__base_bash_libs_cli_flag_enabled__() {
    case "${1-}" in
    1 | true | yes) return 0 ;;
    0 | false | no | '') return 1 ;;
    *) return 1 ;;
    esac
}

__base_bash_libs_cli_option_active__() {
    local model="$1" path="$2" name="$3" type value

    [[ -n "${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[$name]+set}" ]] || return 1
    type="$(__base_bash_libs_cli_option_meta__ "$model" "$path" "$name" type)"
    [[ "$type" == flag ]] || return 0
    value="${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[$name]-}"
    __base_bash_libs_cli_flag_enabled__ "$value"
}

__base_bash_libs_cli_add_repeat__() {
    local name="$1" value="$2" count

    count="${BASE_BASH_LIBS_CLI_RESULT_REPEATABLE_COUNTS[$name]-0}"
    BASE_BASH_LIBS_CLI_RESULT_REPEATED["$name|$count"]="$value"
    BASE_BASH_LIBS_CLI_RESULT_REPEATABLE_COUNTS["$name"]=$((count + 1))
    __base_bash_libs_cli_set_option__ "$name" 1
}

__base_bash_libs_cli_validate_value__() {
    local model="$1" path="$2" kind="$3" name="$4" value="$5"
    local enum validator item matched=0
    local -a __base_bash_libs_cli_enum_values=()

    enum=""
    validator=""
    if [[ "$kind" == option ]]; then
        enum="$(__base_bash_libs_cli_option_meta__ "$model" "$path" "$name" enum)"
        validator="$(__base_bash_libs_cli_option_meta__ "$model" "$path" "$name" validator)"
    else
        enum="$(__base_bash_libs_cli_positional_meta__ "$model" "$path" "$name" enum)"
        validator="$(__base_bash_libs_cli_positional_meta__ "$model" "$path" "$name" validator)"
    fi
    if [[ -n "$enum" ]]; then
        IFS=, read -r -a __base_bash_libs_cli_enum_values <<< "$enum"
        for item in "${__base_bash_libs_cli_enum_values[@]}"; do
            if [[ "$value" == "$item" ]]; then
                matched=1
                break
            fi
        done
        ((matched)) || {
            __base_bash_libs_cli_error__ "value for '$name' is not one of: $enum."
            return $?
        }
    fi
    if [[ -n "$validator" ]]; then
        declare -F "$validator" > /dev/null 2>&1 || {
            __base_bash_libs_cli_error__ "validator '$validator' for '$name' is not defined."
            return $?
        }
        if ! "$validator" "$value" > /dev/null 2>&1; then
            __base_bash_libs_cli_error__ "value for '$name' failed validator '$validator'."
            return $?
        fi
    fi
}

__base_bash_libs_cli_collect_options__() {
    local model="$1" path="$2" ancestor name seen_key
    local -a __base_bash_libs_cli_local_option_names=()

    __base_bash_libs_cli_option_names=()
    __base_bash_libs_cli_option_paths=()
    __base_bash_libs_cli_seen=()
    __base_bash_libs_cli_ancestors_for__ "$path"
    for ancestor in "${__base_bash_libs_cli_ancestors[@]}"; do
        IFS=, read -r -a __base_bash_libs_cli_local_option_names <<< "${__base_bash_libs_cli_models["$model|command|options|$ancestor"]-}"
        for name in "${__base_bash_libs_cli_local_option_names[@]+${__base_bash_libs_cli_local_option_names[@]}}"; do
            seen_key="$name"
            [[ -n "${__base_bash_libs_cli_seen[$seen_key]+set}" ]] && continue
            __base_bash_libs_cli_seen["$seen_key"]=1
            __base_bash_libs_cli_option_names+=("$name")
            __base_bash_libs_cli_option_paths+=("$ancestor")
        done
    done
}

__base_bash_libs_cli_option_declared_for_path__() {
    local model="$1" path="$2" name="$3" ancestor option_names

    __base_bash_libs_cli_ancestors_for__ "$path"
    for ancestor in "${__base_bash_libs_cli_ancestors[@]}"; do
        option_names="${__base_bash_libs_cli_models["$model|command|options|$ancestor"]-}"
        case ",$option_names," in
        *,"$name",*) return 0 ;;
        esac
    done
    return 1
}

__base_bash_libs_cli_paths_overlap__() {
    local left="${1-}" right="${2-}"

    [[ -z "$left" || -z "$right" || "$left" == "$right" || "$left" == "$right/"* || "$right" == "$left/"* ]]
}

__base_bash_libs_cli_index_append__() {
    local result_name="$1" key="$2" value="$3" current
    case "$result_name" in
    name) current="${__base_bash_libs_cli_option_name_index[$key]-}" ;;
    token) current="${__base_bash_libs_cli_option_token_index[$key]-}" ;;
    *) return 2 ;;
    esac
    if [[ -n "$current" ]]; then
        if [[ "$result_name" == name ]]; then
            __base_bash_libs_cli_option_name_index["$key"]="$current,$value"
        else
            __base_bash_libs_cli_option_token_index["$key"]="$current,$value"
        fi
    else
        if [[ "$result_name" == name ]]; then
            __base_bash_libs_cli_option_name_index["$key"]="$value"
        else
            __base_bash_libs_cli_option_token_index["$key"]="$value"
        fi
    fi
}

__base_bash_libs_cli_index_has_overlap__() {
    local index_value="$1" path="$2" existing
    local -a indexed_paths=()
    IFS=, read -r -a indexed_paths <<< "$index_value"
    for existing in "${indexed_paths[@]+${indexed_paths[@]}}"; do
        [[ "$existing" == . ]] && existing=""
        __base_bash_libs_cli_paths_overlap__ "$path" "$existing" && return 0
    done
    return 1
}

__base_bash_libs_cli_collect_positionals__() {
    local model="$1" path="$2" name
    local -a __base_bash_libs_cli_local_positionals=()

    __base_bash_libs_cli_positional_names=()
    IFS=, read -r -a __base_bash_libs_cli_local_positionals <<< "${__base_bash_libs_cli_models["$model|command|positionals|$path"]-}"
    for name in "${__base_bash_libs_cli_local_positionals[@]+${__base_bash_libs_cli_local_positionals[@]}}"; do
        [[ -n "$name" ]] && __base_bash_libs_cli_positional_names+=("$name")
    done
}

__base_bash_libs_cli_reset_results__() {
    BASE_BASH_LIBS_CLI_RESULT_POSITIONALS=()
    BASE_BASH_LIBS_CLI_RESULT_OPTIONS=()
    # shellcheck disable=SC2034 # Published for callers after a successful parse.
    BASE_BASH_LIBS_CLI_RESULT_REPEATED=()
    BASE_BASH_LIBS_CLI_RESULT_REPEATABLE_COUNTS=()
    BASE_BASH_LIBS_CLI_RESULT_MODEL=""
    BASE_BASH_LIBS_CLI_RESULT_COMMAND=""
    BASE_BASH_LIBS_CLI_RESULT_ACTION="run"
}

__base_bash_libs_cli_declaration_usage__() {
    __base_bash_libs_cli_error__ "$1"
    printf '%s\n' "See lib/bash/cli/README.md for the declarative model contract." >&2
    return 2
}

__base_bash_libs_cli_quick_parse_row__() {
    local row="${1-}"

    __base_bash_libs_cli_quick_columns=()
    IFS='|' read -r -a __base_bash_libs_cli_quick_columns <<< "$row"
    ((${#__base_bash_libs_cli_quick_columns[@]} >= 1)) || {
        __base_bash_libs_cli_declaration_usage__ 'base_cli_declare: each row must start with model, command, option, or positional.'
        return 2
    }
    [[ -n "${__base_bash_libs_cli_quick_columns[0]}" ]] || {
        __base_bash_libs_cli_declaration_usage__ 'base_cli_declare: row kind cannot be empty.'
        return 2
    }
    __base_bash_libs_cli_parse_attrs__ "${__base_bash_libs_cli_quick_columns[@]:1}" || return $?
}

__base_bash_libs_cli_quick_validate_keys__() {
    local kind="$1" key

    for key in "${!__base_bash_libs_cli_attrs[@]}"; do
        if ! __base_bash_libs_cli_kind_has_attr__ "$kind" "$key"; then
            __base_bash_libs_cli_declaration_usage__ \
                "base_cli_declare: attribute '$key' is not valid for a $kind row."
            return 2
        fi
    done
}

__base_bash_libs_cli_quick_path_depth__() {
    local path="${1-}" depth=0

    [[ -n "$path" ]] || {
        __base_bash_libs_cli_quick_depth=0
        return 0
    }
    while [[ "$path" == */* ]]; do
        path="${path#*/}"
        depth=$((depth + 1))
    done
    __base_bash_libs_cli_quick_depth=$((depth + 1))
}

__base_bash_libs_cli_restore_declared_model__() {
    local model="$1" key

    for key in "${!__base_bash_libs_cli_models[@]}"; do
        [[ "$key" == "$model|"* ]] && unset "__base_bash_libs_cli_models[$key]"
    done
    # The snapshot is a local owned by base_cli_declare. Bash dynamic scope
    # keeps the rollback path compatible with Bash 4.2 without eval or namerefs.
    # shellcheck disable=SC2154
    for key in "${!__base_bash_libs_cli_declare_snapshot[@]}"; do
        __base_bash_libs_cli_models["$key"]="${__base_bash_libs_cli_declare_snapshot[$key]}"
    done
}

# base_cli_declare - Build a model from compact pipe-delimited declaration rows.
#
# Usage: base_cli_declare MODEL [ROW...]
#        base_cli_declare MODEL <<'EOF'
#        model|name=tool|version=1.0.0|description=Example CLI
#        command|path=admin|description=Administration
#        option|path=admin|name=verbose|type=flag|tokens=--verbose,-v
#        positional|path=admin|name=target|required=true
#        EOF
#
# Rows are data, never shell code. Values may contain spaces; `|` is the field
# delimiter. The model row is applied first and command rows are applied from
# shallowest to deepest path, so declarations may be ordered for readability.
# Options and positionals use the same attributes as base_cli_option and
# base_cli_positional. Option tokens are supplied as one comma-separated
# `tokens=` field. When ROW arguments are omitted, rows are read from stdin.
base_cli_declare() {
    local model="${1-}" line kind row path description name type tokens_value key depth status
    local model_row_count=0 max_depth=0 line_number=0
    local -a rows=() model_row=() command_rows=() option_rows=() positional_rows=()
    local -a declaration_args=() option_tokens=()
    local -A __base_bash_libs_cli_declare_snapshot=()

    (($# >= 1)) || {
        __base_bash_libs_cli_declaration_usage__ 'base_cli_declare: expected a model identifier and declaration rows.'
        return 2
    }
    __base_bash_libs_cli_valid_model__ "$model" || {
        __base_bash_libs_cli_declaration_usage__ "base_cli_declare: invalid model '$model'."
        return 2
    }
    shift
    if (($# > 0)); then
        rows=("$@")
    else
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
            rows+=("$line")
        done
    fi
    ((${#rows[@]} > 0)) || {
        __base_bash_libs_cli_declaration_usage__ 'base_cli_declare: at least one declaration row is required.'
        return 2
    }

    # Parse every row before mutating the model. This catches malformed fields,
    # unknown row kinds, and missing required table columns up front.
    for row in "${rows[@]}"; do
        line_number=$((line_number + 1))
        __base_bash_libs_cli_quick_parse_row__ "$row" || {
            __base_bash_libs_cli_error__ "base_cli_declare: invalid row $line_number."
            return 2
        }
        kind="${__base_bash_libs_cli_quick_columns[0]}"
        case "$kind" in
        model)
            model_row_count=$((model_row_count + 1))
            ((model_row_count == 1)) || {
                __base_bash_libs_cli_declaration_usage__ 'base_cli_declare: exactly one model row is required.'
                return 2
            }
            __base_bash_libs_cli_quick_validate_keys__ "$kind" || return $?
            model_row=("${__base_bash_libs_cli_quick_columns[@]:1}")
            ;;
        command | option | positional)
            __base_bash_libs_cli_quick_validate_keys__ "$kind" || return $?
            [[ -n "${__base_bash_libs_cli_attrs[path]+set}" ]] || {
                __base_bash_libs_cli_declaration_usage__ "base_cli_declare: $kind row requires path=."
                return 2
            }
            path="${__base_bash_libs_cli_attrs[path]}"
            if [[ "$kind" == command ]]; then
                [[ -n "${__base_bash_libs_cli_attrs[description]+set}" ]] || {
                    __base_bash_libs_cli_declaration_usage__ 'base_cli_declare: command row requires description=.'
                    return 2
                }
                __base_bash_libs_cli_quick_path_depth__ "$path"
                depth="$__base_bash_libs_cli_quick_depth"
                ((depth > max_depth)) && max_depth="$depth"
                command_rows+=("$row")
            elif [[ "$kind" == option ]]; then
                for key in name type tokens; do
                    [[ -n "${__base_bash_libs_cli_attrs[$key]+set}" ]] || {
                        __base_bash_libs_cli_declaration_usage__ "base_cli_declare: option row requires $key=."
                        return 2
                    }
                done
                option_rows+=("$row")
            else
                [[ -n "${__base_bash_libs_cli_attrs[name]+set}" ]] || {
                    __base_bash_libs_cli_declaration_usage__ 'base_cli_declare: positional row requires name=.'
                    return 2
                }
                positional_rows+=("$row")
            fi
            ;;
        *)
            __base_bash_libs_cli_declaration_usage__ \
                "base_cli_declare: unknown row kind '$kind' on row $line_number."
            return 2
            ;;
        esac
    done
    ((model_row_count == 1)) || {
        __base_bash_libs_cli_declaration_usage__ 'base_cli_declare: exactly one model row is required.'
        return 2
    }

    for key in "${!__base_bash_libs_cli_models[@]}"; do
        if [[ "$key" == "$model|"* ]]; then
            __base_bash_libs_cli_declare_snapshot["$key"]="${__base_bash_libs_cli_models[$key]}"
        fi
    done

    base_cli_model_init "$model" "${model_row[@]}" || {
        status=$?
        __base_bash_libs_cli_restore_declared_model__ "$model"
        return "$status"
    }
    for ((depth = 1; depth <= max_depth; depth++)); do
        for row in "${command_rows[@]}"; do
            __base_bash_libs_cli_quick_parse_row__ "$row" || {
                status=$?
                __base_bash_libs_cli_restore_declared_model__ "$model"
                return "$status"
            }
            __base_bash_libs_cli_quick_path_depth__ "${__base_bash_libs_cli_attrs[path]}"
            [[ "$__base_bash_libs_cli_quick_depth" -eq "$depth" ]] || continue
            path="${__base_bash_libs_cli_attrs[path]}"
            description="${__base_bash_libs_cli_attrs[description]}"
            declaration_args=("$model" "$path" "$description")
            [[ -n "${__base_bash_libs_cli_attrs[handler]+set}" ]] &&
                declaration_args+=("${__base_bash_libs_cli_attrs[handler]}")
            [[ -n "${__base_bash_libs_cli_attrs[aliases]+set}" ]] &&
                declaration_args+=("aliases=${__base_bash_libs_cli_attrs[aliases]}")
            base_cli_command "${declaration_args[@]}" || {
                status=$?
                __base_bash_libs_cli_restore_declared_model__ "$model"
                return "$status"
            }
        done
    done
    for row in "${option_rows[@]}"; do
        __base_bash_libs_cli_quick_parse_row__ "$row" || {
            status=$?
            __base_bash_libs_cli_restore_declared_model__ "$model"
            return "$status"
        }
        path="${__base_bash_libs_cli_attrs[path]}"
        name="${__base_bash_libs_cli_attrs[name]}"
        type="${__base_bash_libs_cli_attrs[type]}"
        tokens_value="${__base_bash_libs_cli_attrs[tokens]}"
        IFS=, read -r -a option_tokens <<< "$tokens_value"
        declaration_args=("$model" "$path" "$name" "$type" "${option_tokens[@]}")
        local -a allowed_attrs=()
        IFS=, read -r -a allowed_attrs <<< "${__base_bash_libs_cli_allowed_attrs[2]}"
        for key in "${allowed_attrs[@]+${allowed_attrs[@]}}"; do
            __base_bash_libs_cli_attr_is_runtime__ "$key" || continue
            [[ -n "${__base_bash_libs_cli_attrs[$key]+set}" ]] &&
                declaration_args+=("$key=${__base_bash_libs_cli_attrs[$key]}")
        done
        base_cli_option "${declaration_args[@]}" || {
            status=$?
            __base_bash_libs_cli_restore_declared_model__ "$model"
            return "$status"
        }
    done
    for row in "${positional_rows[@]}"; do
        __base_bash_libs_cli_quick_parse_row__ "$row" || {
            status=$?
            __base_bash_libs_cli_restore_declared_model__ "$model"
            return "$status"
        }
        path="${__base_bash_libs_cli_attrs[path]}"
        name="${__base_bash_libs_cli_attrs[name]}"
        declaration_args=("$model" "$path" "$name")
        local -a allowed_attrs=()
        IFS=, read -r -a allowed_attrs <<< "${__base_bash_libs_cli_allowed_attrs[3]}"
        for key in "${allowed_attrs[@]+${allowed_attrs[@]}}"; do
            __base_bash_libs_cli_attr_is_runtime__ "$key" || continue
            [[ -n "${__base_bash_libs_cli_attrs[$key]+set}" ]] &&
                declaration_args+=("$key=${__base_bash_libs_cli_attrs[$key]}")
        done
        base_cli_positional "${declaration_args[@]}" || {
            status=$?
            __base_bash_libs_cli_restore_declared_model__ "$model"
            return "$status"
        }
    done
    return 0
}

# base_cli_model_init - Starts or replaces a named declarative CLI model.
#
# Usage: base_cli_model_init model [name=tool] [version=1.0.0] [description=text]
base_cli_model_init() {
    local model="${1-}" key

    (($# >= 1)) || {
        __base_bash_libs_cli_declaration_usage__ 'base_cli_model_init: expected a model identifier.'
        return 2
    }
    __base_bash_libs_cli_valid_model__ "$model" || {
        __base_bash_libs_cli_declaration_usage__ "base_cli_model_init: invalid model '$model'."
        return 2
    }
    shift
    __base_bash_libs_cli_parse_attrs__ "$@" || return $?
    __base_bash_libs_cli_validate_attrs__ || return $?
    __base_bash_libs_cli_restrict_attrs__ model || return $?
    if [[ -n "${__base_bash_libs_cli_attrs[name]+set}" ]] &&
        ! __base_bash_libs_cli_valid_segment__ "${__base_bash_libs_cli_attrs[name]}"; then
        __base_bash_libs_cli_declaration_usage__ "base_cli_model_init: name must be a single command segment."
        return 2
    fi
    if [[ -n "${__base_bash_libs_cli_attrs[handler]+set}" ]] &&
        [[ ! "${__base_bash_libs_cli_attrs[handler]}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        __base_bash_libs_cli_declaration_usage__ "base_cli_model_init: handler must be a Bash function name."
        return 2
    fi
    for key in "${!__base_bash_libs_cli_models[@]}"; do
        [[ "$key" == "$model|"* ]] && unset "__base_bash_libs_cli_models[$key]"
    done
    for key in "${!__base_bash_libs_cli_option_name_index[@]}"; do
        [[ "$key" == "$model|"* ]] && unset "__base_bash_libs_cli_option_name_index[$key]"
    done
    for key in "${!__base_bash_libs_cli_option_token_index[@]}"; do
        [[ "$key" == "$model|"* ]] && unset "__base_bash_libs_cli_option_token_index[$key]"
    done
    __base_bash_libs_cli_models["$model|meta|name"]="${__base_bash_libs_cli_attrs[name]-$model}"
    __base_bash_libs_cli_models["$model|meta|version"]="${__base_bash_libs_cli_attrs[version]-}"
    __base_bash_libs_cli_models["$model|meta|description"]="${__base_bash_libs_cli_attrs[description]-}"
    __base_bash_libs_cli_models["$model|meta|handler"]="${__base_bash_libs_cli_attrs[handler]-}"
    __base_bash_libs_cli_models["$model|command|exists|"]=1
    __base_bash_libs_cli_models["$model|command|description|"]="${__base_bash_libs_cli_attrs[description]-}"
    __base_bash_libs_cli_models["$model|command|children|"]=""
    __base_bash_libs_cli_models["$model|command|options|"]=""
    __base_bash_libs_cli_models["$model|command|positionals|"]=""
    return 0
}

# base_cli_validate_model - Verify handler wiring and declared route reachability.
#
# Declaration remains order-independent: callers may declare a model before
# defining its handlers. Call this explicitly from tests or CI after all
# handlers have been loaded to fail early on wiring or registry mistakes.
base_cli_validate_model() {
    local model="${1-}" key path handler parent name aliases_value alias route token
    # shellcheck disable=SC2034 # Required output slot for the shared option lookup helper.
    local found_name found_path found_type
    local -a missing_handlers=() unreachable_routes=()
    local -a command_aliases=()

    (($# == 1)) || {
        __base_bash_libs_cli_declaration_usage__ 'base_cli_validate_model: expected a model identifier.'
        return 2
    }
    if ! __base_bash_libs_cli_valid_model__ "$model" || ! __base_bash_libs_cli_model_exists__ "$model"; then
        __base_bash_libs_cli_declaration_usage__ "base_cli_validate_model: model '$model' is not initialized."
        return 2
    fi

    handler="${__base_bash_libs_cli_models["$model|meta|handler"]-}"
    if [[ -n "$handler" ]] && ! declare -F "$handler" > /dev/null 2>&1; then
        missing_handlers+=("<root>:$handler")
    fi
    for key in "${!__base_bash_libs_cli_models[@]}"; do
        [[ "$key" == "$model|command|handler|"* ]] || continue
        path="${key#"$model|command|handler|"}"
        handler="${__base_bash_libs_cli_models["$key"]-}"
        [[ -n "$handler" ]] || continue
        if ! declare -F "$handler" > /dev/null 2>&1; then
            missing_handlers+=("$path:$handler")
        fi
    done
    for key in "${!__base_bash_libs_cli_models[@]}"; do
        [[ "$key" == "$model|command|exists|"* ]] || continue
        path="${key#"$model|command|exists|"}"
        [[ -n "$path" ]] || continue
        parent="${__base_bash_libs_cli_models["$model|command|parent|$path"]-}"
        name="${__base_bash_libs_cli_models["$model|command|name|$path"]-}"
        if [[ -z "$name" || "${__base_bash_libs_cli_models["$model|command|child|$parent|$name"]-}" != "$path" ]]; then
            unreachable_routes+=("command:$path:$name")
        fi
        aliases_value="${__base_bash_libs_cli_models["$model|command|aliases|$path"]-}"
        IFS=, read -r -a command_aliases <<< "$aliases_value"
        for alias in "${command_aliases[@]+${command_aliases[@]}}"; do
            if [[ "${__base_bash_libs_cli_models["$model|command|child|$parent|$alias"]-}" != "$path" ]]; then
                unreachable_routes+=("alias:$path:$alias")
            fi
        done
    done
    for key in "${!__base_bash_libs_cli_models[@]}"; do
        [[ "$key" == "$model|option|"*'|token|'* ]] || continue
        route="${key#"$model|option|"}"
        path="${route%%|token|*}"
        token="${route#*|token|}"
        name="${__base_bash_libs_cli_models[$key]}"
        if __base_bash_libs_cli_is_builtin_option_token__ "$token" ||
            ! __base_bash_libs_cli_option_lookup__ "$model" "$path" "$token" found_name found_path found_type ||
            [[ "$found_name" != "$name" || "$found_path" != "$path" ]]; then
            unreachable_routes+=("option:$path:$token")
        fi
    done
    if ((${#missing_handlers[@]} > 0)); then
        __base_bash_libs_cli_declaration_usage__ "base_cli_validate_model: handlers are not defined: ${missing_handlers[*]}"
        return 2
    fi
    if ((${#unreachable_routes[@]} > 0)); then
        __base_bash_libs_cli_declaration_usage__ "base_cli_validate_model: routes are unreachable: ${unreachable_routes[*]}"
        return 2
    fi
    return 0
}

# base_cli_command - Adds a command path such as `admin/user` to a model.
# Usage: base_cli_command model path description [handler] [aliases=a,b]
base_cli_command() {
    local model="${1-}" path="${2-}" description="${3-}" handler="" parent name alias child_list
    local -a command_aliases=()
    local -A command_route_seen=()

    (($# >= 3)) || {
        __base_bash_libs_cli_declaration_usage__ 'base_cli_command: expected model, path, and description.'
        return 2
    }
    if ! __base_bash_libs_cli_valid_model__ "$model" || ! __base_bash_libs_cli_model_exists__ "$model"; then
        __base_bash_libs_cli_declaration_usage__ "base_cli_command: model '$model' is not initialized."
        return 2
    fi
    if ! __base_bash_libs_cli_valid_path__ "$path" || [[ -z "$path" ]]; then
        __base_bash_libs_cli_declaration_usage__ "base_cli_command: path '$path' must be a non-root command path."
        return 2
    fi
    if __base_bash_libs_cli_command_exists__ "$model" "$path"; then
        __base_bash_libs_cli_declaration_usage__ "base_cli_command: command '$path' is already declared."
        return 2
    fi
    parent="${path%/*}"
    [[ "$parent" == "$path" ]] && parent=""
    if ! __base_bash_libs_cli_command_exists__ "$model" "$parent"; then
        __base_bash_libs_cli_declaration_usage__ "base_cli_command: parent command '$parent' is not declared."
        return 2
    fi
    name="${path##*/}"
    shift 3
    if (($# > 0)) && [[ "$1" != *=* ]]; then
        handler="$1"
        shift
    fi
    __base_bash_libs_cli_parse_attrs__ "$@" || return $?
    __base_bash_libs_cli_validate_attrs__ || return $?
    __base_bash_libs_cli_restrict_attrs__ command || return $?
    if [[ -n "${__base_bash_libs_cli_attrs[handler]+set}" ]]; then
        [[ -z "$handler" ]] || {
            __base_bash_libs_cli_declaration_usage__ "base_cli_command: handler was provided twice."
            return 2
        }
        handler="${__base_bash_libs_cli_attrs[handler]}"
    fi
    if [[ -n "$handler" && ! "$handler" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        __base_bash_libs_cli_declaration_usage__ "base_cli_command: invalid handler '$handler'."
        return 2
    fi
    if [[ -n "${__base_bash_libs_cli_attrs[aliases]+set}" ]]; then
        IFS=, read -r -a command_aliases <<< "${__base_bash_libs_cli_attrs[aliases]}"
    fi
    if [[ -n "${__base_bash_libs_cli_models["$model|command|child|$parent|$name"]+set}" ]]; then
        __base_bash_libs_cli_declaration_usage__ "base_cli_command: command name '$name' is already used by '$parent'."
        return 2
    fi
    command_route_seen["$name"]=1
    for alias in "${command_aliases[@]+${command_aliases[@]}}"; do
        if ! __base_bash_libs_cli_valid_segment__ "$alias"; then
            __base_bash_libs_cli_declaration_usage__ "base_cli_command: invalid alias '$alias'."
            return 2
        fi
        if [[ -n "${command_route_seen[$alias]+set}" ]]; then
            __base_bash_libs_cli_declaration_usage__ "base_cli_command: command route '$alias' was provided more than once."
            return 2
        fi
        if [[ -n "${__base_bash_libs_cli_models["$model|command|child|$parent|$alias"]+set}" ]]; then
            __base_bash_libs_cli_declaration_usage__ "base_cli_command: alias '$alias' is already used by '$parent'."
            return 2
        fi
        command_route_seen["$alias"]=1
    done
    __base_bash_libs_cli_models["$model|command|exists|$path"]=1
    __base_bash_libs_cli_models["$model|command|name|$path"]="$name"
    __base_bash_libs_cli_models["$model|command|parent|$path"]="$parent"
    __base_bash_libs_cli_models["$model|command|description|$path"]="$description"
    __base_bash_libs_cli_models["$model|command|handler|$path"]="$handler"
    __base_bash_libs_cli_models["$model|command|aliases|$path"]="$(
        IFS=,
        printf '%s' "${command_aliases[*]-}"
    )"
    __base_bash_libs_cli_models["$model|command|children|$path"]=""
    __base_bash_libs_cli_models["$model|command|options|$path"]=""
    __base_bash_libs_cli_models["$model|command|positionals|$path"]=""
    __base_bash_libs_cli_models["$model|command|child|$parent|$name"]="$path"
    for alias in "${command_aliases[@]+${command_aliases[@]}}"; do
        __base_bash_libs_cli_models["$model|command|child|$parent|$alias"]="$path"
    done
    child_list="${__base_bash_libs_cli_models["$model|command|children|$parent"]-}"
    if [[ -n "$child_list" ]]; then
        child_list="$child_list,$name"
    else
        child_list="$name"
    fi
    __base_bash_libs_cli_models["$model|command|children|$parent"]="$child_list"
    return 0
}

# base_cli_option - Adds a flag, value, or repeatable option.
# Usage: base_cli_option model command_path name type token... [key=value]
base_cli_option() {
    local model="${1-}" path="${2-}" name="${3-}" type="${4-}" token argument key option_names
    local index_value
    local -a tokens=() attrs=()
    local -A token_seen=()

    if (($# < 5)); then
        __base_bash_libs_cli_declaration_usage__ 'base_cli_option: expected model, command path, name, type, and token.'
        return 2
    fi
    if ! __base_bash_libs_cli_valid_model__ "$model" || ! __base_bash_libs_cli_model_exists__ "$model"; then
        __base_bash_libs_cli_declaration_usage__ "base_cli_option: model '$model' is not initialized."
        return 2
    fi
    if ! __base_bash_libs_cli_valid_path__ "$path" || ! __base_bash_libs_cli_command_exists__ "$model" "$path"; then
        __base_bash_libs_cli_declaration_usage__ "base_cli_option: command path '$path' is not declared."
        return 2
    fi
    if ! __base_bash_libs_cli_valid_identifier__ "$name"; then
        __base_bash_libs_cli_declaration_usage__ "base_cli_option: invalid option name '$name'."
        return 2
    fi
    case "$type" in
    flag | value | repeatable) ;;
    *)
        __base_bash_libs_cli_declaration_usage__ "base_cli_option: type must be flag, value, or repeatable."
        return 2
        ;;
    esac
    if [[ -n "${__base_bash_libs_cli_models["$model|option|$path|meta|$name|type"]+set}" ]]; then
        __base_bash_libs_cli_declaration_usage__ "base_cli_option: option '$name' is already declared on '$path'."
        return 2
    fi
    index_value="${__base_bash_libs_cli_option_name_index["$model|$name"]-}"
    if [[ -n "$index_value" ]] && __base_bash_libs_cli_index_has_overlap__ "$index_value" "$path"; then
        __base_bash_libs_cli_declaration_usage__ "base_cli_option: option name '$name' conflicts across '$path' and an overlapping command path."
        return 2
    fi
    shift 4
    for argument; do
        if [[ "$argument" == *=* ]]; then attrs+=("$argument"); else tokens+=("$argument"); fi
    done
    if ((${#tokens[@]} == 0)); then
        __base_bash_libs_cli_declaration_usage__ "base_cli_option: at least one option token is required."
        return 2
    fi
    __base_bash_libs_cli_parse_attrs__ "${attrs[@]+${attrs[@]}}" || return $?
    __base_bash_libs_cli_validate_attrs__ || return $?
    __base_bash_libs_cli_restrict_attrs__ option || return $?
    __base_bash_libs_cli_validate_enum__ base_cli_option || return $?
    if [[ -n "${__base_bash_libs_cli_attrs[repeatable]+set}" ]]; then
        __base_bash_libs_cli_declaration_usage__ "base_cli_option: repeatable is selected by the option type, not an attribute."
        return 2
    fi
    for token in "${tokens[@]}"; do
        if [[ ! "$token" =~ ^--?[A-Za-z0-9_][A-Za-z0-9_-]*$ ]]; then
            __base_bash_libs_cli_declaration_usage__ "base_cli_option: invalid option token '$token'."
            return 2
        fi
        if __base_bash_libs_cli_is_builtin_option_token__ "$token"; then
            __base_bash_libs_cli_declaration_usage__ "base_cli_option: token '$token' is reserved for built-in CLI behavior."
            return 2
        fi
        if [[ "$token" == *=* ]]; then
            __base_bash_libs_cli_declaration_usage__ "base_cli_option: option token '$token' cannot contain '='."
            return 2
        fi
        if [[ -n "${__base_bash_libs_cli_models["$model|option|$path|token|$token"]+set}" ]]; then
            __base_bash_libs_cli_declaration_usage__ "base_cli_option: token '$token' is already declared on '$path'."
            return 2
        fi
        if [[ -n "${token_seen[$token]+set}" ]]; then
            __base_bash_libs_cli_declaration_usage__ "base_cli_option: option token '$token' was repeated."
            return 2
        fi
        index_value="${__base_bash_libs_cli_option_token_index["$model|$token"]-}"
        if [[ -n "$index_value" ]] && __base_bash_libs_cli_index_has_overlap__ "$index_value" "$path"; then
            __base_bash_libs_cli_declaration_usage__ "base_cli_option: token '$token' conflicts across '$path' and an overlapping command path."
            return 2
        fi
        token_seen["$token"]=1
    done
    if [[ "$type" == flag && -n "${__base_bash_libs_cli_attrs[default]+set}" ]]; then
        if [[ ! "${__base_bash_libs_cli_attrs[default]}" =~ ^(0|1|true|false|yes|no)$ ]]; then
            __base_bash_libs_cli_declaration_usage__ "base_cli_option: flag default must be boolean."
            return 2
        fi
    fi
    if [[ -n "${__base_bash_libs_cli_attrs[validator]+set}" ]]; then
        if [[ ! "${__base_bash_libs_cli_attrs[validator]}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            __base_bash_libs_cli_declaration_usage__ "base_cli_option: validator must be a Bash function name."
            return 2
        fi
    fi
    if [[ -n "${__base_bash_libs_cli_attrs[conflicts]+set}" ]]; then
        local -a conflict_names=()
        local conflict_name
        IFS=, read -r -a conflict_names <<< "${__base_bash_libs_cli_attrs[conflicts]}"
        for conflict_name in "${conflict_names[@]}"; do
            if [[ -z "$conflict_name" || ! "$conflict_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
                __base_bash_libs_cli_declaration_usage__ "base_cli_option: conflicts must name declared options using Bash identifiers."
                return 2
            fi
            if [[ "$conflict_name" == "$name" ]] ||
                ! __base_bash_libs_cli_option_declared_for_path__ "$model" "$path" "$conflict_name"; then
                __base_bash_libs_cli_declaration_usage__ "base_cli_option: conflict option '$conflict_name' is not declared on '$path' or an ancestor command."
                return 2
            fi
        done
    fi
    option_names="${__base_bash_libs_cli_models["$model|command|options|$path"]-}"
    if [[ -n "$option_names" ]]; then option_names="$option_names,$name"; else option_names="$name"; fi
    __base_bash_libs_cli_models["$model|command|options|$path"]="$option_names"
    __base_bash_libs_cli_models["$model|option|$path|meta|$name|type"]="$type"
    __base_bash_libs_cli_models["$model|option|$path|meta|$name|tokens"]="$(
        IFS='|'
        printf '%s' "${tokens[*]}"
    )"
    for key in help metavar default required enum validator conflicts sensitive hidden; do
        if [[ -n "${__base_bash_libs_cli_attrs[$key]+set}" ]]; then
            __base_bash_libs_cli_models["$model|option|$path|meta|$name|$key"]="${__base_bash_libs_cli_attrs[$key]}"
        fi
    done
    for token in "${tokens[@]}"; do
        __base_bash_libs_cli_models["$model|option|$path|token|$token"]="$name"
        __base_bash_libs_cli_index_append__ token "$model|$token" "${path:-.}" || return 1
    done
    __base_bash_libs_cli_index_append__ name "$model|$name" "${path:-.}" || return 1
    return 0
}

# base_cli_positional - Adds a positional value to a command.
# Usage: base_cli_positional model command_path name [required=true] [repeatable=true] ...
base_cli_positional() {
    local model="${1-}" path="${2-}" name="${3-}" key names
    local previous previous_required
    local -a __base_bash_libs_cli_previous_positionals=()

    if (($# < 3)); then
        __base_bash_libs_cli_declaration_usage__ 'base_cli_positional: expected model, command path, and name.'
        return 2
    fi
    if ! __base_bash_libs_cli_valid_model__ "$model" || ! __base_bash_libs_cli_model_exists__ "$model"; then
        __base_bash_libs_cli_declaration_usage__ "base_cli_positional: model '$model' is not initialized."
        return 2
    fi
    if ! __base_bash_libs_cli_valid_path__ "$path" || ! __base_bash_libs_cli_command_exists__ "$model" "$path"; then
        __base_bash_libs_cli_declaration_usage__ "base_cli_positional: command path '$path' is not declared."
        return 2
    fi
    if ! __base_bash_libs_cli_valid_identifier__ "$name"; then
        __base_bash_libs_cli_declaration_usage__ "base_cli_positional: invalid positional name '$name'."
        return 2
    fi
    names="${__base_bash_libs_cli_models["$model|command|positionals|$path"]-}"
    case ",$names," in
    *,"$name",*)
        __base_bash_libs_cli_declaration_usage__ "base_cli_positional: '$name' is already declared on '$path'."
        return 2
        ;;
    esac
    shift 3
    __base_bash_libs_cli_parse_attrs__ "$@" || return $?
    __base_bash_libs_cli_validate_attrs__ || return $?
    __base_bash_libs_cli_restrict_attrs__ positional || return $?
    __base_bash_libs_cli_validate_enum__ base_cli_positional || return $?
    if [[ -n "${__base_bash_libs_cli_attrs[validator]+set}" ]]; then
        if [[ ! "${__base_bash_libs_cli_attrs[validator]}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            __base_bash_libs_cli_declaration_usage__ "base_cli_positional: validator must be a Bash function name."
            return 2
        fi
    fi
    if [[ -n "$names" ]]; then
        IFS=, read -r -a __base_bash_libs_cli_previous_positionals <<< "$names"
        previous="${__base_bash_libs_cli_previous_positionals[${#__base_bash_libs_cli_previous_positionals[@]} - 1]}"
        if [[ "$(__base_bash_libs_cli_positional_meta__ "$model" "$path" "$previous" repeatable)" =~ ^(1|true|yes)$ ]]; then
            __base_bash_libs_cli_declaration_usage__ "base_cli_positional: cannot declare '$name' after repeatable positional '$previous'."
            return 2
        fi
    fi
    if [[ "${__base_bash_libs_cli_attrs[required]-}" =~ ^(1|true|yes)$ && -n "$names" ]]; then
        for previous in "${__base_bash_libs_cli_previous_positionals[@]}"; do
            previous_required="$(__base_bash_libs_cli_positional_meta__ "$model" "$path" "$previous" required)"
            if [[ ! "$previous_required" =~ ^(1|true|yes)$ ||
                -n "${__base_bash_libs_cli_models["$model|positional|$path|meta|$previous|default"]+set}" ]]; then
                __base_bash_libs_cli_declaration_usage__ \
                    "base_cli_positional: cannot declare required positional '$name' after optional positional '$previous'."
                return 2
            fi
        done
    fi
    if [[ -n "$names" ]]; then names="$names,$name"; else names="$name"; fi
    __base_bash_libs_cli_models["$model|command|positionals|$path"]="$names"
    for key in help metavar default required enum validator repeatable; do
        if [[ -n "${__base_bash_libs_cli_attrs[$key]+set}" ]]; then
            __base_bash_libs_cli_models["$model|positional|$path|meta|$name|$key"]="${__base_bash_libs_cli_attrs[$key]}"
        fi
    done
    return 0
}

__base_bash_libs_cli_usage_line__() {
    local model="$1" path="$2" child_list positionals suffix="" name program
    local -a __base_bash_libs_cli_positional_names=()
    program="${__base_bash_libs_cli_models["$model|meta|name"]}"
    child_list="${__base_bash_libs_cli_models["$model|command|children|$path"]-}"
    __base_bash_libs_cli_collect_positionals__ "$model" "$path"
    for name in "${__base_bash_libs_cli_positional_names[@]+${__base_bash_libs_cli_positional_names[@]}}"; do
        if [[ "$(__base_bash_libs_cli_positional_meta__ "$model" "$path" "$name" repeatable)" =~ ^(1|true|yes)$ ]]; then
            suffix="$suffix <$name...>"
        elif [[ "$(__base_bash_libs_cli_positional_meta__ "$model" "$path" "$name" required)" =~ ^(1|true|yes)$ ]]; then
            suffix="$suffix <$name>"
        else
            suffix="$suffix [$name]"
        fi
    done
    [[ -n "$child_list" ]] && suffix="$suffix <command>"
    printf 'Usage: %s%s [options]%s\n' "$program" "${path:+ $path}" "$suffix"
}

# base_cli_help - Renders deterministic command-specific help to stdout.
base_cli_help() {
    local model="${1-}" path="${2-}" child_list child description name alias handler
    local label help_label_width=0 index option_path tokens help metavar required default sensitive
    local -a help_labels=() help_descriptions=() help_sections=() __base_bash_libs_cli_children=()
    local -a __base_bash_libs_cli_option_names=() __base_bash_libs_cli_option_paths=()
    local -a __base_bash_libs_cli_positional_names=()
    local has_commands=0 has_arguments=0

    if (($# > 2)); then
        __base_bash_libs_cli_error__ 'base_cli_help: expected model and optional command path.'
        return 2
    fi
    if ! __base_bash_libs_cli_model_exists__ "$model"; then
        __base_bash_libs_cli_error__ "base_cli_help: model '$model' is not initialized."
        return 2
    fi
    if ! __base_bash_libs_cli_valid_path__ "$path" || ! __base_bash_libs_cli_command_exists__ "$model" "$path"; then
        __base_bash_libs_cli_error__ "base_cli_help: command path '$path' is not declared."
        return 2
    fi
    __base_bash_libs_cli_usage_line__ "$model" "$path"
    description="${__base_bash_libs_cli_models["$model|command|description|$path"]-${__base_bash_libs_cli_models["$model|meta|description"]-}}"
    [[ -n "$description" ]] && printf '\n%s\n' "$description"
    child_list="${__base_bash_libs_cli_models["$model|command|children|$path"]-}"
    if [[ -n "$child_list" ]]; then
        has_commands=1
        IFS=, read -r -a __base_bash_libs_cli_children <<< "$child_list"
        for child in "${__base_bash_libs_cli_children[@]}"; do
            name="${__base_bash_libs_cli_models["$model|command|name|${path:+$path/}$child"]}"
            description="${__base_bash_libs_cli_models["$model|command|description|${path:+$path/}$child"]-}"
            alias="${__base_bash_libs_cli_models["$model|command|aliases|${path:+$path/}$child"]-}"
            [[ -n "$alias" ]] && name="$name ($alias)"
            help_labels+=("$name")
            help_descriptions+=("$description")
            help_sections+=(commands)
        done
    fi
    __base_bash_libs_cli_collect_options__ "$model" "$path"
    help_labels+=('-h, --help')
    help_descriptions+=('Show this help and exit.')
    help_sections+=(options)
    [[ -z "$path" && -n "${__base_bash_libs_cli_models["$model|meta|version"]-}" ]] &&
        help_labels+=('-V, --version') help_descriptions+=('Show the application version and exit.') help_sections+=(options)
    for index in "${!__base_bash_libs_cli_option_names[@]}"; do
        name="${__base_bash_libs_cli_option_names[index]}"
        option_path="${__base_bash_libs_cli_option_paths[index]}"
        [[ "$(__base_bash_libs_cli_option_meta__ "$model" "$option_path" "$name" hidden)" =~ ^(1|true|yes)$ ]] && continue
        tokens="$(__base_bash_libs_cli_option_meta__ "$model" "$option_path" "$name" tokens)"
        tokens="${tokens//|/, }"
        help="$(__base_bash_libs_cli_option_meta__ "$model" "$option_path" "$name" help)"
        metavar="$(__base_bash_libs_cli_option_meta__ "$model" "$option_path" "$name" metavar)"
        [[ -n "$metavar" ]] || metavar="$name"
        required="$(__base_bash_libs_cli_option_meta__ "$model" "$option_path" "$name" required)"
        default="$(__base_bash_libs_cli_option_meta__ "$model" "$option_path" "$name" default)"
        sensitive="$(__base_bash_libs_cli_option_meta__ "$model" "$option_path" "$name" sensitive)"
        [[ "$(__base_bash_libs_cli_option_meta__ "$model" "$option_path" "$name" type)" != flag ]] && tokens="$tokens <$metavar>"
        [[ "$required" =~ ^(1|true|yes)$ ]] && help="$help (required)"
        if [[ -n "$default" ]]; then
            if [[ "$sensitive" =~ ^(1|true|yes)$ ]]; then
                help="$help (default: <redacted>)"
            else
                help="$help (default: $default)"
            fi
        fi
        help_labels+=("$tokens")
        help_descriptions+=("$help")
        help_sections+=(options)
    done
    __base_bash_libs_cli_collect_positionals__ "$model" "$path"
    if ((${#__base_bash_libs_cli_positional_names[@]} > 0)); then
        has_arguments=1
        for name in "${__base_bash_libs_cli_positional_names[@]}"; do
            help="$(__base_bash_libs_cli_positional_meta__ "$model" "$path" "$name" help)"
            help_labels+=("$name")
            help_descriptions+=("$help")
            help_sections+=(arguments)
        done
    fi
    for index in "${!help_labels[@]}"; do
        label="${help_labels[index]}"
        ((${#label} > help_label_width)) && help_label_width=${#label}
    done
    if ((has_commands)); then
        printf '\nCommands:\n'
        for index in "${!help_labels[@]}"; do
            [[ "${help_sections[index]}" == commands ]] || continue
            printf '  %-*s %s\n' "$help_label_width" "${help_labels[index]}" "${help_descriptions[index]}"
        done
    fi
    printf '\nOptions:\n'
    for index in "${!help_labels[@]}"; do
        [[ "${help_sections[index]}" == options ]] || continue
        printf '  %-*s %s\n' "$help_label_width" "${help_labels[index]}" "${help_descriptions[index]}"
    done
    if ((has_arguments)); then
        printf '\nArguments:\n'
        for index in "${!help_labels[@]}"; do
            [[ "${help_sections[index]}" == arguments ]] || continue
            printf '  %-*s %s\n' "$help_label_width" "${help_labels[index]}" "${help_descriptions[index]}"
        done
    fi
    return 0
}

__base_bash_libs_cli_usage_error__() {
    local model="$1" path="$2" message="$3"
    printf 'ERROR: %s\n' "$message" >&2
    base_cli_help "$model" "$path" >&2
    return 2
}

__base_bash_libs_cli_apply_defaults_and_validate__() {
    local model="$1" path="$2" index option_index name option_path type value required default conflicts conflict conflict_path
    local -a conflict_names=()
    local -a __base_bash_libs_cli_option_names=() __base_bash_libs_cli_option_paths=()

    __base_bash_libs_cli_collect_options__ "$model" "$path"
    for index in "${!__base_bash_libs_cli_option_names[@]}"; do
        name="${__base_bash_libs_cli_option_names[index]}"
        option_path="${__base_bash_libs_cli_option_paths[index]}"
        type="$(__base_bash_libs_cli_option_meta__ "$model" "$option_path" "$name" type)"
        required="$(__base_bash_libs_cli_option_meta__ "$model" "$option_path" "$name" required)"
        default="$(__base_bash_libs_cli_option_meta__ "$model" "$option_path" "$name" default)"
        if [[ -z "${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[$name]+set}" ]]; then
            if [[ -n "${__base_bash_libs_cli_models["$model|option|$option_path|meta|$name|default"]+set}" ]]; then
                __base_bash_libs_cli_validate_value__ "$model" "$option_path" option "$name" "$default" || return $?
                if [[ "$type" == repeatable ]]; then
                    __base_bash_libs_cli_add_repeat__ "$name" "$default"
                else
                    __base_bash_libs_cli_set_option__ "$name" "$default"
                fi
            elif [[ "$required" =~ ^(1|true|yes)$ ]]; then
                __base_bash_libs_cli_error__ "required option '$name' was not provided."
                return $?
            fi
        fi
        conflicts="$(__base_bash_libs_cli_option_meta__ "$model" "$option_path" "$name" conflicts)"
        if [[ -n "$conflicts" ]] &&
            __base_bash_libs_cli_option_active__ "$model" "$option_path" "$name"; then
            IFS=, read -r -a conflict_names <<< "$conflicts"
            for conflict in "${conflict_names[@]}"; do
                [[ -z "$conflict" ]] && continue
                conflict_path="$option_path"
                for option_index in "${!__base_bash_libs_cli_option_names[@]}"; do
                    if [[ "${__base_bash_libs_cli_option_names[option_index]}" == "$conflict" ]]; then
                        conflict_path="${__base_bash_libs_cli_option_paths[option_index]}"
                        break
                    fi
                done
                if __base_bash_libs_cli_option_active__ "$model" "$conflict_path" "$conflict"; then
                    __base_bash_libs_cli_error__ "options '$name' and '$conflict' conflict."
                    return $?
                fi
            done
        fi
    done
    return 0
}

__base_bash_libs_cli_apply_positional_default__() {
    local model="$1" path="$2" name="$3" default="$4" has_default="$5" required="$6"

    if [[ "$has_default" == 1 ]]; then
        __base_bash_libs_cli_validate_value__ "$model" "$path" positional "$name" "$default" || return $?
        BASE_BASH_LIBS_CLI_RESULT_POSITIONALS+=("$default")
        return 0
    fi
    if [[ "$required" =~ ^(1|true|yes)$ ]]; then
        __base_bash_libs_cli_error__ "required positional '$name' was not provided."
        return $?
    fi
    return 1
}

__base_bash_libs_cli_apply_positionals__() {
    local model="$1" path="$2" value name index repeatable required default default_set repeat_start status
    local -a __base_bash_libs_cli_positional_names=()

    __base_bash_libs_cli_collect_positionals__ "$model" "$path"
    if ((${#__base_bash_libs_cli_positional_names[@]} == 0)); then
        ((${#BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[@]} == 0)) || {
            __base_bash_libs_cli_error__ "unexpected positional argument '${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[0]}'."
            return $?
        }
        return 0
    fi
    index=0
    for name in "${__base_bash_libs_cli_positional_names[@]}"; do
        repeatable="$(__base_bash_libs_cli_positional_meta__ "$model" "$path" "$name" repeatable)"
        required="$(__base_bash_libs_cli_positional_meta__ "$model" "$path" "$name" required)"
        default="$(__base_bash_libs_cli_positional_meta__ "$model" "$path" "$name" default)"
        default_set=0
        [[ -n "${__base_bash_libs_cli_models["$model|positional|$path|meta|$name|default"]+set}" ]] && default_set=1
        if [[ "$repeatable" =~ ^(1|true|yes)$ ]]; then
            repeat_start="$index"
            while ((index < ${#BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[@]})); do
                value="${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[index]}"
                __base_bash_libs_cli_validate_value__ "$model" "$path" positional "$name" "$value" || return $?
                ((index++))
            done
            if ((index == repeat_start)); then
                if __base_bash_libs_cli_apply_positional_default__ \
                    "$model" "$path" "$name" "$default" "$default_set" "$required"; then
                    [[ "$default_set" == 1 ]] && index=$((index + 1))
                else
                    status=$?
                    ((status == 1)) || return "$status"
                fi
            fi
            return 0
        fi
        if ((index >= ${#BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[@]})); then
            if __base_bash_libs_cli_apply_positional_default__ \
                "$model" "$path" "$name" "$default" "$default_set" "$required"; then
                index=$((index + 1))
                continue
            else
                status=$?
                ((status == 1)) && continue
                return "$status"
            fi
        fi
        value="${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[index]}"
        __base_bash_libs_cli_validate_value__ "$model" "$path" positional "$name" "$value" || return $?
        ((index++))
    done
    ((index == ${#BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[@]})) || {
        __base_bash_libs_cli_error__ "unexpected positional argument '${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[index]}'."
        return $?
    }
    return 0
}

# base_cli_parse - Parses a model and publishes results in BASE_BASH_LIBS_CLI_RESULT_*.
# Usage: base_cli_parse model -- [argv...]
base_cli_parse() {
    local model="${1-}" current path="" token option_value name type child_path option_path
    local builtin_action
    # shellcheck disable=SC2034 # Pass-by-name outputs used only to probe whether an option token is registered.
    local probe_name probe_path probe_type
    local parse_options=1 parse_commands=1

    if (($# < 2)) || [[ "$2" != -- ]]; then
        __base_bash_libs_cli_error__ 'base_cli_parse: usage: base_cli_parse <model> -- [args...]'
        return 2
    fi
    if ! __base_bash_libs_cli_model_exists__ "$model"; then
        __base_bash_libs_cli_error__ "base_cli_parse: model '$model' is not initialized."
        return 2
    fi
    __base_bash_libs_cli_reset_results__
    BASE_BASH_LIBS_CLI_RESULT_MODEL="$model"
    shift 2
    while (($#)); do
        current="$1"
        shift
        if ((parse_options)) && [[ "$current" == -- ]]; then
            parse_options=0
            parse_commands=0
            continue
        fi
        builtin_action=""
        if ((parse_options)); then
            builtin_action="$(__base_bash_libs_cli_builtin_option_action__ "$current" || true)"
        fi
        if [[ "$builtin_action" == help ]]; then
            BASE_BASH_LIBS_CLI_RESULT_COMMAND="$path"
            BASE_BASH_LIBS_CLI_RESULT_ACTION="help"
            base_cli_help "$model" "$path"
            return $?
        fi
        if [[ "$builtin_action" == version ]]; then
            if [[ -n "$path" || -z "${__base_bash_libs_cli_models["$model|meta|version"]-}" ]]; then
                __base_bash_libs_cli_usage_error__ "$model" "$path" "version is not available for this command."
                return 2
            fi
            printf '%s %s\n' "${__base_bash_libs_cli_models["$model|meta|name"]}" "${__base_bash_libs_cli_models["$model|meta|version"]}"
            BASE_BASH_LIBS_CLI_RESULT_COMMAND="$path"
            BASE_BASH_LIBS_CLI_RESULT_ACTION="version"
            return 0
        fi
        if ((parse_options)) && [[ "$current" == -* && "$current" != - ]]; then
            token="$current"
            option_value=""
            if [[ "$current" == --*=* ]]; then
                token="${current%%=*}"
                option_value="${current#*=}"
            fi
            if ! __base_bash_libs_cli_option_lookup__ "$model" "$path" "$token" name option_path type; then
                __base_bash_libs_cli_usage_error__ "$model" "$path" "unknown option '$token'."
                return 2
            fi
            if [[ "$type" == flag ]]; then
                if [[ "$current" == --*=* ]]; then
                    __base_bash_libs_cli_usage_error__ "$model" "$path" "flag '$token' does not accept a value."
                    return 2
                fi
                __base_bash_libs_cli_set_option__ "$name" 1
                continue
            fi
            if [[ "$current" != --*=* ]]; then
                if (($# == 0)); then
                    __base_bash_libs_cli_usage_error__ "$model" "$path" "option '$token' requires a value."
                    return 2
                fi
                option_value="$1"
                shift
                if [[ "$option_value" != -- && "$option_value" == -* ]]; then
                    if __base_bash_libs_cli_option_lookup__ "$model" "$path" "$option_value" \
                        probe_name probe_path probe_type; then
                        __base_bash_libs_cli_usage_error__ "$model" "$path" "option '$token' requires a value before '$option_value'."
                        return 2
                    fi
                fi
            fi
            if ! __base_bash_libs_cli_validate_value__ "$model" "$option_path" option "$name" "$option_value"; then
                __base_bash_libs_cli_usage_error__ "$model" "$path" "invalid value for option '$name'."
                return 2
            fi
            if [[ "$type" == repeatable ]]; then
                __base_bash_libs_cli_add_repeat__ "$name" "$option_value"
            else
                __base_bash_libs_cli_set_option__ "$name" "$option_value"
            fi
            continue
        fi
        if ((parse_commands)); then
            child_path="$(__base_bash_libs_cli_command_child__ "$model" "$path" "$current")"
            if [[ -n "$child_path" ]]; then
                path="$child_path"
                continue
            fi
        fi
        BASE_BASH_LIBS_CLI_RESULT_POSITIONALS+=("$current")
        parse_commands=0
    done
    BASE_BASH_LIBS_CLI_RESULT_COMMAND="$path"
    if [[ -n "${__base_bash_libs_cli_models["$model|command|children|$path"]-}" &&
        -z "${__base_bash_libs_cli_models["$model|command|positionals|$path"]-}" ]]; then
        __base_bash_libs_cli_usage_error__ "$model" "$path" "a subcommand is required."
        return 2
    fi
    if ! __base_bash_libs_cli_apply_defaults_and_validate__ "$model" "$path"; then
        __base_bash_libs_cli_usage_error__ "$model" "$path" "command validation failed."
        return 2
    fi
    if ! __base_bash_libs_cli_apply_positionals__ "$model" "$path"; then
        __base_bash_libs_cli_usage_error__ "$model" "$path" "positional validation failed."
        return 2
    fi
    return 0
}

# base_cli_run - Parses and invokes the declared command handler, if any.
base_cli_run() {
    local model="${1-}" handler path

    base_cli_parse "$@" || return $?
    [[ "$BASE_BASH_LIBS_CLI_RESULT_MODEL" == "$model" ]] || return 1
    [[ "$BASE_BASH_LIBS_CLI_RESULT_ACTION" == run ]] || return 0
    path="$BASE_BASH_LIBS_CLI_RESULT_COMMAND"
    handler="${__base_bash_libs_cli_models["$model|command|handler|$path"]-}"
    [[ -n "$handler" ]] || handler="${__base_bash_libs_cli_models["$model|meta|handler"]-}"
    [[ -z "$handler" ]] && return 0
    declare -F "$handler" > /dev/null 2>&1 || {
        __base_bash_libs_cli_error__ "handler '$handler' for command '$path' is not defined."
        return 1
    }
    "$handler" "${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[@]+${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[@]}}"
}

__base_bash_libs_cli_completion_add__() {
    local candidate="$1" prefix="$2" existing
    [[ "$candidate" == "$prefix"* ]] || return 0
    for existing in "${__base_bash_libs_cli_completion_candidates[@]+${__base_bash_libs_cli_completion_candidates[@]}}"; do
        [[ "$existing" == "$candidate" ]] && return 0
    done
    __base_bash_libs_cli_completion_candidates+=("$candidate")
}

# base_cli_complete - Prints completion candidates, one per line.
# Usage: base_cli_complete model -- [complete argv including the current prefix]
base_cli_complete() {
    local model="${1-}" current prefix path="" word token option_path name type child_path index
    # shellcheck disable=SC2034 # Option lookup path is intentionally unused while resolving completion state.
    local found_name found_path found_type
    local parse_options=1 parse_commands=1 pending_value=0 inline_value=0
    local -a words=() completed=() children=() __base_bash_libs_cli_option_tokens=()
    local -a __base_bash_libs_cli_option_names=() __base_bash_libs_cli_option_paths=()

    if (($# < 2)) || [[ "$2" != -- ]]; then
        __base_bash_libs_cli_error__ 'base_cli_complete: usage: base_cli_complete <model> -- [words...]'
        return 2
    fi
    __base_bash_libs_cli_model_exists__ "$model" || return 1
    shift 2
    words=("$@")
    if ((${#words[@]} == 0)); then prefix=""; else prefix="${words[${#words[@]} - 1]}"; fi
    if ((${#words[@]} > 1)); then completed=("${words[@]:0:${#words[@]}-1}"); fi
    for word in "${completed[@]+${completed[@]}}"; do
        if ((pending_value)); then
            pending_value=0
            continue
        fi
        if ((parse_options)) && [[ "$word" == -- ]]; then
            parse_options=0
            parse_commands=0
            continue
        fi
        ((parse_options)) || continue
        if [[ "$word" == -* && "$word" != - ]]; then
            token="$word"
            inline_value=0
            if [[ "$word" == --*=* ]]; then
                token="${word%%=*}"
                inline_value=1
            fi
            if __base_bash_libs_cli_option_lookup__ "$model" "$path" "$token" \
                found_name found_path found_type; then
                [[ "$found_type" == flag || "$inline_value" -eq 1 ]] || pending_value=1
            fi
            continue
        fi
        if ((parse_commands)); then
            child_path="$(__base_bash_libs_cli_command_child__ "$model" "$path" "$word")"
            if [[ -n "$child_path" ]]; then
                path="$child_path"
                continue
            fi
        fi
        # Match base_cli_parse: the first non-command word is positional and
        # permanently ends command traversal, while options remain available.
        parse_commands=0
    done
    ((parse_options && !pending_value)) || return 0
    if [[ "$prefix" == --*=* ]]; then
        token="${prefix%%=*}"
        if __base_bash_libs_cli_option_lookup__ "$model" "$path" "$token" \
            found_name found_path found_type && [[ "$found_type" != flag ]]; then
            return 0
        fi
    fi
    __base_bash_libs_cli_completion_candidates=()
    if [[ "$prefix" == -* ]]; then
        __base_bash_libs_cli_collect_options__ "$model" "$path"
        __base_bash_libs_cli_completion_add__ -h "$prefix"
        __base_bash_libs_cli_completion_add__ --help "$prefix"
        [[ -z "$path" && -n "${__base_bash_libs_cli_models["$model|meta|version"]-}" ]] &&
            __base_bash_libs_cli_completion_add__ --version "$prefix"
        for index in "${!__base_bash_libs_cli_option_names[@]}"; do
            name="${__base_bash_libs_cli_option_names[index]}"
            option_path="${__base_bash_libs_cli_option_paths[index]}"
            [[ "$(__base_bash_libs_cli_option_meta__ "$model" "$option_path" "$name" hidden)" =~ ^(1|true|yes)$ ]] && continue
            IFS='|' read -r -a __base_bash_libs_cli_option_tokens <<< "$(__base_bash_libs_cli_option_meta__ "$model" "$option_path" "$name" tokens)"
            for token in "${__base_bash_libs_cli_option_tokens[@]}"; do
                __base_bash_libs_cli_completion_add__ "$token" "$prefix"
            done
        done
    else
        IFS=, read -r -a children <<< "${__base_bash_libs_cli_models["$model|command|children|$path"]-}"
        for token in "${children[@]+${children[@]}}"; do
            [[ -n "$token" ]] && __base_bash_libs_cli_completion_add__ "$token" "$prefix"
        done
        local child_alias
        for child_alias in "${!__base_bash_libs_cli_models[@]}"; do
            [[ "$child_alias" == "$model|command|child|$path|"* ]] || continue
            child_alias="${child_alias##*|}"
            __base_bash_libs_cli_completion_add__ "$child_alias" "$prefix"
        done
    fi
    if ((${#__base_bash_libs_cli_completion_candidates[@]} > 0)); then
        printf '%s\n' "${__base_bash_libs_cli_completion_candidates[@]}"
    fi
}

# base_cli_completion_script - Emits a Bash completion function for a model.
base_cli_completion_script() {
    local model="${1-}" function_name="${2-}" program

    if (($# != 2)); then
        __base_bash_libs_cli_error__ 'base_cli_completion_script: usage: base_cli_completion_script <model> <function_name>'
        return 2
    fi
    __base_bash_libs_cli_model_exists__ "$model" || return 1
    if [[ ! "$function_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        __base_bash_libs_cli_error__ 'base_cli_completion_script: invalid function name.'
        return 2
    fi
    program="${__base_bash_libs_cli_models["$model|meta|name"]}"
    printf '%s\n' "$function_name() {"
    printf '%s\n' '    local cursor="${COMP_CWORD:-0}" word_count candidate'
    printf '%s\n' '    local -a completion_words=( "${COMP_WORDS[@]+${COMP_WORDS[@]}}" ) cli_words=()'
    printf '%s\n' '    if [[ "$cursor" =~ ^[0-9]+$ ]]; then cursor=$((10#$cursor)); else cursor=0; fi'
    printf '%s\n' '    word_count="${#completion_words[@]}"'
    printf '%s\n' '    if ((cursor > 0)); then'
    printf '%s\n' '        cli_words=( "${completion_words[@]:1:cursor}" )'
    printf '%s\n' '        if ((cursor >= word_count)); then'
    printf '%s\n' '            # COMP_CWORD at or beyond the array end means the current word is empty.'
    printf '%s\n' '            cli_words+=("")'
    printf '%s\n' '        fi'
    printf '%s\n' '    fi'
    printf '%s\n' '    COMPREPLY=()'
    printf '    while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(base_cli_complete %q -- "${cli_words[@]}")\n' "$model"
    printf '%s\n' '}'
    printf 'complete -F %q %q\n' "$function_name" "$program"
}

# base_cli_result_get - Copies a parsed scalar option into a caller variable.
base_cli_result_get() {
    local __base_bash_libs_cli_result_get_key="${1-}"
    local __base_bash_libs_cli_result_get_result_name="${2-}"

    if (($# != 2)); then
        __base_bash_libs_cli_error__ 'base_cli_result_get: usage: base_cli_result_get <key> <result_variable>'
        return 2
    fi
    __base_bash_libs_std_validate_variable_names__ base_cli_result_get \
        "$__base_bash_libs_cli_result_get_result_name" || return 2
    __base_bash_libs_std_assert_writable_output__ base_cli_result_get \
        "$__base_bash_libs_cli_result_get_result_name" scalar || return 2
    [[ -n "${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[$__base_bash_libs_cli_result_get_key]+set}" ]] || return 1
    printf -v "$__base_bash_libs_cli_result_get_result_name" '%s' \
        "${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[$__base_bash_libs_cli_result_get_key]}"
}

# base_cli_result_get_positional - Copies one parsed positional into a variable.
base_cli_result_get_positional() {
    local __base_bash_libs_cli_result_get_positional_index="${1-}"
    local __base_bash_libs_cli_result_get_positional_result_name="${2-}"
    local __base_bash_libs_cli_result_get_positional_normalized
    local __base_bash_libs_cli_result_get_positional_max_index
    local __base_bash_libs_cli_result_get_positional_max_text

    if (($# != 2)) || [[ ! "$__base_bash_libs_cli_result_get_positional_index" =~ ^[0-9]+$ ]]; then
        __base_bash_libs_cli_error__ 'base_cli_result_get_positional: usage: base_cli_result_get_positional <index> <result_variable>'
        return 2
    fi
    __base_bash_libs_std_validate_variable_names__ base_cli_result_get_positional \
        "$__base_bash_libs_cli_result_get_positional_result_name" || return 2
    __base_bash_libs_std_assert_writable_output__ base_cli_result_get_positional \
        "$__base_bash_libs_cli_result_get_positional_result_name" scalar || return 2
    ((${#BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[@]} > 0)) || return 1
    __base_bash_libs_cli_result_get_positional_normalized="${__base_bash_libs_cli_result_get_positional_index#"${__base_bash_libs_cli_result_get_positional_index%%[!0]*}"}"
    [[ -n "$__base_bash_libs_cli_result_get_positional_normalized" ]] ||
        __base_bash_libs_cli_result_get_positional_normalized=0
    __base_bash_libs_cli_result_get_positional_max_index=$((${#BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[@]} - 1))
    __base_bash_libs_cli_result_get_positional_max_text="$__base_bash_libs_cli_result_get_positional_max_index"
    if ((${#__base_bash_libs_cli_result_get_positional_normalized} > \
        ${#__base_bash_libs_cli_result_get_positional_max_text})); then
        return 1
    fi
    if ((${#__base_bash_libs_cli_result_get_positional_normalized} == \
        ${#__base_bash_libs_cli_result_get_positional_max_text})); then
        # shellcheck disable=SC2071 # `[[ > ]]` is an intentional decimal-string comparison.
        if [[ "$__base_bash_libs_cli_result_get_positional_normalized" > "$__base_bash_libs_cli_result_get_positional_max_text" ]]; then
            return 1
        fi
    fi
    __base_bash_libs_cli_result_get_positional_index=$((10#$__base_bash_libs_cli_result_get_positional_normalized))
    printf -v "$__base_bash_libs_cli_result_get_positional_result_name" '%s' \
        "${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[__base_bash_libs_cli_result_get_positional_index]}"
}

# base_cli_result_count - Copies the occurrence count of a repeatable option.
base_cli_result_count() {
    local __base_bash_libs_cli_result_count_key="${1-}"
    local __base_bash_libs_cli_result_count_result_name="${2-}"

    if (($# != 2)); then
        __base_bash_libs_cli_error__ 'base_cli_result_count: usage: base_cli_result_count <key> <result_variable>'
        return 2
    fi
    __base_bash_libs_std_validate_variable_names__ base_cli_result_count \
        "$__base_bash_libs_cli_result_count_result_name" || return 2
    __base_bash_libs_std_assert_writable_output__ base_cli_result_count \
        "$__base_bash_libs_cli_result_count_result_name" integer || return 2
    printf -v "$__base_bash_libs_cli_result_count_result_name" '%s' \
        "${BASE_BASH_LIBS_CLI_RESULT_REPEATABLE_COUNTS[$__base_bash_libs_cli_result_count_key]-0}"
}
