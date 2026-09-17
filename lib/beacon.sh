# shellcheck shell=bash

beacon_project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

base_launcher_import_base_bash_lib \
    cli/lib_cli.sh app/lib_app.sh file/lib_file.sh git/lib_git.sh \
    str/lib_str.sh list/lib_list.sh

base_require_version 2.0.0 || base_std_fatal_error "Beacon requires Base Bash 2.0.0 or newer."

base_cli_model_init beacon \
    name=beacon version=0.1.0 \
    description="Offline support-bundle collector" handler=beacon_dispatch
base_cli_command beacon status "Show fixture and framework readiness" handler=beacon_dispatch
base_cli_command beacon plan "Describe bundle inputs and redactions" handler=beacon_dispatch
base_cli_command beacon collect "Create a redacted support bundle" handler=beacon_dispatch
base_cli_command beacon verify "Verify a collected support bundle" handler=beacon_dispatch
base_cli_option beacon "" workspace value --workspace \
    help="Input workspace" metavar=PATH
base_cli_option beacon "" output value --output \
    help="Support bundle directory" metavar=PATH
base_cli_option beacon "" lifecycle_log value --lifecycle-log \
    help="Append one machine-readable cleanup event" metavar=PATH
base_cli_option beacon collect scenario value --scenario \
    default=normal enum=normal,failure,interrupt \
    help="Deterministic collection scenario" metavar=NAME
base_app_add_standard_options beacon ""

base_app_init beacon_policy name=beacon description="Beacon collection policy"
base_app_config_define beacon_policy workspace path \
    default="$beacon_project_root/fixtures/workspace" env=BEACON_WORKSPACE
base_app_config_define beacon_policy output path \
    default="$beacon_project_root/.beacon-output/beacon-support" env=BEACON_OUTPUT
base_app_config_define beacon_policy lifecycle_log path \
    default="" env=BEACON_LIFECYCLE_LOG
base_app_config_define beacon_policy scenario enum \
    enum=normal,failure,interrupt default=normal env=BEACON_SCENARIO

declare -a BEACON_SELECTED_FILES=()
declare -a BEACON_SECRET_VALUES=()
declare -a BEACON_UNIQUE_SECRET_VALUES=()
BEACON_ACTIVE_LIFECYCLE_LOG=""

beacon_error() {
    base_std_print_error "$*"
    return 1
}

# The caller owns the root directory; below it, no links or special files are
# supported. This is a preflight policy, not a concurrent-filesystem sandbox.
beacon_check_path() {
    local root="$1" relative="$2" component current="$1"
    [[ -d "$root" && ! -L "$root" ]] || {
        beacon_error "Unsafe input root '$root'."; return 1;
    }
    [[ -n "$relative" && "$relative" != /* ]] || return 1
    local -a components=()
    IFS=/ read -r -a components <<< "$relative"
    for component in "${components[@]}"; do
        [[ -n "$component" && "$component" != . && "$component" != .. ]] || {
            beacon_error "Noncanonical input path."; return 1;
        }
        current="$current/$component"
        [[ ! -L "$current" ]] || {
            beacon_error "Links are not supported in inputs or bundles."; return 1;
        }
        if [[ -e "$current" && ! -d "$current" && ! -f "$current" ]]; then
            beacon_error "Special files are not supported in inputs or bundles."
            return 1
        fi
    done
}

beacon_check_bundle_tree() {
    local root="$1" path listing
    [[ -d "$root" && ! -L "$root" ]] || {
        beacon_error "Unsafe bundle root."; return 1;
    }
    # Capture find's status before consuming its NUL-delimited result.
    base_std_make_temp_file listing beacon-inventory || return 1
    find "$root" -print0 > "$listing" || return 1
    while IFS= read -r -d '' path; do
        [[ "$path" == "$root" ]] && continue
        beacon_check_path "$root" "${path#"$root"/}" || return 1
    done < "$listing"
}

beacon_select_files() {
    local workspace="$1" relative
    local -a candidates=(
        config/app.env
        logs/app.log
        system/info.txt
    )

    BEACON_SELECTED_FILES=()
    for relative in "${candidates[@]}"; do
        beacon_check_path "$workspace" "$relative" || return 1
        [[ -f "$workspace/$relative" ]] || continue
        base_list_append BEACON_SELECTED_FILES "$relative" || return $?
    done
}

beacon_load_secret_values() {
    local workspace="$1" line key value normalized_key

    # Mutated and consumed by name through Base Bash list helpers.
    # shellcheck disable=SC2034
    BEACON_SECRET_VALUES=()
    BEACON_UNIQUE_SECRET_VALUES=()
    beacon_check_path "$workspace" config/app.env || return 1
    [[ -f "$workspace/config/app.env" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == *=* ]] || continue
        key="${line%%=*}"
        value="${line#*=}"
        normalized_key="$key"
        base_str_trim normalized_key
        base_str_upper normalized_key
        case "$normalized_key" in
            *TOKEN*|*SECRET*|*PASSWORD*)
                [[ -n "$value" ]] && base_list_append BEACON_SECRET_VALUES "$value"
                ;;
        esac
    done < "$workspace/config/app.env"

    base_list_unique BEACON_UNIQUE_SECRET_VALUES BEACON_SECRET_VALUES
}

beacon_write_redacted_file() {
    local source_file="$1" target_file="$2"
    local line key normalized_key secret

    base_std_safe_mkdir -p "$(dirname -- "$target_file")" || return $?
    base_std_safe_truncate "$target_file" || return $?

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == *=* ]]; then
            key="${line%%=*}"
            normalized_key="$key"
            base_str_trim normalized_key
            base_str_upper normalized_key
            case "$normalized_key" in
                *TOKEN*|*SECRET*|*PASSWORD*)
                    line="$key=[REDACTED]"
                    ;;
            esac
        fi
        for secret in "${BEACON_UNIQUE_SECRET_VALUES[@]}"; do
            [[ -n "$secret" ]] || continue
            line="${line//"$secret"/[REDACTED]}"
        done
        printf '%s\n' "$line" >> "$target_file" || return 1
    done < "$source_file"
}

beacon_sha256() {
    local file="$1" result_var="$2" tool output digest

    if base_std_command_path tool sha256sum; then
        output="$("$tool" "$file")" || return 1
    elif base_std_command_path tool shasum; then
        output="$("$tool" -a 256 "$file")" || return 1
    else
        beacon_error "Neither sha256sum nor shasum is available."
        return $?
    fi
    digest="${output%% *}"
    printf -v "$result_var" '%s' "$digest"
}

beacon_bundle_contains_value() {
    local bundle="$1" needle="$2" file line

    [[ -n "$needle" ]] || return 1
    while IFS= read -r file; do
        while IFS= read -r line || [[ -n "$line" ]]; do
            base_str_contains "$line" "$needle" && return 0
        done < "$file"
    done < <(find "$bundle" -type f ! -name MANIFEST.sha256 -print | LC_ALL=C sort)
    return 1
}

beacon_status() {
    local workspace="$1" branch="" count="" workspace_ready="no"

    beacon_select_files "$workspace" || return $?
    base_list_length count BEACON_SELECTED_FILES || return $?
    base_git_get_current_branch "$beacon_project_root" branch || return $?
    [[ -n "$branch" ]] || branch="unavailable"
    [[ -d "$workspace" ]] && workspace_ready="yes"

    printf 'application=beacon\n'
    printf 'workspace=%s\n' "$workspace"
    printf 'workspace_ready=%s\n' "$workspace_ready"
    printf 'selected_files=%s\n' "$count"
    printf 'consumer_branch=%s\n' "$branch"
    printf 'framework_version=%s\n' "$BASE_BASH_LIBS_VERSION"
    printf 'framework_commit=%s\n' "$BASE_BASH_LIBS_COMMIT"
    printf 'framework_dirty_state=%s\n' "$BASE_BASH_LIBS_DIRTY_STATE"
    printf 'framework_provenance=%s\n' "$BASE_BASH_LIBS_PROVENANCE"
}

beacon_plan() {
    local workspace="$1" output="$2" relative count="" joined=""

    [[ -d "$workspace" ]] || {
        beacon_error "Workspace '$workspace' does not exist."
        return $?
    }
    beacon_select_files "$workspace" || return $?
    base_list_length count BEACON_SELECTED_FILES || return $?
    base_str_join joined "," BEACON_SELECTED_FILES || return $?

    printf 'operation=collect\n'
    printf 'workspace=%s\n' "$workspace"
    printf 'output=%s\n' "$output"
    printf 'selected_files=%s\n' "$count"
    printf 'inputs=%s\n' "$joined"
    printf 'redact_keys=TOKEN,SECRET,PASSWORD\n'
    for relative in "${BEACON_SELECTED_FILES[@]}"; do
        printf 'include=%s\n' "$relative"
    done
}

beacon_collect() {
    local workspace="$1" output="$2" scenario="$3"
    local stage="" relative target hash branch=""
    local manifest readme owned_output

    [[ -d "$workspace" ]] || {
        beacon_error "Workspace '$workspace' does not exist."
        return $?
    }
    beacon_select_files "$workspace" || return $?
    ((${#BEACON_SELECTED_FILES[@]} > 0)) || {
        beacon_error "Workspace '$workspace' has no supported fixture inputs."
        return $?
    }
    beacon_load_secret_values "$workspace" || return $?

    if ((BASE_BASH_LIBS_APP_DRY_RUN)); then
        printf 'dry_run=true\noperation=collect\noutput=%s\nselected_files=%s\n' \
            "$output" "${#BEACON_SELECTED_FILES[@]}"
        return 0
    fi
    [[ ! -e "$output" && ! -L "$output" ]] || {
        beacon_error "Output '$output' already exists; choose an unused path."
        return $?
    }

    base_std_make_temp_dir stage beacon-support || return $?
    for relative in "${BEACON_SELECTED_FILES[@]}"; do
        target="$stage/files/$relative"
        beacon_check_path "$workspace" "$relative" || return 1
        beacon_write_redacted_file "$workspace/$relative" "$target" || return $?
    done

    case "$scenario" in
        failure)
            base_std_print_error "Simulated collection failure before publication."
            return 70
            ;;
        interrupt)
            printf 'scenario=interrupt\nstate=waiting_for_signal\n'
            while :; do
                sleep 1
            done
            ;;
    esac

    base_git_get_current_branch "$beacon_project_root" branch || return $?
    [[ -n "$branch" ]] || branch="unavailable"
    readme="$stage/README.txt"
    base_std_safe_touch "$readme" || return $?
    base_file_update_file_section "$readme" \
        '# BEGIN BEACON REPORT' '# END BEACON REPORT' \
        'application=beacon' \
        'schema_version=1' \
        "consumer_branch=$branch" \
        "framework_version=$BASE_BASH_LIBS_VERSION" \
        "framework_commit=$BASE_BASH_LIBS_COMMIT" \
        "framework_provenance=$BASE_BASH_LIBS_PROVENANCE" \
        "selected_files=${#BEACON_SELECTED_FILES[@]}" || return $?

    manifest="$stage/MANIFEST.sha256"
    base_std_safe_truncate "$manifest" || return $?
    for relative in README.txt "${BEACON_SELECTED_FILES[@]/#/files/}"; do
        beacon_sha256 "$stage/$relative" hash || return $?
        printf '%s\t%s\n' "$hash" "$relative" >> "$manifest" || return 1
    done

    base_std_safe_mkdir -p "$(dirname -- "$output")" || return $?
    # mkdir (without -p) is the exclusive reservation. Never move a directory
    # onto an unreserved destination: mv would nest it if another creator won.
    if ! mkdir -- "$output"; then
        beacon_error "Cannot reserve output '$output'; another creator may own it."
        return 1
    fi
    owned_output="$(cd -- "$output" && pwd -P)" || return 1
    if ! base_std_register_cleanup_path "$owned_output"; then
        rmdir -- "$output"
        return 1
    fi
    for relative in files README.txt MANIFEST.sha256; do
        base_std_run mv -- "$stage/$relative" "$output/$relative" || return $?
    done
    beacon_verify "$workspace" "$output" > /dev/null || return $?
    base_std_unregister_cleanup_path "$owned_output" || return $?
    printf 'bundle=%s\nmanifest=%s\n' "$output" "$output/MANIFEST.sha256"
}

beacon_verify() {
    local workspace="$1" output="$2" expected relative actual secret record path listing line
    local verified=0 inventory=0 previous="" selected="" schema="" application=""
    local LC_ALL=C
    local -A records=() metadata=()

    beacon_check_bundle_tree "$output" || return 1

    [[ -d "$output" ]] || {
        beacon_error "Bundle '$output' does not exist."
        return $?
    }
    [[ -f "$output/MANIFEST.sha256" && -r "$output/MANIFEST.sha256" ]] || {
        beacon_error "Bundle manifest is missing or unreadable."
        return $?
    }

    while IFS= read -r record || [[ -n "$record" ]]; do
        expected="${record%%$'\t'*}"
        relative="${record#*$'\t'}"
        if [[ ! "$expected" =~ ^[0-9a-f]{64}$ || "$record" != "$expected"$'\t'"$relative" ]]; then
            beacon_error "Malformed manifest record."; return 1
        fi
        case "$relative" in
            README.txt|files/config/app.env|files/logs/app.log|files/system/info.txt) ;;
            *) beacon_error "Unexpected manifest path."; return 1 ;;
        esac
        [[ -z "$previous" || "$relative" > "$previous" ]] || {
            beacon_error "Manifest records must be unique and canonically ordered."; return 1;
        }
        previous="$relative"
        beacon_check_path "$output" "$relative" || return 1
        [[ -f "$output/$relative" && -r "$output/$relative" ]] || {
            beacon_error "Manifest payload is missing or unreadable."; return 1;
        }
        beacon_sha256 "$output/$relative" actual || {
            beacon_error "Cannot read manifest payload."; return 1;
        }
        [[ "$actual" == "$expected" ]] || {
            beacon_error "Manifest checksum mismatch."; return 1;
        }
        records["$relative"]=1
        verified=$((verified + 1))
    done < "$output/MANIFEST.sha256"

    [[ "$verified" -ge 2 && -n "${records[README.txt]-}" ]] || {
        beacon_error "Manifest requires metadata and at least one payload."; return 1;
    }
    base_std_make_temp_file listing beacon-inventory || return 1
    find "$output" -type f -print0 > "$listing" || return 1
    while IFS= read -r -d '' path; do
        relative="${path#"$output"/}"
        [[ "$relative" == MANIFEST.sha256 ]] && continue
        [[ -n "${records[$relative]-}" ]] || {
            beacon_error "Bundle contains an unlisted payload."; return 1;
        }
        inventory=$((inventory + 1))
    done < "$listing"
    [[ "$inventory" -eq "$verified" ]] || {
        beacon_error "Bundle inventory differs from manifest."; return 1;
    }
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            application=*|schema_version=*|selected_files=*)
                [[ -z "${metadata[${line%%=*}]-}" ]] || {
                    beacon_error "Duplicate bundle metadata."; return 1;
                }
                metadata["${line%%=*}"]=1
                ;;
        esac
        case "$line" in
            application=*) application+="${line#*=}" ;;
            schema_version=*) schema+="${line#*=}" ;;
            selected_files=*) selected+="${line#*=}" ;;
        esac
    done < "$output/README.txt"
    [[ "$application" == beacon && "$schema" == 1 && "$selected" == "$((verified - 1))" ]] || {
        beacon_error "Bundle metadata schema or selected-file count is invalid."; return 1;
    }

    beacon_load_secret_values "$workspace" || return $?
    for secret in "${BEACON_UNIQUE_SECRET_VALUES[@]}"; do
        if beacon_bundle_contains_value "$output" "$secret"; then
            beacon_error "Bundle contains a configured sensitive value."
            return $?
        fi
    done

    printf 'verified=true\nfiles=%s\nbundle=%s\n' "$verified" "$output"
}

beacon_cleanup() {
    if [[ -n "$BEACON_ACTIVE_LIFECYCLE_LOG" ]] &&
        ((BASE_BASH_LIBS_APP_DRY_RUN == 0)); then
        printf 'phase=%s\n' "$1" >> "$BEACON_ACTIVE_LIFECYCLE_LOG" || return 1
    fi
    base_std_log_debug -l beacon.lifecycle "cleanup phase=$1 status=$2"
}

beacon_execute() {
    local command="${BASE_BASH_LIBS_CLI_RESULT_COMMAND:-}"
    local workspace output scenario lifecycle_log cli_value config_file user_config
    local -a config_args=()

    base_app_apply_standard_options beacon_policy || return $?
    if base_cli_result_get workspace cli_value 2>/dev/null; then
        base_app_config_set_cli beacon_policy workspace "$cli_value" || return $?
    fi
    if base_cli_result_get output cli_value 2>/dev/null; then
        base_app_config_set_cli beacon_policy output "$cli_value" || return $?
    fi
    if base_cli_result_get lifecycle_log cli_value 2>/dev/null; then
        base_app_config_set_cli beacon_policy lifecycle_log "$cli_value" || return $?
    fi
    if base_cli_result_get scenario cli_value 2>/dev/null; then
        base_app_config_set_cli beacon_policy scenario "$cli_value" || return $?
    fi
    base_cli_result_get config config_file 2>/dev/null && config_args+=(--project "$config_file")
    base_cli_result_get user-config user_config 2>/dev/null && config_args+=(--user "$user_config")
    base_app_config_load beacon_policy "${config_args[@]}" || return $?
    base_app_config_get beacon_policy workspace workspace || return $?
    base_app_config_get beacon_policy output output || return $?
    base_app_config_get beacon_policy scenario scenario || return $?
    base_app_config_get beacon_policy lifecycle_log lifecycle_log || return $?
    BEACON_ACTIVE_LIFECYCLE_LOG="$lifecycle_log"
    base_app_hook beacon_policy cleanup beacon_cleanup beacon_cleanup || return $?

    case "$command" in
        status) beacon_status "$workspace" ;;
        plan) beacon_plan "$workspace" "$output" ;;
        collect) beacon_collect "$workspace" "$output" "$scenario" ;;
        verify) beacon_verify "$workspace" "$output" ;;
        *)
            beacon_error "Unknown command '$command'."
            return $?
            ;;
    esac
}

beacon_dispatch() {
    base_app_run beacon_policy beacon_execute
}

main() {
    base_cli_run beacon -- "$@"
}
