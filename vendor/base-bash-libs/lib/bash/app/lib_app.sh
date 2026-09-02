# shellcheck shell=bash
#
# lib_app.sh - Optional application policy for configuration and lifecycle.
#

[[ -n "${BASE_BASH_LIBS_APP_LOADED:-}" ]] && return 0
if [[ "${BASE_BASH_LIBS_STDLIB_LOADED:-}" != "1" ]]; then
    printf '%s\n' "Error: lib_app.sh requires lib_std.sh to be sourced first." >&2
    return 1 2> /dev/null || exit 1
fi
if [[ "${BASE_BASH_LIBS_CLI_LOADED:-}" != "1" ]]; then
    if ! base_std_import cli/lib_cli.sh 2> /dev/null; then
        printf '%s\n' "Error: lib_app.sh requires lib_cli.sh to be available in the loaded package." >&2
        return 1 2> /dev/null || exit 1
    fi
fi
readonly BASE_BASH_LIBS_APP_LOADED=1

# Application policy is deliberately optional. The core stdlib owns process
# safety and cleanup mechanics; this module supplies a deterministic policy
# layer without executing configuration files or requiring another runtime.
declare -gA __base_bash_libs_app_models=()
declare -gA __base_bash_libs_app_attrs=()
declare -gA __base_bash_libs_app_config=()
declare -gA __base_bash_libs_app_hooks=()
declare -gA __base_bash_libs_app_values=()
declare -gA __base_bash_libs_app_provenance=()
declare -gA __base_bash_libs_app_cli=()
declare -ga __base_bash_libs_app_keys=()
declare -ga __base_bash_libs_app_hook_names=()
declare -g BASE_BASH_LIBS_APP_ACTIVE_MODEL=""
declare -g BASE_BASH_LIBS_APP_LAST_STATUS=0
declare -g BASE_BASH_LIBS_APP_DRY_RUN=0
declare -g BASE_BASH_LIBS_APP_NONINTERACTIVE=0
declare -g BASE_BASH_LIBS_APP_COLOR=auto
declare -g BASE_BASH_LIBS_APP_VERBOSE=0
declare -g BASE_BASH_LIBS_APP_QUIET=0

__base_bash_libs_app_error__() {
    printf 'ERROR: %s\n' "$*" >&2
    return 2
}

__base_bash_libs_app_valid_model__() {
    [[ "${1-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

__base_bash_libs_app_valid_key__() {
    [[ "${1-}" =~ ^[a-z][a-z0-9_.-]*$ ]]
}

__base_bash_libs_app_valid_identifier__() {
    [[ "${1-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ && "${1-}" != __* ]]
}

__base_bash_libs_app_model_exists__() {
    [[ -n "${__base_bash_libs_app_models["${1-}|name"]+set}" ]]
}

__base_bash_libs_app_parse_attrs__() {
    local argument key value

    __base_bash_libs_app_attrs=()
    for argument; do
        [[ "$argument" == *=* ]] || {
            __base_bash_libs_app_error__ "attribute '$argument' must use key=value syntax."
            return 2
        }
        key="${argument%%=*}"
        value="${argument#*=}"
        [[ "$key" =~ ^[a-z][a-z0-9_-]*$ ]] || {
            __base_bash_libs_app_error__ "attribute '$key' has an invalid name."
            return 2
        }
        [[ -z "${__base_bash_libs_app_attrs[$key]+set}" ]] || {
            __base_bash_libs_app_error__ "attribute '$key' was provided more than once."
            return 2
        }
        __base_bash_libs_app_attrs["$key"]="$value"
    done
}

__base_bash_libs_app_attr_allowed__() {
    local key="${1-}"
    case "$key" in
    name | description | env | default | required | secret | enum | validator | help)
        return 0
        ;;
    *)
        __base_bash_libs_app_error__ "unknown application attribute '$key'."
        return 2
        ;;
    esac
}

__base_bash_libs_app_validate_bool__() {
    [[ "${1-}" =~ ^(0|1|true|false|yes|no|on|off)$ ]]
}

__base_bash_libs_app_bool_true__() {
    [[ "${1-}" =~ ^(1|true|yes|on)$ ]]
}

__base_bash_libs_app_trim__() {
    local value="${1-}"
    value="${value#${value%%[![:space:]]*}}"
    value="${value%${value##*[![:space:]]}}"
    printf '%s' "$value"
}

__base_bash_libs_app_validate_value__() {
    local model="$1" key="$2" value="$3" type enum validator item
    type="${__base_bash_libs_app_config["$model|$key|type"]-}"
    enum="${__base_bash_libs_app_config["$model|$key|enum"]-}"
    validator="${__base_bash_libs_app_config["$model|$key|validator"]-}"

    case "$type" in
    string | path) ;;
    bool)
        __base_bash_libs_app_validate_bool__ "$value" || {
            __base_bash_libs_app_error__ "configuration '$key' expects a boolean."
            return 2
        }
        ;;
    integer)
        [[ "$value" =~ ^-?[0-9]+$ ]] || {
            __base_bash_libs_app_error__ "configuration '$key' expects an integer."
            return 2
        }
        ;;
    enum)
        [[ -n "$enum" ]] || {
            __base_bash_libs_app_error__ "configuration '$key' has no enum values."
            return 2
        }
        ;;
    *)
        __base_bash_libs_app_error__ "configuration '$key' has unsupported type '$type'."
        return 2
        ;;
    esac
    if [[ -n "$enum" ]]; then
        local matched=0
        IFS=, read -r -a __base_bash_libs_app_enum_values <<< "$enum"
        for item in "${__base_bash_libs_app_enum_values[@]}"; do
            if [[ "$item" == "$value" ]]; then
                matched=1
                break
            fi
        done
        ((matched)) || {
            __base_bash_libs_app_error__ "configuration '$key' must be one of: $enum."
            return 2
        }
    fi
    if [[ -n "$validator" ]]; then
        declare -F "$validator" > /dev/null 2>&1 || {
            __base_bash_libs_app_error__ "validator '$validator' for configuration '$key' is not defined."
            return 2
        }
        "$validator" "$value" > /dev/null 2>&1 || {
            __base_bash_libs_app_error__ "configuration '$key' failed validator '$validator'."
            return 2
        }
    fi
}

__base_bash_libs_app_set_value__() {
    local model="$1" key="$2" value="$3" source="$4"
    __base_bash_libs_app_validate_value__ "$model" "$key" "$value" || return $?
    __base_bash_libs_app_values["$model|$key"]="$value"
    __base_bash_libs_app_provenance["$model|$key"]="$source"
}

__base_bash_libs_app_set_file_values__() {
    local model="$1" file="$2" source="$3" line key value line_number=0

    [[ -f "$file" ]] || {
        __base_bash_libs_app_error__ "configuration file '$file' does not exist."
        return 1
    }
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number++))
        line="${line%$'\r'}"
        line="$(__base_bash_libs_app_trim__ "$line")"
        [[ -z "$line" || "$line" == \#* ]] && continue
        [[ "$line" == *=* ]] || {
            __base_bash_libs_app_error__ "configuration file '$file' line $line_number is not key=value data."
            return 2
        }
        key="$(__base_bash_libs_app_trim__ "${line%%=*}")"
        value="$(__base_bash_libs_app_trim__ "${line#*=}")"
        __base_bash_libs_app_valid_key__ "$key" || {
            __base_bash_libs_app_error__ "configuration file '$file' line $line_number has invalid key '$key'."
            return 2
        }
        [[ -n "${__base_bash_libs_app_config["$model|$key|type"]+set}" ]] || {
            __base_bash_libs_app_error__ "configuration file '$file' line $line_number contains unknown key '$key'."
            return 2
        }
        __base_bash_libs_app_set_value__ "$model" "$key" "$value" "$source" || return $?
    done < "$file"
}

__base_bash_libs_app_hook_dispatch__() {
    local model="$1" phase="$2" status="$3" index hook function
    local -a hooks=()

    IFS=, read -r -a hooks <<< "${__base_bash_libs_app_models["$model|hooks|$phase"]-}"
    for ((index = ${#hooks[@]} - 1; index >= 0; index--)); do
        hook="${hooks[index]}"
        [[ -n "$hook" ]] || continue
        function="${__base_bash_libs_app_hooks["$model|$phase|$hook"]-}"
        [[ -n "$function" ]] || continue
        if ! "$function" "$phase" "$status"; then
            base_std_log_warn -l base_bash_libs.app "Application $phase hook '$hook' failed; preserving status $status."
        fi
    done
}

__base_bash_libs_app_cleanup_dispatch__() {
    local entry_status=$?
    local status="${1-}" model="${BASE_BASH_LIBS_APP_ACTIVE_MODEL-}"
    if [[ -z "$status" ]]; then
        status=$entry_status
    fi
    [[ -n "$model" ]] || return "$status"
    [[ "${__base_bash_libs_app_models["$model|cleanup-dispatched"]-0}" == 1 ]] && return "$status"
    __base_bash_libs_app_models["$model|cleanup-dispatched"]=1
    case "$status" in
    0) __base_bash_libs_app_hook_dispatch__ "$model" normal "$status" ;;
    129) __base_bash_libs_app_hook_dispatch__ "$model" hup "$status" ;;
    130) __base_bash_libs_app_hook_dispatch__ "$model" int "$status" ;;
    143) __base_bash_libs_app_hook_dispatch__ "$model" term "$status" ;;
    *) __base_bash_libs_app_hook_dispatch__ "$model" fatal "$status" ;;
    esac
    __base_bash_libs_app_hook_dispatch__ "$model" cleanup "$status"
    BASE_BASH_LIBS_APP_LAST_STATUS="$status"
    return "$status"
}

# base_app_init - Initializes an optional application policy model.
base_app_init() {
    local model="${1-}" key

    (($# >= 1)) || {
        __base_bash_libs_app_error__ 'base_app_init: expected a model identifier.'
        return 2
    }
    __base_bash_libs_app_valid_model__ "$model" || {
        __base_bash_libs_app_error__ "base_app_init: invalid model '$model'."
        return 2
    }
    shift
    __base_bash_libs_app_parse_attrs__ "$@" || return $?
    for key in "${!__base_bash_libs_app_attrs[@]}"; do
        __base_bash_libs_app_attr_allowed__ "$key" || return $?
    done
    if [[ -n "${__base_bash_libs_app_attrs[name]+set}" ]] &&
        ! __base_bash_libs_app_valid_key__ "${__base_bash_libs_app_attrs[name]}"; then
        __base_bash_libs_app_error__ 'base_app_init: name must be a lowercase application key.'
        return 2
    fi
    for key in "${!__base_bash_libs_app_models[@]}"; do
        [[ "$key" == "$model|"* ]] && unset "__base_bash_libs_app_models[$key]"
    done
    for key in "${!__base_bash_libs_app_config[@]}"; do
        [[ "$key" == "$model|"* ]] && unset "__base_bash_libs_app_config[$key]"
    done
    for key in "${!__base_bash_libs_app_values[@]}"; do
        [[ "$key" == "$model|"* ]] && unset "__base_bash_libs_app_values[$key]"
    done
    for key in "${!__base_bash_libs_app_provenance[@]}"; do
        [[ "$key" == "$model|"* ]] && unset "__base_bash_libs_app_provenance[$key]"
    done
    for key in "${!__base_bash_libs_app_cli[@]}"; do
        [[ "$key" == "$model|"* ]] && unset "__base_bash_libs_app_cli[$key]"
    done
    for key in "${!__base_bash_libs_app_hooks[@]}"; do
        [[ "$key" == "$model|"* ]] && unset "__base_bash_libs_app_hooks[$key]"
    done
    __base_bash_libs_app_models["$model|name"]="${__base_bash_libs_app_attrs[name]-$model}"
    __base_bash_libs_app_models["$model|description"]="${__base_bash_libs_app_attrs[description]-}"
    __base_bash_libs_app_models["$model|config-keys"]=""
    for key in normal fatal int term hup cleanup; do
        __base_bash_libs_app_models["$model|hooks|$key"]=""
    done
    __base_bash_libs_app_models["$model|cleanup-dispatched"]=0
    return 0
}

# base_app_config_define - Defines one typed configuration value.
base_app_config_define() {
    local model="${1-}" key="${2-}" type="${3-}" argument config_key
    local -a attrs=()

    (($# >= 3)) || {
        __base_bash_libs_app_error__ 'base_app_config_define: expected model, key, and type.'
        return 2
    }
    __base_bash_libs_app_model_exists__ "$model" || {
        __base_bash_libs_app_error__ "base_app_config_define: model '$model' is not initialized."
        return 2
    }
    __base_bash_libs_app_valid_key__ "$key" || {
        __base_bash_libs_app_error__ "base_app_config_define: invalid key '$key'."
        return 2
    }
    case "$type" in string | path | bool | integer | enum) ;; *)
        __base_bash_libs_app_error__ "base_app_config_define: unsupported type '$type'."
        return 2
        ;;
    esac
    config_key="$model|$key|type"
    [[ -z "${__base_bash_libs_app_config[$config_key]+set}" ]] || {
        __base_bash_libs_app_error__ "base_app_config_define: key '$key' is already defined."
        return 2
    }
    shift 3
    for argument; do attrs+=("$argument"); done
    __base_bash_libs_app_parse_attrs__ "${attrs[@]+${attrs[@]}}" || return $?
    for argument in "${!__base_bash_libs_app_attrs[@]}"; do
        __base_bash_libs_app_attr_allowed__ "$argument" || return $?
    done
    if [[ -n "${__base_bash_libs_app_attrs[env]+set}" ]] &&
        ! __base_bash_libs_app_valid_identifier__ "${__base_bash_libs_app_attrs[env]}"; then
        __base_bash_libs_app_error__ "configuration '$key' has an invalid environment variable name."
        return 2
    fi
    if [[ -n "${__base_bash_libs_app_attrs[validator]+set}" ]] &&
        ! __base_bash_libs_app_valid_identifier__ "${__base_bash_libs_app_attrs[validator]}"; then
        __base_bash_libs_app_error__ "configuration '$key' has an invalid validator name."
        return 2
    fi
    if [[ -n "${__base_bash_libs_app_attrs[required]+set}" ]]; then
        __base_bash_libs_app_validate_bool__ "${__base_bash_libs_app_attrs[required]}" || {
            __base_bash_libs_app_error__ "configuration '$key' required must be boolean."
            return 2
        }
    fi
    if [[ -n "${__base_bash_libs_app_attrs[secret]+set}" ]]; then
        __base_bash_libs_app_validate_bool__ "${__base_bash_libs_app_attrs[secret]}" || {
            __base_bash_libs_app_error__ "configuration '$key' secret must be boolean."
            return 2
        }
    fi
    if [[ "$type" == enum && -z "${__base_bash_libs_app_attrs[enum]-}" ]]; then
        __base_bash_libs_app_error__ "configuration '$key' enum values are required."
        return 2
    fi
    __base_bash_libs_app_config["$model|$key|type"]="$type"
    for argument in env default required secret enum validator help; do
        if [[ -n "${__base_bash_libs_app_attrs[$argument]+set}" ]]; then
            __base_bash_libs_app_config["$model|$key|$argument"]="${__base_bash_libs_app_attrs[$argument]}"
        fi
    done
    config_key="${__base_bash_libs_app_models["$model|config-keys"]-}"
    if [[ -n "$config_key" ]]; then config_key="$config_key,$key"; else config_key="$key"; fi
    __base_bash_libs_app_models["$model|config-keys"]="$config_key"
    return 0
}

# base_app_config_set_cli - Supplies a highest-precedence value explicitly.
base_app_config_set_cli() {
    local model="${1-}" key="${2-}" value="${3-}"

    (($# == 3)) || {
        __base_bash_libs_app_error__ 'base_app_config_set_cli: usage: base_app_config_set_cli MODEL KEY VALUE'
        return 2
    }
    __base_bash_libs_app_model_exists__ "$model" || return 1
    [[ -n "${__base_bash_libs_app_config["$model|$key|type"]+set}" ]] || return 1
    __base_bash_libs_app_cli["$model|$key"]="$value"
}

# base_app_config_load - Applies user, project, environment, and CLI values.
# Precedence is CLI > environment > project > user > default.
base_app_config_load() {
    local model="${1-}" argument project_file="" user_file="" key value_key env_name value
    local -a cli_pairs=()
    local parse_options=1

    (($# >= 1)) || {
        __base_bash_libs_app_error__ 'base_app_config_load: expected a model.'
        return 2
    }
    __base_bash_libs_app_model_exists__ "$model" || return 1
    shift
    while (($#)); do
        argument="$1"
        shift
        if ((parse_options)) && [[ "$argument" == -- ]]; then
            parse_options=0
            continue
        fi
        if ((parse_options)) && [[ "$argument" == --project || "$argument" == --config ]]; then
            (($# > 0)) || {
                __base_bash_libs_app_error__ "$argument requires a file."
                return 2
            }
            project_file="$1"
            shift
            continue
        fi
        if ((parse_options)) && [[ "$argument" == --user ]]; then
            (($# > 0)) || {
                __base_bash_libs_app_error__ '--user requires a file.'
                return 2
            }
            user_file="$1"
            shift
            continue
        fi
        if ((parse_options)) && [[ "$argument" == --cli ]]; then
            (($# > 0)) || {
                __base_bash_libs_app_error__ '--cli requires key=value.'
                return 2
            }
            cli_pairs+=("$1")
            shift
            continue
        fi
        __base_bash_libs_app_error__ "unknown configuration load argument '$argument'."
        return 2
    done

    IFS=, read -r -a __base_bash_libs_app_keys <<< "${__base_bash_libs_app_models["$model|config-keys"]-}"
    for key in "${__base_bash_libs_app_keys[@]+${__base_bash_libs_app_keys[@]}}"; do
        value_key="$model|$key"
        unset "__base_bash_libs_app_values[$value_key]" "__base_bash_libs_app_provenance[$value_key]"
        if [[ -n "${__base_bash_libs_app_config["$model|$key|default"]+set}" ]]; then
            __base_bash_libs_app_set_value__ "$model" "$key" "${__base_bash_libs_app_config["$model|$key|default"]}" default || return $?
        fi
    done
    [[ -z "$user_file" ]] || __base_bash_libs_app_set_file_values__ "$model" "$user_file" user || return $?
    [[ -z "$project_file" ]] || __base_bash_libs_app_set_file_values__ "$model" "$project_file" project || return $?
    for key in "${__base_bash_libs_app_keys[@]+${__base_bash_libs_app_keys[@]}}"; do
        env_name="${__base_bash_libs_app_config["$model|$key|env"]-}"
        if [[ -n "$env_name" && -n "${!env_name+x}" ]]; then
            __base_bash_libs_app_set_value__ "$model" "$key" "${!env_name}" environment || return $?
        fi
    done
    for argument in "${cli_pairs[@]+${cli_pairs[@]}}"; do
        [[ "$argument" == *=* ]] || {
            __base_bash_libs_app_error__ "CLI configuration '$argument' must use key=value syntax."
            return 2
        }
        key="${argument%%=*}"
        value="${argument#*=}"
        [[ -n "${__base_bash_libs_app_config["$model|$key|type"]+set}" ]] || {
            __base_bash_libs_app_error__ "CLI configuration contains unknown key '$key'."
            return 2
        }
        __base_bash_libs_app_set_value__ "$model" "$key" "$value" cli || return $?
    done
    for key in "${__base_bash_libs_app_keys[@]+${__base_bash_libs_app_keys[@]}}"; do
        if [[ -n "${__base_bash_libs_app_cli["$model|$key"]+set}" ]]; then
            __base_bash_libs_app_set_value__ "$model" "$key" "${__base_bash_libs_app_cli["$model|$key"]}" cli || return $?
        fi
        if [[ -z "${__base_bash_libs_app_provenance["$model|$key"]-}" ]] &&
            __base_bash_libs_app_bool_true__ "${__base_bash_libs_app_config["$model|$key|required"]-false}"; then
            __base_bash_libs_app_error__ "required configuration '$key' was not provided."
            return 2
        fi
    done
    return 0
}

# base_app_config_get - Copies one effective configuration value by name.
base_app_config_get() {
    local model="${1-}" key="${2-}" result_name="${3-}"

    (($# == 3)) || {
        __base_bash_libs_app_error__ 'base_app_config_get: usage: base_app_config_get MODEL KEY RESULT_VARIABLE'
        return 2
    }
    __base_bash_libs_std_assert_public_variable_names__ base_app_config_get "$result_name" || return 1
    __base_bash_libs_std_assert_writable_output__ base_app_config_get "$result_name" || return 1
    [[ -n "${__base_bash_libs_app_values["$model|$key"]+set}" ]] || return 1
    printf -v "$result_name" '%s' "${__base_bash_libs_app_values["$model|$key"]}"
}

# base_app_config_provenance - Copies the source of one effective value.
base_app_config_provenance() {
    local model="${1-}" key="${2-}" result_name="${3-}"

    (($# == 3)) || {
        __base_bash_libs_app_error__ 'base_app_config_provenance: usage: base_app_config_provenance MODEL KEY RESULT_VARIABLE'
        return 2
    }
    __base_bash_libs_std_assert_public_variable_names__ base_app_config_provenance "$result_name" || return 1
    __base_bash_libs_std_assert_writable_output__ base_app_config_provenance "$result_name" || return 1
    [[ -n "${__base_bash_libs_app_provenance["$model|$key"]+set}" ]] || return 1
    printf -v "$result_name" '%s' "${__base_bash_libs_app_provenance["$model|$key"]}"
}

__base_bash_libs_app_escape_report_field__() {
    local value="${1-}"
    value="${value//\\/\\\\}"
    value="${value//$'\t'/\\t}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    printf '%s' "$value"
}

# base_app_config_report - Emits deterministic, secret-redacted effective data.
base_app_config_report() {
    local model="${1-}" key value source secret

    (($# == 1)) || {
        __base_bash_libs_app_error__ 'base_app_config_report: usage: base_app_config_report MODEL'
        return 2
    }
    __base_bash_libs_app_model_exists__ "$model" || return 1
    IFS=, read -r -a __base_bash_libs_app_keys <<< "${__base_bash_libs_app_models["$model|config-keys"]-}"
    for key in "${__base_bash_libs_app_keys[@]+${__base_bash_libs_app_keys[@]}}"; do
        value="${__base_bash_libs_app_values["$model|$key"]-<unset>}"
        source="${__base_bash_libs_app_provenance["$model|$key"]-unset}"
        secret="${__base_bash_libs_app_config["$model|$key|secret"]-false}"
        __base_bash_libs_app_bool_true__ "$secret" && value='<redacted>'
        printf '%s\t%s\t%s\n' \
            "$(__base_bash_libs_app_escape_report_field__ "$key")" \
            "$(__base_bash_libs_app_escape_report_field__ "$source")" \
            "$(__base_bash_libs_app_escape_report_field__ "$value")"
    done
}

# base_app_add_standard_options - Opts a CLI model into common policy options.
base_app_add_standard_options() {
    local cli_model="${1-}" path="${2-}"

    (($# == 2)) || {
        __base_bash_libs_app_error__ 'base_app_add_standard_options: usage: base_app_add_standard_options CLI_MODEL COMMAND_PATH'
        return 2
    }
    base_cli_option "$cli_model" "$path" verbose flag --verbose -v help='Enable verbose diagnostics' || return $?
    base_cli_option "$cli_model" "$path" quiet flag --quiet -q conflicts=verbose help='Suppress informational output' || return $?
    base_cli_option "$cli_model" "$path" color value --color default=auto enum=auto,always,never metavar=MODE help='Color policy' || return $?
    base_cli_option "$cli_model" "$path" dry_run flag --dry-run help='Plan without mutating' || return $?
    base_cli_option "$cli_model" "$path" noninteractive flag --non-interactive help='Never prompt' || return $?
    base_cli_option "$cli_model" "$path" config value --config metavar=FILE help='Use a project configuration file' || return $?
    base_cli_option "$cli_model" "$path" user_config value --user-config metavar=FILE help='Use a user configuration file' || return $?
}

# base_app_apply_standard_options - Publishes parsed common options as policy state.
base_app_apply_standard_options() {
    local model="${1-}" value

    (($# == 1)) || {
        __base_bash_libs_app_error__ 'base_app_apply_standard_options: usage: base_app_apply_standard_options MODEL'
        return 2
    }
    __base_bash_libs_app_model_exists__ "$model" || return 1
    # These are caller-visible policy globals consumed by application code.
    # shellcheck disable=SC2034
    BASE_BASH_LIBS_APP_VERBOSE="${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[verbose]-0}"
    # shellcheck disable=SC2034
    BASE_BASH_LIBS_APP_QUIET="${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[quiet]-0}"
    BASE_BASH_LIBS_APP_DRY_RUN="${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[dry_run]-0}"
    BASE_BASH_LIBS_APP_NONINTERACTIVE="${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[noninteractive]-0}"
    value="${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[color]-auto}"
    BASE_BASH_LIBS_APP_COLOR="$value"
    BASE_BASH_LIBS_DRY_RUN="$BASE_BASH_LIBS_APP_DRY_RUN"
    export BASE_BASH_LIBS_APP_DRY_RUN BASE_BASH_LIBS_APP_NONINTERACTIVE BASE_BASH_LIBS_APP_COLOR
    export BASE_BASH_LIBS_DRY_RUN
}

# base_app_should_prompt - True only when policy permits interactive prompts.
base_app_should_prompt() {
    local model="${1-}"
    (($# == 1)) || return 2
    __base_bash_libs_app_model_exists__ "$model" || return 1
    [[ "$BASE_BASH_LIBS_APP_NONINTERACTIVE" != 1 ]] || return 1
    base_std_is_interactive
}

# base_app_prompt - Applies the noninteractive policy to a yes/no prompt.
base_app_prompt() {
    local model="${1-}" message="${2-}" default="${3-no}"
    (($# >= 2 && $# <= 3)) || {
        __base_bash_libs_app_error__ 'base_app_prompt: usage: base_app_prompt MODEL MESSAGE [yes|no]'
        return 2
    }
    base_app_should_prompt "$model" || return 1
    base_std_ask_yes_no "$message" "$default"
}

# base_app_hook - Registers an application lifecycle hook. Hooks are LIFO.
base_app_hook() {
    local model="${1-}" phase="${2-}" hook="${3-}" function_name="${4-}" hooks

    (($# == 4)) || {
        __base_bash_libs_app_error__ 'base_app_hook: usage: base_app_hook MODEL PHASE NAME FUNCTION'
        return 2
    }
    __base_bash_libs_app_model_exists__ "$model" || return 1
    case "$phase" in normal | fatal | int | term | hup | cleanup) ;; *)
        __base_bash_libs_app_error__ "base_app_hook: unsupported phase '$phase'."
        return 2
        ;;
    esac
    __base_bash_libs_app_valid_identifier__ "$hook" || {
        __base_bash_libs_app_error__ "base_app_hook: invalid hook name '$hook'."
        return 2
    }
    __base_bash_libs_app_valid_identifier__ "$function_name" || {
        __base_bash_libs_app_error__ "base_app_hook: invalid function name '$function_name'."
        return 2
    }
    declare -F "$function_name" > /dev/null 2>&1 || {
        __base_bash_libs_app_error__ "base_app_hook: function '$function_name' is not defined."
        return 1
    }
    [[ -z "${__base_bash_libs_app_hooks["$model|$phase|$hook"]+set}" ]] || return 1
    __base_bash_libs_app_hooks["$model|$phase|$hook"]="$function_name"
    hooks="${__base_bash_libs_app_models["$model|hooks|$phase"]-}"
    if [[ -n "$hooks" ]]; then hooks="$hooks,$hook"; else hooks="$hook"; fi
    __base_bash_libs_app_models["$model|hooks|$phase"]="$hooks"
    return 0
}

# base_app_run - Runs an application handler with exactly-once lifecycle hooks.
base_app_run() {
    local model="${1-}" handler="${2-}" status

    (($# >= 2)) || {
        __base_bash_libs_app_error__ 'base_app_run: usage: base_app_run MODEL HANDLER [ARGS...]'
        return 2
    }
    __base_bash_libs_app_model_exists__ "$model" || return 1
    __base_bash_libs_app_valid_identifier__ "$handler" || return 2
    declare -F "$handler" > /dev/null 2>&1 || {
        __base_bash_libs_app_error__ "base_app_run: handler '$handler' is not defined."
        return 1
    }
    BASE_BASH_LIBS_APP_ACTIVE_MODEL="$model"
    BASE_BASH_LIBS_APP_LAST_STATUS=0
    __base_bash_libs_app_models["$model|cleanup-dispatched"]=0
    base_std_register_cleanup_hook __base_bash_libs_app_cleanup_dispatch__ || return 1
    "$handler" "${@:3}"
    status=$?
    __base_bash_libs_app_cleanup_dispatch__ "$status"
    base_std_unregister_cleanup_hook __base_bash_libs_app_cleanup_dispatch__ || true
    BASE_BASH_LIBS_APP_ACTIVE_MODEL=""
    BASE_BASH_LIBS_APP_LAST_STATUS="$status"
    return "$status"
}

# base_app_status - Copies the last application status.
base_app_status() {
    local result_name="${2-}"
    (($# == 2)) || {
        __base_bash_libs_app_error__ 'base_app_status: usage: base_app_status MODEL RESULT_VARIABLE'
        return 2
    }
    __base_bash_libs_std_assert_public_variable_names__ base_app_status "$result_name" || return 1
    __base_bash_libs_std_assert_writable_output__ base_app_status "$result_name" || return 1
    __base_bash_libs_app_model_exists__ "$1" || return 1
    printf -v "$result_name" '%s' "$BASE_BASH_LIBS_APP_LAST_STATUS"
}
