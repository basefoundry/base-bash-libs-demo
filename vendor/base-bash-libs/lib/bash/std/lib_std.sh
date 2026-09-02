# shellcheck shell=bash
#
# lib_std.sh - Foundation library for Bash scripts
#              Requires Bash 4.2 or higher.
#
# This library provides a standardized set of functions for common tasks,
# ensuring consistency and robustness across multiple scripts.
#
# Areas covered:
#     - PATH manipulation
#     - Logging (with levels and colors)
#     - Error handling and stack tracing
#     - Bash version check helpers
#     - Library importing
#     - Miscellaneous helpers
#
# Quick Reference
# --------------------------------------------------------------------------------------------------------------------
# Sourcing:
#   source "<repo>/lib/bash/std/lib_std.sh"
#
# Caller-visible metadata:
#   BASE_BASH_LIBS_VERSION
#                    Package version read from VERSION or the embedded release
#                    metadata carried with installed/copy-only artifacts.
#   BASE_BASH_LIBS_COMMIT
#                    Full source commit when the package came from a checkout;
#                    embedded release commit or unknown for copied artifacts.
#   BASE_BASH_LIBS_DIRTY_STATE
#                    clean, dirty, or unknown source-tree state.
#   BASE_BASH_LIBS_PROVENANCE
#                    checkout, release-artifact, source-archive, copy, or unknown.
#   BASE_BASH_LIBS_STDLIB_LOADED
#                    Set to 1 after lib_std.sh has been loaded successfully.
#
# Runtime globals such as BASE_BASH_LIBS_SCRIPT_ARGS and BASE_BASH_LIBS_SCRIPT_DIR are published only
# by base_init. Sourcing this file never consumes or rewrites "$@".
#
# Core helpers:
#   base_std_run [opts] cmd ...
#                                # Safe command runner with dry-run, timeout, retry & failure handling.
#   base_std_exit_if_error rc msg...      # Log + exit when rc != 0 (preserves original status).
#   base_std_fatal_error msg...           # Convenience wrapper: exit with last status or 1.
#   base_std_register_cleanup_hook fn # Run a cleanup function from the shared EXIT trap.
#   base_std_register_cleanup_path p  # Remove owned files/directories from EXIT cleanup.
#   base_std_register_cleanup_path --unsafe p
#                                # Explicitly opt out of path-identity proof.
#   base_std_unregister_cleanup_path p
#                                # Drop files/directories from the shared EXIT cleanup list.
#   base_std_make_temp_file var [pfx] # Create a temp file and store its path in var.
#   base_std_make_temp_dir var [pfx]  # Create a temp directory and store its path in var.
#   base_std_command_path var cmd     # Resolve an external command path without exiting.
#   base_std_function_exists fn       # Predicate for defined Bash functions.
#   base_std_assert_variable_name name    # Validate Bash variable-name arguments.
#   base_std_assert_associative_array map # Validate caller-declared associative arrays.
#   base_require_version min_version
#                                # Exit clearly if the loaded library is too old.
#   base_std_add_to_path [-n] [-p] dir    # Append/prepend unique PATH entries.
#   base_std_set_log_level [LEVEL]        # Adjust terminal verbosity (FATAL..VERBOSE).
#   base_std_set_log_category_level -l category LEVEL
#                                # Gate a category independently of its sinks.
#   base_std_log_is_enabled [-l category] LEVEL
#                                # Test whether any configured sink accepts a level.
#   base_std_log_info/debug/... msgs      # Structured logging (color in interactive shells).
#   base_std_safe_touch file [...]        # touch wrapper that returns on failure (same for base_std_safe_truncate).
#   assert_* utilities           # Validation helpers (base_std_assert_not_null / base_std_assert_integer / ...).
#
# Patterns:
#   base_std_run some_cmd             # exits on failure; BASE_BASH_LIBS_DRY_RUN=true/1/yes/on prints instead.
#   base_std_run --timeout 30 some_cmd
#                                # bounds the command attempt to 30 seconds.
#   base_std_run --max-attempts 3 --retry-delay 2 some_cmd
#                                # retries transient failures.
#   some_cmd || base_std_fatal_error ...  # preserves failing exit code before terminating.
#   base_std_add_to_path -p "/opt/tools"  # inject directories without duplicates.
#
# Notes:
#   - Call base_init <result_array> [--source <script>] [--] [argv...]
#     before using stateful helpers. It strips --debug-wrapper,
#     --verbose-wrapper, --utc-wrapper, and --color into the result array.
#   - --verbose-wrapper is deprecated compatibility surface; prefer --debug-wrapper.
#   - BASE_BASH_LIBS_BOOTSTRAP_SOURCE is accepted as a source-path fallback by the
#     explicit initializer, not consumed while this file is sourced.
#

################################################# INITIALIZATION #######################################################

__base_bash_libs_std_require_supported_bash__() {
    if [[ -z "${BASH_VERSION:-}" ]]; then
        printf '%s\n' "Error: This script requires Bash 4.2 or higher." >&2
        printf '%s\n' "Your shell is not Bash." >&2
        return 1
    fi
    if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 2))); then
        printf '%s\n' "Error: This script requires Bash 4.2 or higher." >&2
        printf '%s\n' "Your version ($BASH_VERSION) is not compatible." >&2
        return 1
    fi
}

# Runtime state remains passive, but loading an unsupported interpreter is a
# deterministic contract error rather than a partially-defined library.
__base_bash_libs_std_require_supported_bash__ || return 1 2> /dev/null || exit 1
unset -f __base_bash_libs_std_require_supported_bash__

__base_bash_libs_std_resolve_file_path__() {
    local source_path="${1-}" link_dir target link_depth=0

    [[ -n "$source_path" ]] || return 1
    [[ -e "$source_path" || -L "$source_path" ]] || return 1

    while [[ -L "$source_path" ]]; do
        ((link_depth += 1))
        ((link_depth <= 40)) || return 1
        link_dir="$(cd -P -- "$(dirname -- "$source_path")" 2> /dev/null && pwd -P)" || return 1
        target="$(readlink "$source_path")" || return 1
        if [[ "$target" == /* ]]; then
            source_path="$target"
        else
            source_path="$link_dir/$target"
        fi
    done

    link_dir="$(cd -P -- "$(dirname -- "$source_path")" 2> /dev/null && pwd -P)" || return 1
    printf '%s/%s\n' "$link_dir" "$(basename -- "$source_path")"
}

__base_bash_libs_std_read_metadata_value__() {
    local metadata_file="${1-}" requested_key="${2-}" metadata_key metadata_value

    [[ -r "$metadata_file" && -n "$requested_key" ]] || return 1
    while IFS='=' read -r metadata_key metadata_value; do
        [[ "$metadata_key" == "$requested_key" ]] || continue
        printf '%s' "$metadata_value"
        return 0
    done < "$metadata_file"
    return 1
}

__base_bash_libs_std_read_package_version__() {
    local source_path="${1-}" package_root version_file metadata_file version

    [[ -n "$source_path" ]] || return 1
    package_root="$(cd -- "$(dirname -- "$source_path")/../../.." &> /dev/null && pwd -P)" || return 1
    version_file="$package_root/VERSION"
    metadata_file="$package_root/lib/bash/base-bash-libs.release"

    if [[ -r "$version_file" ]]; then
        IFS= read -r version < "$version_file" || true
    else
        version="$(
            __base_bash_libs_std_read_metadata_value__ "$metadata_file" version ||
                printf '%s' ""
        )"
    fi
    [[ -n "$version" ]] || {
        printf '%s\n' "Error: base-bash-libs has no readable VERSION or embedded release metadata at '$package_root'." >&2
        return 1
    }
    printf '%s' "$version"
}

# A source guard is deliberately package-prefixed and readonly. It is the only
# source-time state other than immutable package metadata. Re-sourcing the same
# version is a no-op; attempting to mix versions fails before definitions are
# replaced.
if [[ -n "${BASE_BASH_LIBS_STD_SOURCE_GUARD+x}" ]]; then
    __base_bash_libs_std_requested_source_path__="$(__base_bash_libs_std_resolve_file_path__ "${BASH_SOURCE[0]}" 2> /dev/null || printf '%s' "${BASH_SOURCE[0]}")"
    __base_bash_libs_std_requested_source_version__="$(__base_bash_libs_std_read_package_version__ "$__base_bash_libs_std_requested_source_path__" 2> /dev/null || printf '%s' unknown)"
    if [[ "${BASE_BASH_LIBS_STD_SOURCE_VERSION-}" != "$__base_bash_libs_std_requested_source_version__" ||
        "${BASE_BASH_LIBS_STD_SOURCE_PATH-}" != "$__base_bash_libs_std_requested_source_path__" ]]; then
        if [[ -n "${BASE_BASH_LIBS_STD_SOURCE_PATH-}" &&
            "${BASE_BASH_LIBS_STD_SOURCE_VERSION%%.*}" != "${__base_bash_libs_std_requested_source_version__%%.*}" ]]; then
            printf '%s\n' "Error: mixed-major base-bash-libs module graph refused (loaded v${BASE_BASH_LIBS_STD_SOURCE_VERSION%%.*}, requested v${__base_bash_libs_std_requested_source_version__%%.*}). v1 inputs are not fallback-loaded by v2; migrate imports to the package-relative base_std_import contract and use one v2 package root." >&2
        else
            printf '%s\n' "Error: incompatible base-bash-libs stdlib versions or sources are already loaded (loaded ${BASE_BASH_LIBS_STD_SOURCE_VERSION:-unknown} from ${BASE_BASH_LIBS_STD_SOURCE_PATH:-unknown}, requested $__base_bash_libs_std_requested_source_version__ from $__base_bash_libs_std_requested_source_path__)." >&2
        fi
        unset __base_bash_libs_std_requested_source_path__ __base_bash_libs_std_requested_source_version__
        unset -f __base_bash_libs_std_read_package_version__
        unset -f __base_bash_libs_std_read_metadata_value__
        return 1 2> /dev/null || exit 1
    fi
    unset __base_bash_libs_std_requested_source_path__ __base_bash_libs_std_requested_source_version__
    unset -f __base_bash_libs_std_read_package_version__ __base_bash_libs_std_read_metadata_value__
    return 0
fi

if [[ -n "${BASE_BASH_LIBS_VERSION+x}" || -n "${BASE_BASH_LIBS_STDLIB_LOADED+x}" ||
    -n "${BASE_BASH_LIBS_COMMIT+x}" || -n "${BASE_BASH_LIBS_DIRTY_STATE+x}" ||
    -n "${BASE_BASH_LIBS_PROVENANCE+x}" ]]; then
    printf '%s\n' "Error: base-bash-libs metadata names are already owned by the caller; refusing to overwrite them." >&2
    return 1 2> /dev/null || exit 1
fi

BASE_BASH_LIBS_STD_SOURCE_PATH="$(__base_bash_libs_std_resolve_file_path__ "${BASH_SOURCE[0]}")" || {
    printf '%s\n' "Error: Unable to resolve base-bash-libs stdlib source path from '${BASH_SOURCE[0]}'." >&2
    return 1 2> /dev/null || exit 1
}
readonly BASE_BASH_LIBS_STD_SOURCE_PATH
BASE_BASH_LIBS_STD_ROOT="$(cd -- "$(dirname -- "$BASE_BASH_LIBS_STD_SOURCE_PATH")/../../.." &> /dev/null && pwd -P)" || {
    printf '%s\n' "Error: Unable to resolve base-bash-libs root from '$BASE_BASH_LIBS_STD_SOURCE_PATH'." >&2
    return 1 2> /dev/null || exit 1
}
readonly BASE_BASH_LIBS_STD_ROOT
readonly BASE_BASH_LIBS_MODULE_ROOT="$BASE_BASH_LIBS_STD_ROOT/lib/bash"
BASE_BASH_LIBS_VERSION="$(__base_bash_libs_std_read_package_version__ "$BASE_BASH_LIBS_STD_SOURCE_PATH")" || {
    return 1 2> /dev/null || exit 1
}
readonly BASE_BASH_LIBS_VERSION
readonly BASE_BASH_LIBS_STD_SOURCE_VERSION="$BASE_BASH_LIBS_VERSION"
readonly BASE_BASH_LIBS_STD_SOURCE_GUARD=1

__base_bash_libs_std_metadata_file__="$BASE_BASH_LIBS_MODULE_ROOT/base-bash-libs.release"
__base_bash_libs_std_embedded_commit__="$(__base_bash_libs_std_read_metadata_value__ "$__base_bash_libs_std_metadata_file__" commit 2> /dev/null || printf '%s' unknown)"
__base_bash_libs_std_embedded_dirty_state__="$(__base_bash_libs_std_read_metadata_value__ "$__base_bash_libs_std_metadata_file__" dirty_state 2> /dev/null || printf '%s' unknown)"
__base_bash_libs_std_embedded_provenance__="$(__base_bash_libs_std_read_metadata_value__ "$__base_bash_libs_std_metadata_file__" provenance 2> /dev/null || printf '%s' source-archive)"

BASE_BASH_LIBS_COMMIT="$__base_bash_libs_std_embedded_commit__"
BASE_BASH_LIBS_DIRTY_STATE="$__base_bash_libs_std_embedded_dirty_state__"
BASE_BASH_LIBS_PROVENANCE="$__base_bash_libs_std_embedded_provenance__"
if [[ -e "$BASE_BASH_LIBS_STD_ROOT/.git" ]] && command -v git > /dev/null 2>&1; then
    __base_bash_libs_std_git_commit__="$(git -C "$BASE_BASH_LIBS_STD_ROOT" rev-parse --verify HEAD 2> /dev/null || true)"
    if [[ "$__base_bash_libs_std_git_commit__" =~ ^[[:xdigit:]]{40}$ ]]; then
        BASE_BASH_LIBS_COMMIT="$__base_bash_libs_std_git_commit__"
        if git -C "$BASE_BASH_LIBS_STD_ROOT" diff --quiet -- . 2> /dev/null &&
            git -C "$BASE_BASH_LIBS_STD_ROOT" diff --cached --quiet -- . 2> /dev/null &&
            [[ -z "$(git -C "$BASE_BASH_LIBS_STD_ROOT" status --porcelain --untracked-files=all 2> /dev/null)" ]]; then
            BASE_BASH_LIBS_DIRTY_STATE=clean
        else
            BASE_BASH_LIBS_DIRTY_STATE=dirty
        fi
        BASE_BASH_LIBS_PROVENANCE=checkout
    fi
fi
readonly BASE_BASH_LIBS_COMMIT BASE_BASH_LIBS_DIRTY_STATE BASE_BASH_LIBS_PROVENANCE
# Used by companion libraries as a source-order guard. This marker means the
# definitions and immutable metadata are loaded; it does not imply runtime init.
# shellcheck disable=SC2034
readonly BASE_BASH_LIBS_STDLIB_LOADED=1
declare -gA __base_bash_libs_std_import_state=()
declare -ga __base_bash_libs_std_import_stack=()
__base_bash_libs_std_import_state["$BASE_BASH_LIBS_STD_SOURCE_PATH"]=loaded
unset __base_bash_libs_std_metadata_file__ __base_bash_libs_std_embedded_commit__ __base_bash_libs_std_embedded_dirty_state__ __base_bash_libs_std_embedded_provenance__ __base_bash_libs_std_git_commit__
unset -f __base_bash_libs_std_read_package_version__ __base_bash_libs_std_read_metadata_value__

__base_bash_libs_std_is_supported_version__() {
    local version="${1-}" version_re='^[0-9]+([.][0-9]+)*(-(alpha|beta|rc)[.][1-9][0-9]*)?$'
    [[ "$version" =~ $version_re ]]
}

__base_bash_libs_std_version_at_least__() {
    local actual_version="$1" minimum_version="$2"
    local actual_core minimum_core actual_prerelease minimum_prerelease
    local actual_phase minimum_phase actual_number minimum_number
    local actual_rank minimum_rank index max_parts actual_part minimum_part
    local -a actual_parts=() minimum_parts=()

    IFS=- read -r actual_core actual_prerelease <<< "$actual_version"
    IFS=- read -r minimum_core minimum_prerelease <<< "$minimum_version"

    IFS=. read -r -a actual_parts <<< "$actual_core"
    IFS=. read -r -a minimum_parts <<< "$minimum_core"

    max_parts="${#actual_parts[@]}"
    if ((${#minimum_parts[@]} > max_parts)); then
        max_parts="${#minimum_parts[@]}"
    fi

    for ((index = 0; index < max_parts; index++)); do
        actual_part="${actual_parts[$index]:-0}"
        minimum_part="${minimum_parts[$index]:-0}"
        actual_number=$((10#$actual_part))
        minimum_number=$((10#$minimum_part))

        if ((actual_number > minimum_number)); then
            return 0
        fi
        if ((actual_number < minimum_number)); then
            return 1
        fi
    done

    # A stable release is newer than a prerelease of the same core version.
    if [[ -z "$actual_prerelease" && -n "$minimum_prerelease" ]]; then
        return 0
    fi
    if [[ -n "$actual_prerelease" && -z "$minimum_prerelease" ]]; then
        return 1
    fi
    [[ -z "$actual_prerelease" && -z "$minimum_prerelease" ]] && return 0

    IFS=. read -r actual_phase actual_number <<< "$actual_prerelease"
    IFS=. read -r minimum_phase minimum_number <<< "$minimum_prerelease"
    case "$actual_phase" in
    alpha) actual_rank=0 ;;
    beta) actual_rank=1 ;;
    rc) actual_rank=2 ;;
    esac
    case "$minimum_phase" in
    alpha) minimum_rank=0 ;;
    beta) minimum_rank=1 ;;
    rc) minimum_rank=2 ;;
    esac
    if ((actual_rank != minimum_rank)); then
        ((actual_rank > minimum_rank))
        return
    fi
    actual_number=$((10#$actual_number))
    minimum_number=$((10#$minimum_number))
    ((actual_number >= minimum_number))
}

#
# base_require_version - Requires a minimum base-bash-libs version.
#
# Usage:
#   base_require_version 1.1.0
#
base_require_version() {
    local minimum_version="${1-}"

    if (($# != 1)); then
        base_std_log_error -l base_bash_libs.std \
            "base_require_version: expected exactly one minimum version."
        return 2
    fi

    if ! __base_bash_libs_std_is_supported_version__ "$minimum_version" ||
        ! __base_bash_libs_std_is_supported_version__ "$BASE_BASH_LIBS_VERSION"; then
        base_std_log_error -l base_bash_libs.std "base_require_version expects supported SemVer versions."
        return 2
    fi

    if ! __base_bash_libs_std_version_at_least__ "$BASE_BASH_LIBS_VERSION" "$minimum_version"; then
        base_std_log_error -l base_bash_libs.std \
            "base-bash-libs $minimum_version or newer is required; loaded version is $BASE_BASH_LIBS_VERSION."
        return 1
    fi

    return 0
}

############################################ BASH VERSION CHECKER #######################################################

#
# base_std_is_interactive - Checks if the current shell is interactive.
#
# An interactive shell is one where the user is typing commands directly.
# This is used to determine if we can safely prompt the user for input.
#
# Returns:
#   0 (true) if the shell is interactive.
#   1 (false) if the shell is not interactive (e.g., running in a cron job).
#
base_std_is_interactive() {
    [[ -t 0 ]]
}

#
# base_std_check_bash_version - Verifies the Bash version without prompting or installing anything.
#
# This function checks if the running Bash interpreter is version 4.2 or higher and returns
# non-zero when it is not. Base entrypoints should enforce the supported runtime before
# sourcing this library; this helper is intentionally passive so sourcing lib_std.sh never
# prompts, installs packages, or re-execs the caller.
#
# Note: This function is called before logging is initialized, so it uses `echo` to stderr.
#
base_std_check_bash_version() {
    local bash_major bash_minor test_version

    if [[ -n "${BASE_TEST_BASH_VERSION:-}" ]]; then
        test_version="$BASE_TEST_BASH_VERSION"
        if [[ "$test_version" == *.* ]]; then
            bash_major="${test_version%%.*}"
            bash_minor="${test_version#*.}"
        else
            bash_major="${test_version:0:1}"
            bash_minor="${test_version:1}"
        fi
    else
        bash_major="${BASH_VERSINFO[0]}"
        bash_minor="${BASH_VERSINFO[1]}"
    fi
    bash_minor="${bash_minor:-0}"

    if ((bash_major < 4 || (bash_major == 4 && bash_minor < 2))); then
        echo "Error: This script requires Bash 4.2 or higher." >&2
        echo "Your version ($BASH_VERSION) is not compatible." >&2
        return 1
    fi
}

###################################################### INIT ############################################################

__base_bash_libs_std_init_validate_result_array__() {
    local result_name="${1-}" declaration attributes nocasematch_enabled=0 attributes_ok=0

    [[ "$result_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
        printf '%s\n' "base_init: result name must be a valid Bash variable name." >&2
        return 1
    }
    [[ "$result_name" != __* ]] || {
        printf '%s\n' "base_init: result name '$result_name' uses the reserved internal namespace." >&2
        return 1
    }
    declaration="$(declare -p "$result_name" 2> /dev/null || true)"
    [[ -n "$declaration" ]] || {
        printf '%s\n' "base_init: result '$result_name' must be a caller-declared indexed array." >&2
        return 1
    }
    attributes="${declaration#declare -}"
    attributes="${attributes%% *}"
    if shopt -q nocasematch; then
        nocasematch_enabled=1
        shopt -u nocasematch
    fi
    if [[ "$attributes" == *a* &&
        "$attributes" != *A* &&
        "$attributes" != *r* ]]; then
        attributes_ok=1
    fi
    if ((nocasematch_enabled)); then
        shopt -s nocasematch
    fi
    ((attributes_ok)) || {
        printf '%s\n' "base_init: result '$result_name' must be a caller-declared indexed array." >&2
        return 1
    }
}

__base_bash_libs_std_init_publish_array__() {
    local result_name="$1" value
    shift
    eval "$result_name=()"
    # shellcheck disable=SC2034 # eval publishes each value into a caller array.
    for value; do
        eval "$result_name+=(\"\$value\")"
    done
}

__base_bash_libs_std_init_args_match__() {
    local index=0
    (($# == ${#BASE_BASH_LIBS_SCRIPT_ARGS[@]})) || return 1
    for index in "${!BASE_BASH_LIBS_SCRIPT_ARGS[@]}"; do
        [[ "${BASE_BASH_LIBS_SCRIPT_ARGS[$index]}" == "$1" ]] || return 1
        shift
    done
}

__base_bash_libs_std_initialize_runtime_state__() {
    local script_dir="$1"
    shift

    if [[ -n "${BASE_BASH_LIBS_STD_INITIALIZED+x}" ]]; then
        [[ "${BASE_BASH_LIBS_STD_INITIALIZED}" == 1 ]] || {
            printf '%s\n' "base_init: runtime state marker is owned by the caller." >&2
            return 1
        }
        return 0
    fi

    if [[ -n "${BASE_BASH_LIBS_STD_INIT_SOURCE+x}" || -n "${BASE_BASH_LIBS_SCRIPT_ARGS+x}" || -n "${BASE_BASH_LIBS_SCRIPT_DIR+x}" ]]; then
        printf '%s\n' "base_init: initialization names are already owned by the caller." >&2
        return 1
    fi

    __base_bash_libs_std_log_init__
    declare -g BASE_BASH_LIBS_STD_COLOR_ENABLED=0
    declare -ga __base_bash_libs_std_cleanup_hooks=()
    declare -ga __base_bash_libs_std_cleanup_paths=()
    declare -ga __base_bash_libs_std_cleanup_entries=()
    declare -gA __base_bash_libs_std_cleanup_path_fingerprints=()
    declare -g __base_bash_libs_std_cleanup_dispatcher_installed=0
    declare -g __base_bash_libs_std_cleanup_dispatcher_running=0
    declare -g __base_bash_libs_std_cleanup_dispatcher_finished=0
    declare -g __base_bash_libs_std_cleanup_pending_signal_status=0
    declare -g __base_bash_libs_std_cleanup_debug_guard_running=0
    declare -g __base_bash_libs_std_original_exit_trap=""
    declare -g __base_bash_libs_std_original_exit_trap_spec=""
    declare -g __base_bash_libs_std_cleanup_dispatcher_trap_spec=""
    declare -g __base_bash_libs_std_original_int_trap=""
    declare -g __base_bash_libs_std_original_int_trap_spec=""
    declare -g __base_bash_libs_std_cleanup_int_trap_spec="__not-installed__"
    declare -g __base_bash_libs_std_original_term_trap=""
    declare -g __base_bash_libs_std_original_term_trap_spec=""
    declare -g __base_bash_libs_std_cleanup_term_trap_spec="__not-installed__"
    declare -g __base_bash_libs_std_original_debug_trap=""
    declare -g __base_bash_libs_std_original_debug_trap_spec=""
    declare -g __base_bash_libs_std_cleanup_debug_trap_spec="__not-installed__"

    readonly BASE_BASH_LIBS_STD_INIT_SOURCE="$script_dir"
    declare -ga BASE_BASH_LIBS_SCRIPT_ARGS=("$@")
    readonly -a BASE_BASH_LIBS_SCRIPT_ARGS
    declare -g BASE_BASH_LIBS_SCRIPT_DIR="$script_dir"
    readonly BASE_BASH_LIBS_SCRIPT_DIR
    readonly BASE_BASH_LIBS_STD_INITIALIZED=1
}

#
# base_init - Explicitly initializes runtime state and filters wrapper
# flags into a caller-owned indexed array. Sourcing the library never invokes
# this function and never mutates positional parameters.
#
# Usage:
#   declare -a app_args=()
#   base_init app_args --source "$script" -- "$@"
#
base_init() {
    local result_name="${1-}" source_path="" script_dir="" arg
    local parse_config=1 color_requested=0 configure_runtime=0
    local -a input_args=() filtered_args=()

    (($# >= 1)) || {
        printf '%s\n' "base_init: expected a result array name." >&2
        return 1
    }
    __base_bash_libs_std_init_validate_result_array__ "$result_name" || return 1
    shift

    while (($#)); do
        if ((parse_config)) && [[ "$1" == "--source" ]]; then
            (($# >= 2)) || {
                printf '%s\n' "base_init: --source requires a script path." >&2
                return 1
            }
            source_path="$2"
            shift 2
            continue
        fi
        if ((parse_config)) && [[ "$1" == "--" ]]; then
            parse_config=0
            shift
            input_args+=("$@")
            break
        fi
        input_args+=("$1")
        shift
    done

    source_path="${source_path:-${BASE_BASH_LIBS_BOOTSTRAP_SOURCE:-${BASH_SOURCE[1]-}}}"
    if [[ -n "$source_path" ]]; then
        script_dir="$(cd -- "$(dirname -- "$source_path")" &> /dev/null && pwd -P)" || {
            printf '%s\n' "base_init: unable to resolve source directory from '$source_path'." >&2
            return 1
        }
    else
        script_dir="$(pwd -P)" || {
            printf '%s\n' "base_init: unable to resolve the current caller directory." >&2
            return 1
        }
    fi

    if [[ -n "${BASE_BASH_LIBS_STD_INITIALIZED+x}" ]]; then
        [[ "${BASE_BASH_LIBS_STD_INIT_SOURCE:-}" == "$script_dir" ]] || {
            printf '%s\n' "base_init: already initialized for '$BASE_BASH_LIBS_STD_INIT_SOURCE'; requested '$script_dir'." >&2
            return 1
        }
        __base_bash_libs_std_init_args_match__ "${input_args[@]+${input_args[@]}}" || {
            printf '%s\n' "base_init: repeated initialization received different argv; refusing to hide the mismatch." >&2
            return 1
        }
    else
        configure_runtime=1
        __base_bash_libs_std_initialize_runtime_state__ "$script_dir" "${input_args[@]+${input_args[@]}}" || return 1
    fi

    parse_config=1
    for arg in "${input_args[@]+${input_args[@]}}"; do
        if ((parse_config)) && [[ "$arg" == "--" ]]; then
            filtered_args+=("$arg")
            parse_config=0
            continue
        fi
        if ((parse_config)); then
            case "$arg" in
            --debug-wrapper)
                if ((configure_runtime)); then
                    base_std_set_log_level DEBUG
                    base_std_set_log_category_level -l base_bash_libs DEBUG
                    export BASE_BASH_LIBS_LOG_DEBUG=1
                fi
                ;;
            --verbose-wrapper)
                if ((configure_runtime)); then
                    base_std_set_log_level VERBOSE
                    base_std_set_log_category_level -l base_bash_libs VERBOSE
                    export BASE_BASH_LIBS_LOG_DEBUG=1
                fi
                ;;
            --utc-wrapper)
                if ((configure_runtime)); then
                    export BASE_BASH_LIBS_LOG_UTC=1
                fi
                ;;
            --color)
                color_requested=1
                ;;
            *)
                filtered_args+=("$arg")
                ;;
            esac
        else
            filtered_args+=("$arg")
        fi
    done

    if ((configure_runtime)); then
        BASE_BASH_LIBS_STD_COLOR_ENABLED="$color_requested"
        __base_bash_libs_std_init_colors__
        base_std_set_log_category_level -l base_bash_libs INFO
        # Re-apply explicit debug levels after the default category gate.
        for arg in "${input_args[@]+${input_args[@]}}"; do
            if [[ "$arg" == "--debug-wrapper" ]]; then
                base_std_set_log_category_level -l base_bash_libs DEBUG
            elif [[ "$arg" == "--verbose-wrapper" ]]; then
                base_std_set_log_category_level -l base_bash_libs VERBOSE
            fi
        done
    fi

    __base_bash_libs_std_init_publish_array__ "$result_name" "${filtered_args[@]+${filtered_args[@]}}"
    return 0
}

################################################# LIBRARY IMPORTER #####################################################

#
# base_std_import - Sources package-relative library files.
#
# Every supported consumer uses this loader. Paths are relative to the loaded
# package's `lib/bash` root, never to the caller's cwd or script directory. The
# loader validates the path, resolves symlinks, rejects package-root escapes,
# tracks loading state, and sources each module at most once. During source,
# top-level `declare` statements are promoted to globals so module authors do
# not need function-scope implementation knowledge; declarations in functions
# retain their normal Bash behavior after the module is loaded.
#
# Usage:
#   base_std_import str/lib_str.sh
#   base_std_import file/lib_file.sh git/lib_git.sh
#
base_std_import() {
    local module import_path canonical_path module_root source_status saved_declare component
    local -a components=()

    (($# > 0)) || {
        base_std_log_error -l base_bash_libs.std \
            "base_std_import: expected one or more package-relative module paths."
        return 2
    }

    module_root="$(cd -P -- "$BASE_BASH_LIBS_MODULE_ROOT" 2> /dev/null && pwd -P)" || {
        base_std_log_error -l base_bash_libs.std \
            "base_std_import: package module root '$BASE_BASH_LIBS_MODULE_ROOT' is unavailable."
        return 1
    }

    for module; do
        [[ -n "$module" && "$module" != /* && "$module" != *$'\n'* && "$module" != *$'\r'* ]] || {
            base_std_log_error -l base_bash_libs.std \
                "base_std_import: '$module' is not a package-relative module path."
            return 2
        }
        [[ "$module" == *.sh ]] || {
            base_std_log_error -l base_bash_libs.std \
                "base_std_import: module '$module' is not a shell library path."
            return 2
        }
        case "$module" in
        *'//' | /* | */ | ./* | */./* | . | .. | ../* | */.. | */../* | *[^A-Za-z0-9_./-]* | *.sh/*)
            base_std_log_error -l base_bash_libs.std \
                "base_std_import: refusing unsafe package-relative path '$module'."
            return 2
            ;;
        esac
        IFS=/ read -r -a components <<< "$module"
        ((${#components[@]} > 0)) || return 2
        for component in "${components[@]}"; do
            [[ "$component" != "" && "$component" != "." && "$component" != ".." ]] || {
                base_std_log_error -l base_bash_libs.std \
                    "base_std_import: refusing unsafe package-relative path '$module'."
                return 2
            }
        done

        import_path="$module_root/$module"
        [[ -f "$import_path" ]] || {
            base_std_log_error -l base_bash_libs.std \
                "base_std_import: module '$module' does not exist under '$module_root'."
            return 1
        }
        canonical_path="$(__base_bash_libs_std_resolve_file_path__ "$import_path" 2> /dev/null || true)"
        [[ -n "$canonical_path" ]] || {
            base_std_log_error -l base_bash_libs.std \
                "base_std_import: unable to resolve module '$module'."
            return 1
        }
        case "$canonical_path" in
        "$module_root"/*) ;;
        *)
            base_std_log_error -l base_bash_libs.std \
                "base_std_import: refusing module '$module' because its symlink resolves outside '$module_root'."
            return 2
            ;;
        esac

        case "${__base_bash_libs_std_import_state[$canonical_path]-}" in
        loaded)
            continue
            ;;
        loading)
            base_std_log_error -l base_bash_libs.std \
                "base_std_import: dependency cycle detected while loading '$module'."
            return 2
            ;;
        esac

        [[ "$canonical_path" == "$BASE_BASH_LIBS_STD_SOURCE_PATH" ||
            "${BASE_BASH_LIBS_STDLIB_LOADED:-}" == "1" ]] || {
            base_std_log_error -l base_bash_libs.std \
                "base_std_import: module '$module' requires the std library dependency."
            return 2
        }

        __base_bash_libs_std_import_state["$canonical_path"]=loading
        __base_bash_libs_std_import_stack+=("$canonical_path")

        # Bash scopes `declare` variables to this function when a file is
        # sourced from here. A short-lived builtin wrapper makes module-level
        # declarations global while leaving function bodies and caller state
        # untouched. Preserve an intentionally caller-defined declare function.
        # shellcheck disable=SC2316
        saved_declare="$(builtin declare -f declare 2> /dev/null || true)"
        function declare {
            case "${1-}" in
            -p | -F | -f)
                builtin declare "$@"
                ;;
            *)
                case "${1-}" in
                -g | --*) builtin declare "$@" ;;
                *) builtin declare -g "$@" ;;
                esac
                ;;
            esac
        }

        # shellcheck disable=SC1090
        if source "$canonical_path"; then
            source_status=0
        else
            source_status=$?
        fi

        unset -f declare
        if [[ -n "$saved_declare" ]]; then
            eval "$saved_declare"
        fi
        __base_bash_libs_std_import_stack=()

        if ((source_status != 0)); then
            unset '__base_bash_libs_std_import_state['"$canonical_path"']'
            base_std_log_error -l base_bash_libs.std \
                "base_std_import: module '$module' failed to load (status $source_status)."
            return "$source_status"
        fi
        __base_bash_libs_std_import_state["$canonical_path"]=loaded
    done
    return 0
}

################################################# PATH MANIPULATION ####################################################

#
# base_std_add_to_path - Adds one or more directories to the system PATH.
#
# This function safely adds directories to the PATH, avoiding duplicates.
#
# Usage:
#   base_std_add_to_path [options] /path/to/dir1 /path/to/dir2 ...
#
# Options:
#   -p : Prepend the directory to the PATH instead of appending.
#   -n : Do not check if the directory exists before adding it.
#
base_std_add_to_path() {
    local dir path_dir prepend=0 opt strict=1 index in_path directory_count
    local -a path_dirs directories=()
    local OPTIND=1
    while getopts np opt; do
        case "$opt" in
        n) strict=0 ;;  # don't care if directory exists or not before adding it to PATH
        p) prepend=1 ;; # prepend the directory to PATH instead of appending
        *)
            base_std_log_error -l base_bash_libs.std "base_std_add_to_path: invalid option '$opt'"
            return 1
            ;;
        esac
    done

    shift $((OPTIND - 1))

    directories=("$@")
    directory_count=$#
    if ((prepend)); then
        for ((index = directory_count - 1; index >= 0; index--)); do
            dir="${directories[index]}"
            ((strict)) && [[ ! -d $dir ]] && continue
            in_path=0
            IFS=: read -ra path_dirs <<< "$PATH"
            for path_dir in "${path_dirs[@]+"${path_dirs[@]}"}"; do
                if [[ "$path_dir" == "$dir" ]]; then
                    in_path=1
                    break
                fi
            done
            if ((!in_path)); then
                PATH="$dir:$PATH"
            fi
        done
    else
        for dir in "${directories[@]+"${directories[@]}"}"; do
            in_path=0
            ((strict)) && [[ ! -d $dir ]] && continue
            IFS=: read -ra path_dirs <<< "$PATH"
            for path_dir in "${path_dirs[@]+"${path_dirs[@]}"}"; do
                if [[ "$path_dir" == "$dir" ]]; then
                    in_path=1
                    break
                fi
            done
            if ((!in_path)); then
                PATH="$PATH:$dir"
            fi
        done
    fi

    # It's good practice to de-duplicate the path after adding to it
    base_std_dedupe_path
    return 0
}

#
# base_std_dedupe_path - Removes duplicate entries from the PATH variable.
#
base_std_dedupe_path() {
    local -A seen
    local IFS=':' new_path dir
    for dir in $PATH; do
        if [[ -n "$dir" && -z "${seen[$dir]-}" ]]; then
            new_path="${new_path:+$new_path:}$dir"
            seen["$dir"]=1
        fi
    done
    PATH="$new_path"
}

#
# base_std_print_path - Prints each directory in the PATH on a new line.
#
base_std_print_path() {
    local IFS=':' dirs dir
    IFS=: read -ra dirs <<< "$PATH"
    for dir in "${dirs[@]+"${dirs[@]}"}"; do printf '%s\n' "$dir"; done
}

#################################################### LOGGING ###########################################################

#
# __base_bash_libs_std_log_init__ - Initializes the logging system.
#
# Sets up colors for interactive terminals and defines the log level hierarchy.
# This is called by base_init.
#
__base_bash_libs_std_log_init__() {
    # Map log level strings (FATAL, ERROR, etc.) to numeric values.
    # Note the '-g' option passed to declare is essential for global scope.
    unset BASE_BASH_LIBS_STD_LOG_LEVELS BASE_BASH_LIBS_STD_LOGGER_LEVELS BASE_BASH_LIBS_STD_LOG_CATEGORY_LEVELS BASE_BASH_LIBS_STD_LOG_FAILED_SINKS
    declare -gA BASE_BASH_LIBS_STD_LOG_LEVELS BASE_BASH_LIBS_STD_LOGGER_LEVELS BASE_BASH_LIBS_STD_LOG_CATEGORY_LEVELS BASE_BASH_LIBS_STD_LOG_FAILED_SINKS
    BASE_BASH_LIBS_STD_LOG_FAILED_SINKS=()
    # VERBOSE is deprecated compatibility surface; new callers should use DEBUG.
    BASE_BASH_LIBS_STD_LOG_LEVELS=([FATAL]=0 [ERROR]=1 [WARN]=2 [INFO]=3 [DEBUG]=4 [VERBOSE]=5)

    # Terminal output defaults to INFO. Category filtering is a separate,
    # permissive gate so existing callers retain their current sink behavior.
    BASE_BASH_LIBS_STD_LOGGER_LEVELS["default"]=3
    BASE_BASH_LIBS_STD_LOG_CATEGORY_LEVELS["default"]=5
}

#
# __base_bash_libs_std_join_message__ - Join message fragments with a stable single-space separator.
#
__base_bash_libs_std_join_message__() {
    local __base_bash_libs_std_join_message_result="" __base_bash_libs_std_join_message_fragment __base_bash_libs_std_join_message_separator=""

    for __base_bash_libs_std_join_message_fragment in "$@"; do
        __base_bash_libs_std_join_message_result+="${__base_bash_libs_std_join_message_separator}${__base_bash_libs_std_join_message_fragment}"
        __base_bash_libs_std_join_message_separator=" "
    done
    printf '%s' "$__base_bash_libs_std_join_message_result"
}

#
# __base_bash_libs_std_log_timestamp__ - Store the current log timestamp in a named variable.
#
__base_bash_libs_std_log_timestamp__() {
    local __base_bash_libs_std_log_timestamp_result_name="$1"

    if [[ "${BASE_BASH_LIBS_LOG_UTC:-}" == 1 ]]; then
        TZ=UTC0 printf -v "$__base_bash_libs_std_log_timestamp_result_name" '%(%Y-%m-%d %H:%M:%S)T UTC' -1
    else
        printf -v "$__base_bash_libs_std_log_timestamp_result_name" '%(%Y-%m-%d %H:%M:%S %z)T' -1
    fi
}

#
# __base_bash_libs_std_log_source_location__ - Store the first non-stdlib caller location.
#
__base_bash_libs_std_log_source_location__() {
    local __base_bash_libs_std_log_source_result_name="$1"
    local __base_bash_libs_std_log_source_fallback_path="${2:-}" __base_bash_libs_std_log_source_fallback_line="${3:-0}"
    local __base_bash_libs_std_log_source_path="" __base_bash_libs_std_log_source_line=""
    local __base_bash_libs_std_log_source_frame=1 __base_bash_libs_std_log_source_max_frames=20
    local __base_bash_libs_std_log_source_caller_info __base_bash_libs_std_log_source_caller_rest
    local __base_bash_libs_std_log_source_caller_line __base_bash_libs_std_log_source_caller_file

    while ((__base_bash_libs_std_log_source_frame <= __base_bash_libs_std_log_source_max_frames)) &&
        __base_bash_libs_std_log_source_caller_info=$(caller "$__base_bash_libs_std_log_source_frame"); do
        __base_bash_libs_std_log_source_caller_line="${__base_bash_libs_std_log_source_caller_info%% *}"
        __base_bash_libs_std_log_source_caller_rest="${__base_bash_libs_std_log_source_caller_info#* }"
        __base_bash_libs_std_log_source_caller_file="${__base_bash_libs_std_log_source_caller_rest#* }"
        if [[ -n "$__base_bash_libs_std_log_source_caller_file" &&
            "$__base_bash_libs_std_log_source_caller_file" != "$BASE_BASH_LIBS_STD_SOURCE_PATH" ]]; then
            __base_bash_libs_std_log_source_path="$__base_bash_libs_std_log_source_caller_file"
            __base_bash_libs_std_log_source_line="$__base_bash_libs_std_log_source_caller_line"
            break
        fi
        ((__base_bash_libs_std_log_source_frame++))
    done

    if [[ -z "$__base_bash_libs_std_log_source_path" ]]; then
        __base_bash_libs_std_log_source_path="${__base_bash_libs_std_log_source_fallback_path:-${BASH_SOURCE[2]:-${BASH_SOURCE[1]:-${BASH_SOURCE[0]:-unknown}}}}"
        __base_bash_libs_std_log_source_line="${__base_bash_libs_std_log_source_fallback_line:-${BASH_LINENO[1]:-${BASH_LINENO[0]:-0}}}"
    fi

    __base_bash_libs_std_log_source_path="${__base_bash_libs_std_log_source_path#"$BASE_BASH_LIBS_SCRIPT_DIR"/}"
    __base_bash_libs_std_log_source_path="${__base_bash_libs_std_log_source_path#./}"
    printf -v "$__base_bash_libs_std_log_source_result_name" '%s:%s' "$__base_bash_libs_std_log_source_path" "$__base_bash_libs_std_log_source_line"
}

#
# __base_bash_libs_std_log_primary_sink_is_usable__ - Check the primary sink without modifying it.
#
__base_bash_libs_std_log_primary_sink_is_usable__() {
    local __base_bash_libs_std_log_primary_usable_path="${1-}" __base_bash_libs_std_log_primary_usable_parent_dir

    [[ -n "$__base_bash_libs_std_log_primary_usable_path" && "$__base_bash_libs_std_log_primary_usable_path" != */ ]] || return 1
    [[ -z "${BASE_BASH_LIBS_STD_LOG_FAILED_SINKS[$__base_bash_libs_std_log_primary_usable_path]+set}" ]] || return 1
    [[ ! -L "$__base_bash_libs_std_log_primary_usable_path" ]] || return 1

    if [[ -e "$__base_bash_libs_std_log_primary_usable_path" ]]; then
        if [[ -f "$__base_bash_libs_std_log_primary_usable_path" && -O "$__base_bash_libs_std_log_primary_usable_path" &&
            -w "$__base_bash_libs_std_log_primary_usable_path" ]]; then
            return 0
        fi
        return 1
    fi

    if [[ "$__base_bash_libs_std_log_primary_usable_path" == */* ]]; then
        __base_bash_libs_std_log_primary_usable_parent_dir="${__base_bash_libs_std_log_primary_usable_path%/*}"
        [[ -n "$__base_bash_libs_std_log_primary_usable_parent_dir" ]] || __base_bash_libs_std_log_primary_usable_parent_dir=/
    else
        __base_bash_libs_std_log_primary_usable_parent_dir=.
    fi

    [[ -d "$__base_bash_libs_std_log_primary_usable_parent_dir" && -w "$__base_bash_libs_std_log_primary_usable_parent_dir" &&
        -x "$__base_bash_libs_std_log_primary_usable_parent_dir" ]]
}

#
# __base_bash_libs_std_log_primary_sink_prepare__ - Create or privately harden a usable sink.
#
__base_bash_libs_std_log_primary_sink_prepare__() {
    local __base_bash_libs_std_log_primary_prepare_path="$1" __base_bash_libs_std_log_primary_prepare_chmod_path

    __base_bash_libs_std_log_primary_sink_is_usable__ "$__base_bash_libs_std_log_primary_prepare_path" || return 1

    if [[ ! -e "$__base_bash_libs_std_log_primary_prepare_path" ]]; then
        # noclobber avoids truncating a target that appears after the
        # non-mutating eligibility check.
        if ! (
            umask 077
            set -o noclobber
            : > "$__base_bash_libs_std_log_primary_prepare_path"
        ) 2> /dev/null; then
            [[ -e "$__base_bash_libs_std_log_primary_prepare_path" && ! -L "$__base_bash_libs_std_log_primary_prepare_path" ]] || return 1
        fi
    fi

    [[ -f "$__base_bash_libs_std_log_primary_prepare_path" && ! -L "$__base_bash_libs_std_log_primary_prepare_path" &&
        -O "$__base_bash_libs_std_log_primary_prepare_path" && -w "$__base_bash_libs_std_log_primary_prepare_path" ]] || return 1

    # macOS chmod does not accept "--"; prefix a bare option-like path instead.
    __base_bash_libs_std_log_primary_prepare_chmod_path="$__base_bash_libs_std_log_primary_prepare_path"
    [[ "$__base_bash_libs_std_log_primary_prepare_chmod_path" == -* ]] &&
        __base_bash_libs_std_log_primary_prepare_chmod_path="./$__base_bash_libs_std_log_primary_prepare_chmod_path"
    command chmod 600 "$__base_bash_libs_std_log_primary_prepare_chmod_path" 2> /dev/null || return 1

    [[ -f "$__base_bash_libs_std_log_primary_prepare_path" && ! -L "$__base_bash_libs_std_log_primary_prepare_path" &&
        -O "$__base_bash_libs_std_log_primary_prepare_path" && -w "$__base_bash_libs_std_log_primary_prepare_path" ]]
}

#
# __base_bash_libs_std_log_primary_sink_append__ - Append one record or file payload.
#
__base_bash_libs_std_log_primary_sink_append__() {
    local __base_bash_libs_std_log_primary_append_kind="${1-}" __base_bash_libs_std_log_primary_append_payload="${2-}"
    local __base_bash_libs_std_log_primary_append_path="${BASE_BASH_LIBS_PRIMARY_LOG:-}"

    __base_bash_libs_std_log_primary_sink_is_usable__ "$__base_bash_libs_std_log_primary_append_path" || return 1

    (
        umask 077
        __base_bash_libs_std_log_primary_sink_prepare__ "$__base_bash_libs_std_log_primary_append_path" || exit 1

        case "$__base_bash_libs_std_log_primary_append_kind" in
        record)
            printf '%s\n' "$__base_bash_libs_std_log_primary_append_payload"
            ;;
        file)
            command cat -- "$__base_bash_libs_std_log_primary_append_payload" || exit 1
            printf '\n'
            ;;
        *)
            exit 1
            ;;
        esac >> "$__base_bash_libs_std_log_primary_append_path"
    ) 2> /dev/null
}

#
# __base_bash_libs_std_log_primary_sink_write__ - Keep sink failures best-effort and disable them.
#
__base_bash_libs_std_log_primary_sink_write__() {
    local __base_bash_libs_std_log_primary_write_kind="$1" __base_bash_libs_std_log_primary_write_payload="$2"
    local __base_bash_libs_std_log_primary_write_path="${BASE_BASH_LIBS_PRIMARY_LOG:-}"

    if ! __base_bash_libs_std_log_primary_sink_append__ "$__base_bash_libs_std_log_primary_write_kind" "$__base_bash_libs_std_log_primary_write_payload"; then
        BASE_BASH_LIBS_STD_LOG_FAILED_SINKS["$__base_bash_libs_std_log_primary_write_path"]=1
    fi
    return 0
}

#
# __base_bash_libs_std_print_log_record__ - Compose and write a structured log record.
#
__base_bash_libs_std_print_log_record__() {
    local __base_bash_libs_std_log_record_color="$1" __base_bash_libs_std_log_record_level="$2" __base_bash_libs_std_log_record_source="$3"
    local __base_bash_libs_std_log_record_terminal_enabled="${4:-1}" __base_bash_libs_std_log_record_persist_enabled="${5:-0}"
    shift 5
    local __base_bash_libs_std_log_record_message __base_bash_libs_std_log_record_timestamp __base_bash_libs_std_log_record_line

    __base_bash_libs_std_log_record_message="$(__base_bash_libs_std_join_message__ "$@")"
    __base_bash_libs_std_log_timestamp__ __base_bash_libs_std_log_record_timestamp
    printf -v __base_bash_libs_std_log_record_line '%s %-7s %s %s' \
        "$__base_bash_libs_std_log_record_timestamp" "$__base_bash_libs_std_log_record_level" "$__base_bash_libs_std_log_record_source" \
        "$__base_bash_libs_std_log_record_message"
    if ((__base_bash_libs_std_log_record_terminal_enabled)); then
        printf '%b%s%b\n' "$__base_bash_libs_std_log_record_color" "$__base_bash_libs_std_log_record_line" "$BASE_BASH_LIBS_STD_COLOR_OFF" >&2
    fi
    if ((__base_bash_libs_std_log_record_persist_enabled)); then
        __base_bash_libs_std_log_primary_sink_write__ record "$__base_bash_libs_std_log_record_line"
    fi
}

#
# __base_bash_libs_std_init_colors__ - Initialize colors used for logging
# This is called from base_init.
#
__base_bash_libs_std_init_colors__() {
    # If --color was not passed, NO_COLOR is set, or the log stream is not a terminal, disable colors.
    if [[ "$BASE_BASH_LIBS_STD_COLOR_ENABLED" != 1 || -n "${NO_COLOR+x}" || ! -t 2 ]]; then
        BASE_BASH_LIBS_STD_COLOR_BOLD=""
        BASE_BASH_LIBS_STD_COLOR_RED=""
        BASE_BASH_LIBS_STD_COLOR_GREEN=""
        BASE_BASH_LIBS_STD_COLOR_YELLOW=""
        BASE_BASH_LIBS_STD_COLOR_BLUE=""
        BASE_BASH_LIBS_STD_COLOR_OFF=""
    else
        # colors for logging in interactive mode
        BASE_BASH_LIBS_STD_COLOR_BOLD="\033[1m"
        BASE_BASH_LIBS_STD_COLOR_RED="\033[0;31m"
        BASE_BASH_LIBS_STD_COLOR_GREEN="\033[0;32m"
        BASE_BASH_LIBS_STD_COLOR_YELLOW="\033[0;33m"
        BASE_BASH_LIBS_STD_COLOR_BLUE="\033[0;36m"
        BASE_BASH_LIBS_STD_COLOR_OFF="\033[0m"
    fi
    readonly BASE_BASH_LIBS_STD_COLOR_BOLD BASE_BASH_LIBS_STD_COLOR_RED BASE_BASH_LIBS_STD_COLOR_GREEN BASE_BASH_LIBS_STD_COLOR_YELLOW BASE_BASH_LIBS_STD_COLOR_BLUE BASE_BASH_LIBS_STD_COLOR_OFF
}

#
# base_std_set_log_level - Sets the logging verbosity for a given logger.
#
# Usage:
#   base_std_set_log_level [level]
#   base_std_set_log_level -l [logger_name] [level]
#
# Arguments:
#   level: One of FATAL, ERROR, WARN, INFO, DEBUG, VERBOSE. Default is INFO.
#   -l logger_name: (Optional) Specify a named logger. Default is 'default'.
# Invalid levels return 1 and leave the existing logger level unchanged.
#
base_std_set_log_level() {
    local __base_bash_libs_std_set_log_logger=default __base_bash_libs_std_set_log_level __base_bash_libs_std_set_log_level_value
    local __base_bash_libs_std_set_log_source_location
    if [[ "${1-}" == "-l" ]]; then
        if [[ -z "${2-}" ]]; then
            __base_bash_libs_std_log_source_location__ __base_bash_libs_std_set_log_source_location \
                "${BASH_SOURCE[1]:-${0:-unknown}}" "${BASH_LINENO[0]:-0}"
            printf '%(%Y-%m-%d:%H:%M:%S)T %-7s %s\n' -1 WARN \
                "$__base_bash_libs_std_set_log_source_location Option '-l' needs an argument" >&2
            return 1
        fi
        __base_bash_libs_std_set_log_logger=$2
        shift 2 2> /dev/null
    fi
    __base_bash_libs_std_set_log_level="${1:-INFO}"
    if [[ -z "$__base_bash_libs_std_set_log_logger" ]]; then
        __base_bash_libs_std_log_source_location__ __base_bash_libs_std_set_log_source_location \
            "${BASH_SOURCE[1]:-${0:-unknown}}" "${BASH_LINENO[0]:-0}"
        printf '%(%Y-%m-%d:%H:%M:%S)T %-7s %s\n' -1 WARN \
            "$__base_bash_libs_std_set_log_source_location Option '-l' needs an argument" >&2
        return 1
    fi

    if [[ -n "${BASE_BASH_LIBS_STD_LOG_LEVELS[$__base_bash_libs_std_set_log_level]+set}" ]]; then
        __base_bash_libs_std_set_log_level_value="${BASE_BASH_LIBS_STD_LOG_LEVELS[$__base_bash_libs_std_set_log_level]}"
        BASE_BASH_LIBS_STD_LOGGER_LEVELS[$__base_bash_libs_std_set_log_logger]=$__base_bash_libs_std_set_log_level_value
        return 0
    fi

    __base_bash_libs_std_log_source_location__ __base_bash_libs_std_set_log_source_location \
        "${BASH_SOURCE[1]:-${0:-unknown}}" "${BASH_LINENO[0]:-0}"
    printf '%(%Y-%m-%d:%H:%M:%S)T %-7s %s\n' -1 WARN \
        "$__base_bash_libs_std_set_log_source_location Unknown log level '$__base_bash_libs_std_set_log_level' for logger '$__base_bash_libs_std_set_log_logger'" >&2
    return 1
}

#
# base_std_set_log_category_level - Sets the gate for a hierarchical log category.
#
# Usage:
#   base_std_set_log_category_level -l [category] [level]
#
# Categories inherit by dotted parent name. For example, base.git.fetch first
# checks base.git.fetch, then base.git, then base, and finally default.
# Invalid arguments return 1 without changing the existing category level.
#
base_std_set_log_category_level() {
    local __base_bash_libs_std_set_category_name __base_bash_libs_std_set_category_level __base_bash_libs_std_set_category_level_value
    local __base_bash_libs_std_set_category_source_location

    if [[ "$#" -ne 3 || "${1-}" != "-l" || -z "${2-}" || -z "${3-}" ]]; then
        __base_bash_libs_std_log_source_location__ __base_bash_libs_std_set_category_source_location \
            "${BASH_SOURCE[1]:-${0:-unknown}}" "${BASH_LINENO[0]:-0}"
        printf '%(%Y-%m-%d:%H:%M:%S)T %-7s %s\n' -1 WARN \
            "$__base_bash_libs_std_set_category_source_location Usage: base_std_set_log_category_level -l <category> <level>" >&2
        return 1
    fi

    __base_bash_libs_std_set_category_name=$2
    __base_bash_libs_std_set_category_level=$3
    if [[ -n "${BASE_BASH_LIBS_STD_LOG_LEVELS[$__base_bash_libs_std_set_category_level]+set}" ]]; then
        __base_bash_libs_std_set_category_level_value="${BASE_BASH_LIBS_STD_LOG_LEVELS[$__base_bash_libs_std_set_category_level]}"
        BASE_BASH_LIBS_STD_LOG_CATEGORY_LEVELS[$__base_bash_libs_std_set_category_name]=$__base_bash_libs_std_set_category_level_value
        return 0
    fi

    __base_bash_libs_std_log_source_location__ __base_bash_libs_std_set_category_source_location \
        "${BASH_SOURCE[1]:-${0:-unknown}}" "${BASH_LINENO[0]:-0}"
    printf '%(%Y-%m-%d:%H:%M:%S)T %-7s %s\n' -1 WARN \
        "$__base_bash_libs_std_set_category_source_location Unknown log level '$__base_bash_libs_std_set_category_level' for category '$__base_bash_libs_std_set_category_name'" >&2
    return 1
}

#
# __base_bash_libs_std_resolve_log_category_level__ - Resolve a category through its dotted parents.
#
__base_bash_libs_std_resolve_log_category_level__() {
    local __base_bash_libs_std_log_category_result_name="$1" __base_bash_libs_std_log_category_name="${2:-default}"
    local __base_bash_libs_std_log_category_candidate

    __base_bash_libs_std_log_category_candidate=$__base_bash_libs_std_log_category_name
    while [[ -n "$__base_bash_libs_std_log_category_candidate" ]]; do
        if [[ -n "${BASE_BASH_LIBS_STD_LOG_CATEGORY_LEVELS[$__base_bash_libs_std_log_category_candidate]+set}" ]]; then
            printf -v "$__base_bash_libs_std_log_category_result_name" '%s' \
                "${BASE_BASH_LIBS_STD_LOG_CATEGORY_LEVELS[$__base_bash_libs_std_log_category_candidate]}"
            return 0
        fi
        [[ "$__base_bash_libs_std_log_category_candidate" == *.* ]] || break
        __base_bash_libs_std_log_category_candidate="${__base_bash_libs_std_log_category_candidate%.*}"
    done

    printf -v "$__base_bash_libs_std_log_category_result_name" '%s' "${BASE_BASH_LIBS_STD_LOG_CATEGORY_LEVELS[default]}"
}

#
# __base_bash_libs_std_log_sink_state__ - Store terminal and persistent-sink decisions.
#
__base_bash_libs_std_log_sink_state__() {
    local __base_bash_libs_std_log_sink_category="$1" __base_bash_libs_std_log_sink_level="$2"
    local __base_bash_libs_std_log_sink_terminal_result="$3" __base_bash_libs_std_log_sink_persist_result="$4"
    local __base_bash_libs_std_log_sink_event_level __base_bash_libs_std_log_sink_category_level __base_bash_libs_std_log_sink_terminal_level
    local __base_bash_libs_std_log_sink_terminal_state=0 __base_bash_libs_std_log_sink_persist_state=0

    [[ -n "${BASE_BASH_LIBS_STD_LOG_LEVELS[$__base_bash_libs_std_log_sink_level]+set}" ]] || return 1
    __base_bash_libs_std_log_sink_event_level="${BASE_BASH_LIBS_STD_LOG_LEVELS[$__base_bash_libs_std_log_sink_level]}"
    __base_bash_libs_std_resolve_log_category_level__ __base_bash_libs_std_log_sink_category_level "$__base_bash_libs_std_log_sink_category"

    if ((__base_bash_libs_std_log_sink_category_level >= __base_bash_libs_std_log_sink_event_level)); then
        __base_bash_libs_std_log_sink_terminal_level="${BASE_BASH_LIBS_STD_LOGGER_LEVELS[$__base_bash_libs_std_log_sink_category]:-${BASE_BASH_LIBS_STD_LOGGER_LEVELS[default]}}"
        ((__base_bash_libs_std_log_sink_terminal_level >= __base_bash_libs_std_log_sink_event_level)) && __base_bash_libs_std_log_sink_terminal_state=1
        if ((__base_bash_libs_std_log_sink_event_level <= BASE_BASH_LIBS_STD_LOG_LEVELS[DEBUG])) &&
            __base_bash_libs_std_log_primary_sink_is_usable__ "${BASE_BASH_LIBS_PRIMARY_LOG:-}"; then
            __base_bash_libs_std_log_sink_persist_state=1
        fi
    fi

    printf -v "$__base_bash_libs_std_log_sink_terminal_result" '%s' "$__base_bash_libs_std_log_sink_terminal_state"
    printf -v "$__base_bash_libs_std_log_sink_persist_result" '%s' "$__base_bash_libs_std_log_sink_persist_state"
}

#
# base_std_log_is_enabled - Return success when any configured sink accepts a level.
#
# Usage:
#   base_std_log_is_enabled [-l category] level
#
base_std_log_is_enabled() {
    local __base_bash_libs_std_log_enabled_category=default __base_bash_libs_std_log_enabled_level
    local __base_bash_libs_std_log_enabled_terminal __base_bash_libs_std_log_enabled_persist __base_bash_libs_std_log_enabled_source_location

    if [[ "${1-}" == "-l" ]]; then
        if [[ -z "${2-}" ]]; then
            __base_bash_libs_std_log_source_location__ __base_bash_libs_std_log_enabled_source_location \
                "${BASH_SOURCE[1]:-${0:-unknown}}" "${BASH_LINENO[0]:-0}"
            printf '%(%Y-%m-%d:%H:%M:%S)T %-7s %s\n' -1 WARN \
                "$__base_bash_libs_std_log_enabled_source_location Option '-l' needs an argument" >&2
            return 1
        fi
        __base_bash_libs_std_log_enabled_category=$2
        shift 2
    fi
    if [[ "$#" -ne 1 || -z "${1-}" ]]; then
        __base_bash_libs_std_log_source_location__ __base_bash_libs_std_log_enabled_source_location \
            "${BASH_SOURCE[1]:-${0:-unknown}}" "${BASH_LINENO[0]:-0}"
        printf '%(%Y-%m-%d:%H:%M:%S)T %-7s %s\n' -1 WARN \
            "$__base_bash_libs_std_log_enabled_source_location Usage: base_std_log_is_enabled [-l <category>] <level>" >&2
        return 1
    fi
    __base_bash_libs_std_log_enabled_level=$1
    if [[ -z "${BASE_BASH_LIBS_STD_LOG_LEVELS[$__base_bash_libs_std_log_enabled_level]+set}" ]]; then
        __base_bash_libs_std_log_source_location__ __base_bash_libs_std_log_enabled_source_location \
            "${BASH_SOURCE[1]:-${0:-unknown}}" "${BASH_LINENO[0]:-0}"
        printf '%(%Y-%m-%d:%H:%M:%S)T %-7s %s\n' -1 WARN \
            "$__base_bash_libs_std_log_enabled_source_location Unknown log level '$__base_bash_libs_std_log_enabled_level' for category '$__base_bash_libs_std_log_enabled_category'" >&2
        return 1
    fi

    __base_bash_libs_std_log_sink_state__ "$__base_bash_libs_std_log_enabled_category" "$__base_bash_libs_std_log_enabled_level" \
        __base_bash_libs_std_log_enabled_terminal __base_bash_libs_std_log_enabled_persist || return 1
    ((__base_bash_libs_std_log_enabled_terminal || __base_bash_libs_std_log_enabled_persist))
}

#
# __base_bash_libs_std_print_log__ - Core and private log printing logic.
#
# This is the internal engine for the logging functions. It formats the log
# message with a timestamp, log level, and source location. It should not
# be called directly; use the `log_*` helper functions instead.
#
__base_bash_libs_std_print_log__() {
    local __base_bash_libs_std_print_log_level="${1-}"
    [[ -n "$__base_bash_libs_std_print_log_level" ]] || return 1
    shift
    local __base_bash_libs_std_print_log_logger=default __base_bash_libs_std_print_log_color __base_bash_libs_std_print_log_source_location
    local __base_bash_libs_std_print_log_terminal_enabled __base_bash_libs_std_print_log_persist_enabled
    if [[ "${1-}" == "-l" ]]; then
        if [[ -z "${2-}" ]]; then
            __base_bash_libs_std_log_source_location__ __base_bash_libs_std_print_log_source_location \
                "${BASH_SOURCE[1]:-${0:-unknown}}" "${BASH_LINENO[0]:-0}"
            printf '%(%Y-%m-%d %H:%M:%S)T %s\n' -1 \
                "WARN $__base_bash_libs_std_print_log_source_location Option '-l' needs an argument" >&2
            return 1
        fi
        __base_bash_libs_std_print_log_logger=$2
        shift 2
    fi
    __base_bash_libs_std_log_sink_state__ "$__base_bash_libs_std_print_log_logger" "$__base_bash_libs_std_print_log_level" \
        __base_bash_libs_std_print_log_terminal_enabled __base_bash_libs_std_print_log_persist_enabled || return 1

    if ((__base_bash_libs_std_print_log_terminal_enabled || __base_bash_libs_std_print_log_persist_enabled)); then
        # Select color based on log level
        case "$__base_bash_libs_std_print_log_level" in
        FATAL | ERROR) __base_bash_libs_std_print_log_color="$BASE_BASH_LIBS_STD_COLOR_RED" ;;
        WARN) __base_bash_libs_std_print_log_color="$BASE_BASH_LIBS_STD_COLOR_YELLOW" ;;
        INFO) __base_bash_libs_std_print_log_color="$BASE_BASH_LIBS_STD_COLOR_GREEN" ;;
        DEBUG) __base_bash_libs_std_print_log_color="$BASE_BASH_LIBS_STD_COLOR_BLUE" ;;
        *) __base_bash_libs_std_print_log_color="" ;; # No color for VERBOSE or others
        esac

        __base_bash_libs_std_log_source_location__ __base_bash_libs_std_print_log_source_location \
            "${BASH_SOURCE[2]:-}" "${BASH_LINENO[1]:-0}"
        __base_bash_libs_std_print_log_record__ "$__base_bash_libs_std_print_log_color" "$__base_bash_libs_std_print_log_level" \
            "$__base_bash_libs_std_print_log_source_location" "$__base_bash_libs_std_print_log_terminal_enabled" \
            "$__base_bash_libs_std_print_log_persist_enabled" "$@"
    fi
}

#
# __base_bash_libs_std_print_log_file__ - Core function for logging the contents of a file.
#
# Internal helper to be called by `base_std_log_info_file`, etc.
#
__base_bash_libs_std_print_log_file__() {
    local __base_bash_libs_std_print_file_level="${1-}"
    [[ -n "$__base_bash_libs_std_print_file_level" ]] || return 1
    shift
    local __base_bash_libs_std_print_file_logger=default __base_bash_libs_std_print_file_path __base_bash_libs_std_print_file_source_location
    local __base_bash_libs_std_print_file_terminal_enabled __base_bash_libs_std_print_file_persist_enabled
    if [[ "${1-}" == "-l" ]]; then
        if [[ -z "${2-}" ]]; then
            __base_bash_libs_std_log_source_location__ __base_bash_libs_std_print_file_source_location \
                "${BASH_SOURCE[1]:-${0:-unknown}}" "${BASH_LINENO[0]:-0}"
            printf '%(%Y-%m-%d %H:%M:%S)T %s\n' -1 \
                "WARN $__base_bash_libs_std_print_file_source_location Option '-l' needs an argument" >&2
            return 1
        fi
        __base_bash_libs_std_print_file_logger=$2
        shift 2
    fi
    __base_bash_libs_std_print_file_path="${1-}"
    __base_bash_libs_std_log_sink_state__ "$__base_bash_libs_std_print_file_logger" "$__base_bash_libs_std_print_file_level" \
        __base_bash_libs_std_print_file_terminal_enabled __base_bash_libs_std_print_file_persist_enabled || return 1
    if ((__base_bash_libs_std_print_file_terminal_enabled || __base_bash_libs_std_print_file_persist_enabled)) &&
        [[ -f "$__base_bash_libs_std_print_file_path" ]]; then
        __base_bash_libs_std_print_log__ "$__base_bash_libs_std_print_file_level" -l "$__base_bash_libs_std_print_file_logger" \
            "Contents of file '$__base_bash_libs_std_print_file_path':"
        if ((__base_bash_libs_std_print_file_terminal_enabled)); then
            cat -- "$__base_bash_libs_std_print_file_path" >&2
            # Keep the next structured record separate even when the file does
            # not end in a newline. A blank separator is harmless otherwise.
            printf '\n' >&2
        fi
        if ((__base_bash_libs_std_print_file_persist_enabled)); then
            __base_bash_libs_std_log_primary_sink_write__ file "$__base_bash_libs_std_print_file_path"
        fi
    fi
}

#
# Public logging functions.
# These are the primary functions scripts should use for logging.
#
base_std_log_fatal() { __base_bash_libs_std_print_log__ FATAL "$@"; }
base_std_log_error() { __base_bash_libs_std_print_log__ ERROR "$@"; }
base_std_log_warn() { __base_bash_libs_std_print_log__ WARN "$@"; }
base_std_log_info() { __base_bash_libs_std_print_log__ INFO "$@"; }
base_std_log_debug() { __base_bash_libs_std_print_log__ DEBUG "$@"; }
# Deprecated compatibility helper; prefer base_std_log_debug.
base_std_log_verbose() { __base_bash_libs_std_print_log__ VERBOSE "$@"; }

#
# Public functions for logging the content of a file.
#
base_std_log_info_file() { __base_bash_libs_std_print_log_file__ INFO "$@"; }
base_std_log_debug_file() { __base_bash_libs_std_print_log_file__ DEBUG "$@"; }
# Deprecated compatibility helper; prefer base_std_log_debug_file.
base_std_log_verbose_file() { __base_bash_libs_std_print_log_file__ VERBOSE "$@"; }

#
# Public functions for logging function entry and exit points.
#
base_std_log_info_enter() { __base_bash_libs_std_print_log__ INFO "Entering function ${FUNCNAME[1]:-main}"; }
base_std_log_debug_enter() { __base_bash_libs_std_print_log__ DEBUG "Entering function ${FUNCNAME[1]:-main}"; }
# Deprecated compatibility helper; prefer base_std_log_debug_enter.
base_std_log_verbose_enter() { __base_bash_libs_std_print_log__ VERBOSE "Entering function ${FUNCNAME[1]:-main}"; }
base_std_log_info_leave() { __base_bash_libs_std_print_log__ INFO "Leaving function ${FUNCNAME[1]:-main}"; }
base_std_log_debug_leave() { __base_bash_libs_std_print_log__ DEBUG "Leaving function ${FUNCNAME[1]:-main}"; }
# Deprecated compatibility helper; prefer base_std_log_debug_leave.
base_std_log_verbose_leave() { __base_bash_libs_std_print_log__ VERBOSE "Leaving function ${FUNCNAME[1]:-main}"; }

#
# Simple print routines that do not prefix messages with timestamps or levels.
#
base_std_print_error() {
    local __base_bash_libs_std_print_error_message
    __base_bash_libs_std_print_error_message="$(__base_bash_libs_std_join_message__ "$@")"
    { printf '%bERROR: %s%b\n' "$BASE_BASH_LIBS_STD_COLOR_RED" "$__base_bash_libs_std_print_error_message" "$BASE_BASH_LIBS_STD_COLOR_OFF"; } >&2
}
base_std_print_warn() {
    local __base_bash_libs_std_print_warn_message
    __base_bash_libs_std_print_warn_message="$(__base_bash_libs_std_join_message__ "$@")"
    { printf '%bWARN: %s%b\n' "$BASE_BASH_LIBS_STD_COLOR_YELLOW" "$__base_bash_libs_std_print_warn_message" "$BASE_BASH_LIBS_STD_COLOR_OFF"; } >&2
}
base_std_print_info() {
    local __base_bash_libs_std_print_info_message
    __base_bash_libs_std_print_info_message="$(__base_bash_libs_std_join_message__ "$@")"
    { printf '%b%s%b\n' "$BASE_BASH_LIBS_STD_COLOR_GREEN" "$__base_bash_libs_std_print_info_message" "$BASE_BASH_LIBS_STD_COLOR_OFF"; } >&2
}
base_std_print_success() {
    local __base_bash_libs_std_print_success_message
    __base_bash_libs_std_print_success_message="$(__base_bash_libs_std_join_message__ "$@")"
    { printf '%bSUCCESS: %s%b\n' "$BASE_BASH_LIBS_STD_COLOR_GREEN" "$__base_bash_libs_std_print_success_message" "$BASE_BASH_LIBS_STD_COLOR_OFF"; } >&2
}
base_std_print_bold() {
    local __base_bash_libs_std_print_bold_message
    __base_bash_libs_std_print_bold_message="$(__base_bash_libs_std_join_message__ "$@")"
    printf '%b%s%b\n' "$BASE_BASH_LIBS_STD_COLOR_BOLD" "$__base_bash_libs_std_print_bold_message" "$BASE_BASH_LIBS_STD_COLOR_OFF"
}
base_std_print_message() { printf '%s\n' "$@"; }

#
# base_std_print_tty - Prints a message only if the output is going to a terminal.
#
base_std_print_tty() {
    if [[ -t 1 ]]; then
        printf '%s\n' "$(__base_bash_libs_std_join_message__ "$@")"
    fi
}

################################################## ERROR HANDLING ######################################################

#
# base_std_dump_trace - Prints a stack trace of the Bash function calls.
#
# This is useful for debugging to see the sequence of function calls
# that led to an error.
#
base_std_dump_trace() {
    local __base_bash_libs_std_trace_frame=0 __base_bash_libs_std_trace_line __base_bash_libs_std_trace_func __base_bash_libs_std_trace_source __base_bash_libs_std_trace_caller_info
    while __base_bash_libs_std_trace_caller_info="$(caller "$__base_bash_libs_std_trace_frame")"; do
        IFS=' ' read -r __base_bash_libs_std_trace_line __base_bash_libs_std_trace_func __base_bash_libs_std_trace_source <<< "$__base_bash_libs_std_trace_caller_info"
        if ((__base_bash_libs_std_trace_frame == 0)); then
            printf 'Encountered a fatal error\n'
        fi
        printf '%4s at %s\n' " " "$__base_bash_libs_std_trace_func ($__base_bash_libs_std_trace_source:$__base_bash_libs_std_trace_line)"
        ((__base_bash_libs_std_trace_frame += 1))
    done >&2
    return 0
}

#
# base_std_exit_if_error - Exits the script if the provided exit code is non-zero.
#
# This is the primary error handling function. It checks a command's exit
# code and, if it indicates failure, logs a fatal message, dumps a stack
# trace, and exits the script.
#
# Usage:
#   command_that_might_fail
#   base_std_exit_if_error $? "A descriptive error message."
#
# Arguments:
#   $1: The exit code to check (typically $?).
#   $@: The error message to log if the exit code is non-zero.
#
base_std_exit_if_error() {
    (($#)) || return
    local __base_bash_libs_std_exit_number_re='^[0-9]+$'
    local __base_bash_libs_std_exit_status=$1 __base_bash_libs_std_exit_normalized_status
    shift
    local __base_bash_libs_std_exit_message
    if (($#)); then
        __base_bash_libs_std_exit_message="$(__base_bash_libs_std_join_message__ "$@")"
    else
        __base_bash_libs_std_exit_message="No message specified"
    fi
    if ! [[ $__base_bash_libs_std_exit_status =~ $__base_bash_libs_std_exit_number_re ]]; then
        base_std_log_error -l base_bash_libs.std \
            "'$__base_bash_libs_std_exit_status' is not a valid exit code; it needs to be a number greater than zero. Treating it as 1."
        __base_bash_libs_std_exit_status=1
    elif ! __base_bash_libs_std_decimal_integer_value__ __base_bash_libs_std_exit_normalized_status "$__base_bash_libs_std_exit_status"; then
        base_std_log_error -l base_bash_libs.std "'$__base_bash_libs_std_exit_status' is not a valid decimal exit code. Treating it as 1."
        __base_bash_libs_std_exit_status=1
    else
        __base_bash_libs_std_exit_status="$__base_bash_libs_std_exit_normalized_status"
    fi
    ((__base_bash_libs_std_exit_status)) && {
        base_std_log_fatal -l base_bash_libs.std "$__base_bash_libs_std_exit_message"
        base_std_dump_trace
        exit "$__base_bash_libs_std_exit_status"
    }
    return 0
}

#
# base_std_fatal_error - A convenience wrapper around base_std_exit_if_error.
#
# This function immediately triggers a fatal error, using the exit code
# of the last command if it was non-zero, or 1 otherwise.
#
# Usage:
#   [[ -f "$my_file" ]] || base_std_fatal_error "Required file '$my_file' not found."
#
base_std_fatal_error() {
    local __base_bash_libs_std_fatal_status=$?                                        # grab the current exit code
    ((__base_bash_libs_std_fatal_status == 0)) && __base_bash_libs_std_fatal_status=1 # if it is zero, set exit code to 1
    base_std_exit_if_error "$__base_bash_libs_std_fatal_status" "$@"
}

#################################################### COMMAND EXECUTION #################################################

#
# base_std_is_dry_run - Returns true when dry-run mode is enabled.
#
# Dry-run mode accepts common truthy values in BASE_BASH_LIBS_DRY_RUN.
#
base_std_is_dry_run() {
    local __base_bash_libs_std_dry_run_value

    __base_bash_libs_std_dry_run_value="${BASE_BASH_LIBS_DRY_RUN-}"
    case "${__base_bash_libs_std_dry_run_value,,}" in
    true | 1 | yes | on) return 0 ;;
    esac
    return 1
}

__base_bash_libs_std_decimal_integer_value__() {
    local __base_bash_libs_std_decimal_result_name="${1-}" __base_bash_libs_std_decimal_value="${2-}" __base_bash_libs_std_decimal_sign=""
    local __base_bash_libs_std_decimal_digits

    [[ "$__base_bash_libs_std_decimal_value" =~ ^[-+]?[0-9]+$ ]] || return 1
    case "$__base_bash_libs_std_decimal_value" in
    -*)
        __base_bash_libs_std_decimal_sign="-"
        __base_bash_libs_std_decimal_digits="${__base_bash_libs_std_decimal_value#-}"
        ;;
    +*)
        __base_bash_libs_std_decimal_digits="${__base_bash_libs_std_decimal_value#+}"
        ;;
    *)
        __base_bash_libs_std_decimal_digits="$__base_bash_libs_std_decimal_value"
        ;;
    esac

    while [[ "${#__base_bash_libs_std_decimal_digits}" -gt 1 && "${__base_bash_libs_std_decimal_digits:0:1}" == "0" ]]; do
        __base_bash_libs_std_decimal_digits="${__base_bash_libs_std_decimal_digits:1}"
    done

    if [[ "$__base_bash_libs_std_decimal_sign" == "-" && "$__base_bash_libs_std_decimal_digits" != "0" ]]; then
        printf -v "$__base_bash_libs_std_decimal_result_name" '%s' "-$((10#$__base_bash_libs_std_decimal_digits))"
    else
        printf -v "$__base_bash_libs_std_decimal_result_name" '%s' "$((10#$__base_bash_libs_std_decimal_digits))"
    fi
}

__base_bash_libs_std_is_positive_integer__() {
    local __base_bash_libs_std_positive_normalized
    __base_bash_libs_std_decimal_integer_value__ __base_bash_libs_std_positive_normalized "${1-}" || return 1
    ((__base_bash_libs_std_positive_normalized > 0))
}

__base_bash_libs_std_is_non_negative_integer__() {
    local __base_bash_libs_std_non_negative_normalized
    __base_bash_libs_std_decimal_integer_value__ __base_bash_libs_std_non_negative_normalized "${1-}" || return 1
    ((__base_bash_libs_std_non_negative_normalized >= 0))
}

__base_bash_libs_std_is_safe_display__() {
    (($# == 1)) || return 1

    local __base_bash_libs_std_safe_display_value="${1-}"
    local __base_bash_libs_std_safe_display_allowed_ascii
    local __base_bash_libs_std_safe_display_character __base_bash_libs_std_safe_display_index

    # Spell out the printable ASCII set instead of changing LC_ALL. Bash
    # variables use dynamic scope, so even a function-local locale binding can
    # collide with a caller's readonly LC_ALL. Quoted substring membership is
    # independent of character classes and locale collation.
    __base_bash_libs_std_safe_display_allowed_ascii=$' !"#$%&\'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~'

    [[ -n "$__base_bash_libs_std_safe_display_value" && "$__base_bash_libs_std_safe_display_value" != -* ]] || return 1
    for ((__base_bash_libs_std_safe_display_index = 0;  \
    __base_bash_libs_std_safe_display_index < ${#__base_bash_libs_std_safe_display_value};  \
    __base_bash_libs_std_safe_display_index++)); do
        __base_bash_libs_std_safe_display_character="${__base_bash_libs_std_safe_display_value:__base_bash_libs_std_safe_display_index:1}"
        [[ "$__base_bash_libs_std_safe_display_allowed_ascii" == *"$__base_bash_libs_std_safe_display_character"* ]] || return 1
    done
}

__base_bash_libs_std_render_command_display__() {
    (($# >= 4)) || return 1

    local __base_bash_libs_std_render_display_result_name="${1-}"
    local __base_bash_libs_std_render_display_sensitive="${2-}"
    local __base_bash_libs_std_render_display_safe_value="${3-}"
    local __base_bash_libs_std_render_display_protected_description="${4-}"
    local __base_bash_libs_std_render_display_value=""
    shift 4

    case "$__base_bash_libs_std_render_display_sensitive" in
    1)
        if [[ -n "$__base_bash_libs_std_render_display_safe_value" ]]; then
            __base_bash_libs_std_is_safe_display__ "$__base_bash_libs_std_render_display_safe_value" || return 1
            __base_bash_libs_std_render_display_value="$__base_bash_libs_std_render_display_safe_value $__base_bash_libs_std_render_display_protected_description"
        else
            __base_bash_libs_std_render_display_value="$__base_bash_libs_std_render_display_protected_description"
        fi
        ;;
    0)
        if (($#)); then
            printf -v __base_bash_libs_std_render_display_value '%q ' "$@"
            __base_bash_libs_std_render_display_value="${__base_bash_libs_std_render_display_value% }"
        fi
        ;;
    *)
        return 1
        ;;
    esac

    printf -v "$__base_bash_libs_std_render_display_result_name" '%s' "$__base_bash_libs_std_render_display_value"
}

__base_bash_libs_std_join_run_policy__() {
    local result_name="$1" timeout_seconds="$2" max_attempts="$3" retry_delay="$4"
    local policies=()
    local policy joined_policy=""

    [[ -n "$timeout_seconds" ]] && policies+=("${timeout_seconds}s timeout")
    ((max_attempts > 1)) && policies+=("${max_attempts} attempts")
    ((retry_delay > 0)) && policies+=("${retry_delay}s retry delay")

    for policy in "${policies[@]+"${policies[@]}"}"; do
        if [[ -n "$joined_policy" ]]; then
            joined_policy+=", "
        fi
        joined_policy+="$policy"
    done

    printf -v "$result_name" '%s' "$joined_policy"
}

__base_bash_libs_std_emit_dry_run_plan__() {
    local __base_bash_libs_std_dry_run_plan_message="${1-}"
    local __base_bash_libs_std_dry_run_plan_source __base_bash_libs_std_dry_run_plan_timestamp
    local __base_bash_libs_std_dry_run_plan_record __base_bash_libs_std_dry_run_plan_status=0

    # A dry-run plan is a safety control, not an ordinary informational log.
    # Write it directly to stderr so logger and category thresholds cannot hide
    # it. The same already-redacted record is copied to the optional primary
    # log on a best-effort basis.
    __base_bash_libs_std_log_source_location__ __base_bash_libs_std_dry_run_plan_source \
        "${BASH_SOURCE[2]:-}" "${BASH_LINENO[1]:-0}"
    __base_bash_libs_std_log_timestamp__ __base_bash_libs_std_dry_run_plan_timestamp
    builtin printf -v __base_bash_libs_std_dry_run_plan_record '%s %-7s %s %s' \
        "$__base_bash_libs_std_dry_run_plan_timestamp" "DRY-RUN" \
        "$__base_bash_libs_std_dry_run_plan_source" "$__base_bash_libs_std_dry_run_plan_message"
    builtin printf '%s\n' "$__base_bash_libs_std_dry_run_plan_record" >&2 ||
        __base_bash_libs_std_dry_run_plan_status=1
    if __base_bash_libs_std_log_primary_sink_is_usable__ "${BASE_BASH_LIBS_PRIMARY_LOG:-}"; then
        __base_bash_libs_std_log_primary_sink_write__ record "$__base_bash_libs_std_dry_run_plan_record"
    fi
    return "$__base_bash_libs_std_dry_run_plan_status"
}

__base_bash_libs_std_run_once__() {
    local __base_bash_libs_std_run_once_outcome_result_name="$1"
    local __base_bash_libs_std_run_once_timeout_seconds="$2" __base_bash_libs_std_run_once_timeout_path="$3"
    # These mutable locals shadow the caller's authoritative state while a
    # shell-function command runs in Bash's dynamic scope. Assignments made by
    # the command are absorbed here and discarded when this helper returns.
    local __base_bash_libs_std_run_attempt_number="$4"
    local __base_bash_libs_std_run_once_outcome=command __base_bash_libs_std_run_once_status=0
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_std_run_immutable_command_display
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_std_run_policy_exit_on_failure __base_bash_libs_std_run_policy_quiet
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_std_run_policy_timeout_seconds __base_bash_libs_std_run_policy_timeout_path
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_std_run_policy_max_attempts __base_bash_libs_std_run_policy_retry_delay
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_std_run_exit_code __base_bash_libs_std_run_message
    shift 4

    if [[ -n "$__base_bash_libs_std_run_once_timeout_seconds" ]]; then
        if __base_bash_libs_std_run_with_timeout_supervisor__ __base_bash_libs_std_run_once_outcome \
            "$__base_bash_libs_std_run_once_timeout_seconds" \
            "$__base_bash_libs_std_run_once_timeout_path" "$@"; then
            __base_bash_libs_std_run_once_status=0
        else
            __base_bash_libs_std_run_once_status=$?
        fi
    else
        if "$@"; then
            __base_bash_libs_std_run_once_status=0
        else
            __base_bash_libs_std_run_once_status=$?
        fi
    fi

    printf -v "$__base_bash_libs_std_run_once_outcome_result_name" '%s' \
        "$__base_bash_libs_std_run_once_outcome"
    return "$__base_bash_libs_std_run_once_status"
}

__base_bash_libs_std_run_status_message__() {
    local result_name="$1" exit_code="$2" timeout_seconds="$3"
    local outcome="$4" printable_command="$5"

    if [[ "$outcome" == timeout && -n "$timeout_seconds" ]]; then
        printf -v "$result_name" 'Command timed out after %ss: %s' "$timeout_seconds" "$printable_command"
    elif [[ "$outcome" == infrastructure ]]; then
        printf -v "$result_name" 'Command could not be supervised safely (exit %s): %s' "$exit_code" "$printable_command"
    else
        printf -v "$result_name" 'Command failed (exit %s): %s' "$exit_code" "$printable_command"
    fi
}

#
# base_std_run - Safely executes a simple command with its arguments.
#
# This function is designed to be a secure and robust replacement for using
# `eval` or simple command execution. It correctly handles arguments with
# spaces and special characters.
#
# Features:
#   - Secure: Does not use `eval`, preventing arbitrary code execution.
#   - Argument Safe: Correctly handles spaces and special characters in arguments.
#   - Dry-Run Mode: If the global variable BASE_BASH_LIBS_DRY_RUN (or BASE_BASH_LIBS_DRY_RUN) is truthy, it
#     prints the command instead of running it.
#   - Optional Timeout: `--timeout N` bounds each command attempt to N seconds.
#   - Optional Retry: `--max-attempts N` retries failed commands up to N total
#     attempts, optionally sleeping `--retry-delay N` seconds between attempts.
#   - Return on Failure: `base_std_run` returns the command status by default,
#     allowing the caller to decide whether a failure is recoverable.
#   - Explicit Fail-Fast: `base_std_run_or_exit` exits the script when the
#     command returns a non-zero status.
#   - Optional No-Exit: If an initial argument is `--no-exit`, either helper
#     returns on failure, allowing the calling script to handle the error.
#   - Optional Quiet Probe: If an initial argument is `--quiet`, handled
#     failures do not log warnings. This is intended for expected probe
#     failures and is most useful with `--no-exit`.
#   - Protected Diagnostics: `--sensitive` prevents framework-generated
#     diagnostics from rendering the command arguments. `--safe-display`
#     supplies an optional caller-vetted, single-line operation label.
#
# Usage:
#   base_std_run [options] command [arg1] [arg2] ...
#   base_std_run_or_exit [options] command [arg1] [arg2] ...
#   base_std_run --sensitive [--safe-display label] [options] -- command [arg1] ...
#
# Options:
#   --no-exit   Override the helper's default and return the command's original
#               exit code instead of exiting when the command fails.
#   --quiet     Suppress the warning normally logged for a returned failure.
#   --timeout N
#               Bound each command attempt to N seconds.
#   --max-attempts N
#               Try the command up to N total times. Defaults to 1.
#   --retry-attempts N
#               Alias for --max-attempts.
#   --retry-delay N
#               Sleep N seconds between failed attempts. Defaults to 0.
#   --sensitive  Hide the command and all arguments from framework-generated
#               dry-run, retry, timeout, and final-failure diagnostics. A
#               literal `--` must separate runner options from the command.
#   --safe-display LABEL
#               Add a printable ASCII operation label that is non-empty and
#               does not begin with `-`. Valid only with `--sensitive`.
#
# Examples:
#   # Run a command and handle its status in the caller.
#   base_std_run ls -l /tmp
#
#   # Opt into fail-fast behavior with an explicit name.
#   base_std_run_or_exit ls -l /tmp
#
#   # Run a command with spaces in an argument.
#   base_std_run touch "a file with spaces.txt"
#
#   # Run a command but don't exit the script on failure.
#   if ! base_std_run --no-exit grep "not_found" /etc/hosts; then
#       log "INFO" "The text was not found, but we are continuing."
#   fi
#
#   # In a script where BASE_BASH_LIBS_DRY_RUN=true, this will only print the command.
#   BASE_BASH_LIBS_DRY_RUN=true
#   base_std_run rm -rf /some/important/path
#
#   # Protect credentials in framework-generated diagnostics.
#   base_std_run --sensitive --safe-display "upload release asset" -- \
#       curl -H "Authorization: Bearer $token" "$upload_url"
#
################################################################################
__base_bash_libs_std_run_impl__() {
    local helper_name="$1"
    local exit_on_failure="$2"
    shift 2
    local quiet=0 timeout_seconds="" timeout_path="" max_attempts=1 retry_delay=0
    local sensitive=0 safe_display="" safe_display_set=0 option_terminator_seen=0

    # Parse optional run flags before the command.
    while (($#)); do
        case "${1-}" in
        --no-exit)
            exit_on_failure=0
            shift
            ;;
        --quiet)
            quiet=1
            shift
            ;;
        --timeout)
            shift
            if (($# == 0)) || ! __base_bash_libs_std_is_positive_integer__ "${1-}"; then
                base_std_log_error -l base_bash_libs.std "$helper_name: timeout seconds must be a positive integer."
                return 1
            fi
            __base_bash_libs_std_decimal_integer_value__ timeout_seconds "$1"
            shift
            ;;
        --max-attempts | --retry-attempts)
            shift
            if (($# == 0)) || ! __base_bash_libs_std_is_positive_integer__ "${1-}"; then
                base_std_log_error -l base_bash_libs.std "$helper_name: max attempts must be a positive integer."
                return 1
            fi
            __base_bash_libs_std_decimal_integer_value__ max_attempts "$1"
            shift
            ;;
        --retry-delay)
            shift
            if (($# == 0)) || ! __base_bash_libs_std_is_non_negative_integer__ "${1-}"; then
                base_std_log_error -l base_bash_libs.std "$helper_name: retry delay seconds must be a non-negative integer."
                return 1
            fi
            __base_bash_libs_std_decimal_integer_value__ retry_delay "$1"
            shift
            ;;
        --sensitive)
            sensitive=1
            shift
            ;;
        --safe-display)
            safe_display_set=1
            shift
            if (($# == 0)) || [[ "${1-}" == -* ]]; then
                base_std_log_error -l base_bash_libs.std \
                    "$helper_name: --safe-display requires a non-empty printable ASCII label that does not begin with -."
                return 1
            fi
            safe_display="$1"
            shift
            ;;
        --)
            option_terminator_seen=1
            shift
            break
            ;;
        *)
            if [[ "${1-}" == --* ]]; then
                base_std_log_error -l base_bash_libs.std \
                    "$helper_name: unknown runner option. Use -- before commands that begin with --."
                return 1
            fi
            break
            ;;
        esac
    done

    if ((safe_display_set && !sensitive)); then
        base_std_log_error -l base_bash_libs.std "$helper_name: --safe-display is valid only with --sensitive."
        return 1
    fi
    if ((safe_display_set)) && ! __base_bash_libs_std_is_safe_display__ "$safe_display"; then
        base_std_log_error -l base_bash_libs.std \
            "$helper_name: --safe-display requires a non-empty printable ASCII label that does not begin with -."
        return 1
    fi
    if ((sensitive && !option_terminator_seen)); then
        base_std_log_error -l base_bash_libs.std \
            "$helper_name: --sensitive requires -- before the command."
        return 1
    fi

    # Check if the command is empty.
    if [[ $# -eq 0 ]]; then
        base_std_log_error -l base_bash_libs.std "$helper_name: No command provided."
        return 1
    fi

    local __base_bash_libs_std_run_immutable_command_display
    __base_bash_libs_std_render_command_display__ __base_bash_libs_std_run_immutable_command_display "$sensitive" "$safe_display" \
        '[sensitive command; arguments hidden]' "$@" || {
        base_std_log_error -l base_bash_libs.std "$helper_name: could not render a safe command diagnostic."
        return 1
    }
    readonly __base_bash_libs_std_run_immutable_command_display

    # Bash functions execute in the caller's dynamic scope. Freeze every
    # parsed value that remains authoritative after command execution, and use
    # only these uniquely prefixed copies below. A command may happen to assign
    # generic names such as `timeout_seconds` or `quiet`; those assignments
    # must not alter retry behavior or become framework-generated diagnostics.
    local -r __base_bash_libs_std_run_policy_exit_on_failure="$exit_on_failure"
    local -r __base_bash_libs_std_run_policy_quiet="$quiet"
    local -r __base_bash_libs_std_run_policy_timeout_seconds="$timeout_seconds"
    local -r __base_bash_libs_std_run_policy_max_attempts="$max_attempts"
    local -r __base_bash_libs_std_run_policy_retry_delay="$retry_delay"

    # --- Dry-Run Handling ---
    if base_std_is_dry_run; then
        local policy_description __base_bash_libs_std_dry_run_message
        __base_bash_libs_std_join_run_policy__ policy_description \
            "$__base_bash_libs_std_run_policy_timeout_seconds" \
            "$__base_bash_libs_std_run_policy_max_attempts" \
            "$__base_bash_libs_std_run_policy_retry_delay"

        # Ordinary commands use a copy-pastable %q rendering. Sensitive
        # commands use only the caller-vetted label or the protected marker;
        # the renderer does not inspect or format their command arguments.
        if [[ -n "$policy_description" ]]; then
            __base_bash_libs_std_dry_run_message="[DRY-RUN] Would run with ${policy_description}: ${__base_bash_libs_std_run_immutable_command_display}"
        else
            __base_bash_libs_std_dry_run_message="[DRY-RUN] Would run: ${__base_bash_libs_std_run_immutable_command_display}"
        fi
        __base_bash_libs_std_emit_dry_run_plan__ "$__base_bash_libs_std_dry_run_message"
        return $?
    fi

    # --- Execution ---
    # Execute the command. Using "$@" is the key. It expands each argument
    # as a separate, quoted string, preserving spaces and special characters.
    # This is the safe, modern alternative to using `eval`.
    if [[ -n "$__base_bash_libs_std_run_policy_timeout_seconds" ]]; then
        __base_bash_libs_std_timeout_backend_detect__ timeout_path
    fi
    local -r __base_bash_libs_std_run_policy_timeout_path="$timeout_path"

    local __base_bash_libs_std_run_attempt_number=1 __base_bash_libs_std_run_attempts_completed=0
    local __base_bash_libs_std_run_exit_code=0 __base_bash_libs_std_run_message __base_bash_libs_std_run_outcome=command
    while ((__base_bash_libs_std_run_attempt_number <= __base_bash_libs_std_run_policy_max_attempts)); do
        if __base_bash_libs_std_run_once__ \
            __base_bash_libs_std_run_outcome \
            "$__base_bash_libs_std_run_policy_timeout_seconds" \
            "$__base_bash_libs_std_run_policy_timeout_path" \
            "$__base_bash_libs_std_run_attempt_number" \
            "$@"; then
            return 0
        else
            __base_bash_libs_std_run_exit_code=$?
        fi
        __base_bash_libs_std_run_attempts_completed="$__base_bash_libs_std_run_attempt_number"
        if [[ "$__base_bash_libs_std_run_outcome" == infrastructure ||
            "$__base_bash_libs_std_run_outcome" == interrupted ]]; then
            break
        fi

        if ((__base_bash_libs_std_run_attempt_number < __base_bash_libs_std_run_policy_max_attempts)); then
            if ((!__base_bash_libs_std_run_policy_quiet)); then
                __base_bash_libs_std_run_status_message__ __base_bash_libs_std_run_message \
                    "$__base_bash_libs_std_run_exit_code" "$__base_bash_libs_std_run_policy_timeout_seconds" \
                    "$__base_bash_libs_std_run_outcome" \
                    "$__base_bash_libs_std_run_immutable_command_display"
                base_std_log_warn -l base_bash_libs.std \
                    "${__base_bash_libs_std_run_message} (attempt ${__base_bash_libs_std_run_attempt_number} of ${__base_bash_libs_std_run_policy_max_attempts}; retrying)."
            fi
            if ((__base_bash_libs_std_run_policy_retry_delay > 0)); then
                __base_bash_libs_std_sleep_interval__ "$__base_bash_libs_std_run_policy_retry_delay"
            fi
        fi

        __base_bash_libs_std_run_attempt_number=$((__base_bash_libs_std_run_attempt_number + 1))
    done

    if ((__base_bash_libs_std_run_exit_code)); then
        if ((__base_bash_libs_std_run_attempts_completed > 1)); then
            if [[ "$__base_bash_libs_std_run_outcome" == timeout ]]; then
                __base_bash_libs_std_run_message="Command timed out after ${__base_bash_libs_std_run_policy_timeout_seconds}s on final attempt (${__base_bash_libs_std_run_attempts_completed} attempts): ${__base_bash_libs_std_run_immutable_command_display}"
            else
                __base_bash_libs_std_run_message="Command failed after ${__base_bash_libs_std_run_attempts_completed} attempts (exit ${__base_bash_libs_std_run_exit_code}): ${__base_bash_libs_std_run_immutable_command_display}"
            fi
        else
            __base_bash_libs_std_run_status_message__ __base_bash_libs_std_run_message \
                "$__base_bash_libs_std_run_exit_code" "$__base_bash_libs_std_run_policy_timeout_seconds" \
                "$__base_bash_libs_std_run_outcome" \
                "$__base_bash_libs_std_run_immutable_command_display"
        fi
        if ((__base_bash_libs_std_run_policy_exit_on_failure)); then
            base_std_exit_if_error "$__base_bash_libs_std_run_exit_code" "$__base_bash_libs_std_run_message"
        else
            if ((!__base_bash_libs_std_run_policy_quiet)); then
                base_std_log_warn -l base_bash_libs.std "$__base_bash_libs_std_run_message (continuing)."
            fi
            return "$__base_bash_libs_std_run_exit_code"
        fi
    fi

    return 0
}

base_std_run() {
    __base_bash_libs_std_run_impl__ base_std_run 0 "$@"
}

base_std_run_or_exit() {
    __base_bash_libs_std_run_impl__ base_std_run_or_exit 1 "$@"
}

__base_bash_libs_std_sleep_interval__() {
    if [[ -x /bin/sleep ]]; then
        /bin/sleep "$1"
    else
        sleep "$1"
    fi
}

__base_bash_libs_std_timeout_candidate_is_gnu__() {
    (($# == 1)) || return 1
    local __base_bash_libs_std_timeout_candidate_path="$1"
    local __base_bash_libs_std_timeout_candidate_version __base_bash_libs_std_timeout_candidate_first_line

    [[ -x "$__base_bash_libs_std_timeout_candidate_path" ]] || return 1
    __base_bash_libs_std_timeout_candidate_version="$(
        "$__base_bash_libs_std_timeout_candidate_path" --version 2> /dev/null
    )" || return 1
    __base_bash_libs_std_timeout_candidate_first_line="${__base_bash_libs_std_timeout_candidate_version%%$'\n'*}"
    [[ "$__base_bash_libs_std_timeout_candidate_first_line" == "timeout (GNU coreutils)" ||
        "$__base_bash_libs_std_timeout_candidate_first_line" == "timeout (GNU coreutils) "* ]]
}

__base_bash_libs_std_timeout_backend_detect__() {
    (($# == 1)) || return 1
    local __base_bash_libs_std_timeout_backend_result_name="$1"
    local timeout_backend_candidate="" __base_bash_libs_std_timeout_backend_name

    printf -v "$__base_bash_libs_std_timeout_backend_result_name" '%s' ""
    for __base_bash_libs_std_timeout_backend_name in timeout gtimeout; do
        timeout_backend_candidate=""
        if base_std_command_path timeout_backend_candidate \
            "$__base_bash_libs_std_timeout_backend_name" &&
            __base_bash_libs_std_timeout_candidate_is_gnu__ \
                "$timeout_backend_candidate"; then
            printf -v "$__base_bash_libs_std_timeout_backend_result_name" '%s' \
                "$timeout_backend_candidate"
            return 0
        fi
    done
    return 0
}

# GNU timeout and gtimeout are deadline clocks only. They never receive the
# caller's argv: the framework owns the process group and performs TERM/KILL.
__base_bash_libs_std_timeout_wait_clock__() {
    local __base_bash_libs_std_timeout_clock_path="$1" __base_bash_libs_std_timeout_clock_seconds="$2"
    local __base_bash_libs_std_timeout_clock_fd="$3" __base_bash_libs_std_timeout_clock_status=125
    local __base_bash_libs_std_timeout_clock_dd="" __base_bash_libs_std_timeout_clock_byte=""

    if [[ -n "$__base_bash_libs_std_timeout_clock_path" ]]; then
        if [[ -x /bin/dd ]]; then
            __base_bash_libs_std_timeout_clock_dd=/bin/dd
        else
            __base_bash_libs_std_timeout_clock_dd="$(type -P dd 2> /dev/null || true)"
        fi
        [[ -n "$__base_bash_libs_std_timeout_clock_dd" && -x "$__base_bash_libs_std_timeout_clock_dd" ]] ||
            return 125
        if "$__base_bash_libs_std_timeout_clock_path" --foreground --signal=KILL \
            "${__base_bash_libs_std_timeout_clock_seconds}s" "$__base_bash_libs_std_timeout_clock_dd" \
            bs=1 count=1 <&"$__base_bash_libs_std_timeout_clock_fd" > /dev/null 2>&1; then
            __base_bash_libs_std_timeout_clock_status=0
        else
            __base_bash_libs_std_timeout_clock_status=$?
        fi
        case "$__base_bash_libs_std_timeout_clock_status" in
        0) return 0 ;;
        124 | 137) return 124 ;;
        *) return 125 ;;
        esac
    fi

    if IFS= read -r -n 1 -t "$__base_bash_libs_std_timeout_clock_seconds" \
        -u "$__base_bash_libs_std_timeout_clock_fd" __base_bash_libs_std_timeout_clock_byte; then
        return 0
    fi
    return 124
}

__base_bash_libs_std_timeout_latch_cancel__() {
    local __base_bash_libs_std_timeout_latched_signal="$1" __base_bash_libs_std_timeout_latched_status="$2"

    if ((__base_bash_libs_std_timeout_cancel_status == 0)); then
        __base_bash_libs_std_timeout_cancel_signal="$__base_bash_libs_std_timeout_latched_signal"
        __base_bash_libs_std_timeout_cancel_status="$__base_bash_libs_std_timeout_latched_status"
        if [[ -n "$__base_bash_libs_std_timeout_command_pid" ]]; then
            builtin kill "-$__base_bash_libs_std_timeout_latched_signal" -- \
                "-$__base_bash_libs_std_timeout_command_pid" 2> /dev/null || true
        fi
    elif [[ -n "$__base_bash_libs_std_timeout_command_pid" ]]; then
        builtin kill -KILL -- "-$__base_bash_libs_std_timeout_command_pid" 2> /dev/null || true
    fi
}

__base_bash_libs_std_timeout_command_wrapper__() {
    local __base_bash_libs_std_timeout_wrapper_status=0
    local __base_bash_libs_std_timeout_wrapper_cancel_status=0
    local __base_bash_libs_std_timeout_wrapper_child_pid=""
    local __base_bash_libs_std_timeout_wrapper_release_byte=""
    local __base_bash_libs_std_timeout_wrapper_status_record=""

    # The wrapper job starts with stderr redirected away so Bash cannot print
    # a job-control `Killed: 9` notification when its process group is
    # escalated. Restore the caller's original stderr before launching argv;
    # the command therefore retains byte-for-byte diagnostics.
    if [[ -n "${__base_bash_libs_std_timeout_stderr_fd-}" ]]; then
        exec 2>&"$__base_bash_libs_std_timeout_stderr_fd"
        exec {__base_bash_libs_std_timeout_stderr_fd}>&-
    fi

    trap - EXIT
    if ((__base_bash_libs_std_timeout_hup_ignored)); then
        trap '' HUP
    else
        trap '__base_bash_libs_std_timeout_wrapper_cancel_status=129' HUP
    fi
    if ((__base_bash_libs_std_timeout_int_ignored)); then
        trap '' INT
    else
        trap '__base_bash_libs_std_timeout_wrapper_cancel_status=130' INT
    fi
    if ((__base_bash_libs_std_timeout_quit_ignored)); then
        trap '' QUIT
    else
        trap '__base_bash_libs_std_timeout_wrapper_cancel_status=131' QUIT
    fi
    if ((__base_bash_libs_std_timeout_term_ignored)); then
        trap '' TERM
    else
        trap '__base_bash_libs_std_timeout_wrapper_cancel_status=143' TERM
    fi
    if [[ -n "${__base_bash_libs_std_timeout_timer_fd-}" ]]; then
        exec {__base_bash_libs_std_timeout_timer_fd}>&-
    fi

    set +m
    if ((__base_bash_libs_std_timeout_has_stdin)); then
        "${__base_bash_libs_std_timeout_command_argv[@]}" <&0 &
    else
        "${__base_bash_libs_std_timeout_command_argv[@]}" <&- &
    fi
    __base_bash_libs_std_timeout_wrapper_child_pid=$!
    while :; do
        if wait "$__base_bash_libs_std_timeout_wrapper_child_pid" 2> /dev/null; then
            __base_bash_libs_std_timeout_wrapper_status=0
            break
        else
            __base_bash_libs_std_timeout_wrapper_status=$?
        fi
        builtin kill -0 "$__base_bash_libs_std_timeout_wrapper_child_pid" 2> /dev/null ||
            break
    done
    ((__base_bash_libs_std_timeout_wrapper_cancel_status != 0)) &&
        __base_bash_libs_std_timeout_wrapper_status="$__base_bash_libs_std_timeout_wrapper_cancel_status"

    # Keep the process-group leader alive through the final KILL so its PGID
    # cannot be recycled into an unrelated process group.
    __base_bash_libs_std_timeout_wrapper_status_record="S$(printf '%03d' \
        "$__base_bash_libs_std_timeout_wrapper_status")"
    if ! builtin printf '%s' "$__base_bash_libs_std_timeout_wrapper_status_record" \
        >| "$__base_bash_libs_std_timeout_status_file" 2> /dev/null; then
        return 1
    fi
    IFS= read -r -n 1 -u "$__base_bash_libs_std_timeout_status_fd" \
        __base_bash_libs_std_timeout_wrapper_release_byte 2> /dev/null || true
    return "$__base_bash_libs_std_timeout_wrapper_status"
}

__base_bash_libs_std_timeout_watchdog__() {
    local __base_bash_libs_std_timeout_watchdog_seconds="$1"
    local __base_bash_libs_std_timeout_watchdog_path="$2"
    local __base_bash_libs_std_timeout_watchdog_fd="$3"
    local __base_bash_libs_std_timeout_watchdog_command_pid="$4"
    local __base_bash_libs_std_timeout_watchdog_status_file="$5"
    local __base_bash_libs_std_timeout_watchdog_clock_status=125
    local __base_bash_libs_std_timeout_watchdog_final_status=125

    if __base_bash_libs_std_timeout_wait_clock__ "$__base_bash_libs_std_timeout_watchdog_path" \
        "$__base_bash_libs_std_timeout_watchdog_seconds" "$__base_bash_libs_std_timeout_watchdog_fd"; then
        __base_bash_libs_std_timeout_watchdog_final_status=0
        builtin printf 'T%03d' "$__base_bash_libs_std_timeout_watchdog_final_status" \
            >| "$__base_bash_libs_std_timeout_watchdog_status_file" 2> /dev/null || true
    else
        __base_bash_libs_std_timeout_watchdog_clock_status=$?
        case "$__base_bash_libs_std_timeout_watchdog_clock_status" in
        124) __base_bash_libs_std_timeout_watchdog_final_status=124 ;;
        *) __base_bash_libs_std_timeout_watchdog_final_status=125 ;;
        esac
        # Publish the timer result before escalation. The supervisor must not
        # mistake the wrapper's signal-derived status (143/137) for the
        # deadline or clock outcome that caused the escalation.
        builtin printf 'T%03d' "$__base_bash_libs_std_timeout_watchdog_final_status" \
            >| "$__base_bash_libs_std_timeout_watchdog_status_file" 2> /dev/null || true

        builtin kill -TERM -- "-$__base_bash_libs_std_timeout_watchdog_command_pid" \
            2> /dev/null || true
        __base_bash_libs_std_sleep_interval__ 1 || true
        builtin kill -KILL -- "-$__base_bash_libs_std_timeout_watchdog_command_pid" \
            2> /dev/null || true
    fi
    return "$__base_bash_libs_std_timeout_watchdog_final_status"
}

__base_bash_libs_std_timeout_emit_error__() {
    local __base_bash_libs_std_timeout_error_message="$1"
    builtin printf 'base-bash-libs: TIMEOUT ERROR: %s\n' \
        "$__base_bash_libs_std_timeout_error_message" >&2 || true
}

__base_bash_libs_std_timeout_mkfifo_path__() {
    (($# == 1)) || return 1
    local __base_bash_libs_std_timeout_mkfifo_result_name="$1"
    local __base_bash_libs_std_timeout_mkfifo_candidate=""
    for __base_bash_libs_std_timeout_mkfifo_candidate in /usr/bin/mkfifo /bin/mkfifo; do
        if [[ -x "$__base_bash_libs_std_timeout_mkfifo_candidate" ]]; then
            printf -v "$__base_bash_libs_std_timeout_mkfifo_result_name" '%s' \
                "$__base_bash_libs_std_timeout_mkfifo_candidate"
            return 0
        fi
    done
    printf -v "$__base_bash_libs_std_timeout_mkfifo_result_name" '%s' ""
    return 1
}

__base_bash_libs_std_timeout_chmod_path__() {
    (($# == 1)) || return 1
    local __base_bash_libs_std_timeout_chmod_result_name="$1"
    local __base_bash_libs_std_timeout_chmod_candidate=""
    for __base_bash_libs_std_timeout_chmod_candidate in /usr/bin/chmod /bin/chmod; do
        if [[ -x "$__base_bash_libs_std_timeout_chmod_candidate" ]]; then
            printf -v "$__base_bash_libs_std_timeout_chmod_result_name" '%s' \
                "$__base_bash_libs_std_timeout_chmod_candidate"
            return 0
        fi
    done
    printf -v "$__base_bash_libs_std_timeout_chmod_result_name" '%s' ""
    return 1
}

__base_bash_libs_std_run_with_timeout_supervisor__() {
    local __base_bash_libs_std_timeout_outcome_result_name="$1"
    local __base_bash_libs_std_timeout_seconds="$2" __base_bash_libs_std_timeout_path="$3"
    shift 3
    local __base_bash_libs_std_timeout_final_status=125 __base_bash_libs_std_timeout_outcome=infrastructure
    local __base_bash_libs_std_timeout_fifo="" __base_bash_libs_std_timeout_status_fifo=""
    local __base_bash_libs_std_timeout_status_file=""
    local __base_bash_libs_std_timeout_timer_status_file=""
    local __base_bash_libs_std_timeout_mkfifo_path="" __base_bash_libs_std_timeout_chmod_path=""
    local __base_bash_libs_std_timeout_timer_fd="" __base_bash_libs_std_timeout_status_fd=""
    local __base_bash_libs_std_timeout_stderr_fd=""
    local __base_bash_libs_std_timeout_has_stdin=0
    local __base_bash_libs_std_timeout_command_pid="" __base_bash_libs_std_timeout_timer_pid=""
    local __base_bash_libs_std_timeout_timer_status=125 __base_bash_libs_std_timeout_run_status=125
    local __base_bash_libs_std_timeout_child_status="" __base_bash_libs_std_timeout_status_record=""
    local __base_bash_libs_std_timeout_timer_early_status="" __base_bash_libs_std_timeout_timer_status_record=""
    local __base_bash_libs_std_timeout_release_byte=""
    local __base_bash_libs_std_timeout_cancel_status=0 __base_bash_libs_std_timeout_cancel_signal=""
    local __base_bash_libs_std_timeout_saved_hup_trap __base_bash_libs_std_timeout_saved_int_trap
    local __base_bash_libs_std_timeout_saved_quit_trap __base_bash_libs_std_timeout_saved_term_trap
    local __base_bash_libs_std_timeout_hup_ignored=0 __base_bash_libs_std_timeout_int_ignored=0
    local __base_bash_libs_std_timeout_quit_ignored=0 __base_bash_libs_std_timeout_term_ignored=0
    local __base_bash_libs_std_timeout_monitor_was_enabled=0
    local __base_bash_libs_std_timeout_setup_failed=0
    local -a __base_bash_libs_std_timeout_command_argv=("$@")

    if (($# == 0)); then
        __base_bash_libs_std_timeout_emit_error__ "no command was provided."
        printf -v "$__base_bash_libs_std_timeout_outcome_result_name" '%s' infrastructure
        return 125
    fi
    if [[ -t 0 ]]; then
        __base_bash_libs_std_timeout_emit_error__ \
            "timed commands require non-terminal stdin; redirect stdin from a pipe or /dev/null."
        printf -v "$__base_bash_libs_std_timeout_outcome_result_name" '%s' infrastructure
        return 125
    fi

    if ! __base_bash_libs_std_make_internal_temp_file__ --keep \
        __base_bash_libs_std_timeout_fifo base-bash-libs-timeout-clock; then
        printf -v "$__base_bash_libs_std_timeout_outcome_result_name" '%s' infrastructure
        __base_bash_libs_std_timeout_emit_error__ "could not allocate the private timeout clock channel."
        return 125
    fi
    __base_bash_libs_std_make_internal_temp_file__ --keep \
        __base_bash_libs_std_timeout_status_fifo base-bash-libs-timeout-status || {
        rm -f -- "$__base_bash_libs_std_timeout_fifo"
        printf -v "$__base_bash_libs_std_timeout_outcome_result_name" '%s' infrastructure
        __base_bash_libs_std_timeout_emit_error__ "could not allocate the private timeout status channel."
        return 125
    }
    if ! __base_bash_libs_std_make_internal_temp_file__ --keep \
        __base_bash_libs_std_timeout_status_file base-bash-libs-timeout-status-record; then
        rm -f -- "$__base_bash_libs_std_timeout_fifo" "$__base_bash_libs_std_timeout_status_fifo"
        printf -v "$__base_bash_libs_std_timeout_outcome_result_name" '%s' infrastructure
        __base_bash_libs_std_timeout_emit_error__ "could not allocate the private timeout status record."
        return 125
    fi
    if ! __base_bash_libs_std_make_internal_temp_file__ --keep \
        __base_bash_libs_std_timeout_timer_status_file base-bash-libs-timeout-timer-record; then
        rm -f -- "$__base_bash_libs_std_timeout_fifo" "$__base_bash_libs_std_timeout_status_fifo" \
            "$__base_bash_libs_std_timeout_status_file"
        printf -v "$__base_bash_libs_std_timeout_outcome_result_name" '%s' infrastructure
        __base_bash_libs_std_timeout_emit_error__ "could not allocate the private timeout timer record."
        return 125
    fi
    if ! __base_bash_libs_std_timeout_mkfifo_path__ __base_bash_libs_std_timeout_mkfifo_path ||
        ! __base_bash_libs_std_timeout_chmod_path__ __base_bash_libs_std_timeout_chmod_path ||
        ! rm -f -- "$__base_bash_libs_std_timeout_fifo" "$__base_bash_libs_std_timeout_status_fifo" 2> /dev/null ||
        ! "$__base_bash_libs_std_timeout_mkfifo_path" "$__base_bash_libs_std_timeout_fifo" \
            "$__base_bash_libs_std_timeout_status_fifo" \
            2> /dev/null ||
        ! "$__base_bash_libs_std_timeout_chmod_path" 600 "$__base_bash_libs_std_timeout_fifo" \
            "$__base_bash_libs_std_timeout_status_fifo" "$__base_bash_libs_std_timeout_status_file" \
            "$__base_bash_libs_std_timeout_timer_status_file" \
            2> /dev/null ||
        ! exec {__base_bash_libs_std_timeout_timer_fd}<> "$__base_bash_libs_std_timeout_fifo" ||
        ! exec {__base_bash_libs_std_timeout_status_fd}<> "$__base_bash_libs_std_timeout_status_fifo"; then
        rm -f -- "$__base_bash_libs_std_timeout_fifo" "$__base_bash_libs_std_timeout_status_fifo" \
            "$__base_bash_libs_std_timeout_status_file" "$__base_bash_libs_std_timeout_timer_status_file"
        __base_bash_libs_std_timeout_emit_error__ "could not create the private timeout control channels."
        printf -v "$__base_bash_libs_std_timeout_outcome_result_name" '%s' infrastructure
        return 125
    fi

    if [[ -e /dev/fd/0 ]]; then
        __base_bash_libs_std_timeout_has_stdin=1
    fi
    if ((__base_bash_libs_std_timeout_setup_failed)); then
        exec {__base_bash_libs_std_timeout_timer_fd}>&-
        exec {__base_bash_libs_std_timeout_status_fd}>&-
        rm -f -- "$__base_bash_libs_std_timeout_fifo" "$__base_bash_libs_std_timeout_status_fifo" \
            "$__base_bash_libs_std_timeout_status_file" "$__base_bash_libs_std_timeout_timer_status_file"
        __base_bash_libs_std_timeout_emit_error__ "could not preserve command stdin."
        printf -v "$__base_bash_libs_std_timeout_outcome_result_name" '%s' infrastructure
        return 125
    fi

    [[ $- == *m* ]] && __base_bash_libs_std_timeout_monitor_was_enabled=1
    __base_bash_libs_std_timeout_saved_hup_trap="$(trap -p HUP || true)"
    __base_bash_libs_std_timeout_saved_int_trap="$(trap -p INT || true)"
    __base_bash_libs_std_timeout_saved_quit_trap="$(trap -p QUIT || true)"
    __base_bash_libs_std_timeout_saved_term_trap="$(trap -p TERM || true)"
    [[ "$__base_bash_libs_std_timeout_saved_hup_trap" == *"'' SIGHUP" ||
        "$__base_bash_libs_std_timeout_saved_hup_trap" == *"'' HUP" ]] &&
        __base_bash_libs_std_timeout_hup_ignored=1
    [[ "$__base_bash_libs_std_timeout_saved_int_trap" == *"'' SIGINT" ||
        "$__base_bash_libs_std_timeout_saved_int_trap" == *"'' INT" ]] &&
        __base_bash_libs_std_timeout_int_ignored=1
    [[ "$__base_bash_libs_std_timeout_saved_quit_trap" == *"'' SIGQUIT" ||
        "$__base_bash_libs_std_timeout_saved_quit_trap" == *"'' QUIT" ]] &&
        __base_bash_libs_std_timeout_quit_ignored=1
    [[ "$__base_bash_libs_std_timeout_saved_term_trap" == *"'' SIGTERM" ||
        "$__base_bash_libs_std_timeout_saved_term_trap" == *"'' TERM" ]] &&
        __base_bash_libs_std_timeout_term_ignored=1

    if ((__base_bash_libs_std_timeout_hup_ignored)); then trap '' HUP; else trap '__base_bash_libs_std_timeout_latch_cancel__ HUP 129' HUP; fi
    if ((__base_bash_libs_std_timeout_int_ignored)); then trap '' INT; else trap '__base_bash_libs_std_timeout_latch_cancel__ INT 130' INT; fi
    if ((__base_bash_libs_std_timeout_quit_ignored)); then trap '' QUIT; else trap '__base_bash_libs_std_timeout_latch_cancel__ QUIT 131' QUIT; fi
    if ((__base_bash_libs_std_timeout_term_ignored)); then trap '' TERM; else trap '__base_bash_libs_std_timeout_latch_cancel__ TERM 143' TERM; fi

    if ! set -m; then
        __base_bash_libs_std_timeout_setup_failed=1
    else
        if ! exec {__base_bash_libs_std_timeout_stderr_fd}>&2; then
            __base_bash_libs_std_timeout_setup_failed=1
        else
            if ((__base_bash_libs_std_timeout_has_stdin)); then
                __base_bash_libs_std_timeout_command_wrapper__ <&0 2> /dev/null &
            else
                __base_bash_libs_std_timeout_command_wrapper__ <&- 2> /dev/null &
            fi
            __base_bash_libs_std_timeout_command_pid=$!
            __base_bash_libs_std_timeout_watchdog__ "$__base_bash_libs_std_timeout_seconds" \
                "$__base_bash_libs_std_timeout_path" "$__base_bash_libs_std_timeout_timer_fd" \
                "$__base_bash_libs_std_timeout_command_pid" \
                "$__base_bash_libs_std_timeout_timer_status_file" 2> /dev/null &
            __base_bash_libs_std_timeout_timer_pid=$!
            # Remove the process-group sentinel from Bash's job table before
            # escalation. Its terminal status is carried by the private
            # record, so no job-table wait is needed and Bash cannot leak a
            # `Killed: 9` notification when the group is deliberately killed.
            builtin disown "$__base_bash_libs_std_timeout_command_pid" 2> /dev/null || true
            # Both asynchronous jobs already have their isolated process
            # groups. Disable monitor notifications while they are reaped.
            set +m
        fi
    fi

    if ((__base_bash_libs_std_timeout_setup_failed)); then
        __base_bash_libs_std_timeout_emit_error__ "could not enable isolated process-group supervision."
        if [[ -n "$__base_bash_libs_std_timeout_command_pid" ]]; then
            builtin kill -KILL -- "-$__base_bash_libs_std_timeout_command_pid" \
                2> /dev/null || true
            wait "$__base_bash_libs_std_timeout_command_pid" 2> /dev/null || true
        fi
        if [[ -n "$__base_bash_libs_std_timeout_timer_pid" ]]; then
            builtin kill -KILL -- "-$__base_bash_libs_std_timeout_timer_pid" \
                2> /dev/null || true
            wait "$__base_bash_libs_std_timeout_timer_pid" 2> /dev/null || true
        fi
    else
        while [[ -z "$__base_bash_libs_std_timeout_child_status" &&
            -z "$__base_bash_libs_std_timeout_timer_early_status" &&
            "$__base_bash_libs_std_timeout_cancel_status" == 0 ]]; do
            if [[ -s "$__base_bash_libs_std_timeout_timer_status_file" ]]; then
                __base_bash_libs_std_timeout_timer_status_record="$(< "$__base_bash_libs_std_timeout_timer_status_file")"
                case "$__base_bash_libs_std_timeout_timer_status_record" in
                T[0-9][0-9][0-9])
                    __base_bash_libs_std_timeout_timer_early_status="$((10#${__base_bash_libs_std_timeout_timer_status_record:1}))"
                    break
                    ;;
                esac
            fi
            if [[ -s "$__base_bash_libs_std_timeout_status_file" ]]; then
                __base_bash_libs_std_timeout_status_record="$(< "$__base_bash_libs_std_timeout_status_file")"
                if [[ "$__base_bash_libs_std_timeout_status_record" =~ ^S[0-9]{3}$ ]]; then
                    __base_bash_libs_std_timeout_child_status="$((10#${__base_bash_libs_std_timeout_status_record:1}))"
                    break
                fi
            fi
            builtin kill -0 "$__base_bash_libs_std_timeout_command_pid" 2> /dev/null ||
                break
            __base_bash_libs_std_sleep_interval__ 0.01 || true
        done

        if ((__base_bash_libs_std_timeout_cancel_status != 0)); then
            { builtin printf 'x' >&"$__base_bash_libs_std_timeout_timer_fd"; } 2> /dev/null || true
            if wait "$__base_bash_libs_std_timeout_timer_pid" 2> /dev/null; then
                __base_bash_libs_std_timeout_timer_status=0
            else
                __base_bash_libs_std_timeout_timer_status=$?
            fi
            if [[ -z "$__base_bash_libs_std_timeout_child_status" &&
                -s "$__base_bash_libs_std_timeout_status_file" ]]; then
                __base_bash_libs_std_timeout_status_record="$(< "$__base_bash_libs_std_timeout_status_file")"
                case "$__base_bash_libs_std_timeout_status_record" in
                S[0-9][0-9][0-9])
                    __base_bash_libs_std_timeout_child_status="$((10#${__base_bash_libs_std_timeout_status_record:1}))"
                    ;;
                esac
            fi
            if [[ -z "$__base_bash_libs_std_timeout_child_status" &&
                -n "$__base_bash_libs_std_timeout_timer_early_status" ]]; then
                __base_bash_libs_std_timeout_timer_status="$__base_bash_libs_std_timeout_timer_early_status"
            fi
            __base_bash_libs_std_sleep_interval__ 1 || true
            builtin kill -KILL -- "-$__base_bash_libs_std_timeout_command_pid" \
                2> /dev/null || true
            wait "$__base_bash_libs_std_timeout_command_pid" 2> /dev/null || true
            __base_bash_libs_std_timeout_final_status="$__base_bash_libs_std_timeout_cancel_status"
            __base_bash_libs_std_timeout_outcome=interrupted
        else
            { builtin printf 'x' >&"$__base_bash_libs_std_timeout_timer_fd"; } 2> /dev/null || true
            if wait "$__base_bash_libs_std_timeout_timer_pid" 2> /dev/null; then
                __base_bash_libs_std_timeout_timer_status=0
            else
                __base_bash_libs_std_timeout_timer_status=$?
            fi
            if [[ -z "$__base_bash_libs_std_timeout_child_status" &&
                -s "$__base_bash_libs_std_timeout_status_file" ]]; then
                __base_bash_libs_std_timeout_status_record="$(< "$__base_bash_libs_std_timeout_status_file")"
                case "$__base_bash_libs_std_timeout_status_record" in
                S[0-9][0-9][0-9])
                    __base_bash_libs_std_timeout_child_status="$((10#${__base_bash_libs_std_timeout_status_record:1}))"
                    ;;
                esac
            fi
            if [[ -z "$__base_bash_libs_std_timeout_child_status" &&
                -n "$__base_bash_libs_std_timeout_timer_early_status" ]]; then
                __base_bash_libs_std_timeout_timer_status="$__base_bash_libs_std_timeout_timer_early_status"
            fi
            if [[ -n "$__base_bash_libs_std_timeout_cancel_signal" ]]; then
                __base_bash_libs_std_timeout_final_status="$__base_bash_libs_std_timeout_cancel_status"
                __base_bash_libs_std_timeout_outcome=interrupted
            elif [[ -n "$__base_bash_libs_std_timeout_child_status" ]]; then
                # The private status record is written only by the wrapper as
                # S%03d from Bash's wait status, so a non-empty record is
                # already constrained to the command's 0..255 exit range.
                __base_bash_libs_std_timeout_run_status="$__base_bash_libs_std_timeout_child_status"
                case "$__base_bash_libs_std_timeout_timer_status" in
                0)
                    __base_bash_libs_std_timeout_final_status="$__base_bash_libs_std_timeout_run_status"
                    __base_bash_libs_std_timeout_outcome="command"
                    ;;
                124)
                    __base_bash_libs_std_timeout_final_status=124
                    __base_bash_libs_std_timeout_outcome=timeout
                    ;;
                125)
                    # A command that has already published a terminal
                    # status completed before the deadline clock was
                    # canceled.  Preserve that command result even when
                    # an older Bash/coreutils combination reports the
                    # canceled clock as an infrastructure failure.
                    if ((__base_bash_libs_std_timeout_run_status == 137 || \
                        __base_bash_libs_std_timeout_run_status == 143)); then
                        # These are the wrapper statuses produced when an
                        # external clock fails and escalates the group.
                        # Do not expose the wrapper's signal status as a
                        # natural command result.
                        __base_bash_libs_std_timeout_final_status=125
                        __base_bash_libs_std_timeout_outcome=infrastructure
                    else
                        __base_bash_libs_std_timeout_final_status="$__base_bash_libs_std_timeout_run_status"
                        __base_bash_libs_std_timeout_outcome="command"
                    fi
                    ;;
                *)
                    __base_bash_libs_std_timeout_final_status=125
                    __base_bash_libs_std_timeout_outcome=infrastructure
                    ;;
                esac
            else
                case "$__base_bash_libs_std_timeout_timer_status" in
                124)
                    __base_bash_libs_std_timeout_final_status=124
                    __base_bash_libs_std_timeout_outcome=timeout
                    ;;
                *)
                    __base_bash_libs_std_timeout_final_status=125
                    __base_bash_libs_std_timeout_outcome=infrastructure
                    ;;
                esac
            fi
        fi
        { builtin printf 'x' >&"$__base_bash_libs_std_timeout_status_fd"; } 2> /dev/null || true
        wait "$__base_bash_libs_std_timeout_command_pid" 2> /dev/null || true
    fi

    exec {__base_bash_libs_std_timeout_timer_fd}>&-
    exec {__base_bash_libs_std_timeout_status_fd}>&-
    if [[ -n "$__base_bash_libs_std_timeout_stderr_fd" ]]; then
        exec {__base_bash_libs_std_timeout_stderr_fd}>&-
    fi
    rm -f -- "$__base_bash_libs_std_timeout_fifo" "$__base_bash_libs_std_timeout_status_fifo" \
        "$__base_bash_libs_std_timeout_status_file" "$__base_bash_libs_std_timeout_timer_status_file"

    if ((__base_bash_libs_std_timeout_monitor_was_enabled)); then
        set -m
    else
        set +m
    fi
    # Restore each saved disposition directly. Resetting all four signals to
    # their defaults first creates a small window in which a caller's ignored
    # TERM (or a signal queued during cleanup) can kill the supervising shell.
    # An empty saved trap is the only case that needs the default disposition.
    if [[ -n "$__base_bash_libs_std_timeout_saved_hup_trap" ]]; then
        eval "$__base_bash_libs_std_timeout_saved_hup_trap"
    else
        trap - HUP
    fi
    if [[ -n "$__base_bash_libs_std_timeout_saved_int_trap" ]]; then
        eval "$__base_bash_libs_std_timeout_saved_int_trap"
    else
        trap - INT
    fi
    if [[ -n "$__base_bash_libs_std_timeout_saved_quit_trap" ]]; then
        eval "$__base_bash_libs_std_timeout_saved_quit_trap"
    else
        trap - QUIT
    fi
    if [[ -n "$__base_bash_libs_std_timeout_saved_term_trap" ]]; then
        eval "$__base_bash_libs_std_timeout_saved_term_trap"
    else
        trap - TERM
    fi

    printf -v "$__base_bash_libs_std_timeout_outcome_result_name" '%s' \
        "$__base_bash_libs_std_timeout_outcome"
    if [[ -n "$__base_bash_libs_std_timeout_cancel_signal" ]]; then
        builtin kill "-$__base_bash_libs_std_timeout_cancel_signal" "$BASHPID" \
            2> /dev/null || true
    fi
    return "$__base_bash_libs_std_timeout_final_status"
}

__base_bash_libs_std_run_with_timeout_fallback__() {
    local __base_bash_libs_std_timeout_fallback_seconds="$1"
    shift
    local __base_bash_libs_std_timeout_fallback_outcome=command
    __base_bash_libs_std_run_with_timeout_supervisor__ __base_bash_libs_std_timeout_fallback_outcome \
        "$__base_bash_libs_std_timeout_fallback_seconds" "" "$@"
}
############################################## FILE AND DIRECTORY HANDLING ############################################

#
# base_std_safe_mkdir: Attempt to create directories and return on failure.
#             Creates as many directories as possible.
#
# Usage: base_std_safe_mkdir [-p] dir1 dir2 ...
#
base_std_safe_mkdir() {
    local dir opt failed_dirs=() mkdir_args=()
    local OPTIND=1

    while getopts ":p" opt; do
        case "$opt" in
        p) mkdir_args=(-p) ;;
        \?)
            base_std_log_error -l base_bash_libs.std "base_std_safe_mkdir: invalid option '-$OPTARG'"
            return 1
            ;;
        esac
    done
    shift $((OPTIND - 1))

    if (($# == 0)); then
        base_std_log_warn -l base_bash_libs.std "base_std_safe_mkdir: No directories provided to create."
        return 0
    fi

    for dir; do
        [[ -d "$dir" ]] && continue
        if ! mkdir "${mkdir_args[@]+"${mkdir_args[@]}"}" -- "$dir"; then
            failed_dirs+=("$dir")
        fi
    done
    if [[ -n "${failed_dirs[0]+set}" ]]; then
        base_std_log_error -l base_bash_libs.std "Failed to create directories: ${failed_dirs[*]}"
        return 1
    fi
    return 0
}

#
# base_std_safe_touch - Creates or updates the timestamp of one or more files.
#
# This function iterates through all provided file paths. It attempts to
# 'touch' each file. If any operation fails (e.g., due to permissions),
# it collects the names of the failed files and reports them all before returning.
#
# Usage:
#   base_std_safe_touch "/tmp/file1.log" "/var/run/app.pid"
#
# Arguments:
#   $@: One or more file paths to touch.
#
base_std_safe_touch() {
    local failed_files=()
    local file touch_path

    if (($# == 0)); then
        base_std_log_warn -l base_bash_libs.std "base_std_safe_touch: No files provided to touch."
        return 0
    fi

    for file; do
        touch_path="$file"
        [[ "$touch_path" == -* ]] && touch_path="./$touch_path"
        if ! touch "$touch_path" 2> /dev/null; then
            failed_files+=("$file")
        fi
    done

    if [[ -n "${failed_files[0]+set}" ]]; then
        base_std_log_error -l base_bash_libs.std \
            "Failed to touch the following files: ${failed_files[*]}"
        return 1
    fi

    return 0
}

#
# base_std_safe_truncate - Truncates one or more files to zero bytes.
#
# This function iterates through all provided file paths. It attempts to
# truncate each file. If any operation fails (e.g., due to permissions),
# it collects the names of the failed files and reports them all before returning.
#
# Usage:
#   base_std_safe_truncate "/var/log/app.log" "/tmp/data.tmp"
#
# Arguments:
#   $@: One or more file paths to truncate.
#
base_std_safe_truncate() {
    local failed_files=()
    local file

    if (($# == 0)); then
        base_std_log_warn -l base_bash_libs.std "base_std_safe_truncate: No files provided to truncate."
        return 0
    fi

    for file; do
        # The > redirection is the simplest way to truncate a file.
        # We redirect stderr to /dev/null to suppress system error messages,
        # as we will provide our own comprehensive error message.
        if ! : > "$file" 2> /dev/null; then
            failed_files+=("$file")
        fi
    done

    if [[ -n "${failed_files[0]+set}" ]]; then
        base_std_log_error -l base_bash_libs.std \
            "Failed to truncate the following files: ${failed_files[*]}"
        return 1
    fi

    return 0
}

######################################################## CLEANUP #######################################################

__base_bash_libs_std_return_status__() {
    return "$1"
}

__base_bash_libs_std_get_trap_command__() {
    local result_name="${1-}" signal="${2-}" trap_name trap_spec=""
    local trap_prefix="trap -- '" trap_suffix

    case "$signal" in
    EXIT | DEBUG)
        trap_name="$signal"
        ;;
    INT | TERM)
        trap_name="SIG$signal"
        ;;
    *)
        printf -v "$result_name" '%s' ""
        return 1
        ;;
    esac

    trap_suffix="' $trap_name"
    trap_spec="$(trap -p "$signal" || true)"
    if [[ "$trap_spec" == "$trap_prefix"*"$trap_suffix" ]]; then
        trap_spec="${trap_spec#"$trap_prefix"}"
        trap_spec="${trap_spec%"$trap_suffix"}"
        printf -v "$result_name" '%s' "$trap_spec"
    else
        printf -v "$result_name" '%s' ""
    fi
}

__base_bash_libs_std_get_exit_trap_command__() {
    __base_bash_libs_std_get_trap_command__ "$1" EXIT
}

__base_bash_libs_std_restore_trap_spec__() {
    local signal="$1" trap_spec="$2"

    if [[ -n "$trap_spec" ]]; then
        eval "$trap_spec"
    else
        trap - "$signal"
    fi
}

__base_bash_libs_std_run_saved_trap_command__() {
    local trap_command="$1" exit_status="$2"

    [[ -n "$trap_command" ]] || return 0
    (
        __base_bash_libs_std_return_status__ "$exit_status"
        eval "$trap_command"
    ) || true
}

__base_bash_libs_std_stat_path_identity__() {
    local result_name="$1" path="$2" stat_identity

    if stat_identity="$(stat -c '%d:%i' -- "$path" 2> /dev/null)"; then
        printf -v "$result_name" '%s' "$stat_identity"
        return 0
    fi
    if stat_identity="$(stat -f '%d:%i' -- "$path" 2> /dev/null)"; then
        printf -v "$result_name" '%s' "$stat_identity"
        return 0
    fi
    return 1
}

__base_bash_libs_std_capture_cleanup_path_fingerprint__() {
    local result_name="$1" path="$2" current="$2" component_identity path_fingerprint=""

    [[ -e "$path" || -L "$path" ]] || return 1
    while :; do
        __base_bash_libs_std_stat_path_identity__ component_identity "$current" || return 1
        path_fingerprint+="$current"$'\t'"$component_identity"$'\n'
        [[ "$current" == "/" ]] && break
        current="$(dirname -- "$current")" || return 1
    done

    printf -v "$result_name" '%s' "$path_fingerprint"
}

__base_bash_libs_std_cleanup_path_fingerprint_matches__() {
    local path="$1" fingerprint="${__base_bash_libs_std_cleanup_path_fingerprints[$1]-}"
    local expected_path expected_identity actual_identity

    [[ -n "$fingerprint" && "$fingerprint" != UNSAFE ]] || return 1
    while IFS=$'\t' read -r expected_path expected_identity; do
        [[ -n "$expected_path" ]] || continue
        __base_bash_libs_std_stat_path_identity__ actual_identity "$expected_path" || return 1
        [[ "$actual_identity" == "$expected_identity" ]] || return 1
    done <<< "$fingerprint"
}

__base_bash_libs_std_cleanup_delete_path__() {
    local cleanup_path="$1"
    local fingerprint="${__base_bash_libs_std_cleanup_path_fingerprints[$cleanup_path]-}"

    [[ -e "$cleanup_path" || -L "$cleanup_path" ]] || return 0
    if [[ "$fingerprint" != UNSAFE ]] &&
        ! __base_bash_libs_std_cleanup_path_fingerprint_matches__ "$cleanup_path"; then
        base_std_log_warn -l base_bash_libs.std "Cleanup path '$cleanup_path' changed identity; refusing to remove it."
        return 1
    fi
    if [[ "$fingerprint" == UNSAFE ]]; then
        base_std_log_warn -l base_bash_libs.std "Removing explicitly unsafe cleanup path '$cleanup_path'."
    fi
    if ! rm -rf -- "$cleanup_path"; then
        base_std_log_warn -l base_bash_libs.std "Cleanup path '$cleanup_path' could not be removed."
        return 1
    fi
    return 0
}

__base_bash_libs_std_cleanup_refresh_signal_traps__() {
    local current_int_trap current_term_trap

    current_int_trap="$(trap -p INT || true)"
    if [[ "$current_int_trap" != "$__base_bash_libs_std_cleanup_int_trap_spec" ]]; then
        __base_bash_libs_std_original_int_trap_spec="$current_int_trap"
        __base_bash_libs_std_get_trap_command__ __base_bash_libs_std_original_int_trap INT || true
        if [[ -n "$current_int_trap" && -z "$__base_bash_libs_std_original_int_trap" ]]; then
            __base_bash_libs_std_cleanup_int_trap_spec="$current_int_trap"
        else
            trap '__base_bash_libs_std_cleanup_signal_exit__ INT 130' INT
            __base_bash_libs_std_cleanup_int_trap_spec="$(trap -p INT || true)"
        fi
    fi

    current_term_trap="$(trap -p TERM || true)"
    if [[ "$current_term_trap" != "$__base_bash_libs_std_cleanup_term_trap_spec" ]]; then
        __base_bash_libs_std_original_term_trap_spec="$current_term_trap"
        __base_bash_libs_std_get_trap_command__ __base_bash_libs_std_original_term_trap TERM || true
        if [[ -n "$current_term_trap" && -z "$__base_bash_libs_std_original_term_trap" ]]; then
            __base_bash_libs_std_cleanup_term_trap_spec="$current_term_trap"
        else
            trap '__base_bash_libs_std_cleanup_signal_exit__ TERM 143' TERM
            __base_bash_libs_std_cleanup_term_trap_spec="$(trap -p TERM || true)"
        fi
    fi
}

__base_bash_libs_std_cleanup_refresh_traps__() {
    local current_exit_trap

    ((__base_bash_libs_std_cleanup_dispatcher_installed)) || return 0
    current_exit_trap="$(trap -p EXIT || true)"
    if [[ "$current_exit_trap" != "$__base_bash_libs_std_cleanup_dispatcher_trap_spec" ]]; then
        __base_bash_libs_std_original_exit_trap_spec="$current_exit_trap"
        __base_bash_libs_std_get_exit_trap_command__ __base_bash_libs_std_original_exit_trap || true
        trap '__base_bash_libs_std_run_cleanup_hooks__' EXIT
        __base_bash_libs_std_cleanup_dispatcher_trap_spec="$(trap -p EXIT || true)"
    fi
    __base_bash_libs_std_cleanup_refresh_signal_traps__
}

__base_bash_libs_std_cleanup_debug_guard__() {
    local current_debug_status=$?

    ((current_debug_status)) && :
    ((__base_bash_libs_std_cleanup_dispatcher_installed)) || return 0
    ((__base_bash_libs_std_cleanup_debug_guard_running)) && return 0
    __base_bash_libs_std_cleanup_debug_guard_running=1

    if [[ -n "$__base_bash_libs_std_original_debug_trap" ]]; then
        (eval "$__base_bash_libs_std_original_debug_trap") || true
    fi
    __base_bash_libs_std_cleanup_refresh_traps__
    __base_bash_libs_std_cleanup_debug_guard_running=0
    return 0
}

__base_bash_libs_std_cleanup_signal_exit__() {
    local signal="$1" exit_status="$2"

    case "$signal" in
    INT)
        __base_bash_libs_std_run_saved_trap_command__ "$__base_bash_libs_std_original_int_trap" "$exit_status"
        ;;
    TERM)
        __base_bash_libs_std_run_saved_trap_command__ "$__base_bash_libs_std_original_term_trap" "$exit_status"
        ;;
    esac

    if ((__base_bash_libs_std_cleanup_dispatcher_running)); then
        __base_bash_libs_std_cleanup_pending_signal_status="$exit_status"
        return 0
    fi
    exit "$exit_status"
}

__base_bash_libs_std_run_cleanup_hooks__() {
    local exit_status=$? entry entry_type entry_value index

    ((__base_bash_libs_std_cleanup_dispatcher_finished)) && return "$exit_status"
    ((__base_bash_libs_std_cleanup_dispatcher_running)) && return "$exit_status"
    __base_bash_libs_std_cleanup_dispatcher_running=1
    trap - DEBUG

    if [[ -n "${__base_bash_libs_std_original_exit_trap:-}" ]]; then
        __base_bash_libs_std_run_saved_trap_command__ "$__base_bash_libs_std_original_exit_trap" "$exit_status"
    fi

    for ((index = ${#__base_bash_libs_std_cleanup_entries[@]} - 1; index >= 0; index--)); do
        entry="${__base_bash_libs_std_cleanup_entries[index]}"
        entry_type="${entry%%:*}"
        entry_value="${entry#*:}"
        case "$entry_type" in
        hook)
            if ! "$entry_value"; then
                base_std_log_warn -l base_bash_libs.std "Cleanup hook '$entry_value' failed."
            fi
            ;;
        path)
            __base_bash_libs_std_cleanup_delete_path__ "$entry_value" || true
            ;;
        esac
    done

    if ((__base_bash_libs_std_cleanup_pending_signal_status)); then
        exit_status="$__base_bash_libs_std_cleanup_pending_signal_status"
    fi
    __base_bash_libs_std_cleanup_dispatcher_finished=1
    __base_bash_libs_std_cleanup_dispatcher_running=0
    if ((__base_bash_libs_std_cleanup_pending_signal_status)); then
        exit "$exit_status"
    fi
    return "$exit_status" 2> /dev/null || exit "$exit_status"
}

__base_bash_libs_std_install_cleanup_dispatcher__() {
    if ((__base_bash_libs_std_cleanup_dispatcher_installed)); then
        return 0
    fi

    __base_bash_libs_std_cleanup_dispatcher_running=0
    __base_bash_libs_std_cleanup_dispatcher_finished=0
    __base_bash_libs_std_cleanup_pending_signal_status=0
    __base_bash_libs_std_original_exit_trap_spec="$(trap -p EXIT || true)"
    __base_bash_libs_std_get_exit_trap_command__ __base_bash_libs_std_original_exit_trap
    __base_bash_libs_std_original_int_trap_spec="$(trap -p INT || true)"
    __base_bash_libs_std_get_trap_command__ __base_bash_libs_std_original_int_trap INT || true
    __base_bash_libs_std_original_term_trap_spec="$(trap -p TERM || true)"
    __base_bash_libs_std_get_trap_command__ __base_bash_libs_std_original_term_trap TERM || true
    __base_bash_libs_std_original_debug_trap_spec="$(trap -p DEBUG || true)"
    __base_bash_libs_std_get_trap_command__ __base_bash_libs_std_original_debug_trap DEBUG || true
    __base_bash_libs_std_cleanup_int_trap_spec="__not-installed__"
    __base_bash_libs_std_cleanup_term_trap_spec="__not-installed__"
    __base_bash_libs_std_cleanup_debug_trap_spec="__not-installed__"
    trap '__base_bash_libs_std_run_cleanup_hooks__' EXIT
    __base_bash_libs_std_cleanup_dispatcher_trap_spec="$(trap -p EXIT || true)"
    trap '__base_bash_libs_std_cleanup_debug_guard__' DEBUG
    __base_bash_libs_std_cleanup_debug_trap_spec="$(trap -p DEBUG || true)"
    __base_bash_libs_std_cleanup_dispatcher_installed=1
    __base_bash_libs_std_cleanup_refresh_signal_traps__
    return 0
}

__base_bash_libs_std_maybe_uninstall_cleanup_dispatcher__() {
    local current_exit_trap_spec current_int_trap_spec
    local current_term_trap_spec current_debug_trap_spec

    ((__base_bash_libs_std_cleanup_dispatcher_installed)) || return 0
    if ((${#__base_bash_libs_std_cleanup_entries[@]})); then
        return 0
    fi

    __base_bash_libs_std_cleanup_debug_guard_running=1
    current_exit_trap_spec="$(trap -p EXIT || true)"
    if [[ "$current_exit_trap_spec" == "$__base_bash_libs_std_cleanup_dispatcher_trap_spec" ]]; then
        trap - EXIT
        __base_bash_libs_std_restore_trap_spec__ EXIT "$__base_bash_libs_std_original_exit_trap_spec"
    fi
    current_int_trap_spec="$(trap -p INT || true)"
    if [[ "$current_int_trap_spec" == "$__base_bash_libs_std_cleanup_int_trap_spec" ]]; then
        __base_bash_libs_std_restore_trap_spec__ INT "$__base_bash_libs_std_original_int_trap_spec"
    fi
    current_term_trap_spec="$(trap -p TERM || true)"
    if [[ "$current_term_trap_spec" == "$__base_bash_libs_std_cleanup_term_trap_spec" ]]; then
        __base_bash_libs_std_restore_trap_spec__ TERM "$__base_bash_libs_std_original_term_trap_spec"
    fi
    current_debug_trap_spec="$(trap -p DEBUG || true)"
    if [[ "$current_debug_trap_spec" == "$__base_bash_libs_std_cleanup_debug_trap_spec" ||
        "$current_debug_trap_spec" == *"__base_bash_libs_std_cleanup_debug_guard__"* ]]; then
        __base_bash_libs_std_restore_trap_spec__ DEBUG "$__base_bash_libs_std_original_debug_trap_spec"
    fi

    __base_bash_libs_std_cleanup_dispatcher_installed=0
    __base_bash_libs_std_cleanup_debug_guard_running=0
    __base_bash_libs_std_original_exit_trap=""
    __base_bash_libs_std_original_exit_trap_spec=""
    __base_bash_libs_std_cleanup_dispatcher_trap_spec=""
    __base_bash_libs_std_original_int_trap=""
    __base_bash_libs_std_original_int_trap_spec=""
    __base_bash_libs_std_cleanup_int_trap_spec="__not-installed__"
    __base_bash_libs_std_original_term_trap=""
    __base_bash_libs_std_original_term_trap_spec=""
    __base_bash_libs_std_cleanup_term_trap_spec="__not-installed__"
    __base_bash_libs_std_original_debug_trap=""
    __base_bash_libs_std_original_debug_trap_spec=""
    __base_bash_libs_std_cleanup_debug_trap_spec="__not-installed__"
    return 0
}

#
# base_std_register_cleanup_hook - Registers a function to run from the shared EXIT trap.
#
# Cleanup hooks run after any EXIT trap that existed before the first cleanup hook
# registration. Hooks are function names, not shell command strings.
#
# Usage:
#   cleanup_workspace() { rm -rf -- "$workspace"; }
#   base_std_register_cleanup_hook cleanup_workspace
#
base_std_register_cleanup_hook() {
    local hook="${1-}" existing_hook

    if (($# != 1)); then
        base_std_log_error -l base_bash_libs.std "base_std_register_cleanup_hook: expected exactly one function name."
        return 1
    fi
    if ! __base_bash_libs_std_is_valid_variable_name__ "$hook" || ! declare -F "$hook" > /dev/null; then
        base_std_log_error -l base_bash_libs.std "base_std_register_cleanup_hook: '$hook' is not a defined cleanup function."
        return 1
    fi

    for existing_hook in "${__base_bash_libs_std_cleanup_hooks[@]+"${__base_bash_libs_std_cleanup_hooks[@]}"}"; do
        [[ "$existing_hook" == "$hook" ]] && return 0
    done

    __base_bash_libs_std_cleanup_hooks+=("$hook")
    __base_bash_libs_std_cleanup_entries+=("hook:$hook")
    __base_bash_libs_std_install_cleanup_dispatcher__
    return 0
}

#
# base_std_unregister_cleanup_hook - Removes a function from the shared EXIT cleanup hook list.
#
# Usage:
#   base_std_unregister_cleanup_hook cleanup_workspace
#
base_std_unregister_cleanup_hook() {
    local hook="${1-}" existing_hook entry entry_type entry_value
    local -a remaining_hooks=() remaining_entries=()

    if (($# != 1)); then
        base_std_log_error -l base_bash_libs.std "base_std_unregister_cleanup_hook: expected exactly one function name."
        return 1
    fi

    for existing_hook in "${__base_bash_libs_std_cleanup_hooks[@]+"${__base_bash_libs_std_cleanup_hooks[@]}"}"; do
        [[ "$existing_hook" == "$hook" ]] && continue
        remaining_hooks+=("$existing_hook")
    done
    __base_bash_libs_std_cleanup_hooks=("${remaining_hooks[@]+"${remaining_hooks[@]}"}")
    for entry in "${__base_bash_libs_std_cleanup_entries[@]+"${__base_bash_libs_std_cleanup_entries[@]}"}"; do
        entry_type="${entry%%:*}"
        entry_value="${entry#*:}"
        if [[ "$entry_type" == hook && "$entry_value" == "$hook" ]]; then
            continue
        fi
        remaining_entries+=("$entry")
    done
    __base_bash_libs_std_cleanup_entries=("${remaining_entries[@]+"${remaining_entries[@]}"}")
    __base_bash_libs_std_maybe_uninstall_cleanup_dispatcher__
    return 0
}

__base_bash_libs_std_is_safe_cleanup_path__() {
    local path="${1-}"

    [[ -n "$path" ]] || return 1
    [[ "$path" == /* ]] || return 1
    [[ "$path" =~ ^/+$ ]] && return 1
    case "$path" in
    . | .. | */.. | */../* | */. | */./*)
        return 1
        ;;
    esac
    return 0
}

__base_bash_libs_std_is_broad_cleanup_path__() {
    local path="${1-}"
    local home_dir="${HOME:-}" tmp_dir="${TMPDIR:-}"

    [[ "$path" == "/" ]] && return 0
    [[ -n "$home_dir" && "$path" == "$home_dir" ]] && return 0
    [[ -n "$tmp_dir" && "$path" == "$tmp_dir" ]] && return 0
    case "$path" in
    /tmp | /var/tmp | /private/tmp | /private/var/tmp | \
        /bin | /bin/* | /sbin | /sbin/* | /usr | /usr/* | /etc | /etc/* | \
        /var | /System | /System/* | /Library | /Library/* | \
        /Applications | /Applications/* | /dev | /dev/*)
        return 0
        ;;
    esac
    return 1
}

#
# base_std_register_cleanup_path - Registers files or directories for removal at shell exit.
#
# Paths are removed with `rm -rf --` from the shared EXIT trap. Paths must be
# absolute so cleanup cannot drift when a script changes directory after
# registration. The normal form snapshots every path component (device and
# inode) at registration and refuses deletion if any component is replaced.
# `--unsafe` opts out of that identity proof for a specific path, but broad
# roots and system/shared directories remain rejected in all modes.
#
# Usage:
#   workspace="$(mktemp -d)"
#   base_std_register_cleanup_path "$workspace"
#   base_std_register_cleanup_path --unsafe "$legacy_path"
#
base_std_register_cleanup_path() {
    local path existing_path fingerprint
    local unsafe=0 already_registered had_valid_path=0 status=0

    if (($# == 0)); then
        base_std_log_warn -l base_bash_libs.std "base_std_register_cleanup_path: No paths provided."
        return 0
    fi

    if [[ "${1-}" == "--unsafe" ]]; then
        unsafe=1
        shift
    fi
    if [[ "${1-}" == "--" ]]; then
        shift
    fi
    if (($# == 0)); then
        base_std_log_warn -l base_bash_libs.std "base_std_register_cleanup_path: No paths provided."
        return 0
    fi

    for path; do
        if ! __base_bash_libs_std_is_safe_cleanup_path__ "$path"; then
            base_std_log_error -l base_bash_libs.std "base_std_register_cleanup_path: refusing to register unsafe cleanup path '$path'."
            status=1
            continue
        fi
        if __base_bash_libs_std_is_broad_cleanup_path__ "$path"; then
            base_std_log_error -l base_bash_libs.std "base_std_register_cleanup_path: refusing to register broad or protected path '$path'."
            status=1
            continue
        fi
        if ((!unsafe)) && [[ -L "$path" ]]; then
            base_std_log_error -l base_bash_libs.std "base_std_register_cleanup_path: refusing to register symlink '$path' without --unsafe."
            status=1
            continue
        fi
        if ((!unsafe)) && ! [[ -e "$path" ]]; then
            base_std_log_error -l base_bash_libs.std "base_std_register_cleanup_path: path '$path' does not exist for ownership proof."
            status=1
            continue
        fi

        had_valid_path=1
        already_registered=0
        for existing_path in "${__base_bash_libs_std_cleanup_paths[@]+"${__base_bash_libs_std_cleanup_paths[@]}"}"; do
            if [[ "$existing_path" == "$path" ]]; then
                already_registered=1
                break
            fi
        done
        if ((!already_registered)); then
            if ((unsafe)); then
                fingerprint=UNSAFE
            elif ! __base_bash_libs_std_capture_cleanup_path_fingerprint__ fingerprint "$path"; then
                base_std_log_error -l base_bash_libs.std "base_std_register_cleanup_path: unable to snapshot ownership for '$path'."
                status=1
                continue
            fi
            __base_bash_libs_std_cleanup_paths+=("$path")
            __base_bash_libs_std_cleanup_entries+=("path:$path")
            __base_bash_libs_std_cleanup_path_fingerprints["$path"]="$fingerprint"
        fi
    done

    if ((had_valid_path)); then
        __base_bash_libs_std_install_cleanup_dispatcher__
    fi
    return "$status"
}

#
# base_std_unregister_cleanup_path - Removes files or directories from the shared EXIT cleanup path list.
#
# This is useful after eager cleanup removes or moves a path that was previously
# registered for fallback cleanup. Paths use the same safety checks as
# registration. Safe paths in a mixed call are still unregistered, and the
# function returns nonzero if any path was rejected.
#
# Usage:
#   rm -rf -- "$workspace"
#   base_std_unregister_cleanup_path "$workspace"
#
base_std_unregister_cleanup_path() {
    local path existing_path entry entry_type entry_value
    local should_remove had_valid_path=0 status=0
    local -a paths_to_remove=() remaining_paths=() remaining_entries=()

    if (($# == 0)); then
        base_std_log_warn -l base_bash_libs.std "base_std_unregister_cleanup_path: No paths provided."
        return 0
    fi

    for path; do
        if ! __base_bash_libs_std_is_safe_cleanup_path__ "$path"; then
            base_std_log_error -l base_bash_libs.std "base_std_unregister_cleanup_path: refusing to unregister unsafe cleanup path '$path'."
            status=1
            continue
        fi

        had_valid_path=1
        paths_to_remove+=("$path")
    done

    if ((had_valid_path)); then
        for existing_path in "${__base_bash_libs_std_cleanup_paths[@]+"${__base_bash_libs_std_cleanup_paths[@]}"}"; do
            should_remove=0
            for path in "${paths_to_remove[@]+"${paths_to_remove[@]}"}"; do
                if [[ "$existing_path" == "$path" ]]; then
                    should_remove=1
                    break
                fi
            done
            ((should_remove)) || remaining_paths+=("$existing_path")
        done
        __base_bash_libs_std_cleanup_paths=("${remaining_paths[@]+"${remaining_paths[@]}"}")
        for entry in "${__base_bash_libs_std_cleanup_entries[@]+"${__base_bash_libs_std_cleanup_entries[@]}"}"; do
            entry_type="${entry%%:*}"
            entry_value="${entry#*:}"
            should_remove=0
            if [[ "$entry_type" == path ]]; then
                for path in "${paths_to_remove[@]+"${paths_to_remove[@]}"}"; do
                    if [[ "$entry_value" == "$path" ]]; then
                        should_remove=1
                        break
                    fi
                done
            fi
            ((should_remove)) || remaining_entries+=("$entry")
        done
        __base_bash_libs_std_cleanup_entries=("${remaining_entries[@]+"${remaining_entries[@]}"}")
        for path in "${paths_to_remove[@]+"${paths_to_remove[@]}"}"; do
            unset "__base_bash_libs_std_cleanup_path_fingerprints[$path]"
        done
    fi

    __base_bash_libs_std_maybe_uninstall_cleanup_dispatcher__
    return "$status"
}

######################################################## TEMP FILES ####################################################

__base_bash_libs_std_make_temp_path__() {
    local __base_bash_libs_std_temp_helper_name="$1" __base_bash_libs_std_temp_path_kind="$2"
    shift 2
    local __base_bash_libs_std_temp_keep=0 __base_bash_libs_std_temp_result_name __base_bash_libs_std_temp_prefix __base_bash_libs_std_temp_root __base_bash_libs_std_temp_template __base_bash_libs_std_temp_path

    while (($#)); do
        case "${1-}" in
        --keep)
            __base_bash_libs_std_temp_keep=1
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
        esac
    done

    if (($# < 1 || $# > 2)); then
        base_std_log_error -l base_bash_libs.std "$__base_bash_libs_std_temp_helper_name: usage: $__base_bash_libs_std_temp_helper_name [--keep] <result_variable_name> [prefix]"
        return 1
    fi

    __base_bash_libs_std_temp_result_name="$1"
    __base_bash_libs_std_temp_prefix="${2:-base-bash-libs}"

    if ! __base_bash_libs_std_is_valid_variable_name__ "$__base_bash_libs_std_temp_result_name"; then
        base_std_log_error -l base_bash_libs.std "$__base_bash_libs_std_temp_helper_name: result variable name must be a valid Bash variable name."
        return 1
    fi
    __base_bash_libs_std_assert_writable_output__ "$__base_bash_libs_std_temp_helper_name" "$__base_bash_libs_std_temp_result_name" || return 1
    if [[ -z "$__base_bash_libs_std_temp_prefix" || "$__base_bash_libs_std_temp_prefix" == */* ]]; then
        base_std_log_error -l base_bash_libs.std "$__base_bash_libs_std_temp_helper_name: prefix must be a non-empty filename prefix without '/'."
        return 1
    fi

    __base_bash_libs_std_temp_root="${TMPDIR:-/tmp}"
    if [[ "$__base_bash_libs_std_temp_root" != /* ]]; then
        if ! __base_bash_libs_std_temp_root="$(cd -- "$__base_bash_libs_std_temp_root" 2> /dev/null && pwd -P)"; then
            base_std_log_error -l base_bash_libs.std "$__base_bash_libs_std_temp_helper_name: TMPDIR is not a directory: ${TMPDIR:-/tmp}"
            return 1
        fi
    fi
    while [[ "$__base_bash_libs_std_temp_root" != "/" && "$__base_bash_libs_std_temp_root" == */ ]]; do
        __base_bash_libs_std_temp_root="${__base_bash_libs_std_temp_root%/}"
    done
    if [[ -z "$__base_bash_libs_std_temp_root" || ! -d "$__base_bash_libs_std_temp_root" ]]; then
        base_std_log_error -l base_bash_libs.std "$__base_bash_libs_std_temp_helper_name: TMPDIR is not a directory: ${TMPDIR:-/tmp}"
        return 1
    fi

    if [[ "$__base_bash_libs_std_temp_root" == "/" ]]; then
        __base_bash_libs_std_temp_template="/$__base_bash_libs_std_temp_prefix.XXXXXXXXXX"
    else
        __base_bash_libs_std_temp_template="$__base_bash_libs_std_temp_root/$__base_bash_libs_std_temp_prefix.XXXXXXXXXX"
    fi
    if [[ "$__base_bash_libs_std_temp_path_kind" == "dir" ]]; then
        __base_bash_libs_std_temp_path="$(mktemp -d "$__base_bash_libs_std_temp_template" 2> /dev/null)" || {
            base_std_log_error -l base_bash_libs.std "$__base_bash_libs_std_temp_helper_name: failed to create temporary directory."
            return 1
        }
    else
        __base_bash_libs_std_temp_path="$(mktemp "$__base_bash_libs_std_temp_template" 2> /dev/null)" || {
            base_std_log_error -l base_bash_libs.std "$__base_bash_libs_std_temp_helper_name: failed to create temporary file."
            return 1
        }
    fi

    if ((!__base_bash_libs_std_temp_keep)); then
        if ! base_std_register_cleanup_path "$__base_bash_libs_std_temp_path"; then
            rm -rf -- "$__base_bash_libs_std_temp_path"
            return 1
        fi
    fi

    printf -v "$__base_bash_libs_std_temp_result_name" '%s' "$__base_bash_libs_std_temp_path"
    return 0
}

#
# base_std_make_temp_file - Creates a temporary file and stores its path in a named variable.
#
# The created file is registered for exit cleanup unless `--keep` is provided.
#
# Usage:
#   base_std_make_temp_file [--keep] <result_variable_name> [prefix]
#
base_std_make_temp_file() {
    __base_bash_libs_std_preflight_temp_result_name__ base_std_make_temp_file "$@" || return 1
    __base_bash_libs_std_make_temp_path__ base_std_make_temp_file file "$@"
}

# Private counterpart for reserved implementation-local result variables.
# Public named-output helpers continue to reject the `__` namespace.
__base_bash_libs_std_make_internal_temp_file__() {
    __base_bash_libs_std_make_temp_path__ __base_bash_libs_std_make_internal_temp_file__ file "$@"
}

#
# base_std_make_temp_dir - Creates a temporary directory and stores its path in a named variable.
#
# The created directory is registered for exit cleanup unless `--keep` is provided.
#
# Usage:
#   base_std_make_temp_dir [--keep] <result_variable_name> [prefix]
#
base_std_make_temp_dir() {
    __base_bash_libs_std_preflight_temp_result_name__ base_std_make_temp_dir "$@" || return 1
    __base_bash_libs_std_make_temp_path__ base_std_make_temp_dir dir "$@"
}

# Private counterpart for reserved implementation-local result variables.
# Public named-output helpers continue to reject the `__` namespace.
__base_bash_libs_std_make_internal_temp_dir__() {
    __base_bash_libs_std_make_temp_path__ __base_bash_libs_std_make_internal_temp_dir__ dir "$@"
}

####################################################### ASSERTIONS ####################################################

__base_bash_libs_std_is_valid_variable_name__() {
    local __base_bash_libs_std_variable_name="${1-}"
    local __base_bash_libs_std_variable_name_re='^[A-Za-z_][A-Za-z0-9_]*$'
    [[ "$__base_bash_libs_std_variable_name" =~ $__base_bash_libs_std_variable_name_re ]]
}

__base_bash_libs_std_assert_writable_output__() {
    local __base_bash_libs_std_output_function_name="${1-}" __base_bash_libs_std_output_name="${2-}"
    local __base_bash_libs_std_output_declaration __base_bash_libs_std_output_attributes

    if [[ "$__base_bash_libs_std_output_name" == __* ]]; then
        case "$__base_bash_libs_std_output_function_name" in
        __base_bash_libs_std_make_internal_temp_file__ | __base_bash_libs_std_make_internal_temp_dir__) ;;
        *)
            base_std_log_error -l base_bash_libs.std \
                "$__base_bash_libs_std_output_function_name: result variable '$__base_bash_libs_std_output_name' uses the reserved '__' internal namespace."
            return 1
            ;;
        esac
    fi

    __base_bash_libs_std_output_declaration="$(declare -p "$__base_bash_libs_std_output_name" 2> /dev/null || true)"
    [[ -n "$__base_bash_libs_std_output_declaration" ]] || return 0
    __base_bash_libs_std_output_attributes="${__base_bash_libs_std_output_declaration#declare -}"
    __base_bash_libs_std_output_attributes="${__base_bash_libs_std_output_attributes%% *}"
    if [[ "$__base_bash_libs_std_output_attributes" == *r* ]]; then
        base_std_log_error -l base_bash_libs.std \
            "$__base_bash_libs_std_output_function_name: result variable '$__base_bash_libs_std_output_name' is readonly."
        return 1
    fi
    return 0
}

__base_bash_libs_std_assert_public_variable_names__() {
    (($# >= 1)) || return 1
    set -- "${@:2}" "$1"

    while (($# > 1)); do
        if [[ "${1-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ && "${1-}" == __* ]]; then
            base_std_log_error -l base_bash_libs.std \
                "${!#}: variable '${1-}' uses the reserved '__' internal namespace."
            return 1
        fi
        shift
    done
    return 0
}

__base_bash_libs_std_preflight_temp_result_name__() {
    (($# >= 1)) || return 1
    shift
    while (($#)); do
        case "${1-}" in
        --keep)
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
        esac
    done
    (($# >= 1)) || return 0
    __base_bash_libs_std_assert_public_variable_names__ "${FUNCNAME[1]}" "${1-}"
}

#
# base_std_assert_variable_name - Verifies that one or more arguments are valid Bash variable names.
#
# This validates the names themselves. It does not require the named variables to
# exist or have non-empty values.
#
# Usage:
#   base_std_assert_variable_name result_name array_name
#
base_std_assert_variable_name() {
    local __base_bash_libs_std_assert_variable_name

    if (($# == 0)); then
        base_std_fatal_error "base_std_assert_variable_name: No variable names provided for validation."
    fi

    for __base_bash_libs_std_assert_variable_name in "$@"; do
        if ! __base_bash_libs_std_is_valid_variable_name__ "$__base_bash_libs_std_assert_variable_name"; then
            base_std_fatal_error "base_std_assert_variable_name expects valid Bash variable names; one or more arguments are invalid."
        fi
    done

    return 0
}

__base_bash_libs_std_declares_array_kind__() {
    local __base_bash_libs_std_array_variable_name="${1-}" __base_bash_libs_std_array_kind="${2-}"
    local __base_bash_libs_std_array_declaration __base_bash_libs_std_array_attributes

    __base_bash_libs_std_array_declaration="$(declare -p "$__base_bash_libs_std_array_variable_name" 2> /dev/null)" || return 1
    __base_bash_libs_std_array_attributes="${__base_bash_libs_std_array_declaration#declare -}"
    __base_bash_libs_std_array_attributes="${__base_bash_libs_std_array_attributes%% *}"
    [[ "$__base_bash_libs_std_array_attributes" == *"$__base_bash_libs_std_array_kind"* ]]
}

#
# base_std_assert_indexed_array - Verifies that one or more variables are declared indexed arrays.
#
# This validates that callers declared the named variables with indexed-array
# semantics before passing them to helpers that mutate or read arrays in place.
#
# Usage:
#   declare -a values=()
#   base_std_assert_indexed_array values
#
base_std_assert_indexed_array() {
    if (($# == 0)); then
        base_std_fatal_error "base_std_assert_indexed_array: No variable names provided for validation."
    fi
    __base_bash_libs_std_assert_public_variable_names__ base_std_assert_indexed_array "$@" || return 1
    local __base_bash_libs_std_assert_indexed_name

    for __base_bash_libs_std_assert_indexed_name in "$@"; do
        base_std_assert_variable_name "$__base_bash_libs_std_assert_indexed_name"
        if ! __base_bash_libs_std_declares_array_kind__ "$__base_bash_libs_std_assert_indexed_name" "a"; then
            base_std_fatal_error "Variable '$__base_bash_libs_std_assert_indexed_name' must be an indexed array declared by the caller."
        fi
    done

    return 0
}

#
# base_std_assert_associative_array - Verifies that one or more variables are declared associative arrays.
#
# This validates that callers declared the named variables with associative-array
# semantics before passing them to helpers that mutate or read maps in place.
#
# Usage:
#   declare -A options=()
#   base_std_assert_associative_array options
#
base_std_assert_associative_array() {
    if (($# == 0)); then
        base_std_fatal_error "base_std_assert_associative_array: No variable names provided for validation."
    fi
    __base_bash_libs_std_assert_public_variable_names__ base_std_assert_associative_array "$@" || return 1
    local __base_bash_libs_std_assert_associative_name

    for __base_bash_libs_std_assert_associative_name in "$@"; do
        base_std_assert_variable_name "$__base_bash_libs_std_assert_associative_name"
        if ! __base_bash_libs_std_declares_array_kind__ "$__base_bash_libs_std_assert_associative_name" "A"; then
            base_std_fatal_error "Variable '$__base_bash_libs_std_assert_associative_name' must be an associative array declared by the caller."
        fi
    done

    return 0
}

##################################################### INTROSPECTION ###################################################

#
# base_std_command_path - Resolves an external command path without exiting the caller.
#
# Usage:
#   if base_std_command_path git_path git; then
#       base_std_run "$git_path" status --short
#   fi
#
base_std_command_path() {
    if (($# != 2)); then
        base_std_log_error -l base_bash_libs.std "base_std_command_path: usage: base_std_command_path <result_variable_name> <command_name>"
        return 1
    fi
    __base_bash_libs_std_assert_public_variable_names__ base_std_command_path "${1-}" || return 1
    local __base_bash_libs_std_command_result_name="$1" __base_bash_libs_std_command_name="$2" __base_bash_libs_std_command_resolved_path=""

    if ! __base_bash_libs_std_is_valid_variable_name__ "$__base_bash_libs_std_command_result_name"; then
        base_std_log_error -l base_bash_libs.std "base_std_command_path: result variable name must be a valid Bash variable name."
        return 1
    fi
    __base_bash_libs_std_assert_writable_output__ base_std_command_path "$__base_bash_libs_std_command_result_name" || return 1

    if [[ -n "$__base_bash_libs_std_command_name" ]]; then
        __base_bash_libs_std_command_resolved_path="$(type -P "$__base_bash_libs_std_command_name" 2> /dev/null || true)"
    fi
    printf -v "$__base_bash_libs_std_command_result_name" '%s' "$__base_bash_libs_std_command_resolved_path"
    [[ -n "$__base_bash_libs_std_command_resolved_path" ]]
}

#
# base_std_function_exists - Checks whether a Bash function is currently defined.
#
base_std_function_exists() {
    local function_name="${1-}"

    (($# == 1)) || return 1
    __base_bash_libs_std_is_valid_variable_name__ "$function_name" || return 1
    declare -F "$function_name" > /dev/null
}

#
# base_std_assert_function_exists - Verifies that one or more Bash functions are defined.
#
# Usage:
#   base_std_assert_function_exists main cleanup_workspace
#
base_std_assert_function_exists() {
    local missing_functions=() function_name

    if (($# == 0)); then
        base_std_fatal_error "base_std_assert_function_exists: No function names provided for validation."
    fi

    for function_name in "$@"; do
        if ! __base_bash_libs_std_is_valid_variable_name__ "$function_name"; then
            base_std_fatal_error "base_std_assert_function_exists expects function names; one or more arguments are not valid Bash function names."
        fi
        if ! base_std_function_exists "$function_name"; then
            missing_functions+=("$function_name")
        fi
    done

    if [[ -n "${missing_functions[0]+set}" ]]; then
        base_std_fatal_error "Required functions are not defined: ${missing_functions[*]}"
    fi

    return 0
}

#
# base_std_assert_not_null - Checks that one or more variables are not empty.
#
# This function takes the *name* of one or more variables and checks that
# each one has a non-empty value. It is useful for validating required
# script inputs or configuration variables. Unlike other assertions, it
# checks all provided variables and reports all failures at once.
#
# Usage:
#   USER="admin"
#   TOKEN=""
#   base_std_assert_not_null USER       # This will succeed.
#   base_std_assert_not_null USER TOKEN # This will fail, listing TOKEN as empty.
#   base_std_assert_not_null "$TOKEN"   # Wrong: pass variable names, not values.
#
# Arguments:
#   $@: One or more variable names to check.
#
base_std_assert_not_null() {
    if (($# == 0)); then
        base_std_fatal_error "base_std_assert_not_null: No variable names provided for validation."
    fi
    __base_bash_libs_std_assert_public_variable_names__ base_std_assert_not_null "$@" || return 1
    local -a __base_bash_libs_std_assert_not_null_unset_names=()
    local __base_bash_libs_std_assert_not_null_name

    for __base_bash_libs_std_assert_not_null_name in "$@"; do
        if ! __base_bash_libs_std_is_valid_variable_name__ "$__base_bash_libs_std_assert_not_null_name"; then
            base_std_fatal_error "base_std_assert_not_null expects variable names, not values; one or more arguments are not valid Bash variable names."
        fi
        # Use indirection to get the value of the variable whose name is stored in var_name.
        # The -v check is for unset variables, -z is for empty strings.
        # We check for empty string as per the request.
        if [[ ! -v $__base_bash_libs_std_assert_not_null_name || -z "${!__base_bash_libs_std_assert_not_null_name-}" ]]; then
            __base_bash_libs_std_assert_not_null_unset_names+=("$__base_bash_libs_std_assert_not_null_name")
        fi
    done

    if [[ -n "${__base_bash_libs_std_assert_not_null_unset_names[0]+set}" ]]; then
        base_std_fatal_error "These required variables are not set or are empty: ${__base_bash_libs_std_assert_not_null_unset_names[*]}"
    fi

    return 0
}

#
# base_std_assert_integer - Checks if the values of one or more variables are valid integers.
#
__base_bash_libs_std_assert_integer_names__() {
    local __base_bash_libs_std_assert_integer_name __base_bash_libs_std_assert_integer_value
    local __base_bash_libs_std_assert_integer_re='^[-+]?[0-9]+$'
    for __base_bash_libs_std_assert_integer_name in "$@"; do
        if ! __base_bash_libs_std_is_valid_variable_name__ "$__base_bash_libs_std_assert_integer_name"; then
            base_std_fatal_error "base_std_assert_integer expects variable names, not values; one or more arguments are not valid Bash variable names."
        fi
        __base_bash_libs_std_assert_integer_value="${!__base_bash_libs_std_assert_integer_name-}"
        ! [[ "$__base_bash_libs_std_assert_integer_value" =~ $__base_bash_libs_std_assert_integer_re ]] &&
            base_std_fatal_error "Variable '$__base_bash_libs_std_assert_integer_name' with value '$__base_bash_libs_std_assert_integer_value' is not a valid integer."
    done
    return 0
}

base_std_assert_integer() {
    (($# == 0)) && base_std_fatal_error "base_std_assert_integer: No variable names provided."
    __base_bash_libs_std_assert_public_variable_names__ base_std_assert_integer "$@" || return 1
    __base_bash_libs_std_assert_integer_names__ "$@"
}

#
# base_std_assert_integer_range - Checks if a variable's value is an integer within a specified range.
#
# Arguments:
#   $1: The NAME of the variable to check.
#   $2: The minimum value.
#   $3: The maximum value.
#
base_std_assert_integer_range() {
    (($# != 3)) && base_std_fatal_error "base_std_assert_integer_range: Expected 3 arguments, got $#."
    __base_bash_libs_std_assert_public_variable_names__ base_std_assert_integer_range "${1-}" || return 1
    local __base_bash_libs_std_range_name="$1" __base_bash_libs_std_range_min="$2" __base_bash_libs_std_range_max="$3"
    local __base_bash_libs_std_range_value __base_bash_libs_std_range_value_number __base_bash_libs_std_range_min_number __base_bash_libs_std_range_max_number
    if ! __base_bash_libs_std_is_valid_variable_name__ "$__base_bash_libs_std_range_name"; then
        base_std_fatal_error "base_std_assert_integer_range expects a variable name as its first argument."
    fi
    if ! [[ "$__base_bash_libs_std_range_min" =~ ^[-+]?[0-9]+$ ]]; then
        base_std_fatal_error "base_std_assert_integer_range minimum bound '$__base_bash_libs_std_range_min' is not a valid integer."
    fi
    if ! [[ "$__base_bash_libs_std_range_max" =~ ^[-+]?[0-9]+$ ]]; then
        base_std_fatal_error "base_std_assert_integer_range maximum bound '$__base_bash_libs_std_range_max' is not a valid integer."
    fi
    __base_bash_libs_std_range_value="${!__base_bash_libs_std_range_name-}"
    __base_bash_libs_std_assert_integer_names__ "$__base_bash_libs_std_range_name"
    __base_bash_libs_std_decimal_integer_value__ __base_bash_libs_std_range_value_number "$__base_bash_libs_std_range_value"
    __base_bash_libs_std_decimal_integer_value__ __base_bash_libs_std_range_min_number "$__base_bash_libs_std_range_min"
    __base_bash_libs_std_decimal_integer_value__ __base_bash_libs_std_range_max_number "$__base_bash_libs_std_range_max"
    ((__base_bash_libs_std_range_min_number > __base_bash_libs_std_range_max_number)) &&
        base_std_fatal_error "base_std_assert_integer_range minimum '$__base_bash_libs_std_range_min' cannot exceed maximum '$__base_bash_libs_std_range_max'."
    ((__base_bash_libs_std_range_value_number < __base_bash_libs_std_range_min_number || __base_bash_libs_std_range_value_number > __base_bash_libs_std_range_max_number)) &&
        base_std_fatal_error "Variable '$__base_bash_libs_std_range_name' ($__base_bash_libs_std_range_value) is out of range [$__base_bash_libs_std_range_min, $__base_bash_libs_std_range_max]."
    return 0
}

#
# base_std_assert_arg_count - Checks that the number of arguments falls within a given range.
#
# Usage:
#   base_std_assert_arg_count $# 2      # Fails if arg count is not exactly 2
#   base_std_assert_arg_count $# 1 3    # Fails if arg count is not between 1 and 3 (inclusive)
#
# Arguments:
#   $1: The actual number of arguments (typically $#).
#   $2: The exact expected count, or the minimum count for a range.
#   $3: (Optional) The maximum count for a range.
#
base_std_assert_arg_count() {
    local __base_bash_libs_std_arg_count_actual="${1-}" __base_bash_libs_std_arg_count_first="${2-}" __base_bash_libs_std_arg_count_second="${3-}"
    local __base_bash_libs_std_arg_count_arity=$#

    # Check the number of arguments passed to this function itself.
    if ((__base_bash_libs_std_arg_count_arity < 2 || __base_bash_libs_std_arg_count_arity > 3)); then
        base_std_fatal_error "base_std_assert_arg_count: Incorrect usage. Expected 2 or 3 arguments, but got $__base_bash_libs_std_arg_count_arity."
    fi

    # Create temporary named variables for base_std_assert_integer to check
    local __base_bash_libs_std_arg_count_actual_value="$__base_bash_libs_std_arg_count_actual" __base_bash_libs_std_arg_count_first_value="$__base_bash_libs_std_arg_count_first"
    local __base_bash_libs_std_arg_count_actual_number __base_bash_libs_std_arg_count_first_number __base_bash_libs_std_arg_count_second_number
    __base_bash_libs_std_assert_integer_names__ __base_bash_libs_std_arg_count_actual_value __base_bash_libs_std_arg_count_first_value

    if [[ -n "$__base_bash_libs_std_arg_count_second" ]]; then
        local __base_bash_libs_std_arg_count_second_value="$__base_bash_libs_std_arg_count_second"
        __base_bash_libs_std_assert_integer_names__ __base_bash_libs_std_arg_count_second_value
    fi

    __base_bash_libs_std_decimal_integer_value__ __base_bash_libs_std_arg_count_actual_number "$__base_bash_libs_std_arg_count_actual"
    __base_bash_libs_std_decimal_integer_value__ __base_bash_libs_std_arg_count_first_number "$__base_bash_libs_std_arg_count_first"
    if [[ -n "$__base_bash_libs_std_arg_count_second" ]]; then
        __base_bash_libs_std_decimal_integer_value__ __base_bash_libs_std_arg_count_second_number "$__base_bash_libs_std_arg_count_second"
        ((__base_bash_libs_std_arg_count_first_number > __base_bash_libs_std_arg_count_second_number)) &&
            base_std_fatal_error "base_std_assert_arg_count minimum '$__base_bash_libs_std_arg_count_first' cannot exceed maximum '$__base_bash_libs_std_arg_count_second'."
    fi

    if [[ -z "$__base_bash_libs_std_arg_count_second" ]]; then
        # Exact match case
        if ((__base_bash_libs_std_arg_count_actual_number != __base_bash_libs_std_arg_count_first_number)); then
            base_std_fatal_error "Argument count mismatch: expected $__base_bash_libs_std_arg_count_first but got $__base_bash_libs_std_arg_count_actual arguments"
        fi
    else
        # Range match case
        if ((__base_bash_libs_std_arg_count_actual_number < __base_bash_libs_std_arg_count_first_number || \
            __base_bash_libs_std_arg_count_actual_number > __base_bash_libs_std_arg_count_second_number)); then
            base_std_fatal_error "Argument count mismatch: expected between $__base_bash_libs_std_arg_count_first and $__base_bash_libs_std_arg_count_second arguments, but got $__base_bash_libs_std_arg_count_actual"
        fi
    fi
    return 0
}

#
# base_std_assert_command_exists - Checks that one or more commands are available in the system's PATH.
#
# This function iterates through all provided command names and uses 'command -v'
# to verify their existence. If any command is not found, it collects the names
# and reports them all in a single fatal error.
#
# Usage:
#   base_std_assert_command_exists git curl jq
#
# Arguments:
#   $@: One or more command names to check.
#
base_std_assert_command_exists() {
    local missing_commands=()
    local cmd

    if (($# == 0)); then
        base_std_log_warn -l base_bash_libs.std "base_std_assert_command_exists: No commands provided to check."
        return 0
    fi

    for cmd; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done

    if [[ -n "${missing_commands[0]+set}" ]]; then
        base_std_fatal_error "These required commands were not found in your PATH: ${missing_commands[*]}"
    fi

    return 0
}

#
# base_std_assert_file_exists - Checks that one or more paths exist and are regular files.
#
# This function iterates through all provided paths. If any path does not
# exist or is not a regular file (e.g., it's a directory or a symlink to
# a non-file), it collects the names and reports them all in a single fatal error.
#
# Usage:
#   base_std_assert_file_exists "/etc/hosts" "./my_script.sh"
#
# Arguments:
#   $@: One or more file paths to check.
#
base_std_assert_file_exists() {
    local missing_files=()
    local file

    if (($# == 0)); then
        base_std_log_warn -l base_bash_libs.std "base_std_assert_file_exists: No files provided to check."
        return 0
    fi

    for file; do
        if [[ ! -f "$file" ]]; then
            missing_files+=("$file")
        fi
    done

    if [[ -n "${missing_files[0]+set}" ]]; then
        base_std_fatal_error "These required files do not exist or are not regular files: ${missing_files[*]}"
    fi

    return 0
}

#
# base_std_assert_executable - Checks that one or more paths exist and are executable files.
#
# This function iterates through all provided paths. If any path does not
# exist, is not a regular file, or is not executable, it collects the names
# and reports them all in a single fatal error.
#
# Use this for explicit paths such as project-local scripts. Use
# `base_std_assert_command_exists` when checking whether a command is discoverable
# through PATH.
#
# Usage:
#   base_std_assert_executable "./bin/tool" "/opt/vendor/bin/tool"
#
# Arguments:
#   $@: One or more executable file paths to check.
#
base_std_assert_executable() {
    local missing_executables=()
    local executable

    if (($# == 0)); then
        base_std_log_warn -l base_bash_libs.std "base_std_assert_executable: No executable paths provided to check."
        return 0
    fi

    for executable; do
        if [[ ! -f "$executable" || ! -x "$executable" ]]; then
            missing_executables+=("$executable")
        fi
    done

    if [[ -n "${missing_executables[0]+set}" ]]; then
        base_std_fatal_error "These required executable paths do not exist, are not regular files, or are not executable: ${missing_executables[*]}"
    fi

    return 0
}

#
# base_std_assert_dir_exists - Checks that one or more paths exist and are directories.
#
# This function iterates through all provided paths. If any path does not
# exist or is not a directory, it collects the names and reports them all
# in a single fatal error.
#
# Usage:
#   base_std_assert_dir_exists "/tmp" "/var/log"
#
# Arguments:
#   $@: One or more directory paths to check.
#
base_std_assert_dir_exists() {
    local missing_dirs=()
    local dir

    if (($# == 0)); then
        base_std_log_warn -l base_bash_libs.std "base_std_assert_dir_exists: No directories provided to check."
        return 0
    fi

    for dir; do
        if [[ ! -d "$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done

    if [[ -n "${missing_dirs[0]+set}" ]]; then
        base_std_fatal_error "These required directories do not exist: ${missing_dirs[*]}"
    fi

    return 0
}

################################################# MISC FUNCTIONS #######################################################

#
# base_std_safe_cd - A safe version of the 'cd' command that returns on failure.
#
base_std_safe_cd() {
    local dir="${1-}"
    if [[ -z "$dir" || $# -ne 1 ]]; then
        base_std_log_error -l base_bash_libs.std \
            "base_std_safe_cd: expected exactly one non-empty directory path."
        return 2
    fi
    if ! cd -- "$dir"; then
        base_std_log_error -l base_bash_libs.std "Can't cd to '$dir'."
        return 1
    fi
}

#
# base_std_safe_unalias - Safely unaliases a command, without erroring if it doesn't exist.
#
base_std_safe_unalias() {
    # Ref: https://stackoverflow.com/a/61471333/6862601
    local alias_name
    for alias_name; do
        [[ ${BASH_ALIASES[$alias_name]-} ]] && unalias "$alias_name"
    done
    return 0
}

#
# base_std_get_my_source_dir - Returns the absolute path to the directory of the calling script through the passed variable name.
#
# Usage:
#   base_std_get_my_source_dir var_name
#
base_std_get_my_source_dir() {
    if [[ -z "${1-}" ]]; then
        base_std_log_error -l base_bash_libs.std \
            "base_std_get_my_source_dir: no result variable name provided."
        return 2
    fi
    __base_bash_libs_std_assert_public_variable_names__ base_std_get_my_source_dir "${1-}" || return 1
    local __base_bash_libs_std_source_result_name="$1"

    if ! __base_bash_libs_std_is_valid_variable_name__ "$__base_bash_libs_std_source_result_name"; then
        base_std_log_error -l base_bash_libs.std \
            "base_std_get_my_source_dir: result variable name must be a valid Bash variable name."
        return 2
    fi
    __base_bash_libs_std_assert_writable_output__ base_std_get_my_source_dir "$__base_bash_libs_std_source_result_name" || return 1
    local __base_bash_libs_std_source_dir __base_bash_libs_std_source_path="${BASH_SOURCE[1]-}"
    # Reference: https://stackoverflow.com/a/246128/6862601
    if [[ -n "$__base_bash_libs_std_source_path" ]]; then
        if ! __base_bash_libs_std_source_dir="$(cd "$(dirname -- "$__base_bash_libs_std_source_path")" > /dev/null 2>&1 && pwd -P)"; then
            base_std_log_error -l base_bash_libs.std \
                "base_std_get_my_source_dir: unable to resolve source directory."
            return 1
        fi
    else
        if ! __base_bash_libs_std_source_dir="$(pwd -P)"; then
            base_std_log_error -l base_bash_libs.std \
                "base_std_get_my_source_dir: unable to resolve source directory."
            return 1
        fi
    fi
    printf -v "$__base_bash_libs_std_source_result_name" '%s' "$__base_bash_libs_std_source_dir"
}

#
# base_std_ask_yes_no - Get user's confirmation
#
# Prompts the user with a given message for a yes/no answer and returns 0 or 1
# based on user's choice of yes or no. It reads a single character without
# requiring the user to press Enter.
#
# Arguments:
#   $1: The message string to display as the prompt.
#   $2: Optional default, either `no` (the default) or `yes`.
#
# Usage:
#
#   if base_std_ask_yes_no "Do you want to continue?"; then
#       echo "User chose to continue."
#   else
#       echo "User chose not to continue."
#   fi
#
base_std_ask_yes_no() {
    if (("$#" < 1 || "$#" > 2)); then
        base_std_log_error -l base_bash_libs.std "base_std_ask_yes_no: invalid arguments"
        base_std_log_info -l base_bash_libs.std "Usage: base_std_ask_yes_no <prompt_message> [yes|no]"
        return 2
    fi

    local message=$1 user_input tty_fd default="no" prompt_suffix
    if (($# == 2)); then
        case "${2,,}" in
        yes) default="yes" ;;
        no) default="no" ;;
        *)
            base_std_log_error -l base_bash_libs.std \
                "base_std_ask_yes_no: default must be 'yes' or 'no'."
            return 2
            ;;
        esac
    fi
    if [[ "$default" == yes ]]; then
        prompt_suffix='[Y/n]'
    else
        prompt_suffix='[y/N]'
    fi
    if ! exec {tty_fd}< /dev/tty 2> /dev/null; then
        base_std_log_error -l base_bash_libs.std "base_std_ask_yes_no: /dev/tty is not available"
        return 1
    fi

    while true; do
        # Prompt the user for input.
        # -n 1: Reads only one character.
        # -r: Prevents backslash from acting as an escape character.
        # -p: Displays the prompt string.
        # The text "[y/N]" suggests that 'N' is the default choice.
        if ! read -r -n 1 -p "$message $prompt_suffix: " user_input <&"$tty_fd"; then
            exec {tty_fd}<&-
            echo
            return 1
        fi

        # Add a newline since the user won't press Enter.
        echo

        case "$user_input" in
        [yY])
            exec {tty_fd}<&-
            return 0
            ;;
        [nN])
            exec {tty_fd}<&-
            return 1
            ;;
        $'\n' | $'\r' | '')
            exec {tty_fd}<&-
            [[ "$default" == yes ]]
            return $?
            ;;
        *) echo "Invalid input. Please enter 'y' or 'n'." ;;
        esac
    done
}

#
# base_std_wait_for_enter - Pauses the script and waits for the user to press the Enter key.
#
# Arguments:
#   $1: (Optional) The prompt to display. Defaults to "Press Enter to continue".
#
base_std_wait_for_enter() {
    if (("$#" > 1)); then
        base_std_log_error -l base_bash_libs.std "base_std_wait_for_enter: invalid arguments"
        base_std_log_info -l base_bash_libs.std "Usage: base_std_wait_for_enter [prompt_message]"
        return 1
    fi

    local prompt=${1:-"Press Enter to continue"} tty_fd read_status
    if ! exec {tty_fd}< /dev/tty 2> /dev/null; then
        base_std_log_error -l base_bash_libs.std "base_std_wait_for_enter: /dev/tty is not available"
        return 1
    fi

    if read -r -s -p "$prompt" <&"$tty_fd"; then
        read_status=0
    else
        read_status=$?
    fi
    exec {tty_fd}<&-

    if ((read_status != 0)); then
        base_std_log_error -l base_bash_libs.std "base_std_wait_for_enter: failed to read from /dev/tty"
        return "$read_status"
    fi

    return 0
}

#################################################### END OF FUNCTIONS ##################################################
