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
    [[ "${1-}" =~ ^[A-Za-z0-9_-]+$ ]]
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

__base_bash_libs_cli_attr_allowed__() {
    local key="${1-}"
    case "$key" in
    name | version | description | handler | aliases | help | metavar | default | required | enum | validator | conflicts | sensitive | hidden | repeatable)
        return 0
        ;;
    *)
        __base_bash_libs_cli_error__ "unknown declaration attribute '$key'."
        return $?
        ;;
    esac
}

__base_bash_libs_cli_validate_bool__() {
    [[ "${1-}" =~ ^(0|1|true|false|yes|no)$ ]]
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
    local allowed="$1" key

    for key in "${!__base_bash_libs_cli_attrs[@]}"; do
        case ",$allowed," in
        *,"$key",*) ;;
        *)
            __base_bash_libs_cli_error__ "attribute '$key' is not valid for this declaration."
            return 2
            ;;
        esac
    done
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
    local model="$1" path="$2" token="$3" ancestor

    __base_bash_libs_cli_option_name=""
    __base_bash_libs_cli_option_path=""
    __base_bash_libs_cli_option_type=""
    __base_bash_libs_cli_ancestors_for__ "$path"
    for ancestor in "${__base_bash_libs_cli_ancestors[@]}"; do
        if [[ -n "${__base_bash_libs_cli_models["$model|option|$ancestor|token|$token"]+set}" ]]; then
            __base_bash_libs_cli_option_name="${__base_bash_libs_cli_models["$model|option|$ancestor|token|$token"]}"
            __base_bash_libs_cli_option_path="$ancestor"
            __base_bash_libs_cli_option_type="${__base_bash_libs_cli_models["$model|option|$ancestor|meta|$__base_bash_libs_cli_option_name|type"]}"
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

__base_bash_libs_cli_collect_positionals__() {
    local model="$1" path="$2" name

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
        case "$kind:$key" in
        model:name | model:version | model:description | model:handler | \
            command:path | command:description | command:handler | command:aliases | \
            option:path | option:name | option:type | option:tokens | option:help | \
            option:metavar | option:default | option:required | option:enum | \
            option:validator | option:conflicts | option:sensitive | option:hidden | \
            positional:path | positional:name | positional:help | positional:metavar | \
            positional:default | positional:required | positional:enum | \
            positional:validator | positional:repeatable) ;;
        *)
            __base_bash_libs_cli_declaration_usage__ \
                "base_cli_declare: attribute '$key' is not valid for a $kind row."
            return 2
            ;;
        esac
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
    local model="${1-}" line kind row path description name type tokens_value key depth
    local model_row_count=0 max_depth=0 line_number=0
    local -a rows=() model_row=() command_rows=() option_rows=() positional_rows=()
    local -a declaration_args=() option_tokens=()

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

    base_cli_model_init "$model" "${model_row[@]}" || return $?
    for ((depth = 1; depth <= max_depth; depth++)); do
        for row in "${command_rows[@]}"; do
            __base_bash_libs_cli_quick_parse_row__ "$row" || return $?
            __base_bash_libs_cli_quick_path_depth__ "${__base_bash_libs_cli_attrs[path]}"
            [[ "$__base_bash_libs_cli_quick_depth" -eq "$depth" ]] || continue
            path="${__base_bash_libs_cli_attrs[path]}"
            description="${__base_bash_libs_cli_attrs[description]}"
            declaration_args=("$model" "$path" "$description")
            [[ -n "${__base_bash_libs_cli_attrs[handler]+set}" ]] &&
                declaration_args+=("${__base_bash_libs_cli_attrs[handler]}")
            [[ -n "${__base_bash_libs_cli_attrs[aliases]+set}" ]] &&
                declaration_args+=("aliases=${__base_bash_libs_cli_attrs[aliases]}")
            base_cli_command "${declaration_args[@]}" || return $?
        done
    done
    for row in "${option_rows[@]}"; do
        __base_bash_libs_cli_quick_parse_row__ "$row" || return $?
        path="${__base_bash_libs_cli_attrs[path]}"
        name="${__base_bash_libs_cli_attrs[name]}"
        type="${__base_bash_libs_cli_attrs[type]}"
        tokens_value="${__base_bash_libs_cli_attrs[tokens]}"
        IFS=, read -r -a option_tokens <<< "$tokens_value"
        declaration_args=("$model" "$path" "$name" "$type" "${option_tokens[@]}")
        for key in help metavar default required enum validator conflicts sensitive hidden; do
            [[ -n "${__base_bash_libs_cli_attrs[$key]+set}" ]] &&
                declaration_args+=("$key=${__base_bash_libs_cli_attrs[$key]}")
        done
        base_cli_option "${declaration_args[@]}" || return $?
    done
    for row in "${positional_rows[@]}"; do
        __base_bash_libs_cli_quick_parse_row__ "$row" || return $?
        path="${__base_bash_libs_cli_attrs[path]}"
        name="${__base_bash_libs_cli_attrs[name]}"
        declaration_args=("$model" "$path" "$name")
        for key in help metavar default required enum validator repeatable; do
            [[ -n "${__base_bash_libs_cli_attrs[$key]+set}" ]] &&
                declaration_args+=("$key=${__base_bash_libs_cli_attrs[$key]}")
        done
        base_cli_positional "${declaration_args[@]}" || return $?
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
    __base_bash_libs_cli_restrict_attrs__ 'name,version,description,handler' || return $?
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

# base_cli_validate_model - Verify that every declared command handler exists.
#
# Declaration remains order-independent: callers may declare a model before
# defining its handlers. Call this explicitly from tests or CI after all
# handlers have been loaded to fail early on wiring mistakes.
base_cli_validate_model() {
    local model="${1-}" key path handler
    local -a missing_handlers=()

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
    if ((${#missing_handlers[@]} > 0)); then
        __base_bash_libs_cli_declaration_usage__ "base_cli_validate_model: handlers are not defined: ${missing_handlers[*]}"
        return 2
    fi
    return 0
}

# base_cli_command - Adds a command path such as `admin/user` to a model.
# Usage: base_cli_command model path description [handler] [aliases=a,b]
base_cli_command() {
    local model="${1-}" path="${2-}" description="${3-}" handler="" parent name alias child_list
    local -a command_aliases=()

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
    __base_bash_libs_cli_restrict_attrs__ 'handler,aliases' || return $?
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
    for alias in "${command_aliases[@]+${command_aliases[@]}}"; do
        if ! __base_bash_libs_cli_valid_segment__ "$alias"; then
            __base_bash_libs_cli_declaration_usage__ "base_cli_command: invalid alias '$alias'."
            return 2
        fi
        if [[ -n "${__base_bash_libs_cli_models["$model|command|child|$parent|$alias"]+set}" ]]; then
            __base_bash_libs_cli_declaration_usage__ "base_cli_command: alias '$alias' is already used by '$parent'."
            return 2
        fi
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
    __base_bash_libs_cli_restrict_attrs__ 'help,metavar,default,required,enum,validator,conflicts,sensitive,hidden' || return $?
    if [[ -n "${__base_bash_libs_cli_attrs[repeatable]+set}" ]]; then
        __base_bash_libs_cli_declaration_usage__ "base_cli_option: repeatable is selected by the option type, not an attribute."
        return 2
    fi
    for token in "${tokens[@]}"; do
        if [[ ! "$token" =~ ^--?[A-Za-z0-9_][A-Za-z0-9_-]*$ ]]; then
            __base_bash_libs_cli_declaration_usage__ "base_cli_option: invalid option token '$token'."
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
    done
    return 0
}

# base_cli_positional - Adds a positional value to a command.
# Usage: base_cli_positional model command_path name [required=true] [repeatable=true] ...
base_cli_positional() {
    local model="${1-}" path="${2-}" name="${3-}" key names

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
    __base_bash_libs_cli_restrict_attrs__ 'help,metavar,default,required,enum,validator,repeatable' || return $?
    if [[ -n "${__base_bash_libs_cli_attrs[validator]+set}" ]]; then
        if [[ ! "${__base_bash_libs_cli_attrs[validator]}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            __base_bash_libs_cli_declaration_usage__ "base_cli_positional: validator must be a Bash function name."
            return 2
        fi
    fi
    if [[ -n "$names" ]]; then
        IFS=, read -r -a __base_bash_libs_cli_previous_positionals <<< "$names"
        local previous="${__base_bash_libs_cli_previous_positionals[${#__base_bash_libs_cli_previous_positionals[@]} - 1]}"
        if [[ "$(__base_bash_libs_cli_positional_meta__ "$model" "$path" "$previous" repeatable)" =~ ^(1|true|yes)$ ]]; then
            __base_bash_libs_cli_declaration_usage__ "base_cli_positional: cannot declare '$name' after repeatable positional '$previous'."
            return 2
        fi
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
    local -a help_labels=() help_descriptions=() help_sections=()
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
    local model="$1" path="$2" index name option_path type value required default conflicts conflict
    local -a conflict_names=()

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
        if [[ -n "$conflicts" && -n "${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[$name]+set}" ]]; then
            IFS=, read -r -a conflict_names <<< "$conflicts"
            for conflict in "${conflict_names[@]}"; do
                [[ -z "$conflict" ]] && continue
                if [[ -n "${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[$conflict]+set}" ]]; then
                    __base_bash_libs_cli_error__ "options '$name' and '$conflict' conflict."
                    return $?
                fi
            done
        fi
    done
    return 0
}

__base_bash_libs_cli_apply_positionals__() {
    local model="$1" path="$2" value name index repeatable required default

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
        if [[ "$repeatable" =~ ^(1|true|yes)$ ]]; then
            while ((index < ${#BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[@]})); do
                value="${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[index]}"
                __base_bash_libs_cli_validate_value__ "$model" "$path" positional "$name" "$value" || return $?
                ((index++))
            done
            if ((index == 0)) && [[ "$required" =~ ^(1|true|yes)$ ]]; then
                __base_bash_libs_cli_error__ "required positional '$name' was not provided."
                return $?
            fi
            return 0
        fi
        if ((index >= ${#BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[@]})); then
            if [[ -n "${__base_bash_libs_cli_models["$model|positional|$path|meta|$name|default"]+set}" ]]; then
                BASE_BASH_LIBS_CLI_RESULT_POSITIONALS+=("$default")
                __base_bash_libs_cli_validate_value__ "$model" "$path" positional "$name" "$default" || return $?
                ((index++))
                continue
            fi
            [[ "$required" =~ ^(1|true|yes)$ ]] || continue
            __base_bash_libs_cli_error__ "required positional '$name' was not provided."
            return $?
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
    local model="${1-}" current path="" token option_value name type child_path
    local parse_options=1

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
            continue
        fi
        if ((parse_options)) && [[ "$current" == -h || "$current" == --help ]]; then
            BASE_BASH_LIBS_CLI_RESULT_COMMAND="$path"
            BASE_BASH_LIBS_CLI_RESULT_ACTION="help"
            base_cli_help "$model" "$path"
            return $?
        fi
        if ((parse_options)) && [[ "$current" == -V || "$current" == --version ]]; then
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
            if ! __base_bash_libs_cli_option_lookup__ "$model" "$path" "$token"; then
                __base_bash_libs_cli_usage_error__ "$model" "$path" "unknown option '$token'."
                return 2
            fi
            name="$__base_bash_libs_cli_option_name"
            type="$__base_bash_libs_cli_option_type"
            if [[ "$type" == flag ]]; then
                if [[ -n "$option_value" ]]; then
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
                    if __base_bash_libs_cli_option_lookup__ "$model" "$path" "$option_value"; then
                        __base_bash_libs_cli_usage_error__ "$model" "$path" "option '$token' requires a value before '$option_value'."
                        return 2
                    fi
                fi
            fi
            if ! __base_bash_libs_cli_validate_value__ "$model" "$__base_bash_libs_cli_option_path" option "$name" "$option_value"; then
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
        child_path="$(__base_bash_libs_cli_command_child__ "$model" "$path" "$current")"
        if [[ -n "$child_path" ]]; then
            path="$child_path"
            continue
        fi
        BASE_BASH_LIBS_CLI_RESULT_POSITIONALS+=("$current")
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
    local model="${1-}" current prefix path="" word token option_path name index
    local -a words=() completed=() children=()

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
        [[ "$word" == -* ]] && continue
        token="$(__base_bash_libs_cli_command_child__ "$model" "$path" "$word")"
        [[ -n "$token" ]] && path="$token"
    done
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
    printf '%s\n' '    local current="${COMP_WORDS[COMP_CWORD]-}"'
    printf '%s\n' '    local -a cli_words=( "${COMP_WORDS[@]:1}" )'
    printf '%s\n' '    COMPREPLY=()'
    printf '    while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(base_cli_complete %q -- "${cli_words[@]}")\n' "$model"
    printf '%s\n' '}'
    printf 'complete -F %q %q\n' "$function_name" "$program"
}

# base_cli_result_get - Copies a parsed scalar option into a caller variable.
base_cli_result_get() {
    local key="${1-}" result_name="${2-}"

    if (($# != 2)); then
        __base_bash_libs_cli_error__ 'base_cli_result_get: usage: base_cli_result_get <key> <result_variable>'
        return 2
    fi
    __base_bash_libs_std_assert_public_variable_names__ base_cli_result_get "$result_name" || return 1
    __base_bash_libs_std_assert_writable_output__ base_cli_result_get "$result_name" || return 1
    [[ -n "${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[$key]+set}" ]] || return 1
    printf -v "$result_name" '%s' "${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[$key]}"
}

# base_cli_result_get_positional - Copies one parsed positional into a variable.
base_cli_result_get_positional() {
    local index="${1-}" result_name="${2-}"

    if (($# != 2)) || [[ ! "$index" =~ ^[0-9]+$ ]]; then
        __base_bash_libs_cli_error__ 'base_cli_result_get_positional: usage: base_cli_result_get_positional <index> <result_variable>'
        return 2
    fi
    __base_bash_libs_std_assert_public_variable_names__ base_cli_result_get_positional "$result_name" || return 1
    __base_bash_libs_std_assert_writable_output__ base_cli_result_get_positional "$result_name" || return 1
    ((index < ${#BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[@]})) || return 1
    printf -v "$result_name" '%s' "${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[index]}"
}

# base_cli_result_count - Copies the occurrence count of a repeatable option.
base_cli_result_count() {
    local key="${1-}" result_name="${2-}"

    if (($# != 2)); then
        __base_bash_libs_cli_error__ 'base_cli_result_count: usage: base_cli_result_count <key> <result_variable>'
        return 2
    fi
    __base_bash_libs_std_assert_public_variable_names__ base_cli_result_count "$result_name" || return 1
    __base_bash_libs_std_assert_writable_output__ base_cli_result_count "$result_name" || return 1
    printf -v "$result_name" '%s' "${BASE_BASH_LIBS_CLI_RESULT_REPEATABLE_COUNTS[$key]-0}"
}
