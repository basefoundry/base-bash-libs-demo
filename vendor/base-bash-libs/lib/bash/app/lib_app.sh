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
if [[ "${BASE_BASH_LIBS_STR_LOADED:-}" != "1" ]]; then
    if ! base_std_import str/lib_str.sh; then
        printf '%s\n' "Error: lib_app.sh requires lib_str.sh to be available in the loaded package." >&2
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
declare -gA __base_bash_libs_app_staged_values=()
declare -gA __base_bash_libs_app_staged_provenance=()
declare -gA __base_bash_libs_app_cli=()
declare -ga __base_bash_libs_app_keys=()
declare -ga __base_bash_libs_app_hook_names=()
declare -ga __base_bash_libs_app_run_models=()
declare -ga __base_bash_libs_app_run_dispatched=()
declare -ga __base_bash_libs_app_run_previous_active_models=()
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

__base_bash_libs_app_restrict_attrs__() {
    local owner="$1" allowed="$2" key

    for key in "${!__base_bash_libs_app_attrs[@]}"; do
        __base_bash_libs_app_attr_allowed__ "$key" || return $?
        case ",$allowed," in
        *,"$key",*) ;;
        *)
            __base_bash_libs_app_error__ "$owner: attribute '$key' is not valid for this declaration."
            return 2
            ;;
        esac
    done
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
    local model="$1" key="$2" value="$3" type enum validator item __base_bash_libs_app_integer_normalized
    local -a __base_bash_libs_app_enum_values=()
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
        [[ "$value" =~ ^[-+]?[0-9]+$ ]] &&
            __base_bash_libs_std_decimal_integer_value__ __base_bash_libs_app_integer_normalized "$value" || {
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

__base_bash_libs_app_clear_staged_config__() {
    __base_bash_libs_app_staged_values=()
    __base_bash_libs_app_staged_provenance=()
}

__base_bash_libs_app_clear_global_staged_config__() {
    # Explicit -g keeps cleanup targeted at the compatibility globals even
    # when a caller is already inside another dynamically scoped load frame.
    declare -gA __base_bash_libs_app_staged_values=()
    declare -gA __base_bash_libs_app_staged_provenance=()
}

__base_bash_libs_app_set_value__() {
    local model="$1" key="$2" value="$3" source="$4"
    __base_bash_libs_app_validate_value__ "$model" "$key" "$value" || return $?
    __base_bash_libs_app_staged_values["$model|$key"]="$value"
    __base_bash_libs_app_staged_provenance["$model|$key"]="$source"
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

__base_bash_libs_app_run_frame_dispatch__() {
    local frame_index="$1" status="$2"
    local model="${__base_bash_libs_app_run_models[$frame_index]-}"
    local previous_active_model="${BASE_BASH_LIBS_APP_ACTIVE_MODEL-}"

    [[ -n "$model" ]] || return "$status"
    [[ "${__base_bash_libs_app_run_dispatched[$frame_index]-0}" == 1 ]] && return "$status"
    __base_bash_libs_app_run_dispatched[$frame_index]=1
    __base_bash_libs_app_models["$model|cleanup-dispatched"]=1
    BASE_BASH_LIBS_APP_ACTIVE_MODEL="$model"
    case "$status" in
    0) __base_bash_libs_app_hook_dispatch__ "$model" normal "$status" ;;
    129) __base_bash_libs_app_hook_dispatch__ "$model" hup "$status" ;;
    130) __base_bash_libs_app_hook_dispatch__ "$model" int "$status" ;;
    143) __base_bash_libs_app_hook_dispatch__ "$model" term "$status" ;;
    *) __base_bash_libs_app_hook_dispatch__ "$model" fatal "$status" ;;
    esac
    __base_bash_libs_app_hook_dispatch__ "$model" cleanup "$status"
    __base_bash_libs_app_models["$model|last-status"]="$status"
    BASE_BASH_LIBS_APP_LAST_STATUS="$status"
    BASE_BASH_LIBS_APP_ACTIVE_MODEL="$previous_active_model"
    return "$status"
}

__base_bash_libs_app_cleanup_dispatch__() {
    local entry_status=$?
    local status="${1-}" model frame_index

    if [[ -z "$status" ]]; then
        if [[ "${__base_bash_libs_std_cleanup_dispatcher_running-0}" == 1 ]]; then
            status="${__base_bash_libs_std_cleanup_status-$entry_status}"
        else
            status=$entry_status
        fi
    fi
    if ((${#__base_bash_libs_app_run_models[@]} > 0)); then
        for ((frame_index = ${#__base_bash_libs_app_run_models[@]} - 1; frame_index >= 0; frame_index--)); do
            __base_bash_libs_app_run_frame_dispatch__ "$frame_index" "$status" || true
        done
        return "$status"
    fi

    # Retain the internal dispatcher fallback used by existing integrations
    # that set the active model before invoking the shared cleanup boundary.
    model="${BASE_BASH_LIBS_APP_ACTIVE_MODEL-}"
    [[ -n "$model" ]] || return "$status"
    [[ "${__base_bash_libs_app_models["$model|cleanup-dispatched"]-0}" == 1 ]] && return "$status"
    __base_bash_libs_app_run_models+=("$model")
    __base_bash_libs_app_run_dispatched+=(0)
    frame_index=$((${#__base_bash_libs_app_run_models[@]} - 1))
    __base_bash_libs_app_run_frame_dispatch__ "$frame_index" "$status" || true
    unset '__base_bash_libs_app_run_models[frame_index]'
    unset '__base_bash_libs_app_run_dispatched[frame_index]'
    return "$status"
}

# base_app_init - Initializes an optional application policy model.
# Usage: base_app_init MODEL [name=APP_KEY] [description=TEXT]
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
    __base_bash_libs_app_restrict_attrs__ base_app_init 'name,description' || return $?
    if [[ -n "${__base_bash_libs_app_attrs[name]+set}" ]] &&
        ! __base_bash_libs_app_valid_key__ "${__base_bash_libs_app_attrs[name]}"; then
        __base_bash_libs_app_error__ 'base_app_init: name must be a lowercase application key.'
        return 2
    fi
    if ((${#__base_bash_libs_app_run_models[@]} > 0)); then
        __base_bash_libs_app_error__ "base_app_init: cannot reinitialize model '$model' while an application run is active."
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
    for key in "${!__base_bash_libs_app_staged_values[@]}"; do
        [[ "$key" == "$model|"* ]] && unset "__base_bash_libs_app_staged_values[$key]"
    done
    for key in "${!__base_bash_libs_app_staged_provenance[@]}"; do
        [[ "$key" == "$model|"* ]] && unset "__base_bash_libs_app_staged_provenance[$key]"
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
    __base_bash_libs_app_models["$model|last-status"]=0
    for key in normal fatal int term hup cleanup; do
        __base_bash_libs_app_models["$model|hooks|$key"]=""
    done
    __base_bash_libs_app_models["$model|cleanup-dispatched"]=0
    return 0
}

# base_app_config_define - Defines one typed configuration value.
# Usage: base_app_config_define MODEL KEY TYPE [env=NAME] [default=VALUE]
#        [required=BOOL] [secret=BOOL] [enum=A,B] [validator=FUNCTION]
#        [help=TEXT]
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
    __base_bash_libs_app_restrict_attrs__ base_app_config_define \
        'env,default,required,secret,enum,validator,help' || return $?
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
    local __base_bash_libs_app_load_model="${1-}" __base_bash_libs_app_load_argument
    local __base_bash_libs_app_load_project_file="" __base_bash_libs_app_load_user_file=""
    local __base_bash_libs_app_load_key __base_bash_libs_app_load_value_key
    local __base_bash_libs_app_load_env_name __base_bash_libs_app_load_value
    local __base_bash_libs_app_load_status
    local -a __base_bash_libs_app_load_cli_pairs=()
    local -a __base_bash_libs_app_keys=()
    # Keep each load transaction on the dynamic call frame. Validators may
    # legitimately load another model (or re-enter this one); a global staging
    # map would let the nested transaction clear or overwrite the outer one.
    # Bash's dynamic scoping makes these locals visible to the existing helper
    # functions without changing their public/internal interfaces.
    local -A __base_bash_libs_app_staged_values=()
    local -A __base_bash_libs_app_staged_provenance=()
    __base_bash_libs_app_clear_global_staged_config__
    local __base_bash_libs_app_load_parse_options=1

    (($# >= 1)) || {
        __base_bash_libs_app_error__ 'base_app_config_load: expected a model.'
        return 2
    }
    __base_bash_libs_app_model_exists__ "$__base_bash_libs_app_load_model" || return 1
    shift
    while (($#)); do
        __base_bash_libs_app_load_argument="$1"
        shift
        if ((__base_bash_libs_app_load_parse_options)) && [[ "$__base_bash_libs_app_load_argument" == -- ]]; then
            __base_bash_libs_app_load_parse_options=0
            continue
        fi
        if ((__base_bash_libs_app_load_parse_options)) && [[ "$__base_bash_libs_app_load_argument" == --project || "$__base_bash_libs_app_load_argument" == --config ]]; then
            (($# > 0)) || {
                __base_bash_libs_app_error__ "$__base_bash_libs_app_load_argument requires a file."
                __base_bash_libs_app_clear_staged_config__
                return 2
            }
            __base_bash_libs_app_load_project_file="$1"
            shift
            continue
        fi
        if ((__base_bash_libs_app_load_parse_options)) && [[ "$__base_bash_libs_app_load_argument" == --user ]]; then
            (($# > 0)) || {
                __base_bash_libs_app_error__ '--user requires a file.'
                __base_bash_libs_app_clear_staged_config__
                return 2
            }
            __base_bash_libs_app_load_user_file="$1"
            shift
            continue
        fi
        if ((__base_bash_libs_app_load_parse_options)) && [[ "$__base_bash_libs_app_load_argument" == --cli ]]; then
            (($# > 0)) || {
                __base_bash_libs_app_error__ '--cli requires key=value.'
                __base_bash_libs_app_clear_staged_config__
                return 2
            }
            __base_bash_libs_app_load_cli_pairs+=("$1")
            shift
            continue
        fi
        __base_bash_libs_app_error__ "unknown configuration load argument '$__base_bash_libs_app_load_argument'."
        __base_bash_libs_app_clear_staged_config__
        return 2
    done

    IFS=, read -r -a __base_bash_libs_app_keys <<< "${__base_bash_libs_app_models["$__base_bash_libs_app_load_model|config-keys"]-}"
    for __base_bash_libs_app_load_key in "${__base_bash_libs_app_keys[@]+${__base_bash_libs_app_keys[@]}}"; do
        if [[ -n "${__base_bash_libs_app_config["$__base_bash_libs_app_load_model|$__base_bash_libs_app_load_key|default"]+set}" ]]; then
            __base_bash_libs_app_set_value__ "$__base_bash_libs_app_load_model" "$__base_bash_libs_app_load_key" "${__base_bash_libs_app_config["$__base_bash_libs_app_load_model|$__base_bash_libs_app_load_key|default"]}" default || {
                __base_bash_libs_app_load_status=$?
                __base_bash_libs_app_clear_staged_config__
                return "$__base_bash_libs_app_load_status"
            }
        fi
    done
    if [[ -n "$__base_bash_libs_app_load_user_file" ]]; then
        __base_bash_libs_app_set_file_values__ "$__base_bash_libs_app_load_model" "$__base_bash_libs_app_load_user_file" user || {
            __base_bash_libs_app_load_status=$?
            __base_bash_libs_app_clear_staged_config__
            return "$__base_bash_libs_app_load_status"
        }
    fi
    if [[ -n "$__base_bash_libs_app_load_project_file" ]]; then
        __base_bash_libs_app_set_file_values__ "$__base_bash_libs_app_load_model" "$__base_bash_libs_app_load_project_file" project || {
            __base_bash_libs_app_load_status=$?
            __base_bash_libs_app_clear_staged_config__
            return "$__base_bash_libs_app_load_status"
        }
    fi
    for __base_bash_libs_app_load_key in "${__base_bash_libs_app_keys[@]+${__base_bash_libs_app_keys[@]}}"; do
        __base_bash_libs_app_load_env_name="${__base_bash_libs_app_config["$__base_bash_libs_app_load_model|$__base_bash_libs_app_load_key|env"]-}"
        if [[ -n "$__base_bash_libs_app_load_env_name" && -n "${!__base_bash_libs_app_load_env_name-}" ]]; then
            __base_bash_libs_app_set_value__ "$__base_bash_libs_app_load_model" "$__base_bash_libs_app_load_key" "${!__base_bash_libs_app_load_env_name}" environment || {
                __base_bash_libs_app_load_status=$?
                __base_bash_libs_app_clear_staged_config__
                return "$__base_bash_libs_app_load_status"
            }
        fi
    done
    for __base_bash_libs_app_load_argument in "${__base_bash_libs_app_load_cli_pairs[@]+${__base_bash_libs_app_load_cli_pairs[@]}}"; do
        [[ "$__base_bash_libs_app_load_argument" == *=* ]] || {
            __base_bash_libs_app_error__ "CLI configuration '$__base_bash_libs_app_load_argument' must use key=value syntax."
            __base_bash_libs_app_clear_staged_config__
            return 2
        }
        __base_bash_libs_app_load_key="${__base_bash_libs_app_load_argument%%=*}"
        __base_bash_libs_app_load_value="${__base_bash_libs_app_load_argument#*=}"
        [[ -n "${__base_bash_libs_app_config["$__base_bash_libs_app_load_model|$__base_bash_libs_app_load_key|type"]+set}" ]] || {
            __base_bash_libs_app_error__ "CLI configuration contains unknown key '$__base_bash_libs_app_load_key'."
            __base_bash_libs_app_clear_staged_config__
            return 2
        }
        __base_bash_libs_app_set_value__ "$__base_bash_libs_app_load_model" "$__base_bash_libs_app_load_key" "$__base_bash_libs_app_load_value" cli || {
            __base_bash_libs_app_load_status=$?
            __base_bash_libs_app_clear_staged_config__
            return "$__base_bash_libs_app_load_status"
        }
    done
    for __base_bash_libs_app_load_key in "${__base_bash_libs_app_keys[@]+${__base_bash_libs_app_keys[@]}}"; do
        if [[ -n "${__base_bash_libs_app_cli["$__base_bash_libs_app_load_model|$__base_bash_libs_app_load_key"]+set}" ]]; then
            __base_bash_libs_app_set_value__ "$__base_bash_libs_app_load_model" "$__base_bash_libs_app_load_key" "${__base_bash_libs_app_cli["$__base_bash_libs_app_load_model|$__base_bash_libs_app_load_key"]}" cli || {
                __base_bash_libs_app_load_status=$?
                __base_bash_libs_app_clear_staged_config__
                return "$__base_bash_libs_app_load_status"
            }
        fi
        if [[ -z "${__base_bash_libs_app_staged_provenance["$__base_bash_libs_app_load_model|$__base_bash_libs_app_load_key"]-}" ]] &&
            __base_bash_libs_app_bool_true__ "${__base_bash_libs_app_config["$__base_bash_libs_app_load_model|$__base_bash_libs_app_load_key|required"]-false}"; then
            __base_bash_libs_app_error__ "required configuration '$__base_bash_libs_app_load_key' was not provided."
            __base_bash_libs_app_clear_staged_config__
            return 2
        fi
    done

    for __base_bash_libs_app_load_value_key in "${!__base_bash_libs_app_values[@]}"; do
        [[ "$__base_bash_libs_app_load_value_key" == "$__base_bash_libs_app_load_model|"* ]] && unset "__base_bash_libs_app_values[$__base_bash_libs_app_load_value_key]"
    done
    for __base_bash_libs_app_load_value_key in "${!__base_bash_libs_app_provenance[@]}"; do
        [[ "$__base_bash_libs_app_load_value_key" == "$__base_bash_libs_app_load_model|"* ]] && unset "__base_bash_libs_app_provenance[$__base_bash_libs_app_load_value_key]"
    done
    for __base_bash_libs_app_load_value_key in "${!__base_bash_libs_app_staged_values[@]}"; do
        __base_bash_libs_app_values["$__base_bash_libs_app_load_value_key"]="${__base_bash_libs_app_staged_values["$__base_bash_libs_app_load_value_key"]}"
    done
    for __base_bash_libs_app_load_value_key in "${!__base_bash_libs_app_staged_provenance[@]}"; do
        __base_bash_libs_app_provenance["$__base_bash_libs_app_load_value_key"]="${__base_bash_libs_app_staged_provenance["$__base_bash_libs_app_load_value_key"]}"
    done
    __base_bash_libs_app_clear_staged_config__
    return 0
}

# base_app_config_get - Copies one effective configuration value by name.
base_app_config_get() {
    local __base_bash_libs_app_config_get_model="${1-}"
    local __base_bash_libs_app_config_get_key="${2-}"
    local __base_bash_libs_app_config_get_result_name="${3-}"
    local __base_bash_libs_app_config_get_output_kind=scalar

    (($# == 3)) || {
        __base_bash_libs_app_error__ 'base_app_config_get: usage: base_app_config_get MODEL KEY RESULT_VARIABLE'
        return 2
    }
    __base_bash_libs_std_validate_variable_names__ base_app_config_get \
        "$__base_bash_libs_app_config_get_result_name" || return 2
    if [[ "${__base_bash_libs_app_config["$__base_bash_libs_app_config_get_model|$__base_bash_libs_app_config_get_key|type"]-}" == integer ]]; then
        __base_bash_libs_app_config_get_output_kind=integer
    fi
    __base_bash_libs_std_assert_writable_output__ base_app_config_get \
        "$__base_bash_libs_app_config_get_result_name" \
        "$__base_bash_libs_app_config_get_output_kind" || return 2
    [[ -n "${__base_bash_libs_app_values["$__base_bash_libs_app_config_get_model|$__base_bash_libs_app_config_get_key"]+set}" ]] || return 1
    local __base_bash_libs_app_config_get_value="${__base_bash_libs_app_values["$__base_bash_libs_app_config_get_model|$__base_bash_libs_app_config_get_key"]}"
    local __base_bash_libs_app_config_get_declaration=""
    if __base_bash_libs_app_config_get_declaration=$(declare -p "$__base_bash_libs_app_config_get_result_name" 2> /dev/null) &&
        [[ "$__base_bash_libs_app_config_get_declaration" == declare\ -i* ]]; then
        __base_bash_libs_std_decimal_integer_value__ __base_bash_libs_app_config_get_value "$__base_bash_libs_app_config_get_value" || {
            __base_bash_libs_app_error__ "configuration '$__base_bash_libs_app_config_get_key' is outside the supported integer range."
            return 2
        }
    fi
    printf -v "$__base_bash_libs_app_config_get_result_name" '%s' "$__base_bash_libs_app_config_get_value"
}

# base_app_config_provenance - Copies the source of one effective value.
base_app_config_provenance() {
    local __base_bash_libs_app_config_provenance_model="${1-}"
    local __base_bash_libs_app_config_provenance_key="${2-}"
    local __base_bash_libs_app_config_provenance_result_name="${3-}"

    (($# == 3)) || {
        __base_bash_libs_app_error__ 'base_app_config_provenance: usage: base_app_config_provenance MODEL KEY RESULT_VARIABLE'
        return 2
    }
    __base_bash_libs_std_validate_variable_names__ base_app_config_provenance \
        "$__base_bash_libs_app_config_provenance_result_name" || return 2
    __base_bash_libs_std_assert_writable_output__ base_app_config_provenance \
        "$__base_bash_libs_app_config_provenance_result_name" scalar || return 2
    [[ -n "${__base_bash_libs_app_provenance["$__base_bash_libs_app_config_provenance_model|$__base_bash_libs_app_config_provenance_key"]+set}" ]] || return 1
    printf -v "$__base_bash_libs_app_config_provenance_result_name" '%s' \
        "${__base_bash_libs_app_provenance["$__base_bash_libs_app_config_provenance_model|$__base_bash_libs_app_config_provenance_key"]}"
}

# base_app_config_report - Emits deterministic, secret-redacted effective data.
base_app_config_report() {
    local __base_bash_libs_app_report_model="${1-}"
    local __base_bash_libs_app_report_key __base_bash_libs_app_report_value
    local __base_bash_libs_app_report_source __base_bash_libs_app_report_secret
    local -a __base_bash_libs_app_report_keys=()

    (($# == 1)) || {
        __base_bash_libs_app_error__ 'base_app_config_report: usage: base_app_config_report MODEL'
        return 2
    }
    __base_bash_libs_app_model_exists__ "$__base_bash_libs_app_report_model" || return 1
    IFS=, read -r -a __base_bash_libs_app_report_keys <<< "${__base_bash_libs_app_models["$__base_bash_libs_app_report_model|config-keys"]-}"
    for __base_bash_libs_app_report_key in "${__base_bash_libs_app_report_keys[@]+${__base_bash_libs_app_report_keys[@]}}"; do
        __base_bash_libs_app_report_value="${__base_bash_libs_app_values["$__base_bash_libs_app_report_model|$__base_bash_libs_app_report_key"]-<unset>}"
        __base_bash_libs_app_report_source="${__base_bash_libs_app_provenance["$__base_bash_libs_app_report_model|$__base_bash_libs_app_report_key"]-unset}"
        __base_bash_libs_app_report_secret="${__base_bash_libs_app_config["$__base_bash_libs_app_report_model|$__base_bash_libs_app_report_key|secret"]-false}"
        __base_bash_libs_app_bool_true__ "$__base_bash_libs_app_report_secret" && __base_bash_libs_app_report_value='<redacted>'
        printf '%s\t%s\t%s\n' \
            "$(__base_bash_libs_str_escape_tsv_field__ "$__base_bash_libs_app_report_key")" \
            "$(__base_bash_libs_str_escape_tsv_field__ "$__base_bash_libs_app_report_source")" \
            "$(__base_bash_libs_str_escape_tsv_field__ "$__base_bash_libs_app_report_value")"
    done
}

# base_app_add_standard_options - Opts a CLI model into common policy options.
base_app_add_standard_options() {
    local cli_model="${1-}" path="${2-}" color_modes

    (($# == 2)) || {
        __base_bash_libs_app_error__ 'base_app_add_standard_options: usage: base_app_add_standard_options CLI_MODEL COMMAND_PATH'
        return 2
    }
    color_modes="$(__base_bash_libs_std_color_modes__)" || return $?
    base_cli_option "$cli_model" "$path" verbose flag --verbose -v help='Enable verbose diagnostics' || return $?
    base_cli_option "$cli_model" "$path" quiet flag --quiet -q conflicts=verbose help='Suppress informational output' || return $?
    base_cli_option "$cli_model" "$path" color value --color default=auto enum="$color_modes" metavar=MODE help='Color policy' || return $?
    base_cli_option "$cli_model" "$path" dry_run flag --dry-run help='Plan without mutating' || return $?
    base_cli_option "$cli_model" "$path" noninteractive flag --non-interactive help='Never prompt' || return $?
    base_cli_option "$cli_model" "$path" config value --config metavar=FILE help='Use a project configuration file' || return $?
    base_cli_option "$cli_model" "$path" user_config value --user-config metavar=FILE help='Use a user configuration file' || return $?
}

# base_app_apply_standard_options - Publishes parsed common options as policy state.
base_app_apply_standard_options() {
    local model="${1-}" value cli_color

    (($# == 1)) || {
        __base_bash_libs_app_error__ 'base_app_apply_standard_options: usage: base_app_apply_standard_options MODEL'
        return 2
    }
    __base_bash_libs_app_model_exists__ "$model" || return 1
    cli_color="${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[color]-auto}"
    if ! __base_bash_libs_std_color_mode_is_valid__ "$cli_color"; then
        __base_bash_libs_app_error__ "base_app_apply_standard_options: invalid color mode '$cli_color'."
        return 2
    fi
    value="${__base_bash_libs_std_wrapper_color_mode:-$cli_color}"
    # These are caller-visible policy globals consumed by application code.
    # shellcheck disable=SC2034
    BASE_BASH_LIBS_APP_VERBOSE="${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[verbose]-0}"
    # shellcheck disable=SC2034
    BASE_BASH_LIBS_APP_QUIET="${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[quiet]-0}"
    BASE_BASH_LIBS_APP_DRY_RUN="${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[dry_run]-0}"
    BASE_BASH_LIBS_APP_NONINTERACTIVE="${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[noninteractive]-0}"
    if [[ -n "${BASE_BASH_LIBS_STD_LOG_LEVELS[INFO]+set}" ]]; then
        case "${BASE_BASH_LIBS_APP_QUIET}:${BASE_BASH_LIBS_APP_VERBOSE}" in
        1:0) base_std_set_log_level WARN || return $? ;;
        0:1) base_std_set_log_level DEBUG || return $? ;;
        0:0) base_std_set_log_level INFO || return $? ;;
        *)
            __base_bash_libs_app_error__ 'base_app_apply_standard_options: quiet and verbose cannot both be enabled.'
            return 2
            ;;
        esac
    elif [[ "${BASE_BASH_LIBS_APP_QUIET}:${BASE_BASH_LIBS_APP_VERBOSE}" == 1:1 ]]; then
        __base_bash_libs_app_error__ 'base_app_apply_standard_options: quiet and verbose cannot both be enabled.'
        return 2
    fi
    __base_bash_libs_std_apply_color_mode__ "$value" || return $?
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
    local model="${1-}" handler="${2-}" status frame_index outermost=0

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
    ((${#__base_bash_libs_app_run_models[@]} == 0)) && outermost=1
    __base_bash_libs_app_run_previous_active_models+=("${BASE_BASH_LIBS_APP_ACTIVE_MODEL-}")
    __base_bash_libs_app_run_models+=("$model")
    __base_bash_libs_app_run_dispatched+=(0)
    frame_index=$((${#__base_bash_libs_app_run_models[@]} - 1))
    BASE_BASH_LIBS_APP_ACTIVE_MODEL="$model"
    # shellcheck disable=SC2034 # Published compatibility status for callers.
    BASE_BASH_LIBS_APP_LAST_STATUS=0
    __base_bash_libs_app_models["$model|cleanup-dispatched"]=0
    if ((outermost)) && ! base_std_register_cleanup_hook __base_bash_libs_app_cleanup_dispatch__; then
        BASE_BASH_LIBS_APP_ACTIVE_MODEL="${__base_bash_libs_app_run_previous_active_models[$frame_index]-}"
        unset '__base_bash_libs_app_run_models[frame_index]'
        unset '__base_bash_libs_app_run_dispatched[frame_index]'
        unset '__base_bash_libs_app_run_previous_active_models[frame_index]'
        return 1
    fi
    "$handler" "${@:3}"
    status=$?
    __base_bash_libs_app_run_frame_dispatch__ "$frame_index" "$status" || true
    BASE_BASH_LIBS_APP_ACTIVE_MODEL="${__base_bash_libs_app_run_previous_active_models[$frame_index]-}"
    unset '__base_bash_libs_app_run_models[frame_index]'
    unset '__base_bash_libs_app_run_dispatched[frame_index]'
    unset '__base_bash_libs_app_run_previous_active_models[frame_index]'
    if ((outermost)); then
        base_std_unregister_cleanup_hook __base_bash_libs_app_cleanup_dispatch__ || true
    fi
    return "$status"
}

# base_app_status - Copies the model's last run status; never-run models are 0.
base_app_status() {
    local __base_bash_libs_app_status_model="${1-}"
    local __base_bash_libs_app_status_result_name="${2-}"
    (($# == 2)) || {
        __base_bash_libs_app_error__ 'base_app_status: usage: base_app_status MODEL RESULT_VARIABLE'
        return 2
    }
    __base_bash_libs_std_validate_variable_names__ base_app_status \
        "$__base_bash_libs_app_status_result_name" || return 2
    __base_bash_libs_std_assert_writable_output__ base_app_status \
        "$__base_bash_libs_app_status_result_name" integer || return 2
    __base_bash_libs_app_model_exists__ "$__base_bash_libs_app_status_model" || return 1
    printf -v "$__base_bash_libs_app_status_result_name" '%s' \
        "${__base_bash_libs_app_models["$__base_bash_libs_app_status_model|last-status"]-0}"
}
