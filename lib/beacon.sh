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

beacon_select_files() {
    local workspace="$1" relative
    local -a candidates=(
        config/app.env
        logs/app.log
        system/info.txt
    )

    BEACON_SELECTED_FILES=()
    for relative in "${candidates[@]}"; do
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
    local manifest readme

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
    [[ ! -e "$output" ]] || {
        beacon_error "Output '$output' already exists; choose an unused path."
        return $?
    }

    base_std_make_temp_dir stage beacon-support || return $?
    for relative in "${BEACON_SELECTED_FILES[@]}"; do
        target="$stage/files/$relative"
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
    base_std_run mv -- "$stage" "$output" || return $?
    base_std_unregister_cleanup_path "$stage" || return $?
    printf 'bundle=%s\nmanifest=%s\n' "$output" "$output/MANIFEST.sha256"
}

beacon_verify() {
    local workspace="$1" output="$2" expected relative actual secret
    local verified=0

    [[ -d "$output" ]] || {
        beacon_error "Bundle '$output' does not exist."
        return $?
    }
    [[ -f "$output/MANIFEST.sha256" ]] || {
        beacon_error "Bundle manifest is missing."
        return $?
    }

    while IFS=$'\t' read -r expected relative || [[ -n "$expected$relative" ]]; do
        [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
        [[ -n "$relative" && "$relative" != /* && "$relative" != *../* ]] || return 1
        [[ -f "$output/$relative" ]] || return 1
        beacon_sha256 "$output/$relative" actual || return $?
        [[ "$actual" == "$expected" ]] || return 1
        verified=$((verified + 1))
    done < "$output/MANIFEST.sha256"

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
