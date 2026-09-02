# shellcheck shell=bash
#
# lib_gh.sh - Generic GitHub CLI helpers for Bash scripts.
#

[[ -n "${BASE_BASH_LIBS_GH_LOADED:-}" ]] && return 0
if [[ "${BASE_BASH_LIBS_STDLIB_LOADED:-}" != "1" ]]; then
    printf '%s\n' "Error: lib_gh.sh requires lib_std.sh to be sourced first." >&2
    return 1 2> /dev/null || exit 1
fi
readonly BASE_BASH_LIBS_GH_LOADED=1

# Public callers may provide the optional install hint even though internal
# callers use the default.
# shellcheck disable=SC2120
base_gh_require_cli() {
    if (($# > 1)); then
        base_std_log_error -l base_bash_libs.gh "Usage: base_gh_require_cli [install_hint]"
        return 2
    fi

    local install_hint="${1:-}"

    command -v gh > /dev/null 2>&1 || {
        base_std_log_error -l base_bash_libs.gh "Required command 'gh' was not found on PATH."
        [[ -z "$install_hint" ]] || base_std_log_error -l base_bash_libs.gh "$install_hint"
        return 1
    }
}

__base_bash_libs_gh_sensitive_controls_usage__() {
    local __base_bash_libs_gh_controls_helper_name="${1-}"

    case "$__base_bash_libs_gh_controls_helper_name" in
    base_gh_report_command_failure)
        base_std_log_error -l base_bash_libs.gh \
            "Usage: base_gh_report_command_failure <status> [gh args...] or base_gh_report_command_failure --sensitive [--safe-display <label>] -- <status> [gh args...]"
        ;;
    *)
        base_std_log_error -l base_bash_libs.gh \
            "Usage: $__base_bash_libs_gh_controls_helper_name [--sensitive [--safe-display <label>] --] [gh args...]"
        ;;
    esac
}

# Parse the optional protected-diagnostic prefix without interpreting ordinary
# GitHub arguments. Once either control is present, an explicit `--` is
# required so a malformed protected call cannot accidentally render an argv.
__base_bash_libs_gh_parse_sensitive_controls__() {
    local __base_bash_libs_gh_controls_consumed_result_name="${1-}"
    local __base_bash_libs_gh_controls_sensitive_result_name="${2-}"
    local __base_bash_libs_gh_controls_display_result_name="${3-}"
    local __base_bash_libs_gh_controls_helper_name="${4-}"
    shift 4

    local __base_bash_libs_gh_controls_consumed=0 __base_bash_libs_gh_controls_sensitive=0
    local __base_bash_libs_gh_controls_safe_display="" __base_bash_libs_gh_controls_display_seen=0
    local __base_bash_libs_gh_controls_separator_seen=0

    case "${1-}" in
    --sensitive | --safe-display) ;;
    *)
        printf -v "$__base_bash_libs_gh_controls_consumed_result_name" '%s' 0
        printf -v "$__base_bash_libs_gh_controls_sensitive_result_name" '%s' 0
        printf -v "$__base_bash_libs_gh_controls_display_result_name" '%s' ""
        return 0
        ;;
    esac

    while (($#)); do
        case "${1-}" in
        --sensitive)
            if ((__base_bash_libs_gh_controls_sensitive)); then
                __base_bash_libs_gh_sensitive_controls_usage__ "$__base_bash_libs_gh_controls_helper_name"
                return 2
            fi
            __base_bash_libs_gh_controls_sensitive=1
            __base_bash_libs_gh_controls_consumed=$((__base_bash_libs_gh_controls_consumed + 1))
            shift
            ;;
        --safe-display)
            if ((__base_bash_libs_gh_controls_display_seen)) || (($# < 2)) ||
                ! __base_bash_libs_std_is_safe_display__ "${2-}"; then
                base_std_log_error -l base_bash_libs.gh \
                    "$__base_bash_libs_gh_controls_helper_name: --safe-display requires one non-empty printable ASCII label that does not begin with '-'."
                return 2
            fi
            __base_bash_libs_gh_controls_safe_display="$2"
            __base_bash_libs_gh_controls_display_seen=1
            __base_bash_libs_gh_controls_consumed=$((__base_bash_libs_gh_controls_consumed + 2))
            shift 2
            ;;
        --)
            __base_bash_libs_gh_controls_separator_seen=1
            __base_bash_libs_gh_controls_consumed=$((__base_bash_libs_gh_controls_consumed + 1))
            shift
            break
            ;;
        *)
            # Do not echo the malformed token: it may itself contain a
            # credential in an option=value form.
            base_std_log_error -l base_bash_libs.gh \
                "$__base_bash_libs_gh_controls_helper_name: protected diagnostic controls must end with -- before GitHub arguments."
            return 2
            ;;
        esac
    done

    if ((!__base_bash_libs_gh_controls_sensitive)); then
        base_std_log_error -l base_bash_libs.gh \
            "$__base_bash_libs_gh_controls_helper_name: --safe-display is valid only with --sensitive."
        return 2
    fi
    if ((!__base_bash_libs_gh_controls_separator_seen)); then
        base_std_log_error -l base_bash_libs.gh \
            "$__base_bash_libs_gh_controls_helper_name: --sensitive requires -- before GitHub arguments."
        return 2
    fi

    printf -v "$__base_bash_libs_gh_controls_consumed_result_name" '%s' "$__base_bash_libs_gh_controls_consumed"
    printf -v "$__base_bash_libs_gh_controls_sensitive_result_name" '%s' "$__base_bash_libs_gh_controls_sensitive"
    printf -v "$__base_bash_libs_gh_controls_display_result_name" '%s' "$__base_bash_libs_gh_controls_safe_display"
}

__base_bash_libs_gh_auth_status_diagnostics__() {
    local __base_bash_libs_gh_auth_sensitive="${1-0}" __base_bash_libs_gh_auth_safe_display="${2-}"
    local __base_bash_libs_gh_auth_login_hint="${3-Run 'gh auth login -h github.com' and retry.}"
    local __base_bash_libs_gh_auth_output __base_bash_libs_gh_auth_line __base_bash_libs_gh_auth_display

    base_gh_require_cli || return 1

    if __base_bash_libs_gh_auth_output="$(gh auth status -h github.com 2>&1)"; then
        return 0
    fi

    if ((__base_bash_libs_gh_auth_sensitive)); then
        if ! __base_bash_libs_std_render_command_display__ __base_bash_libs_gh_auth_display 1 "$__base_bash_libs_gh_auth_safe_display" \
            "[sensitive GitHub operation; arguments hidden]"; then
            __base_bash_libs_gh_auth_display="[sensitive GitHub operation; arguments hidden]"
        fi
        base_std_log_error -l base_bash_libs.gh \
            "GitHub authentication status could not be confirmed while diagnosing $__base_bash_libs_gh_auth_display; raw auth diagnostics hidden."
    else
        while IFS= read -r __base_bash_libs_gh_auth_line || [[ -n "$__base_bash_libs_gh_auth_line" ]]; do
            [[ -n "$__base_bash_libs_gh_auth_line" ]] &&
                base_std_log_error -l base_bash_libs.gh "gh auth status: $__base_bash_libs_gh_auth_line"
        done <<< "$__base_bash_libs_gh_auth_output"
    fi
    [[ -z "$__base_bash_libs_gh_auth_login_hint" ]] || base_std_log_error -l base_bash_libs.gh "$__base_bash_libs_gh_auth_login_hint"
    return 1
}

# Public callers may provide the optional login hint even though the internal
# failure reporter uses the default.
# shellcheck disable=SC2120
base_gh_auth_status_diagnostics() {
    if (($# > 1)); then
        base_std_log_error -l base_bash_libs.gh "Usage: base_gh_auth_status_diagnostics [login_hint]"
        return 2
    fi

    __base_bash_libs_gh_auth_status_diagnostics__ 0 "" "${1:-Run 'gh auth login -h github.com' and retry.}"
}

__base_bash_libs_gh_report_command_failure__() {
    local __base_bash_libs_gh_report_status="${1-1}" __base_bash_libs_gh_report_sensitive="${2-0}"
    local __base_bash_libs_gh_report_safe_display="${3-}" __base_bash_libs_gh_report_display
    shift 3

    if ! __base_bash_libs_std_render_command_display__ __base_bash_libs_gh_report_display "$__base_bash_libs_gh_report_sensitive" \
        "$__base_bash_libs_gh_report_safe_display" "[sensitive GitHub operation; arguments hidden]" gh "$@"; then
        if ((__base_bash_libs_gh_report_sensitive)); then
            __base_bash_libs_gh_report_display="[sensitive GitHub operation; arguments hidden]"
        else
            __base_bash_libs_gh_report_display=gh
        fi
    fi

    base_std_log_error -l base_bash_libs.gh \
        "GitHub command failed: $__base_bash_libs_gh_report_display (exit $__base_bash_libs_gh_report_status)"
    __base_bash_libs_gh_auth_status_diagnostics__ "$__base_bash_libs_gh_report_sensitive" "$__base_bash_libs_gh_report_safe_display" \
        "Run 'gh auth login -h github.com' and retry." || true
    return "$__base_bash_libs_gh_report_status"
}

base_gh_report_command_failure() {
    local __base_bash_libs_gh_report_public_consumed=0 __base_bash_libs_gh_report_public_sensitive=0
    local __base_bash_libs_gh_report_public_safe_display=""
    local __base_bash_libs_gh_report_public_status

    __base_bash_libs_gh_parse_sensitive_controls__ __base_bash_libs_gh_report_public_consumed \
        __base_bash_libs_gh_report_public_sensitive __base_bash_libs_gh_report_public_safe_display \
        base_gh_report_command_failure "$@" || return $?
    ((__base_bash_libs_gh_report_public_consumed == 0)) || shift "$__base_bash_libs_gh_report_public_consumed"

    if (($# < 1)); then
        __base_bash_libs_gh_sensitive_controls_usage__ base_gh_report_command_failure
        return 2
    fi
    __base_bash_libs_gh_report_public_status="$1"
    shift

    if [[ ! "$__base_bash_libs_gh_report_public_status" =~ ^[0-9]{1,3}$ ]]; then
        __base_bash_libs_gh_sensitive_controls_usage__ base_gh_report_command_failure
        return 2
    fi
    __base_bash_libs_gh_report_public_status=$((10#$__base_bash_libs_gh_report_public_status))
    if ((__base_bash_libs_gh_report_public_status < 1 || __base_bash_libs_gh_report_public_status > 255)); then
        __base_bash_libs_gh_sensitive_controls_usage__ base_gh_report_command_failure
        return 2
    fi

    __base_bash_libs_gh_report_command_failure__ "$__base_bash_libs_gh_report_public_status" \
        "$__base_bash_libs_gh_report_public_sensitive" "$__base_bash_libs_gh_report_public_safe_display" "$@" || true
    return "$__base_bash_libs_gh_report_public_status"
}

base_gh_run() {
    local __base_bash_libs_gh_run_consumed=0 __base_bash_libs_gh_run_sensitive=0 __base_bash_libs_gh_run_safe_display=""
    local __base_bash_libs_gh_run_status=0

    __base_bash_libs_gh_parse_sensitive_controls__ __base_bash_libs_gh_run_consumed __base_bash_libs_gh_run_sensitive \
        __base_bash_libs_gh_run_safe_display base_gh_run "$@" || return $?
    ((__base_bash_libs_gh_run_consumed == 0)) || shift "$__base_bash_libs_gh_run_consumed"
    # A caller may provide `gh` as a shell function. Lock the normalized
    # diagnostic policy before invoking it so Bash's dynamic scope cannot let
    # that function downgrade protected failure reporting.
    local -r __base_bash_libs_gh_run_locked_sensitive="$__base_bash_libs_gh_run_sensitive"
    local -r __base_bash_libs_gh_run_locked_safe_display="$__base_bash_libs_gh_run_safe_display"

    base_gh_require_cli || return 1
    if gh "$@"; then
        return 0
    else
        __base_bash_libs_gh_run_status=$?
    fi

    __base_bash_libs_gh_report_command_failure__ "$__base_bash_libs_gh_run_status" "$__base_bash_libs_gh_run_locked_sensitive" \
        "$__base_bash_libs_gh_run_locked_safe_display" "$@" || true
    return "$__base_bash_libs_gh_run_status"
}

__base_bash_libs_gh_parse_repo_from_remote_url__() {
    local __base_bash_libs_gh_parse_remote_url="${1-}" __base_bash_libs_gh_parse_result_name="${2-}"
    local __base_bash_libs_gh_parse_repo

    case "$__base_bash_libs_gh_parse_remote_url" in
    git@github.com:*)
        __base_bash_libs_gh_parse_repo="${__base_bash_libs_gh_parse_remote_url#git@github.com:}"
        ;;
    ssh://git@github.com/*)
        __base_bash_libs_gh_parse_repo="${__base_bash_libs_gh_parse_remote_url#ssh://git@github.com/}"
        ;;
    https://github.com/*)
        __base_bash_libs_gh_parse_repo="${__base_bash_libs_gh_parse_remote_url#https://github.com/}"
        ;;
    *)
        return 1
        ;;
    esac

    __base_bash_libs_gh_parse_repo="${__base_bash_libs_gh_parse_repo%.git}"
    [[ "$__base_bash_libs_gh_parse_repo" =~ ^[^/[:space:]?#]+/[^/[:space:]?#]+$ ]] || return 1
    printf -v "$__base_bash_libs_gh_parse_result_name" '%s' "$__base_bash_libs_gh_parse_repo"
}

base_gh_repo_from_remote_url() {
    if (($# != 2)); then
        base_std_log_error -l base_bash_libs.gh "Usage: base_gh_repo_from_remote_url <remote_url> <result_variable_name>"
        return 2
    fi
    __base_bash_libs_std_assert_public_variable_names__ base_gh_repo_from_remote_url "${2-}" || return 2

    local __base_bash_libs_gh_remote_url="$1"
    local __base_bash_libs_gh_result_name="$2"
    local __base_bash_libs_gh_parsed_repo

    if [[ -z "$__base_bash_libs_gh_remote_url" || -z "$__base_bash_libs_gh_result_name" ]]; then
        base_std_log_error -l base_bash_libs.gh "Usage: base_gh_repo_from_remote_url <remote_url> <result_variable_name>"
        return 2
    fi
    base_std_assert_variable_name "$__base_bash_libs_gh_result_name" || return 2
    __base_bash_libs_std_assert_writable_output__ base_gh_repo_from_remote_url "$__base_bash_libs_gh_result_name" || return 2

    __base_bash_libs_gh_parse_repo_from_remote_url__ "$__base_bash_libs_gh_remote_url" __base_bash_libs_gh_parsed_repo || return 2
    printf -v "$__base_bash_libs_gh_result_name" '%s' "$__base_bash_libs_gh_parsed_repo"
}

base_gh_infer_repo_from_origin() {
    if (($# < 2 || $# > 3)) || { (($# == 3)) && [[ "$3" != "--optional" ]]; }; then
        base_std_log_error -l base_bash_libs.gh "Usage: base_gh_infer_repo_from_origin <repo_dir> <result_variable_name> [--optional]"
        return 2
    fi
    __base_bash_libs_std_assert_public_variable_names__ base_gh_infer_repo_from_origin "${2-}" || return 2

    local __base_bash_libs_gh_infer_repo_dir="$1"
    local __base_bash_libs_gh_infer_result_name="$2"
    local __base_bash_libs_gh_infer_optional=0
    local __base_bash_libs_gh_infer_parsed_repo __base_bash_libs_gh_infer_remote_url

    if [[ -z "$__base_bash_libs_gh_infer_repo_dir" || -z "$__base_bash_libs_gh_infer_result_name" ]]; then
        base_std_log_error -l base_bash_libs.gh "Usage: base_gh_infer_repo_from_origin <repo_dir> <result_variable_name> [--optional]"
        return 2
    fi
    base_std_assert_variable_name "$__base_bash_libs_gh_infer_result_name" || return 2
    __base_bash_libs_std_assert_writable_output__ base_gh_infer_repo_from_origin "$__base_bash_libs_gh_infer_result_name" || return 2

    if [[ "${3:-}" == "--optional" ]]; then
        __base_bash_libs_gh_infer_optional=1
    fi

    __base_bash_libs_gh_infer_remote_url="$(git -C "$__base_bash_libs_gh_infer_repo_dir" remote get-url origin 2> /dev/null || true)"
    if [[ -z "$__base_bash_libs_gh_infer_remote_url" ]] ||
        ! __base_bash_libs_gh_parse_repo_from_remote_url__ "$__base_bash_libs_gh_infer_remote_url" __base_bash_libs_gh_infer_parsed_repo; then
        if ((__base_bash_libs_gh_infer_optional)); then
            printf -v "$__base_bash_libs_gh_infer_result_name" '%s' ""
            return 0
        fi
        base_std_log_error -l base_bash_libs.gh "Could not infer GitHub repository from '$__base_bash_libs_gh_infer_repo_dir' origin remote."
        return 1
    fi

    printf -v "$__base_bash_libs_gh_infer_result_name" '%s' "$__base_bash_libs_gh_infer_parsed_repo"
}

base_gh_repo_default_branch() {
    if (($# != 2)); then
        base_std_log_error -l base_bash_libs.gh "Usage: base_gh_repo_default_branch <owner/repo> <result_variable_name>"
        return 2
    fi
    __base_bash_libs_std_assert_public_variable_names__ base_gh_repo_default_branch "${2-}" || return 2

    local __base_bash_libs_gh_repo="$1"
    local __base_bash_libs_gh_repo_result_name="$2"
    local __base_bash_libs_gh_repo_default_branch __base_bash_libs_gh_repo_status=0

    if [[ -z "$__base_bash_libs_gh_repo" || -z "$__base_bash_libs_gh_repo_result_name" ]]; then
        base_std_log_error -l base_bash_libs.gh "Usage: base_gh_repo_default_branch <owner/repo> <result_variable_name>"
        return 2
    fi
    base_std_assert_variable_name "$__base_bash_libs_gh_repo_result_name" || return 2
    __base_bash_libs_std_assert_writable_output__ base_gh_repo_default_branch "$__base_bash_libs_gh_repo_result_name" || return 2

    base_gh_require_cli || return 1
    __base_bash_libs_gh_repo_default_branch="$(gh repo view "$__base_bash_libs_gh_repo" --json defaultBranchRef --jq .defaultBranchRef.name 2> /dev/null)" || __base_bash_libs_gh_repo_status=$?
    if ((__base_bash_libs_gh_repo_status != 0)); then
        base_gh_report_command_failure "$__base_bash_libs_gh_repo_status" repo view "$__base_bash_libs_gh_repo" --json defaultBranchRef --jq .defaultBranchRef.name
        return $?
    fi
    if [[ -z "$__base_bash_libs_gh_repo_default_branch" ]]; then
        base_std_log_error -l base_bash_libs.gh "GitHub repository '$__base_bash_libs_gh_repo' does not report a default branch."
        return 1
    fi

    printf -v "$__base_bash_libs_gh_repo_result_name" '%s' "$__base_bash_libs_gh_repo_default_branch"
}

__base_bash_libs_gh_api_controls_usage__() {
    base_std_log_error -l base_bash_libs.gh \
        "Usage: base_gh_api_with_retry [--sensitive] [--safe-display <label>] [--retry-policy read-only|never|replay-safe] [--max-attempts <1..10>] [--max-elapsed-seconds <1..3600>] [--attempt-timeout-seconds <1..600>] [--base-delay-seconds <0..60>] [--max-delay-seconds <1..300>] -- <endpoint> [gh api args...]"
}

__base_bash_libs_gh_api_bounded_decimal__() {
    local __base_bash_libs_gh_decimal_value="${1-}" __base_bash_libs_gh_decimal_min="${2-}" __base_bash_libs_gh_decimal_max="${3-}"
    local __base_bash_libs_gh_decimal_result_name="${4-}" __base_bash_libs_gh_decimal_normalized

    [[ "$__base_bash_libs_gh_decimal_value" =~ ^[0-9]+$ && ${#__base_bash_libs_gh_decimal_value} -le 4 ]] || return 1
    __base_bash_libs_gh_decimal_normalized=$((10#$__base_bash_libs_gh_decimal_value))
    ((__base_bash_libs_gh_decimal_normalized >= __base_bash_libs_gh_decimal_min && \
    __base_bash_libs_gh_decimal_normalized <= __base_bash_libs_gh_decimal_max)) || return 1
    printf -v "$__base_bash_libs_gh_decimal_result_name" '%s' "$__base_bash_libs_gh_decimal_normalized"
}

# Parse retry controls only at the beginning of the invocation. Once any
# framework control is present, `--` is mandatory so future gh flags cannot be
# mistaken for framework policy.
__base_bash_libs_gh_parse_api_controls__() {
    local __base_bash_libs_gh_controls_consumed_name="$1" __base_bash_libs_gh_controls_sensitive_name="$2"
    local __base_bash_libs_gh_controls_display_name="$3" __base_bash_libs_gh_controls_policy_name="$4"
    local __base_bash_libs_gh_controls_attempts_name="$5" __base_bash_libs_gh_controls_elapsed_name="$6"
    local __base_bash_libs_gh_controls_timeout_name="$7" __base_bash_libs_gh_controls_base_name="$8"
    local __base_bash_libs_gh_controls_cap_name="$9"
    shift 9

    local __base_bash_libs_gh_controls_consumed_value=0 __base_bash_libs_gh_controls_sensitive_value=0
    local __base_bash_libs_gh_controls_display_value="" __base_bash_libs_gh_controls_policy_value=read-only
    local __base_bash_libs_gh_controls_attempts_value=3 __base_bash_libs_gh_controls_elapsed_value=300
    local __base_bash_libs_gh_controls_timeout_value=60 __base_bash_libs_gh_controls_base_value=2
    local __base_bash_libs_gh_controls_cap_value=120 __base_bash_libs_gh_controls_separator=0
    local __base_bash_libs_gh_controls_display_seen=0 __base_bash_libs_gh_controls_policy_seen=0
    local __base_bash_libs_gh_controls_attempts_seen=0 __base_bash_libs_gh_controls_elapsed_seen=0
    local __base_bash_libs_gh_controls_timeout_seen=0 __base_bash_libs_gh_controls_base_seen=0
    local __base_bash_libs_gh_controls_cap_seen=0 __base_bash_libs_gh_controls_started=0

    case "${1-}" in
    --sensitive | --safe-display | --retry-policy | --max-attempts | \
        --max-elapsed-seconds | --attempt-timeout-seconds | \
        --base-delay-seconds | --max-delay-seconds)
        __base_bash_libs_gh_controls_started=1
        ;;
    esac

    if ((!__base_bash_libs_gh_controls_started)); then
        printf -v "$__base_bash_libs_gh_controls_consumed_name" '%s' 0
        printf -v "$__base_bash_libs_gh_controls_sensitive_name" '%s' 0
        printf -v "$__base_bash_libs_gh_controls_display_name" '%s' ""
        printf -v "$__base_bash_libs_gh_controls_policy_name" '%s' "$__base_bash_libs_gh_controls_policy_value"
        printf -v "$__base_bash_libs_gh_controls_attempts_name" '%s' "$__base_bash_libs_gh_controls_attempts_value"
        printf -v "$__base_bash_libs_gh_controls_elapsed_name" '%s' "$__base_bash_libs_gh_controls_elapsed_value"
        printf -v "$__base_bash_libs_gh_controls_timeout_name" '%s' "$__base_bash_libs_gh_controls_timeout_value"
        printf -v "$__base_bash_libs_gh_controls_base_name" '%s' "$__base_bash_libs_gh_controls_base_value"
        printf -v "$__base_bash_libs_gh_controls_cap_name" '%s' "$__base_bash_libs_gh_controls_cap_value"
        return 0
    fi

    while (($#)); do
        case "${1-}" in
        --sensitive)
            if ((__base_bash_libs_gh_controls_sensitive_value)); then
                __base_bash_libs_gh_api_controls_usage__
                return 2
            fi
            __base_bash_libs_gh_controls_sensitive_value=1
            __base_bash_libs_gh_controls_consumed_value=$((__base_bash_libs_gh_controls_consumed_value + 1))
            shift
            ;;
        --safe-display)
            if ((__base_bash_libs_gh_controls_display_seen)) || (($# < 2)) ||
                ! __base_bash_libs_std_is_safe_display__ "${2-}"; then
                base_std_log_error -l base_bash_libs.gh \
                    "base_gh_api_with_retry: --safe-display requires one non-empty printable ASCII label that does not begin with '-'."
                return 2
            fi
            __base_bash_libs_gh_controls_display_value="$2"
            __base_bash_libs_gh_controls_display_seen=1
            __base_bash_libs_gh_controls_consumed_value=$((__base_bash_libs_gh_controls_consumed_value + 2))
            shift 2
            ;;
        --retry-policy)
            if ((__base_bash_libs_gh_controls_policy_seen)) || (($# < 2)); then
                __base_bash_libs_gh_api_controls_usage__
                return 2
            fi
            case "$2" in
            read-only | never | replay-safe) __base_bash_libs_gh_controls_policy_value="$2" ;;
            *)
                base_std_log_error -l base_bash_libs.gh \
                    "base_gh_api_with_retry: --retry-policy must be read-only, never, or replay-safe."
                return 2
                ;;
            esac
            __base_bash_libs_gh_controls_policy_seen=1
            __base_bash_libs_gh_controls_consumed_value=$((__base_bash_libs_gh_controls_consumed_value + 2))
            shift 2
            ;;
        --max-attempts | --max-elapsed-seconds | --attempt-timeout-seconds | \
            --base-delay-seconds | --max-delay-seconds)
            local __base_bash_libs_gh_controls_numeric_option="$1" __base_bash_libs_gh_controls_numeric_value
            if (($# < 2)); then
                __base_bash_libs_gh_api_controls_usage__
                return 2
            fi
            case "$__base_bash_libs_gh_controls_numeric_option" in
            --max-attempts)
                ((__base_bash_libs_gh_controls_attempts_seen == 0)) &&
                    __base_bash_libs_gh_api_bounded_decimal__ "$2" 1 10 __base_bash_libs_gh_controls_numeric_value || {
                    __base_bash_libs_gh_api_controls_usage__
                    return 2
                }
                __base_bash_libs_gh_controls_attempts_seen=1
                __base_bash_libs_gh_controls_attempts_value="$__base_bash_libs_gh_controls_numeric_value"
                ;;
            --max-elapsed-seconds)
                ((__base_bash_libs_gh_controls_elapsed_seen == 0)) &&
                    __base_bash_libs_gh_api_bounded_decimal__ "$2" 1 3600 __base_bash_libs_gh_controls_numeric_value || {
                    __base_bash_libs_gh_api_controls_usage__
                    return 2
                }
                __base_bash_libs_gh_controls_elapsed_seen=1
                __base_bash_libs_gh_controls_elapsed_value="$__base_bash_libs_gh_controls_numeric_value"
                ;;
            --attempt-timeout-seconds)
                ((__base_bash_libs_gh_controls_timeout_seen == 0)) &&
                    __base_bash_libs_gh_api_bounded_decimal__ "$2" 1 600 __base_bash_libs_gh_controls_numeric_value || {
                    __base_bash_libs_gh_api_controls_usage__
                    return 2
                }
                __base_bash_libs_gh_controls_timeout_seen=1
                __base_bash_libs_gh_controls_timeout_value="$__base_bash_libs_gh_controls_numeric_value"
                ;;
            --base-delay-seconds)
                ((__base_bash_libs_gh_controls_base_seen == 0)) &&
                    __base_bash_libs_gh_api_bounded_decimal__ "$2" 0 60 __base_bash_libs_gh_controls_numeric_value || {
                    __base_bash_libs_gh_api_controls_usage__
                    return 2
                }
                __base_bash_libs_gh_controls_base_seen=1
                __base_bash_libs_gh_controls_base_value="$__base_bash_libs_gh_controls_numeric_value"
                ;;
            --max-delay-seconds)
                ((__base_bash_libs_gh_controls_cap_seen == 0)) &&
                    __base_bash_libs_gh_api_bounded_decimal__ "$2" 1 300 __base_bash_libs_gh_controls_numeric_value || {
                    __base_bash_libs_gh_api_controls_usage__
                    return 2
                }
                __base_bash_libs_gh_controls_cap_seen=1
                __base_bash_libs_gh_controls_cap_value="$__base_bash_libs_gh_controls_numeric_value"
                ;;
            esac
            __base_bash_libs_gh_controls_consumed_value=$((__base_bash_libs_gh_controls_consumed_value + 2))
            shift 2
            ;;
        --)
            __base_bash_libs_gh_controls_separator=1
            __base_bash_libs_gh_controls_consumed_value=$((__base_bash_libs_gh_controls_consumed_value + 1))
            shift
            break
            ;;
        *)
            base_std_log_error -l base_bash_libs.gh \
                "base_gh_api_with_retry: framework controls must end with -- before GitHub arguments."
            return 2
            ;;
        esac
    done

    if ((!__base_bash_libs_gh_controls_separator)); then
        base_std_log_error -l base_bash_libs.gh \
            "base_gh_api_with_retry: framework controls require -- before GitHub arguments."
        return 2
    fi
    if ((__base_bash_libs_gh_controls_display_seen && !__base_bash_libs_gh_controls_sensitive_value)); then
        base_std_log_error -l base_bash_libs.gh \
            "base_gh_api_with_retry: --safe-display is valid only with --sensitive."
        return 2
    fi
    if ((__base_bash_libs_gh_controls_base_value > __base_bash_libs_gh_controls_cap_value)); then
        base_std_log_error -l base_bash_libs.gh \
            "base_gh_api_with_retry: --base-delay-seconds must not exceed --max-delay-seconds."
        return 2
    fi

    printf -v "$__base_bash_libs_gh_controls_consumed_name" '%s' "$__base_bash_libs_gh_controls_consumed_value"
    printf -v "$__base_bash_libs_gh_controls_sensitive_name" '%s' "$__base_bash_libs_gh_controls_sensitive_value"
    printf -v "$__base_bash_libs_gh_controls_display_name" '%s' "$__base_bash_libs_gh_controls_display_value"
    printf -v "$__base_bash_libs_gh_controls_policy_name" '%s' "$__base_bash_libs_gh_controls_policy_value"
    printf -v "$__base_bash_libs_gh_controls_attempts_name" '%s' "$__base_bash_libs_gh_controls_attempts_value"
    printf -v "$__base_bash_libs_gh_controls_elapsed_name" '%s' "$__base_bash_libs_gh_controls_elapsed_value"
    printf -v "$__base_bash_libs_gh_controls_timeout_name" '%s' "$__base_bash_libs_gh_controls_timeout_value"
    printf -v "$__base_bash_libs_gh_controls_base_name" '%s' "$__base_bash_libs_gh_controls_base_value"
    printf -v "$__base_bash_libs_gh_controls_cap_name" '%s' "$__base_bash_libs_gh_controls_cap_value"
}

__base_bash_libs_gh_api_path_is_stream__() {
    local __base_bash_libs_gh_stream_path="${1-}"

    case "$__base_bash_libs_gh_stream_path" in
    - | /dev/stdin | /dev/fd/* | /proc/self/fd/* | /proc/[0-9]*/fd/*)
        return 0
        ;;
    esac
    [[ -n "$__base_bash_libs_gh_stream_path" ]] || return 1
    # Existing non-regular sources (FIFO, character/block device, or socket)
    # are not stable rewindable request data.
    [[ -e "$__base_bash_libs_gh_stream_path" && ! -f "$__base_bash_libs_gh_stream_path" ]] && return 0
    [[ -e /dev/stdin && "$__base_bash_libs_gh_stream_path" -ef /dev/stdin ]] && return 0
    [[ -e /dev/fd/0 && "$__base_bash_libs_gh_stream_path" -ef /dev/fd/0 ]]
}

__base_bash_libs_gh_api_classify_argv__() {
    local __base_bash_libs_gh_class_method_name="$1" __base_bash_libs_gh_class_include_name="$2"
    local __base_bash_libs_gh_class_stdin_name="$3" __base_bash_libs_gh_class_file_name="$4"
    local __base_bash_libs_gh_class_graphql_name="$5" __base_bash_libs_gh_class_ambiguous_name="$6"
    shift 6

    local __base_bash_libs_gh_class_method_value="" __base_bash_libs_gh_class_include_value=0
    local __base_bash_libs_gh_class_stdin_value=0 __base_bash_libs_gh_class_file_value=0
    local __base_bash_libs_gh_class_graphql_value=0 __base_bash_libs_gh_class_ambiguous_value=0
    local __base_bash_libs_gh_class_method_count=0 __base_bash_libs_gh_class_field_seen=0
    local __base_bash_libs_gh_class_input_seen=0 __base_bash_libs_gh_class_endpoint_count=0
    local __base_bash_libs_gh_class_endpoint="" __base_bash_libs_gh_class_token __base_bash_libs_gh_class_short
    local __base_bash_libs_gh_class_char __base_bash_libs_gh_class_value __base_bash_libs_gh_class_bool __base_bash_libs_gh_class_field_payload
    local __base_bash_libs_gh_class_file_path
    local __base_bash_libs_gh_class_flags_done=0

    while (($#)); do
        __base_bash_libs_gh_class_token="$1"
        shift

        if ((__base_bash_libs_gh_class_flags_done)); then
            __base_bash_libs_gh_class_endpoint_count=$((__base_bash_libs_gh_class_endpoint_count + 1))
            ((__base_bash_libs_gh_class_endpoint_count == 1)) && __base_bash_libs_gh_class_endpoint="$__base_bash_libs_gh_class_token"
            continue
        fi

        case "$__base_bash_libs_gh_class_token" in
        --)
            __base_bash_libs_gh_class_flags_done=1
            ;;
        --method | --field | --raw-field | --input | --cache | --header | \
            --hostname | --jq | --preview | --template)
            if (($# == 0)); then
                __base_bash_libs_gh_class_ambiguous_value=1
                continue
            fi
            __base_bash_libs_gh_class_value="$1"
            shift
            case "$__base_bash_libs_gh_class_token" in
            --method)
                __base_bash_libs_gh_class_method_count=$((__base_bash_libs_gh_class_method_count + 1))
                __base_bash_libs_gh_class_method_value="$__base_bash_libs_gh_class_value"
                [[ -n "$__base_bash_libs_gh_class_value" ]] || __base_bash_libs_gh_class_ambiguous_value=1
                ;;
            --field)
                __base_bash_libs_gh_class_field_seen=1
                [[ -n "$__base_bash_libs_gh_class_value" ]] || __base_bash_libs_gh_class_ambiguous_value=1
                if [[ "$__base_bash_libs_gh_class_value" == *=* ]]; then
                    __base_bash_libs_gh_class_field_payload="${__base_bash_libs_gh_class_value#*=}"
                else
                    __base_bash_libs_gh_class_field_payload=""
                fi
                if [[ "$__base_bash_libs_gh_class_field_payload" == @* ]]; then
                    __base_bash_libs_gh_class_file_path="${__base_bash_libs_gh_class_field_payload#@}"
                    if __base_bash_libs_gh_api_path_is_stream__ "$__base_bash_libs_gh_class_file_path"; then
                        __base_bash_libs_gh_class_stdin_value=1
                    else
                        __base_bash_libs_gh_class_file_value=1
                    fi
                fi
                ;;
            --raw-field)
                __base_bash_libs_gh_class_field_seen=1
                [[ -n "$__base_bash_libs_gh_class_value" ]] || __base_bash_libs_gh_class_ambiguous_value=1
                ;;
            --input)
                __base_bash_libs_gh_class_input_seen=$((__base_bash_libs_gh_class_input_seen + 1))
                if __base_bash_libs_gh_api_path_is_stream__ "$__base_bash_libs_gh_class_value"; then
                    __base_bash_libs_gh_class_stdin_value=1
                elif [[ -n "$__base_bash_libs_gh_class_value" ]]; then
                    __base_bash_libs_gh_class_file_value=1
                else
                    __base_bash_libs_gh_class_ambiguous_value=1
                fi
                ;;
            esac
            ;;
        --method=* | --field=* | --raw-field=* | --input=* | --cache=* | \
            --header=* | --hostname=* | --jq=* | --preview=* | --template=*)
            __base_bash_libs_gh_class_value="${__base_bash_libs_gh_class_token#*=}"
            case "$__base_bash_libs_gh_class_token" in
            --method=*)
                __base_bash_libs_gh_class_method_count=$((__base_bash_libs_gh_class_method_count + 1))
                __base_bash_libs_gh_class_method_value="$__base_bash_libs_gh_class_value"
                [[ -n "$__base_bash_libs_gh_class_value" ]] || __base_bash_libs_gh_class_ambiguous_value=1
                ;;
            --field=*)
                __base_bash_libs_gh_class_field_seen=1
                [[ -n "$__base_bash_libs_gh_class_value" ]] || __base_bash_libs_gh_class_ambiguous_value=1
                if [[ "$__base_bash_libs_gh_class_value" == *=* ]]; then
                    __base_bash_libs_gh_class_field_payload="${__base_bash_libs_gh_class_value#*=}"
                else
                    __base_bash_libs_gh_class_field_payload=""
                fi
                if [[ "$__base_bash_libs_gh_class_field_payload" == @* ]]; then
                    __base_bash_libs_gh_class_file_path="${__base_bash_libs_gh_class_field_payload#@}"
                    if __base_bash_libs_gh_api_path_is_stream__ "$__base_bash_libs_gh_class_file_path"; then
                        __base_bash_libs_gh_class_stdin_value=1
                    else
                        __base_bash_libs_gh_class_file_value=1
                    fi
                fi
                ;;
            --raw-field=*)
                __base_bash_libs_gh_class_field_seen=1
                [[ -n "$__base_bash_libs_gh_class_value" ]] || __base_bash_libs_gh_class_ambiguous_value=1
                ;;
            --input=*)
                __base_bash_libs_gh_class_input_seen=$((__base_bash_libs_gh_class_input_seen + 1))
                if __base_bash_libs_gh_api_path_is_stream__ "$__base_bash_libs_gh_class_value"; then
                    __base_bash_libs_gh_class_stdin_value=1
                elif [[ -n "$__base_bash_libs_gh_class_value" ]]; then
                    __base_bash_libs_gh_class_file_value=1
                else
                    __base_bash_libs_gh_class_ambiguous_value=1
                fi
                ;;
            *)
                [[ -n "$__base_bash_libs_gh_class_value" ]] || __base_bash_libs_gh_class_ambiguous_value=1
                ;;
            esac
            ;;
        --include)
            __base_bash_libs_gh_class_include_value=1
            ;;
        --include=*)
            __base_bash_libs_gh_class_bool="${__base_bash_libs_gh_class_token#*=}"
            case "$__base_bash_libs_gh_class_bool" in
            1 | t | T | true | TRUE | True) __base_bash_libs_gh_class_include_value=1 ;;
            0 | f | F | false | FALSE | False) __base_bash_libs_gh_class_include_value=0 ;;
            *) __base_bash_libs_gh_class_ambiguous_value=1 ;;
            esac
            ;;
        --allow-escape-sequences | --paginate | --silent | --slurp | --verbose) ;;
        --allow-escape-sequences=* | --paginate=* | --silent=* | --slurp=* | --verbose=*)
            __base_bash_libs_gh_class_bool="${__base_bash_libs_gh_class_token#*=}"
            case "$__base_bash_libs_gh_class_bool" in
            0 | 1 | f | F | false | FALSE | False | \
                t | T | true | TRUE | True) ;;
            *) __base_bash_libs_gh_class_ambiguous_value=1 ;;
            esac
            ;;
        --*)
            __base_bash_libs_gh_class_ambiguous_value=1
            ;;
        -?*)
            __base_bash_libs_gh_class_short="${__base_bash_libs_gh_class_token#-}"
            while [[ -n "$__base_bash_libs_gh_class_short" ]]; do
                __base_bash_libs_gh_class_char="${__base_bash_libs_gh_class_short:0:1}"
                __base_bash_libs_gh_class_short="${__base_bash_libs_gh_class_short:1}"
                case "$__base_bash_libs_gh_class_char" in
                i)
                    if [[ "$__base_bash_libs_gh_class_short" == =* ]]; then
                        __base_bash_libs_gh_class_bool="${__base_bash_libs_gh_class_short#=}"
                        __base_bash_libs_gh_class_short=""
                        case "$__base_bash_libs_gh_class_bool" in
                        1 | t | T | true | TRUE | True) __base_bash_libs_gh_class_include_value=1 ;;
                        0 | f | F | false | FALSE | False) __base_bash_libs_gh_class_include_value=0 ;;
                        *) __base_bash_libs_gh_class_ambiguous_value=1 ;;
                        esac
                    else
                        __base_bash_libs_gh_class_include_value=1
                    fi
                    ;;
                F | H | q | X | p | f | t)
                    if [[ -n "$__base_bash_libs_gh_class_short" ]]; then
                        __base_bash_libs_gh_class_value="$__base_bash_libs_gh_class_short"
                        __base_bash_libs_gh_class_value="${__base_bash_libs_gh_class_value#= }"
                        [[ "$__base_bash_libs_gh_class_short" == =* ]] &&
                            __base_bash_libs_gh_class_value="${__base_bash_libs_gh_class_short#=}"
                        __base_bash_libs_gh_class_short=""
                    elif (($#)); then
                        __base_bash_libs_gh_class_value="$1"
                        shift
                    else
                        __base_bash_libs_gh_class_value=""
                        __base_bash_libs_gh_class_ambiguous_value=1
                    fi
                    case "$__base_bash_libs_gh_class_char" in
                    X)
                        __base_bash_libs_gh_class_method_count=$((__base_bash_libs_gh_class_method_count + 1))
                        __base_bash_libs_gh_class_method_value="$__base_bash_libs_gh_class_value"
                        [[ -n "$__base_bash_libs_gh_class_value" ]] || __base_bash_libs_gh_class_ambiguous_value=1
                        ;;
                    F)
                        __base_bash_libs_gh_class_field_seen=1
                        [[ -n "$__base_bash_libs_gh_class_value" ]] || __base_bash_libs_gh_class_ambiguous_value=1
                        if [[ "$__base_bash_libs_gh_class_value" == *=* ]]; then
                            __base_bash_libs_gh_class_field_payload="${__base_bash_libs_gh_class_value#*=}"
                        else
                            __base_bash_libs_gh_class_field_payload=""
                        fi
                        if [[ "$__base_bash_libs_gh_class_field_payload" == @* ]]; then
                            __base_bash_libs_gh_class_file_path="${__base_bash_libs_gh_class_field_payload#@}"
                            if __base_bash_libs_gh_api_path_is_stream__ "$__base_bash_libs_gh_class_file_path"; then
                                __base_bash_libs_gh_class_stdin_value=1
                            else
                                __base_bash_libs_gh_class_file_value=1
                            fi
                        fi
                        ;;
                    f)
                        __base_bash_libs_gh_class_field_seen=1
                        [[ -n "$__base_bash_libs_gh_class_value" ]] || __base_bash_libs_gh_class_ambiguous_value=1
                        ;;
                    esac
                    break
                    ;;
                *)
                    __base_bash_libs_gh_class_ambiguous_value=1
                    __base_bash_libs_gh_class_short=""
                    ;;
                esac
            done
            ;;
        *)
            __base_bash_libs_gh_class_endpoint_count=$((__base_bash_libs_gh_class_endpoint_count + 1))
            ((__base_bash_libs_gh_class_endpoint_count == 1)) && __base_bash_libs_gh_class_endpoint="$__base_bash_libs_gh_class_token"
            ;;
        esac
    done

    ((__base_bash_libs_gh_class_endpoint_count == 1)) || __base_bash_libs_gh_class_ambiguous_value=1
    ((__base_bash_libs_gh_class_input_seen <= 1)) || __base_bash_libs_gh_class_ambiguous_value=1
    if ((__base_bash_libs_gh_class_method_count == 1)); then
        __base_bash_libs_gh_class_method_value="${__base_bash_libs_gh_class_method_value^^}"
    elif ((__base_bash_libs_gh_class_method_count == 0)); then
        if ((__base_bash_libs_gh_class_field_seen || __base_bash_libs_gh_class_input_seen)); then
            __base_bash_libs_gh_class_method_value=POST
        else
            __base_bash_libs_gh_class_method_value=GET
        fi
    else
        __base_bash_libs_gh_class_method_value=UNKNOWN
        __base_bash_libs_gh_class_ambiguous_value=1
    fi
    [[ "$__base_bash_libs_gh_class_endpoint" == "graphql" ]] && __base_bash_libs_gh_class_graphql_value=1

    printf -v "$__base_bash_libs_gh_class_method_name" '%s' "$__base_bash_libs_gh_class_method_value"
    printf -v "$__base_bash_libs_gh_class_include_name" '%s' "$__base_bash_libs_gh_class_include_value"
    printf -v "$__base_bash_libs_gh_class_stdin_name" '%s' "$__base_bash_libs_gh_class_stdin_value"
    printf -v "$__base_bash_libs_gh_class_file_name" '%s' "$__base_bash_libs_gh_class_file_value"
    printf -v "$__base_bash_libs_gh_class_graphql_name" '%s' "$__base_bash_libs_gh_class_graphql_value"
    printf -v "$__base_bash_libs_gh_class_ambiguous_name" '%s' "$__base_bash_libs_gh_class_ambiguous_value"
}

__base_bash_libs_gh_api_can_inject_include__() {
    local __base_bash_libs_gh_inject_result_name="$1" __base_bash_libs_gh_inject_value=1 __base_bash_libs_gh_inject_token
    shift

    # Forced terminal rendering can decorate the status line and destroy the
    # byte-exact prefix contract. Pagination can interleave multiple response
    # header blocks with bodies, while verbose mode uses a different channel.
    [[ -z "${GH_FORCE_TTY-}${CLICOLOR_FORCE-}${FORCE_COLOR-}" ]] ||
        __base_bash_libs_gh_inject_value=0
    for __base_bash_libs_gh_inject_token; do
        case "$__base_bash_libs_gh_inject_token" in
        --include | --include=* | -i | -i=* | \
            --paginate | --paginate=* | --slurp | --slurp=* | \
            --verbose | --verbose=*)
            __base_bash_libs_gh_inject_value=0
            ;;
        esac
    done
    printf -v "$__base_bash_libs_gh_inject_result_name" '%s' "$__base_bash_libs_gh_inject_value"
}

__base_bash_libs_gh_api_unstructured_transport_is_safe__() {
    local __base_bash_libs_gh_transport_result_name="$1" __base_bash_libs_gh_transport_value=1
    local __base_bash_libs_gh_transport_token
    shift

    for __base_bash_libs_gh_transport_token; do
        case "$__base_bash_libs_gh_transport_token" in
        --jq | --jq=* | --template | --template=* | --silent | --silent=true | \
            --paginate | --paginate=true | --slurp | --slurp=true | \
            --verbose | --verbose=true | -q | -q?* | -t | -t?*)
            __base_bash_libs_gh_transport_value=0
            ;;
        esac
    done
    case "${GH_DEBUG-}:${DEBUG-}" in
    *api*) __base_bash_libs_gh_transport_value=0 ;;
    esac
    printf -v "$__base_bash_libs_gh_transport_result_name" '%s' "$__base_bash_libs_gh_transport_value"
}

__base_bash_libs_gh_api_replay_file__() {
    local __base_bash_libs_gh_replay_file="$1" __base_bash_libs_gh_replay_prefix="${2-0}"

    if [[ "$__base_bash_libs_gh_replay_prefix" =~ ^[1-9][0-9]*$ ]]; then
        # A block exactly the size of the parsed header prefix makes POSIX dd
        # skip it without byte-at-a-time copying. Suppress dd's own EPIPE text;
        # the caller reports a channel-safe replay diagnostic.
        command dd if="$__base_bash_libs_gh_replay_file" bs="$__base_bash_libs_gh_replay_prefix" skip=1 2> /dev/null
    else
        command cat -- "$__base_bash_libs_gh_replay_file"
    fi
}

__base_bash_libs_gh_api_monotonic_seconds__() {
    local __base_bash_libs_gh_clock_result_name="$1" __base_bash_libs_gh_clock_value="${SECONDS:-0}"
    [[ "$__base_bash_libs_gh_clock_value" =~ ^[0-9]+$ ]] || return 1
    printf -v "$__base_bash_libs_gh_clock_result_name" '%s' "$__base_bash_libs_gh_clock_value"
}

__base_bash_libs_gh_api_epoch_seconds__() {
    local __base_bash_libs_gh_epoch_result_name="$1" __base_bash_libs_gh_epoch_value
    __base_bash_libs_gh_epoch_value="$(command date +%s 2> /dev/null)" || return 1
    [[ "$__base_bash_libs_gh_epoch_value" =~ ^[0-9]+$ && ${#__base_bash_libs_gh_epoch_value} -le 12 ]] || return 1
    printf -v "$__base_bash_libs_gh_epoch_result_name" '%s' "$__base_bash_libs_gh_epoch_value"
}

__base_bash_libs_gh_api_jitter_seconds__() {
    local __base_bash_libs_gh_jitter_result_name="$1" __base_bash_libs_gh_jitter_cap="$2"
    local __base_bash_libs_gh_jitter_floor __base_bash_libs_gh_jitter_span __base_bash_libs_gh_jitter_value

    ((__base_bash_libs_gh_jitter_cap > 0)) || {
        printf -v "$__base_bash_libs_gh_jitter_result_name" '%s' 0
        return 0
    }
    __base_bash_libs_gh_jitter_floor=$(((__base_bash_libs_gh_jitter_cap + 1) / 2))
    __base_bash_libs_gh_jitter_span=$((__base_bash_libs_gh_jitter_cap - __base_bash_libs_gh_jitter_floor + 1))
    __base_bash_libs_gh_jitter_value=$((__base_bash_libs_gh_jitter_floor + RANDOM % __base_bash_libs_gh_jitter_span))
    printf -v "$__base_bash_libs_gh_jitter_result_name" '%s' "$__base_bash_libs_gh_jitter_value"
}

__base_bash_libs_gh_api_sleep__() {
    local __base_bash_libs_gh_sleep_seconds="$1" __base_bash_libs_gh_sleep_pid="" __base_bash_libs_gh_sleep_status=0

    ((__base_bash_libs_gh_sleep_seconds > 0)) || return 0
    if ((__base_bash_libs_gh_api_cancel_status != 0)); then
        return "$__base_bash_libs_gh_api_cancel_status"
    fi

    __base_bash_libs_std_sleep_interval__ "$__base_bash_libs_gh_sleep_seconds" &
    __base_bash_libs_gh_sleep_pid=$!
    __base_bash_libs_gh_api_active_sleep_pid="$__base_bash_libs_gh_sleep_pid"
    if ((__base_bash_libs_gh_api_cancel_status != 0)); then
        kill -KILL "$__base_bash_libs_gh_sleep_pid" 2> /dev/null || true
        wait "$__base_bash_libs_gh_sleep_pid" 2> /dev/null || true
        __base_bash_libs_gh_api_active_sleep_pid=""
        return "$__base_bash_libs_gh_api_cancel_status"
    fi
    if wait "$__base_bash_libs_gh_sleep_pid" 2> /dev/null; then
        __base_bash_libs_gh_sleep_status=0
    else
        __base_bash_libs_gh_sleep_status=$?
    fi
    __base_bash_libs_gh_api_active_sleep_pid=""
    if ((__base_bash_libs_gh_api_cancel_status != 0)); then
        kill -KILL "$__base_bash_libs_gh_sleep_pid" 2> /dev/null || true
        wait "$__base_bash_libs_gh_sleep_pid" 2> /dev/null || true
        return "$__base_bash_libs_gh_api_cancel_status"
    fi
    return "$__base_bash_libs_gh_sleep_status"
}

# Bash functions share dynamic scope with their caller. Keep test seams and
# caller-shadowed private functions useful without allowing them to rewrite
# the authoritative retry state in base_gh_api_with_retry.
__base_bash_libs_gh_api_call_hook__() {
    local __base_bash_libs_gh_hook_kind="$1"
    shift
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_gh_api_consumed __base_bash_libs_gh_api_sensitive __base_bash_libs_gh_api_safe_display __base_bash_libs_gh_api_policy
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_gh_api_max_attempts __base_bash_libs_gh_api_max_elapsed __base_bash_libs_gh_api_attempt_timeout
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_gh_api_base_delay __base_bash_libs_gh_api_max_delay __base_bash_libs_gh_api_method __base_bash_libs_gh_api_include
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_gh_api_stdin __base_bash_libs_gh_api_file __base_bash_libs_gh_api_graphql __base_bash_libs_gh_api_ambiguous
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_gh_api_retry_authorized __base_bash_libs_gh_api_stdout __base_bash_libs_gh_api_stderr __base_bash_libs_gh_api_display
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_gh_api_injected_include __base_bash_libs_gh_api_header_bytes __base_bash_libs_gh_api_suppress_stdout
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_gh_api_can_inject __base_bash_libs_gh_api_transport_syntax_safe __base_bash_libs_gh_api_transport_allowed
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_gh_api_structured_metadata __base_bash_libs_gh_api_metadata_include
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_gh_api_probe_status __base_bash_libs_gh_api_probe_retry
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_gh_api_probe_remaining __base_bash_libs_gh_api_probe_reset __base_bash_libs_gh_api_probe_invalid
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_gh_api_timeout_path __base_bash_libs_gh_api_attempt __base_bash_libs_gh_api_status __base_bash_libs_gh_api_start
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_gh_api_now __base_bash_libs_gh_api_elapsed __base_bash_libs_gh_api_remaining __base_bash_libs_gh_api_effective_timeout
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_gh_api_retryable __base_bash_libs_gh_api_rate_limited __base_bash_libs_gh_api_server_delay
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_gh_api_metadata_invalid __base_bash_libs_gh_api_backoff_cap __base_bash_libs_gh_api_delay __base_bash_libs_gh_api_reason
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_gh_api_owned_workspace __base_bash_libs_gh_api_guardian_pid __base_bash_libs_gh_api_guardian_fd
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_gh_api_public_status __base_bash_libs_gh_api_saved_hup_trap __base_bash_libs_gh_api_saved_int_trap
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shields.
    local __base_bash_libs_gh_api_saved_quit_trap __base_bash_libs_gh_api_saved_term_trap
    # shellcheck disable=SC2034 # Deliberate dynamic-scope collision shield.
    local -a __base_bash_libs_gh_api_attempt_argv=()

    case "$__base_bash_libs_gh_hook_kind" in
    attempt) __base_bash_libs_gh_api_attempt__ "$@" ;;
    epoch) __base_bash_libs_gh_api_epoch_seconds__ "$@" ;;
    jitter) __base_bash_libs_gh_api_jitter_seconds__ "$@" ;;
    monotonic) __base_bash_libs_gh_api_monotonic_seconds__ "$@" ;;
    sleep) __base_bash_libs_gh_api_sleep__ "$@" ;;
    *) return 1 ;;
    esac
}

__base_bash_libs_gh_api_attempt__() {
    local __base_bash_libs_gh_attempt_timeout="$1" __base_bash_libs_gh_attempt_timeout_path="$2"
    local __base_bash_libs_gh_attempt_number="$3" __base_bash_libs_gh_attempt_stdout="$4" __base_bash_libs_gh_attempt_stderr="$5"
    local __base_bash_libs_gh_attempt_outcome=command
    shift 5

    # Keep the timeout supervisor in the calling shell so caller-local Bash
    # functions and terminal input remain available to the attempted command.
    # The invocation workspace independently captures its output channels.
    __base_bash_libs_std_run_once__ __base_bash_libs_gh_attempt_outcome \
        "$__base_bash_libs_gh_attempt_timeout" "$__base_bash_libs_gh_attempt_timeout_path" \
        "$__base_bash_libs_gh_attempt_number" gh api "$@" \
        >| "$__base_bash_libs_gh_attempt_stdout" 2>| "$__base_bash_libs_gh_attempt_stderr"
}

__base_bash_libs_gh_api_byte_length__() {
    local __base_bash_libs_gh_byte_result_name="$1" __base_bash_libs_gh_byte_value __base_bash_libs_gh_byte_count

    __base_bash_libs_gh_byte_count="$(printf '%s' "$2" | command wc -c 2> /dev/null)" || return 1
    __base_bash_libs_gh_byte_count="${__base_bash_libs_gh_byte_count//[[:space:]]/}"
    [[ "$__base_bash_libs_gh_byte_count" =~ ^[0-9]{1,8}$ ]] || return 1
    __base_bash_libs_gh_byte_value="$((10#$__base_bash_libs_gh_byte_count))"
    printf -v "$__base_bash_libs_gh_byte_result_name" '%s' "$__base_bash_libs_gh_byte_value"
}

__base_bash_libs_gh_api_file_prefix_is_nul_free__() {
    local __base_bash_libs_gh_nul_file="$1" __base_bash_libs_gh_nul_bytes="$2"
    local __base_bash_libs_gh_nul_raw_count __base_bash_libs_gh_nul_clean_count
    local -a __base_bash_libs_gh_nul_pipeline_status=()

    [[ "$__base_bash_libs_gh_nul_bytes" =~ ^[1-9][0-9]{0,7}$ ]] || return 1
    __base_bash_libs_gh_nul_raw_count="$(
        LC_ALL=C command dd if="$__base_bash_libs_gh_nul_file" bs="$__base_bash_libs_gh_nul_bytes" count=1 2> /dev/null |
            LC_ALL=C command wc -c 2> /dev/null
        __base_bash_libs_gh_nul_pipeline_status=("${PIPESTATUS[@]}")
        ((__base_bash_libs_gh_nul_pipeline_status[0] == 0 && \
        __base_bash_libs_gh_nul_pipeline_status[1] == 0)) || exit 1
    )" || return 1
    __base_bash_libs_gh_nul_clean_count="$(
        LC_ALL=C command dd if="$__base_bash_libs_gh_nul_file" bs="$__base_bash_libs_gh_nul_bytes" count=1 2> /dev/null |
            LC_ALL=C command tr -d '\000' |
            LC_ALL=C command wc -c 2> /dev/null
        __base_bash_libs_gh_nul_pipeline_status=("${PIPESTATUS[@]}")
        ((__base_bash_libs_gh_nul_pipeline_status[0] == 0 && \
        __base_bash_libs_gh_nul_pipeline_status[1] == 0 && \
        __base_bash_libs_gh_nul_pipeline_status[2] == 0)) || exit 1
    )" || return 1
    __base_bash_libs_gh_nul_raw_count="${__base_bash_libs_gh_nul_raw_count//[[:space:]]/}"
    __base_bash_libs_gh_nul_clean_count="${__base_bash_libs_gh_nul_clean_count//[[:space:]]/}"
    [[ "$__base_bash_libs_gh_nul_raw_count" =~ ^[0-9]{1,8}$ &&
        "$__base_bash_libs_gh_nul_clean_count" =~ ^[0-9]{1,8}$ ]] || return 1
    ((10#$__base_bash_libs_gh_nul_raw_count == 10#$__base_bash_libs_gh_nul_bytes)) || return 1
    ((10#$__base_bash_libs_gh_nul_clean_count == 10#$__base_bash_libs_gh_nul_raw_count))
}

__base_bash_libs_gh_api_file_size__() {
    local __base_bash_libs_gh_size_result_name="$1" __base_bash_libs_gh_size_file="$2" __base_bash_libs_gh_size_value=""

    [[ -f "$__base_bash_libs_gh_size_file" ]] || return 1
    if __base_bash_libs_gh_size_value="$(
        LC_ALL=C command stat -c '%s' "$__base_bash_libs_gh_size_file" 2> /dev/null
    )" && [[ "$__base_bash_libs_gh_size_value" =~ ^[0-9]{1,18}$ ]]; then
        :
    elif __base_bash_libs_gh_size_value="$(
        LC_ALL=C command stat -f '%z' "$__base_bash_libs_gh_size_file" 2> /dev/null
    )" && [[ "$__base_bash_libs_gh_size_value" =~ ^[0-9]{1,18}$ ]]; then
        :
    else
        return 1
    fi
    printf -v "$__base_bash_libs_gh_size_result_name" '%s' "$((10#$__base_bash_libs_gh_size_value))"
}

__base_bash_libs_gh_api_file_is_nul_free__() {
    local __base_bash_libs_gh_nul_file="$1" __base_bash_libs_gh_nul_max_bytes="$2"
    local __base_bash_libs_gh_nul_raw_count __base_bash_libs_gh_nul_clean_count
    local -a __base_bash_libs_gh_nul_pipeline_status=()

    __base_bash_libs_gh_api_file_size__ __base_bash_libs_gh_nul_raw_count "$__base_bash_libs_gh_nul_file" || return 1
    ((10#$__base_bash_libs_gh_nul_raw_count <= __base_bash_libs_gh_nul_max_bytes)) || return 1
    __base_bash_libs_gh_nul_clean_count="$(
        LC_ALL=C command tr -d '\000' < "$__base_bash_libs_gh_nul_file" |
            LC_ALL=C command wc -c 2> /dev/null
        __base_bash_libs_gh_nul_pipeline_status=("${PIPESTATUS[@]}")
        ((__base_bash_libs_gh_nul_pipeline_status[0] == 0 && \
        __base_bash_libs_gh_nul_pipeline_status[1] == 0)) || exit 1
    )" || return 1
    __base_bash_libs_gh_nul_clean_count="${__base_bash_libs_gh_nul_clean_count//[[:space:]]/}"
    [[ "$__base_bash_libs_gh_nul_clean_count" =~ ^[0-9]{1,8}$ ]] || return 1
    ((10#$__base_bash_libs_gh_nul_clean_count == 10#$__base_bash_libs_gh_nul_raw_count))
}

__base_bash_libs_gh_api_parse_headers__() {
    local __base_bash_libs_gh_headers_file="$1" __base_bash_libs_gh_headers_status_name="$2"
    local __base_bash_libs_gh_headers_retry_name="$3" __base_bash_libs_gh_headers_remaining_name="$4"
    local __base_bash_libs_gh_headers_reset_name="$5" __base_bash_libs_gh_headers_invalid_name="$6"
    local __base_bash_libs_gh_headers_bytes_name="${7-}"
    local __base_bash_libs_gh_headers_line="" __base_bash_libs_gh_headers_raw_line=""
    local __base_bash_libs_gh_headers_name __base_bash_libs_gh_headers_value
    local __base_bash_libs_gh_headers_status_value="" __base_bash_libs_gh_headers_retry_value=""
    local __base_bash_libs_gh_headers_remaining_value="" __base_bash_libs_gh_headers_reset_value=""
    local __base_bash_libs_gh_headers_invalid_value=0 __base_bash_libs_gh_headers_lines=0
    local __base_bash_libs_gh_headers_terminated=0 __base_bash_libs_gh_headers_bytes=0 __base_bash_libs_gh_headers_normalized
    local __base_bash_libs_gh_headers_line_bytes=0

    {
        if IFS= read -r __base_bash_libs_gh_headers_line <&7; then
            __base_bash_libs_gh_headers_raw_line="$__base_bash_libs_gh_headers_line"
            __base_bash_libs_gh_headers_line="${__base_bash_libs_gh_headers_line%$'\r'}"
            if ! __base_bash_libs_gh_api_byte_length__ __base_bash_libs_gh_headers_line_bytes "$__base_bash_libs_gh_headers_raw_line"; then
                printf -v "$__base_bash_libs_gh_headers_status_name" '%s' ""
                printf -v "$__base_bash_libs_gh_headers_retry_name" '%s' ""
                printf -v "$__base_bash_libs_gh_headers_remaining_name" '%s' ""
                printf -v "$__base_bash_libs_gh_headers_reset_name" '%s' ""
                printf -v "$__base_bash_libs_gh_headers_invalid_name" '%s' 1
                [[ -z "$__base_bash_libs_gh_headers_bytes_name" ]] ||
                    printf -v "$__base_bash_libs_gh_headers_bytes_name" '%s' 0
                return 0
            fi
            __base_bash_libs_gh_headers_bytes=$((__base_bash_libs_gh_headers_line_bytes + 1))
            if ((__base_bash_libs_gh_headers_line_bytes > 8192 || __base_bash_libs_gh_headers_bytes > 65536)); then
                __base_bash_libs_gh_headers_invalid_value=1
            elif [[ "$__base_bash_libs_gh_headers_line" =~ [[:cntrl:]] ]]; then
                __base_bash_libs_gh_headers_invalid_value=1
            elif [[ "$__base_bash_libs_gh_headers_line" =~ ^HTTP/[0-9]+([.][0-9]+)?[[:space:]]+([0-9]{3})([[:space:]].*)?$ ]]; then
                __base_bash_libs_gh_headers_status_value="${BASH_REMATCH[2]}"
            else
                printf -v "$__base_bash_libs_gh_headers_status_name" '%s' ""
                printf -v "$__base_bash_libs_gh_headers_retry_name" '%s' ""
                printf -v "$__base_bash_libs_gh_headers_remaining_name" '%s' ""
                printf -v "$__base_bash_libs_gh_headers_reset_name" '%s' ""
                printf -v "$__base_bash_libs_gh_headers_invalid_name" '%s' 0
                [[ -z "$__base_bash_libs_gh_headers_bytes_name" ]] ||
                    printf -v "$__base_bash_libs_gh_headers_bytes_name" '%s' 0
                return 0
            fi
        else
            printf -v "$__base_bash_libs_gh_headers_status_name" '%s' ""
            printf -v "$__base_bash_libs_gh_headers_retry_name" '%s' ""
            printf -v "$__base_bash_libs_gh_headers_remaining_name" '%s' ""
            printf -v "$__base_bash_libs_gh_headers_reset_name" '%s' ""
            printf -v "$__base_bash_libs_gh_headers_invalid_name" '%s' 0
            [[ -z "$__base_bash_libs_gh_headers_bytes_name" ]] ||
                printf -v "$__base_bash_libs_gh_headers_bytes_name" '%s' 0
            return 0
        fi

        while IFS= read -r __base_bash_libs_gh_headers_line <&7; do
            __base_bash_libs_gh_headers_raw_line="$__base_bash_libs_gh_headers_line"
            __base_bash_libs_gh_headers_line="${__base_bash_libs_gh_headers_line%$'\r'}"
            if ! __base_bash_libs_gh_api_byte_length__ __base_bash_libs_gh_headers_line_bytes "$__base_bash_libs_gh_headers_raw_line"; then
                __base_bash_libs_gh_headers_invalid_value=1
                break
            fi
            __base_bash_libs_gh_headers_bytes=$((__base_bash_libs_gh_headers_bytes + __base_bash_libs_gh_headers_line_bytes + 1))
            if [[ -z "$__base_bash_libs_gh_headers_line" ]]; then
                __base_bash_libs_gh_headers_terminated=1
                break
            fi
            __base_bash_libs_gh_headers_lines=$((__base_bash_libs_gh_headers_lines + 1))
            if ((__base_bash_libs_gh_headers_lines > 100 || __base_bash_libs_gh_headers_bytes > 65536)) ||
                ((__base_bash_libs_gh_headers_line_bytes > 8192)); then
                __base_bash_libs_gh_headers_invalid_value=1
                break
            fi
            __base_bash_libs_gh_headers_normalized="${__base_bash_libs_gh_headers_line//$'\t'/}"
            if [[ "$__base_bash_libs_gh_headers_normalized" =~ [[:cntrl:]] ]]; then
                __base_bash_libs_gh_headers_invalid_value=1
                continue
            fi
            [[ "$__base_bash_libs_gh_headers_line" == *:* ]] || continue
            __base_bash_libs_gh_headers_name="${__base_bash_libs_gh_headers_line%%:*}"
            __base_bash_libs_gh_headers_name="${__base_bash_libs_gh_headers_name,,}"
            __base_bash_libs_gh_headers_value="${__base_bash_libs_gh_headers_line#*:}"
            __base_bash_libs_gh_headers_value="${__base_bash_libs_gh_headers_value#"${__base_bash_libs_gh_headers_value%%[!$' \t']*}"}"
            __base_bash_libs_gh_headers_value="${__base_bash_libs_gh_headers_value%"${__base_bash_libs_gh_headers_value##*[!$' \t']}"}"
            case "$__base_bash_libs_gh_headers_name" in
            retry-after)
                if [[ ! "$__base_bash_libs_gh_headers_value" =~ ^[0-9]+$ || ${#__base_bash_libs_gh_headers_value} -gt 10 ]]; then
                    __base_bash_libs_gh_headers_invalid_value=1
                elif [[ -n "$__base_bash_libs_gh_headers_retry_value" &&
                    "$__base_bash_libs_gh_headers_retry_value" != "$__base_bash_libs_gh_headers_value" ]]; then
                    __base_bash_libs_gh_headers_invalid_value=1
                else
                    __base_bash_libs_gh_headers_retry_value="$((10#$__base_bash_libs_gh_headers_value))"
                fi
                ;;
            x-ratelimit-remaining)
                if [[ "$__base_bash_libs_gh_headers_value" =~ ^[0-9]+$ && ${#__base_bash_libs_gh_headers_value} -le 10 ]]; then
                    __base_bash_libs_gh_headers_normalized="$((10#$__base_bash_libs_gh_headers_value))"
                    if [[ -n "$__base_bash_libs_gh_headers_remaining_value" &&
                        "$__base_bash_libs_gh_headers_remaining_value" != "$__base_bash_libs_gh_headers_normalized" ]]; then
                        __base_bash_libs_gh_headers_invalid_value=1
                    else
                        __base_bash_libs_gh_headers_remaining_value="$__base_bash_libs_gh_headers_normalized"
                    fi
                else
                    __base_bash_libs_gh_headers_invalid_value=1
                fi
                ;;
            x-ratelimit-reset)
                if [[ "$__base_bash_libs_gh_headers_value" =~ ^[0-9]+$ && ${#__base_bash_libs_gh_headers_value} -le 12 ]]; then
                    __base_bash_libs_gh_headers_normalized="$((10#$__base_bash_libs_gh_headers_value))"
                    if [[ -n "$__base_bash_libs_gh_headers_reset_value" &&
                        "$__base_bash_libs_gh_headers_reset_value" != "$__base_bash_libs_gh_headers_normalized" ]]; then
                        __base_bash_libs_gh_headers_invalid_value=1
                    else
                        __base_bash_libs_gh_headers_reset_value="$__base_bash_libs_gh_headers_normalized"
                    fi
                else
                    __base_bash_libs_gh_headers_invalid_value=1
                fi
                ;;
            esac
        done
        ((__base_bash_libs_gh_headers_terminated)) || __base_bash_libs_gh_headers_invalid_value=1
    } 7< "$__base_bash_libs_gh_headers_file"
    ((__base_bash_libs_gh_headers_terminated)) || __base_bash_libs_gh_headers_bytes=0
    if ((__base_bash_libs_gh_headers_bytes > 0)) &&
        ! __base_bash_libs_gh_api_file_prefix_is_nul_free__ "$__base_bash_libs_gh_headers_file" \
            "$__base_bash_libs_gh_headers_bytes"; then
        __base_bash_libs_gh_headers_status_value=""
        __base_bash_libs_gh_headers_retry_value=""
        __base_bash_libs_gh_headers_remaining_value=""
        __base_bash_libs_gh_headers_reset_value=""
        __base_bash_libs_gh_headers_invalid_value=1
        __base_bash_libs_gh_headers_bytes=0
    fi

    printf -v "$__base_bash_libs_gh_headers_status_name" '%s' "$__base_bash_libs_gh_headers_status_value"
    printf -v "$__base_bash_libs_gh_headers_retry_name" '%s' "$__base_bash_libs_gh_headers_retry_value"
    printf -v "$__base_bash_libs_gh_headers_remaining_name" '%s' "$__base_bash_libs_gh_headers_remaining_value"
    printf -v "$__base_bash_libs_gh_headers_reset_name" '%s' "$__base_bash_libs_gh_headers_reset_value"
    printf -v "$__base_bash_libs_gh_headers_invalid_name" '%s' "$__base_bash_libs_gh_headers_invalid_value"
    [[ -z "$__base_bash_libs_gh_headers_bytes_name" ]] ||
        printf -v "$__base_bash_libs_gh_headers_bytes_name" '%s' "$__base_bash_libs_gh_headers_bytes"
}

__base_bash_libs_gh_api_parse_stderr__() {
    local __base_bash_libs_gh_stderr_file="$1" __base_bash_libs_gh_stderr_status_name="$2"
    local __base_bash_libs_gh_stderr_transport_name="$3" __base_bash_libs_gh_stderr_invalid_name="$4"
    local __base_bash_libs_gh_stderr_rate_name="$5"
    local __base_bash_libs_gh_stderr_line="" __base_bash_libs_gh_stderr_first="" __base_bash_libs_gh_stderr_second=""
    local __base_bash_libs_gh_stderr_lower __base_bash_libs_gh_stderr_detail=""
    local __base_bash_libs_gh_stderr_transport_value=0 __base_bash_libs_gh_stderr_lines=0
    local __base_bash_libs_gh_stderr_invalid_value=0
    local __base_bash_libs_gh_stderr_url_error_re='^(Get|Head|Options|Post|Put|Patch|Delete) "https?://[^"[:cntrl:]]+": (.+)$'

    if ! __base_bash_libs_gh_api_file_is_nul_free__ "$__base_bash_libs_gh_stderr_file" 16386; then
        __base_bash_libs_gh_stderr_invalid_value=1
    else
        while IFS= read -r __base_bash_libs_gh_stderr_line <&7 || [[ -n "$__base_bash_libs_gh_stderr_line" ]]; do
            __base_bash_libs_gh_stderr_lines=$((__base_bash_libs_gh_stderr_lines + 1))
            if ((__base_bash_libs_gh_stderr_lines > 256)) || ((${#__base_bash_libs_gh_stderr_line} > 8192)); then
                __base_bash_libs_gh_stderr_lines=257
                break
            fi
            case "$__base_bash_libs_gh_stderr_lines" in
            1) __base_bash_libs_gh_stderr_first="$__base_bash_libs_gh_stderr_line" ;;
            2) __base_bash_libs_gh_stderr_second="$__base_bash_libs_gh_stderr_line" ;;
            esac
        done 7< "$__base_bash_libs_gh_stderr_file"
    fi

    # GitHub CLI renders HTTP/API response errors as `gh: ...`, so that
    # channel is attacker-influenced and never authorizes a retry. Genuine
    # client.Do transport errors are either one raw Go url.Error line or the
    # exact two-line friendly DNS diagnostic. Match the whole file and only a
    # narrow transient suffix allowlist; extra/debug lines fail closed.
    if ((!__base_bash_libs_gh_stderr_invalid_value)) && ((__base_bash_libs_gh_stderr_lines == 2)) &&
        [[ "$__base_bash_libs_gh_stderr_first" =~ ^error\ connecting\ to\ ([A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?)(:[0-9]{1,5})?$ ]] &&
        [[ "$__base_bash_libs_gh_stderr_second" == "check your internet connection or https://githubstatus.com" ]]; then
        __base_bash_libs_gh_stderr_transport_value=1
    elif ((!__base_bash_libs_gh_stderr_invalid_value)) && ((__base_bash_libs_gh_stderr_lines == 1)) &&
        [[ "$__base_bash_libs_gh_stderr_first" =~ $__base_bash_libs_gh_stderr_url_error_re ]]; then
        __base_bash_libs_gh_stderr_detail="${BASH_REMATCH[2]}"
        __base_bash_libs_gh_stderr_lower="${__base_bash_libs_gh_stderr_detail,,}"
        case "$__base_bash_libs_gh_stderr_lower" in
        "eof" | "unexpected eof" | "net/http: tls handshake timeout" | \
            dial\ tcp\ *:\ connect:\ connection\ refused | \
            dial\ tcp\ *:\ connect:\ network\ is\ unreachable | \
            dial\ tcp\ *:\ connect:\ no\ route\ to\ host | \
            read\ tcp\ *:\ read:\ connection\ reset\ by\ peer | \
            write\ tcp\ *:\ write:\ connection\ reset\ by\ peer | \
            *": i/o timeout" | *": connection timed out")
            __base_bash_libs_gh_stderr_transport_value=1
            ;;
        esac
    fi

    printf -v "$__base_bash_libs_gh_stderr_status_name" '%s' ""
    printf -v "$__base_bash_libs_gh_stderr_transport_name" '%s' "$__base_bash_libs_gh_stderr_transport_value"
    printf -v "$__base_bash_libs_gh_stderr_invalid_name" '%s' "$__base_bash_libs_gh_stderr_invalid_value"
    printf -v "$__base_bash_libs_gh_stderr_rate_name" '%s' 0
}

__base_bash_libs_gh_api_failure_metadata__() {
    local __base_bash_libs_gh_meta_exit_status="$1" __base_bash_libs_gh_meta_include="$2"
    local __base_bash_libs_gh_meta_stdout="$3" __base_bash_libs_gh_meta_stderr="$4"
    local __base_bash_libs_gh_meta_retryable_name="$5" __base_bash_libs_gh_meta_rate_name="$6"
    local __base_bash_libs_gh_meta_delay_name="$7" __base_bash_libs_gh_meta_invalid_name="$8"
    local __base_bash_libs_gh_meta_status_name="${9-}"
    local __base_bash_libs_gh_meta_transport_allowed="${10-1}"
    local __base_bash_libs_gh_meta_header_status="" __base_bash_libs_gh_meta_stderr_status=""
    local __base_bash_libs_gh_meta_retry_after="" __base_bash_libs_gh_meta_remaining="" __base_bash_libs_gh_meta_reset=""
    local __base_bash_libs_gh_meta_headers_invalid=0 __base_bash_libs_gh_meta_stderr_invalid=0
    local __base_bash_libs_gh_meta_transport=0 __base_bash_libs_gh_meta_stderr_rate=0 __base_bash_libs_gh_meta_status="" __base_bash_libs_gh_meta_epoch
    local __base_bash_libs_gh_meta_epoch_output="" __base_bash_libs_gh_meta_reset_delay=""
    local __base_bash_libs_gh_meta_retryable_value=0 __base_bash_libs_gh_meta_rate_value=0
    local __base_bash_libs_gh_meta_delay_value="" __base_bash_libs_gh_meta_invalid_value=0

    if ((__base_bash_libs_gh_meta_include)); then
        __base_bash_libs_gh_api_parse_headers__ "$__base_bash_libs_gh_meta_stdout" __base_bash_libs_gh_meta_header_status \
            __base_bash_libs_gh_meta_retry_after __base_bash_libs_gh_meta_remaining __base_bash_libs_gh_meta_reset \
            __base_bash_libs_gh_meta_headers_invalid
    fi
    __base_bash_libs_gh_api_parse_stderr__ "$__base_bash_libs_gh_meta_stderr" __base_bash_libs_gh_meta_stderr_status \
        __base_bash_libs_gh_meta_transport __base_bash_libs_gh_meta_stderr_invalid __base_bash_libs_gh_meta_stderr_rate

    # gh does not append the real HTTP status for every error-body shape;
    # `errors[]` strings can therefore imitate "(HTTP 503)" on stderr. Only
    # the bounded leading header block is authoritative response metadata.
    if [[ -n "$__base_bash_libs_gh_meta_header_status" ]]; then
        __base_bash_libs_gh_meta_status="$__base_bash_libs_gh_meta_header_status"
    fi
    ((__base_bash_libs_gh_meta_headers_invalid || __base_bash_libs_gh_meta_stderr_invalid)) &&
        __base_bash_libs_gh_meta_invalid_value=1

    if ((__base_bash_libs_gh_meta_exit_status == 2 || __base_bash_libs_gh_meta_exit_status == 4)); then
        __base_bash_libs_gh_meta_retryable_value=0
    elif ((__base_bash_libs_gh_meta_exit_status == 124)); then
        __base_bash_libs_gh_meta_retryable_value=1
    elif ((__base_bash_libs_gh_meta_exit_status >= 128 && __base_bash_libs_gh_meta_exit_status <= 192)); then
        # Preserve conventional signal-derived statuses, including Ctrl-C
        # (130), KILL (137), and TERM (143), without replaying the request.
        __base_bash_libs_gh_meta_retryable_value=0
    elif [[ -n "$__base_bash_libs_gh_meta_status" ]]; then
        case "$__base_bash_libs_gh_meta_status" in
        408 | 425 | 429 | 500 | 502 | 503 | 504)
            __base_bash_libs_gh_meta_retryable_value=1
            ;;
        403)
            if [[ -n "$__base_bash_libs_gh_meta_retry_after" || "$__base_bash_libs_gh_meta_remaining" == "0" ]]; then
                __base_bash_libs_gh_meta_retryable_value=1
            fi
            ;;
        esac
    elif ((__base_bash_libs_gh_meta_transport && __base_bash_libs_gh_meta_transport_allowed)); then
        __base_bash_libs_gh_meta_retryable_value=1
    fi

    if ((__base_bash_libs_gh_meta_retryable_value)) && {
        [[ "$__base_bash_libs_gh_meta_status" == "429" || "$__base_bash_libs_gh_meta_status" == "403" ||
            "$__base_bash_libs_gh_meta_remaining" == "0" ]]
    }; then
        __base_bash_libs_gh_meta_rate_value=1
    fi
    if [[ "$__base_bash_libs_gh_meta_remaining" == "0" && -n "$__base_bash_libs_gh_meta_reset" ]]; then
        if __base_bash_libs_gh_api_call_hook__ epoch __base_bash_libs_gh_meta_epoch_output &&
            [[ "$__base_bash_libs_gh_meta_epoch_output" =~ ^[0-9]+$ &&
                ${#__base_bash_libs_gh_meta_epoch_output} -le 12 ]]; then
            __base_bash_libs_gh_meta_epoch="$((10#$__base_bash_libs_gh_meta_epoch_output))"
            if ((__base_bash_libs_gh_meta_reset > __base_bash_libs_gh_meta_epoch)); then
                __base_bash_libs_gh_meta_reset_delay=$((__base_bash_libs_gh_meta_reset - __base_bash_libs_gh_meta_epoch))
            else
                __base_bash_libs_gh_meta_reset_delay=0
            fi
        else
            __base_bash_libs_gh_meta_invalid_value=1
        fi
    fi
    if [[ -n "$__base_bash_libs_gh_meta_retry_after" ]]; then
        __base_bash_libs_gh_meta_delay_value="$__base_bash_libs_gh_meta_retry_after"
    fi
    if [[ -n "$__base_bash_libs_gh_meta_reset_delay" ]] && {
        [[ -z "$__base_bash_libs_gh_meta_delay_value" ]] ||
            ((__base_bash_libs_gh_meta_reset_delay > __base_bash_libs_gh_meta_delay_value))
    }; then
        __base_bash_libs_gh_meta_delay_value="$__base_bash_libs_gh_meta_reset_delay"
    fi

    printf -v "$__base_bash_libs_gh_meta_retryable_name" '%s' "$__base_bash_libs_gh_meta_retryable_value"
    printf -v "$__base_bash_libs_gh_meta_rate_name" '%s' "$__base_bash_libs_gh_meta_rate_value"
    printf -v "$__base_bash_libs_gh_meta_delay_name" '%s' "$__base_bash_libs_gh_meta_delay_value"
    printf -v "$__base_bash_libs_gh_meta_invalid_name" '%s' "$__base_bash_libs_gh_meta_invalid_value"
    [[ -z "$__base_bash_libs_gh_meta_status_name" ]] ||
        printf -v "$__base_bash_libs_gh_meta_status_name" '%s' "$__base_bash_libs_gh_meta_status"
}

__base_bash_libs_gh_api_exponential_cap__() {
    local __base_bash_libs_gh_backoff_result_name="$1" __base_bash_libs_gh_backoff_base="$2"
    local __base_bash_libs_gh_backoff_max="$3" __base_bash_libs_gh_backoff_failure_number="$4"
    local __base_bash_libs_gh_backoff_value="$__base_bash_libs_gh_backoff_base" __base_bash_libs_gh_backoff_index=1

    while ((__base_bash_libs_gh_backoff_index < __base_bash_libs_gh_backoff_failure_number)); do
        if ((__base_bash_libs_gh_backoff_value >= __base_bash_libs_gh_backoff_max)); then
            __base_bash_libs_gh_backoff_value="$__base_bash_libs_gh_backoff_max"
            break
        fi
        __base_bash_libs_gh_backoff_value=$((__base_bash_libs_gh_backoff_value * 2))
        ((__base_bash_libs_gh_backoff_value <= __base_bash_libs_gh_backoff_max)) || __base_bash_libs_gh_backoff_value="$__base_bash_libs_gh_backoff_max"
        __base_bash_libs_gh_backoff_index=$((__base_bash_libs_gh_backoff_index + 1))
    done
    printf -v "$__base_bash_libs_gh_backoff_result_name" '%s' "$__base_bash_libs_gh_backoff_value"
}

__base_bash_libs_gh_api_cleanup_capture__() {
    local __base_bash_libs_gh_cleanup_path
    for __base_bash_libs_gh_cleanup_path in "$@"; do
        [[ -n "$__base_bash_libs_gh_cleanup_path" ]] || continue
        command rm -f -- "$__base_bash_libs_gh_cleanup_path" 2> /dev/null || true
    done
}

__base_bash_libs_gh_api_cleanup_workspace__() {
    local __base_bash_libs_gh_workspace_dir="${1-}"

    [[ -n "$__base_bash_libs_gh_workspace_dir" ]] || return 0
    command rm -f -- \
        "$__base_bash_libs_gh_workspace_dir/stdout" \
        "$__base_bash_libs_gh_workspace_dir/stderr" \
        "$__base_bash_libs_gh_workspace_dir/guardian" \
        "$__base_bash_libs_gh_workspace_dir/guardian.ready" 2> /dev/null || true
    command rmdir -- "$__base_bash_libs_gh_workspace_dir" 2> /dev/null || true
}

__base_bash_libs_gh_api_start_capture_guardian__() {
    local __base_bash_libs_gh_guard_pid_name="$1" __base_bash_libs_gh_guard_fd_name="$2"
    local __base_bash_libs_gh_guard_owner_pid="$3" __base_bash_libs_gh_guard_workspace="$4"
    local __base_bash_libs_gh_guard_pid __base_bash_libs_gh_guard_fd __base_bash_libs_gh_guard_monitor_was_enabled=0
    local __base_bash_libs_gh_guard_probe

    if ! exec {__base_bash_libs_gh_guard_fd}<> "$__base_bash_libs_gh_guard_workspace/guardian"; then
        return 1
    fi
    [[ $- == *m* ]] && __base_bash_libs_gh_guard_monitor_was_enabled=1
    set +m
    (
        local __base_bash_libs_gh_guard_command="" __base_bash_libs_gh_guard_read_fd __base_bash_libs_gh_guard_read_status=0
        local __base_bash_libs_gh_guard_parent_pid="" __base_bash_libs_gh_guard_self_pid="$BASHPID"
        trap - EXIT
        trap '' HUP INT QUIT TERM
        # Descendants of the owner can inherit its FIFO descriptor. The
        # guardian therefore combines the normal stop/EOF channel with the
        # actual parent relationship reported for its own BASHPID. A recycled
        # owner PID cannot impersonate that relationship after reparenting.
        exec {__base_bash_libs_gh_guard_fd}>&-
        if ! exec {__base_bash_libs_gh_guard_read_fd}< "$__base_bash_libs_gh_guard_workspace/guardian"; then
            __base_bash_libs_gh_api_cleanup_workspace__ "$__base_bash_libs_gh_guard_workspace"
            exit 1
        fi
        : > "$__base_bash_libs_gh_guard_workspace/guardian.ready" || exit 1
        while :; do
            if IFS= read -r -t 1 -u "$__base_bash_libs_gh_guard_read_fd" __base_bash_libs_gh_guard_command; then
                break
            else
                __base_bash_libs_gh_guard_read_status=$?
            fi
            # EOF or a descriptor error means that no usable owner control
            # channel remains. A timeout is the only reason to keep polling.
            ((__base_bash_libs_gh_guard_read_status > 128)) || break
            __base_bash_libs_gh_guard_parent_pid=""
            if [[ -x /bin/ps ]]; then
                __base_bash_libs_gh_guard_parent_pid="$(
                    LC_ALL=C /bin/ps -o ppid= -p "$__base_bash_libs_gh_guard_self_pid" 2> /dev/null
                )" || __base_bash_libs_gh_guard_parent_pid=""
            else
                __base_bash_libs_gh_guard_parent_pid="$(
                    LC_ALL=C command ps -o ppid= -p "$__base_bash_libs_gh_guard_self_pid" 2> /dev/null
                )" || __base_bash_libs_gh_guard_parent_pid=""
            fi
            __base_bash_libs_gh_guard_parent_pid="${__base_bash_libs_gh_guard_parent_pid//[[:space:]]/}"
            if [[ "$__base_bash_libs_gh_guard_parent_pid" =~ ^[1-9][0-9]*$ ]]; then
                [[ "$__base_bash_libs_gh_guard_parent_pid" == "$__base_bash_libs_gh_guard_owner_pid" ]] || break
            elif ! kill -0 "$__base_bash_libs_gh_guard_owner_pid" 2> /dev/null; then
                break
            fi
        done
        __base_bash_libs_gh_api_cleanup_workspace__ "$__base_bash_libs_gh_guard_workspace"
    ) < /dev/null > /dev/null 2>&1 &
    __base_bash_libs_gh_guard_pid=$!
    if ((__base_bash_libs_gh_guard_monitor_was_enabled)); then
        set -m
    else
        set +m
    fi
    for ((__base_bash_libs_gh_guard_probe = 0; __base_bash_libs_gh_guard_probe < 100; __base_bash_libs_gh_guard_probe++)); do
        [[ -e "$__base_bash_libs_gh_guard_workspace/guardian.ready" ]] && break
        kill -0 "$__base_bash_libs_gh_guard_pid" 2> /dev/null || break
        __base_bash_libs_std_sleep_interval__ 0.01 || break
    done
    if [[ ! -e "$__base_bash_libs_gh_guard_workspace/guardian.ready" ]]; then
        kill -KILL "$__base_bash_libs_gh_guard_pid" 2> /dev/null || true
        wait "$__base_bash_libs_gh_guard_pid" 2> /dev/null || true
        exec {__base_bash_libs_gh_guard_fd}>&-
        return 1
    fi
    printf -v "$__base_bash_libs_gh_guard_pid_name" '%s' "$__base_bash_libs_gh_guard_pid"
    printf -v "$__base_bash_libs_gh_guard_fd_name" '%s' "$__base_bash_libs_gh_guard_fd"
}

__base_bash_libs_gh_api_stop_capture_guardian__() {
    local __base_bash_libs_gh_guard_pid="${1-}" __base_bash_libs_gh_guard_fd="${2-}"

    if [[ "$__base_bash_libs_gh_guard_fd" =~ ^[1-9][0-9]*$ ]]; then
        { printf 'stop\n' 1>&"$__base_bash_libs_gh_guard_fd"; } 2> /dev/null || true
        exec {__base_bash_libs_gh_guard_fd}>&-
    fi
    if [[ "$__base_bash_libs_gh_guard_pid" =~ ^[1-9][0-9]*$ ]]; then
        # `wait` can reap only this shell's child, so a guardian that has
        # already exited can never turn a recycled PID into a signal target.
        while kill -0 "$__base_bash_libs_gh_guard_pid" 2> /dev/null; do
            wait "$__base_bash_libs_gh_guard_pid" 2> /dev/null && break
            kill -0 "$__base_bash_libs_gh_guard_pid" 2> /dev/null || break
        done
        wait "$__base_bash_libs_gh_guard_pid" 2> /dev/null || true
    fi
}

__base_bash_libs_gh_api_trap_is_ignored__() {
    local __base_bash_libs_gh_trap_spec="${1-}" __base_bash_libs_gh_trap_signal="${2-}"

    [[ "$__base_bash_libs_gh_trap_spec" == "trap -- '' SIG${__base_bash_libs_gh_trap_signal}" ]]
}

__base_bash_libs_gh_api_record_signal__() {
    if ((__base_bash_libs_gh_api_cancel_status == 0)); then
        __base_bash_libs_gh_api_cancel_status="$1"
        __base_bash_libs_gh_api_cancel_signal="$2"
    fi
}

__base_bash_libs_gh_api_finish__() {
    local __base_bash_libs_gh_finish_status="$1" __base_bash_libs_gh_finish_stdout="$2" __base_bash_libs_gh_finish_stderr="$3"
    local __base_bash_libs_gh_finish_sensitive="$4" __base_bash_libs_gh_finish_display="$5"
    local __base_bash_libs_gh_finish_attempt="$6" __base_bash_libs_gh_finish_max_attempts="$7"
    local __base_bash_libs_gh_finish_reason="${8-}"
    local __base_bash_libs_gh_finish_method="${__base_bash_libs_gh_api_method:-UNKNOWN}"
    local __base_bash_libs_gh_finish_http="${__base_bash_libs_gh_api_http_status:-unknown}"
    local __base_bash_libs_gh_finish_elapsed="${__base_bash_libs_gh_api_elapsed:-0}"
    local __base_bash_libs_gh_finish_budget="${__base_bash_libs_gh_api_max_elapsed:-unknown}"
    local __base_bash_libs_gh_finish_stdout_prefix=0
    local __base_bash_libs_gh_finish_suppress_stdout="${__base_bash_libs_gh_api_suppress_stdout:-0}"
    local __base_bash_libs_gh_finish_context __base_bash_libs_gh_finish_replay_status=0 __base_bash_libs_gh_finish_channel_status=0

    if ((${__base_bash_libs_gh_api_injected_include:-0})); then
        __base_bash_libs_gh_finish_stdout_prefix="${__base_bash_libs_gh_api_header_bytes:-0}"
    fi

    case "$__base_bash_libs_gh_finish_method" in
    GET | HEAD | OPTIONS | POST | PUT | PATCH | DELETE) ;;
    *) __base_bash_libs_gh_finish_method=OTHER ;;
    esac
    [[ "$__base_bash_libs_gh_finish_http" =~ ^[0-9]{3}$ ]] || __base_bash_libs_gh_finish_http=unknown
    [[ "$__base_bash_libs_gh_finish_elapsed" =~ ^[0-9]+$ ]] || __base_bash_libs_gh_finish_elapsed=unknown
    [[ "$__base_bash_libs_gh_finish_budget" =~ ^[0-9]+$ ]] || __base_bash_libs_gh_finish_budget=unknown
    __base_bash_libs_gh_finish_context="method=$__base_bash_libs_gh_finish_method, http=$__base_bash_libs_gh_finish_http, attempt=$__base_bash_libs_gh_finish_attempt/$__base_bash_libs_gh_finish_max_attempts, elapsed=${__base_bash_libs_gh_finish_elapsed}s, budget=${__base_bash_libs_gh_finish_budget}s"

    if ((__base_bash_libs_gh_finish_status == 0)); then
        if ((__base_bash_libs_gh_finish_suppress_stdout)); then
            __base_bash_libs_gh_finish_replay_status=1
        elif __base_bash_libs_gh_api_replay_file__ "$__base_bash_libs_gh_finish_stdout" "$__base_bash_libs_gh_finish_stdout_prefix"; then
            :
        else
            __base_bash_libs_gh_finish_replay_status=$?
        fi
        if command cat -- "$__base_bash_libs_gh_finish_stderr" >&2; then
            :
        else
            __base_bash_libs_gh_finish_channel_status=$?
            ((__base_bash_libs_gh_finish_replay_status != 0)) ||
                __base_bash_libs_gh_finish_replay_status="$__base_bash_libs_gh_finish_channel_status"
        fi
    elif ((__base_bash_libs_gh_finish_sensitive)); then
        base_std_log_error -l base_bash_libs.gh \
            "GitHub API call failed: $__base_bash_libs_gh_finish_display (exit $__base_bash_libs_gh_finish_status; $__base_bash_libs_gh_finish_context; captured output hidden)."
        [[ -z "$__base_bash_libs_gh_finish_reason" ]] ||
            base_std_log_warn -l base_bash_libs.gh "$__base_bash_libs_gh_finish_reason"
    else
        [[ -z "$__base_bash_libs_gh_finish_reason" ]] ||
            base_std_log_warn -l base_bash_libs.gh "$__base_bash_libs_gh_finish_reason"
        base_std_log_error -l base_bash_libs.gh \
            "GitHub API call failed (exit $__base_bash_libs_gh_finish_status; $__base_bash_libs_gh_finish_context)."
        if ((__base_bash_libs_gh_finish_suppress_stdout)); then
            base_std_log_warn -l base_bash_libs.gh \
                "GitHub API failure stdout was withheld because injected response headers could not be separated safely."
        elif ! __base_bash_libs_gh_api_replay_file__ "$__base_bash_libs_gh_finish_stdout" "$__base_bash_libs_gh_finish_stdout_prefix"; then
            base_std_log_warn -l base_bash_libs.gh \
                "GitHub API failure stdout could not be replayed completely."
        fi
        if ! command cat -- "$__base_bash_libs_gh_finish_stderr" >&2; then
            base_std_log_warn -l base_bash_libs.gh \
                "GitHub API failure stderr could not be replayed completely."
        fi
    fi
    __base_bash_libs_gh_api_cleanup_capture__ "$__base_bash_libs_gh_finish_stdout" "$__base_bash_libs_gh_finish_stderr"
    if ((__base_bash_libs_gh_finish_status == 0 && __base_bash_libs_gh_finish_replay_status != 0)); then
        base_std_log_error -l base_bash_libs.gh \
            "GitHub API response could not be replayed completely (exit $__base_bash_libs_gh_finish_replay_status)."
        return "$__base_bash_libs_gh_finish_replay_status"
    fi
    return "$__base_bash_libs_gh_finish_status"
}

__base_bash_libs_gh_api_with_retry_impl__() {
    local __base_bash_libs_gh_api_consumed=0 __base_bash_libs_gh_api_sensitive=0 __base_bash_libs_gh_api_safe_display=""
    local __base_bash_libs_gh_api_policy=read-only __base_bash_libs_gh_api_max_attempts=3
    local __base_bash_libs_gh_api_max_elapsed=300 __base_bash_libs_gh_api_attempt_timeout=60
    local __base_bash_libs_gh_api_base_delay=2 __base_bash_libs_gh_api_max_delay=120
    local __base_bash_libs_gh_api_method __base_bash_libs_gh_api_include=0 __base_bash_libs_gh_api_stdin=0 __base_bash_libs_gh_api_file=0
    local __base_bash_libs_gh_api_graphql=0 __base_bash_libs_gh_api_ambiguous=0 __base_bash_libs_gh_api_retry_authorized=0
    local __base_bash_libs_gh_api_injected_include=0 __base_bash_libs_gh_api_header_bytes=0
    local __base_bash_libs_gh_api_suppress_stdout=0 __base_bash_libs_gh_api_can_inject=0
    local __base_bash_libs_gh_api_transport_syntax_safe=0 __base_bash_libs_gh_api_transport_allowed=0
    local __base_bash_libs_gh_api_structured_metadata=1 __base_bash_libs_gh_api_metadata_include=0
    local __base_bash_libs_gh_api_stdout="" __base_bash_libs_gh_api_stderr="" __base_bash_libs_gh_api_display=""
    local __base_bash_libs_gh_api_capture_workspace=""
    local __base_bash_libs_gh_api_timeout_path="" __base_bash_libs_gh_api_attempt=1 __base_bash_libs_gh_api_status=0
    local __base_bash_libs_gh_api_start __base_bash_libs_gh_api_now __base_bash_libs_gh_api_elapsed __base_bash_libs_gh_api_remaining
    local __base_bash_libs_gh_api_effective_timeout __base_bash_libs_gh_api_retryable __base_bash_libs_gh_api_rate_limited
    local __base_bash_libs_gh_api_server_delay __base_bash_libs_gh_api_metadata_invalid __base_bash_libs_gh_api_http_status=""
    local __base_bash_libs_gh_api_backoff_cap
    local __base_bash_libs_gh_api_delay __base_bash_libs_gh_api_reason=""
    local __base_bash_libs_gh_api_probe_status="" __base_bash_libs_gh_api_probe_retry=""
    local __base_bash_libs_gh_api_probe_remaining="" __base_bash_libs_gh_api_probe_reset=""
    local __base_bash_libs_gh_api_probe_invalid=0
    local __base_bash_libs_gh_api_hook_result=""
    local -a __base_bash_libs_gh_api_attempt_argv=()

    __base_bash_libs_gh_parse_api_controls__ __base_bash_libs_gh_api_consumed __base_bash_libs_gh_api_sensitive \
        __base_bash_libs_gh_api_safe_display __base_bash_libs_gh_api_policy __base_bash_libs_gh_api_max_attempts \
        __base_bash_libs_gh_api_max_elapsed __base_bash_libs_gh_api_attempt_timeout __base_bash_libs_gh_api_base_delay \
        __base_bash_libs_gh_api_max_delay "$@" || return $?
    ((__base_bash_libs_gh_api_consumed == 0)) || shift "$__base_bash_libs_gh_api_consumed"
    if (($# == 0)); then
        __base_bash_libs_gh_api_controls_usage__
        return 2
    fi

    base_gh_require_cli || return 1
    __base_bash_libs_gh_api_classify_argv__ __base_bash_libs_gh_api_method __base_bash_libs_gh_api_include __base_bash_libs_gh_api_stdin \
        __base_bash_libs_gh_api_file __base_bash_libs_gh_api_graphql __base_bash_libs_gh_api_ambiguous "$@"

    case "$__base_bash_libs_gh_api_policy" in
    never)
        __base_bash_libs_gh_api_retry_authorized=0
        ;;
    replay-safe)
        ((__base_bash_libs_gh_api_stdin == 0)) && __base_bash_libs_gh_api_retry_authorized=1
        ;;
    read-only)
        if ((!__base_bash_libs_gh_api_stdin && !__base_bash_libs_gh_api_file && !__base_bash_libs_gh_api_graphql && !__base_bash_libs_gh_api_ambiguous)); then
            case "$__base_bash_libs_gh_api_method" in
            GET | HEAD | OPTIONS) __base_bash_libs_gh_api_retry_authorized=1 ;;
            esac
        fi
        ;;
    esac

    __base_bash_libs_gh_api_attempt_argv=("$@")
    if ((__base_bash_libs_gh_api_retry_authorized && !__base_bash_libs_gh_api_include && !__base_bash_libs_gh_api_ambiguous)); then
        __base_bash_libs_gh_api_can_inject_include__ __base_bash_libs_gh_api_can_inject "$@"
        if ((__base_bash_libs_gh_api_can_inject)); then
            __base_bash_libs_gh_api_injected_include=1
            __base_bash_libs_gh_api_include=1
            __base_bash_libs_gh_api_attempt_argv=(--include "$@")
        fi
    fi
    __base_bash_libs_gh_api_unstructured_transport_is_safe__ __base_bash_libs_gh_api_transport_syntax_safe "$@"
    ((__base_bash_libs_gh_api_ambiguous == 0)) || __base_bash_libs_gh_api_transport_syntax_safe=0
    [[ -z "${GH_FORCE_TTY-}${CLICOLOR_FORCE-}${FORCE_COLOR-}" ]] ||
        __base_bash_libs_gh_api_structured_metadata=0

    if ((__base_bash_libs_gh_api_sensitive)); then
        if ! __base_bash_libs_std_render_command_display__ __base_bash_libs_gh_api_display 1 "$__base_bash_libs_gh_api_safe_display" \
            "[sensitive GitHub operation; arguments hidden]" gh api "$@"; then
            __base_bash_libs_gh_api_display="[sensitive GitHub operation; arguments hidden]"
        fi
    fi
    # A mode-0700 invocation workspace lets a guardian exist before any
    # response data does. It is independent of the caller's shared EXIT
    # dispatcher, whose inherited trap state Bash cannot safely round-trip
    # inside command substitutions.
    __base_bash_libs_std_make_internal_temp_dir__ --keep __base_bash_libs_gh_api_capture_workspace \
        base-bash-libs-gh-api || return 1
    __base_bash_libs_gh_api_owned_workspace="$__base_bash_libs_gh_api_capture_workspace"
    if ! command chmod 700 "$__base_bash_libs_gh_api_owned_workspace" 2> /dev/null ||
        ! command mkfifo "$__base_bash_libs_gh_api_owned_workspace/guardian" 2> /dev/null ||
        ! command chmod 600 "$__base_bash_libs_gh_api_owned_workspace/guardian" 2> /dev/null; then
        __base_bash_libs_gh_api_cleanup_workspace__ "$__base_bash_libs_gh_api_owned_workspace"
        base_std_log_error -l base_bash_libs.gh \
            "base_gh_api_with_retry: could not secure the retry capture workspace."
        return 1
    fi
    if ! __base_bash_libs_gh_api_start_capture_guardian__ __base_bash_libs_gh_api_guardian_pid \
        __base_bash_libs_gh_api_guardian_fd "$BASHPID" "$__base_bash_libs_gh_api_owned_workspace"; then
        __base_bash_libs_gh_api_cleanup_workspace__ "$__base_bash_libs_gh_api_owned_workspace"
        base_std_log_error -l base_bash_libs.gh \
            "base_gh_api_with_retry: could not start the retry capture guardian."
        return 1
    fi
    __base_bash_libs_gh_api_stdout="$__base_bash_libs_gh_api_owned_workspace/stdout"
    __base_bash_libs_gh_api_stderr="$__base_bash_libs_gh_api_owned_workspace/stderr"
    if ! : > "$__base_bash_libs_gh_api_stdout" 2> /dev/null ||
        ! : > "$__base_bash_libs_gh_api_stderr" 2> /dev/null ||
        ! command chmod 600 "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr" 2> /dev/null; then
        __base_bash_libs_gh_api_cleanup_workspace__ "$__base_bash_libs_gh_api_owned_workspace"
        base_std_log_error -l base_bash_libs.gh \
            "base_gh_api_with_retry: could not secure retry capture files."
        return 1
    fi

    # base_std_run owns a single TERM-then-KILL supervisor. GNU timeout/gtimeout,
    # when verified, provide only its deadline clock; the framework never
    # delegates the GitHub argv directly to those binaries.
    __base_bash_libs_std_timeout_backend_detect__ __base_bash_libs_gh_api_timeout_path
    __base_bash_libs_gh_api_hook_result=""
    if ! __base_bash_libs_gh_api_call_hook__ monotonic __base_bash_libs_gh_api_hook_result ||
        [[ ! "$__base_bash_libs_gh_api_hook_result" =~ ^[0-9]+$ ||
            ${#__base_bash_libs_gh_api_hook_result} -gt 12 ]]; then
        __base_bash_libs_gh_api_cleanup_capture__ "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr"
        base_std_log_error -l base_bash_libs.gh \
            "base_gh_api_with_retry: could not initialize the elapsed-time budget."
        return 1
    fi
    __base_bash_libs_gh_api_start="$((10#$__base_bash_libs_gh_api_hook_result))"

    while ((__base_bash_libs_gh_api_attempt <= __base_bash_libs_gh_api_max_attempts)); do
        if ((__base_bash_libs_gh_api_cancel_status != 0)); then
            __base_bash_libs_gh_api_cleanup_capture__ "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr"
            return "$__base_bash_libs_gh_api_cancel_status"
        fi
        __base_bash_libs_gh_api_hook_result=""
        if ! __base_bash_libs_gh_api_call_hook__ monotonic __base_bash_libs_gh_api_hook_result ||
            [[ ! "$__base_bash_libs_gh_api_hook_result" =~ ^[0-9]+$ ||
                ${#__base_bash_libs_gh_api_hook_result} -gt 12 ]]; then
            if ((__base_bash_libs_gh_api_attempt > 1 && __base_bash_libs_gh_api_status != 0)); then
                __base_bash_libs_gh_api_reason="GitHub API retry stopped because the elapsed-time budget could not be read safely."
                __base_bash_libs_gh_api_finish__ "$__base_bash_libs_gh_api_status" "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr" \
                    "$__base_bash_libs_gh_api_sensitive" "$__base_bash_libs_gh_api_display" "$((__base_bash_libs_gh_api_attempt - 1))" \
                    "$__base_bash_libs_gh_api_max_attempts" "$__base_bash_libs_gh_api_reason"
                return $?
            fi
            __base_bash_libs_gh_api_cleanup_capture__ "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr"
            base_std_log_error -l base_bash_libs.gh \
                "base_gh_api_with_retry: could not read the elapsed-time budget."
            return 1
        fi
        __base_bash_libs_gh_api_now="$((10#$__base_bash_libs_gh_api_hook_result))"
        if ((__base_bash_libs_gh_api_now < __base_bash_libs_gh_api_start)); then
            if ((__base_bash_libs_gh_api_attempt > 1 && __base_bash_libs_gh_api_status != 0)); then
                __base_bash_libs_gh_api_reason="GitHub API retry stopped because the elapsed-time clock moved backwards."
                __base_bash_libs_gh_api_finish__ "$__base_bash_libs_gh_api_status" "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr" \
                    "$__base_bash_libs_gh_api_sensitive" "$__base_bash_libs_gh_api_display" "$((__base_bash_libs_gh_api_attempt - 1))" \
                    "$__base_bash_libs_gh_api_max_attempts" "$__base_bash_libs_gh_api_reason"
                return $?
            fi
            __base_bash_libs_gh_api_cleanup_capture__ "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr"
            base_std_log_error -l base_bash_libs.gh \
                "base_gh_api_with_retry: elapsed-time clock moved backwards."
            return 1
        fi
        __base_bash_libs_gh_api_elapsed=$((__base_bash_libs_gh_api_now - __base_bash_libs_gh_api_start))
        __base_bash_libs_gh_api_remaining=$((__base_bash_libs_gh_api_max_elapsed - __base_bash_libs_gh_api_elapsed))
        if ((__base_bash_libs_gh_api_remaining <= 0)); then
            __base_bash_libs_gh_api_reason="GitHub API retry stopped because the total elapsed-time budget was exhausted."
            if ((__base_bash_libs_gh_api_attempt == 1)); then
                __base_bash_libs_gh_api_status=124
            fi
            __base_bash_libs_gh_api_finish__ "$__base_bash_libs_gh_api_status" "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr" \
                "$__base_bash_libs_gh_api_sensitive" "$__base_bash_libs_gh_api_display" \
                "$((__base_bash_libs_gh_api_attempt > 1 ? __base_bash_libs_gh_api_attempt - 1 : 1))" \
                "$__base_bash_libs_gh_api_max_attempts" "$__base_bash_libs_gh_api_reason"
            return $?
        fi
        __base_bash_libs_gh_api_effective_timeout="$__base_bash_libs_gh_api_attempt_timeout"
        ((__base_bash_libs_gh_api_effective_timeout <= __base_bash_libs_gh_api_remaining)) ||
            __base_bash_libs_gh_api_effective_timeout="$__base_bash_libs_gh_api_remaining"
        __base_bash_libs_gh_api_http_status=""
        __base_bash_libs_gh_api_header_bytes=0
        __base_bash_libs_gh_api_suppress_stdout=0

        if __base_bash_libs_gh_api_call_hook__ attempt \
            "$__base_bash_libs_gh_api_effective_timeout" "$__base_bash_libs_gh_api_timeout_path" \
            "$__base_bash_libs_gh_api_attempt" "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr" \
            "${__base_bash_libs_gh_api_attempt_argv[@]}"; then
            __base_bash_libs_gh_api_status=0
        else
            __base_bash_libs_gh_api_status=$?
        fi
        if ((__base_bash_libs_gh_api_cancel_status != 0)); then
            __base_bash_libs_gh_api_cleanup_capture__ "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr"
            return "$__base_bash_libs_gh_api_cancel_status"
        fi
        if ((__base_bash_libs_gh_api_injected_include)); then
            __base_bash_libs_gh_api_probe_status=""
            __base_bash_libs_gh_api_probe_retry=""
            __base_bash_libs_gh_api_probe_remaining=""
            __base_bash_libs_gh_api_probe_reset=""
            __base_bash_libs_gh_api_probe_invalid=0
            __base_bash_libs_gh_api_parse_headers__ "$__base_bash_libs_gh_api_stdout" __base_bash_libs_gh_api_probe_status \
                __base_bash_libs_gh_api_probe_retry __base_bash_libs_gh_api_probe_remaining __base_bash_libs_gh_api_probe_reset \
                __base_bash_libs_gh_api_probe_invalid __base_bash_libs_gh_api_header_bytes
            if [[ -s "$__base_bash_libs_gh_api_stdout" && "$__base_bash_libs_gh_api_header_bytes" == "0" ]]; then
                __base_bash_libs_gh_api_suppress_stdout=1
            fi
        fi
        if ((__base_bash_libs_gh_api_status == 0)); then
            __base_bash_libs_gh_api_finish__ 0 "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr" \
                "$__base_bash_libs_gh_api_sensitive" "$__base_bash_libs_gh_api_display" "$__base_bash_libs_gh_api_attempt" \
                "$__base_bash_libs_gh_api_max_attempts"
            return $?
        fi

        __base_bash_libs_gh_api_hook_result=""
        if ! __base_bash_libs_gh_api_call_hook__ monotonic __base_bash_libs_gh_api_hook_result ||
            [[ ! "$__base_bash_libs_gh_api_hook_result" =~ ^[0-9]+$ ||
                ${#__base_bash_libs_gh_api_hook_result} -gt 12 ]] ||
            ((10#$__base_bash_libs_gh_api_hook_result < __base_bash_libs_gh_api_start)); then
            __base_bash_libs_gh_api_elapsed=unknown
            __base_bash_libs_gh_api_reason="GitHub API retry stopped because the elapsed-time budget could not be read safely after an attempt."
            __base_bash_libs_gh_api_finish__ "$__base_bash_libs_gh_api_status" "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr" \
                "$__base_bash_libs_gh_api_sensitive" "$__base_bash_libs_gh_api_display" "$__base_bash_libs_gh_api_attempt" \
                "$__base_bash_libs_gh_api_max_attempts" "$__base_bash_libs_gh_api_reason"
            return $?
        fi
        __base_bash_libs_gh_api_now="$((10#$__base_bash_libs_gh_api_hook_result))"
        __base_bash_libs_gh_api_elapsed=$((__base_bash_libs_gh_api_now - __base_bash_libs_gh_api_start))

        __base_bash_libs_gh_api_metadata_include=0
        if ((__base_bash_libs_gh_api_include && __base_bash_libs_gh_api_structured_metadata)); then
            __base_bash_libs_gh_api_metadata_include=1
        fi
        __base_bash_libs_gh_api_transport_allowed=0
        if [[ ! -s "$__base_bash_libs_gh_api_stdout" ]] &&
            ((__base_bash_libs_gh_api_metadata_include || __base_bash_libs_gh_api_transport_syntax_safe)); then
            __base_bash_libs_gh_api_transport_allowed=1
        fi
        __base_bash_libs_gh_api_failure_metadata__ "$__base_bash_libs_gh_api_status" "$__base_bash_libs_gh_api_metadata_include" \
            "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr" __base_bash_libs_gh_api_retryable \
            __base_bash_libs_gh_api_rate_limited __base_bash_libs_gh_api_server_delay __base_bash_libs_gh_api_metadata_invalid \
            __base_bash_libs_gh_api_http_status __base_bash_libs_gh_api_transport_allowed

        if ((__base_bash_libs_gh_api_metadata_invalid)); then
            __base_bash_libs_gh_api_reason="GitHub API retry withheld because retry metadata was malformed or conflicting."
        elif ((!__base_bash_libs_gh_api_retryable)); then
            __base_bash_libs_gh_api_reason=""
        elif ((__base_bash_libs_gh_api_stdin)); then
            __base_bash_libs_gh_api_reason="GitHub API retry prohibited because the request may consume stdin; the mutation outcome may be unknown."
        elif [[ "$__base_bash_libs_gh_api_policy" == "never" ]]; then
            __base_bash_libs_gh_api_reason=""
        elif ((!__base_bash_libs_gh_api_retry_authorized)); then
            __base_bash_libs_gh_api_reason="GitHub API retry withheld because the request is not confidently classified as a replay-safe read; the mutation outcome may be unknown. Use --retry-policy replay-safe only when replay is semantically safe and request data is stable."
        elif ((__base_bash_libs_gh_api_attempt >= __base_bash_libs_gh_api_max_attempts)); then
            __base_bash_libs_gh_api_reason="GitHub API retry stopped after the configured maximum attempts."
        else
            __base_bash_libs_gh_api_reason=""
        fi

        if ((__base_bash_libs_gh_api_metadata_invalid || !__base_bash_libs_gh_api_retryable || !__base_bash_libs_gh_api_retry_authorized || \
            __base_bash_libs_gh_api_attempt >= __base_bash_libs_gh_api_max_attempts)); then
            __base_bash_libs_gh_api_finish__ "$__base_bash_libs_gh_api_status" "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr" \
                "$__base_bash_libs_gh_api_sensitive" "$__base_bash_libs_gh_api_display" "$__base_bash_libs_gh_api_attempt" \
                "$__base_bash_libs_gh_api_max_attempts" "$__base_bash_libs_gh_api_reason"
            return $?
        fi

        __base_bash_libs_gh_api_exponential_cap__ __base_bash_libs_gh_api_backoff_cap "$__base_bash_libs_gh_api_base_delay" \
            "$__base_bash_libs_gh_api_max_delay" "$__base_bash_libs_gh_api_attempt"
        if [[ -n "$__base_bash_libs_gh_api_server_delay" ]]; then
            __base_bash_libs_gh_api_delay="$__base_bash_libs_gh_api_server_delay"
            ((__base_bash_libs_gh_api_delay >= __base_bash_libs_gh_api_backoff_cap)) || __base_bash_libs_gh_api_delay="$__base_bash_libs_gh_api_backoff_cap"
            if ((__base_bash_libs_gh_api_delay > __base_bash_libs_gh_api_max_delay)); then
                __base_bash_libs_gh_api_reason="GitHub API retry stopped because the server-directed wait exceeds the configured delay bound."
                __base_bash_libs_gh_api_finish__ "$__base_bash_libs_gh_api_status" "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr" \
                    "$__base_bash_libs_gh_api_sensitive" "$__base_bash_libs_gh_api_display" "$__base_bash_libs_gh_api_attempt" \
                    "$__base_bash_libs_gh_api_max_attempts" "$__base_bash_libs_gh_api_reason"
                return $?
            fi
        elif ((__base_bash_libs_gh_api_rate_limited)); then
            __base_bash_libs_gh_api_exponential_cap__ __base_bash_libs_gh_api_delay 60 "$__base_bash_libs_gh_api_max_delay" \
                "$__base_bash_libs_gh_api_attempt"
            ((__base_bash_libs_gh_api_delay >= 60)) || __base_bash_libs_gh_api_delay=60
            if ((__base_bash_libs_gh_api_delay > __base_bash_libs_gh_api_max_delay)); then
                __base_bash_libs_gh_api_reason="GitHub API retry stopped because a safe rate-limit wait exceeds the configured delay bound."
                __base_bash_libs_gh_api_finish__ "$__base_bash_libs_gh_api_status" "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr" \
                    "$__base_bash_libs_gh_api_sensitive" "$__base_bash_libs_gh_api_display" "$__base_bash_libs_gh_api_attempt" \
                    "$__base_bash_libs_gh_api_max_attempts" "$__base_bash_libs_gh_api_reason"
                return $?
            fi
        else
            __base_bash_libs_gh_api_hook_result=""
            if __base_bash_libs_gh_api_call_hook__ jitter __base_bash_libs_gh_api_hook_result \
                "$__base_bash_libs_gh_api_backoff_cap" &&
                [[ "$__base_bash_libs_gh_api_hook_result" =~ ^[0-9]+$ &&
                    ${#__base_bash_libs_gh_api_hook_result} -le 3 ]] &&
                ((10#$__base_bash_libs_gh_api_hook_result <= __base_bash_libs_gh_api_backoff_cap)); then
                __base_bash_libs_gh_api_delay="$((10#$__base_bash_libs_gh_api_hook_result))"
            else
                __base_bash_libs_gh_api_reason="GitHub API retry stopped because a safe jitter delay could not be selected."
                __base_bash_libs_gh_api_finish__ "$__base_bash_libs_gh_api_status" "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr" \
                    "$__base_bash_libs_gh_api_sensitive" "$__base_bash_libs_gh_api_display" "$__base_bash_libs_gh_api_attempt" \
                    "$__base_bash_libs_gh_api_max_attempts" "$__base_bash_libs_gh_api_reason"
                return $?
            fi
        fi

        __base_bash_libs_gh_api_hook_result=""
        if ! __base_bash_libs_gh_api_call_hook__ monotonic __base_bash_libs_gh_api_hook_result ||
            [[ ! "$__base_bash_libs_gh_api_hook_result" =~ ^[0-9]+$ ||
                ${#__base_bash_libs_gh_api_hook_result} -gt 12 ]]; then
            __base_bash_libs_gh_api_reason="GitHub API retry stopped because the elapsed-time budget could not be read safely."
            __base_bash_libs_gh_api_finish__ "$__base_bash_libs_gh_api_status" "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr" \
                "$__base_bash_libs_gh_api_sensitive" "$__base_bash_libs_gh_api_display" "$__base_bash_libs_gh_api_attempt" \
                "$__base_bash_libs_gh_api_max_attempts" "$__base_bash_libs_gh_api_reason"
            return $?
        fi
        __base_bash_libs_gh_api_now="$((10#$__base_bash_libs_gh_api_hook_result))"
        if ((__base_bash_libs_gh_api_now < __base_bash_libs_gh_api_start)); then
            __base_bash_libs_gh_api_reason="GitHub API retry stopped because the elapsed-time budget could not be read safely."
            __base_bash_libs_gh_api_finish__ "$__base_bash_libs_gh_api_status" "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr" \
                "$__base_bash_libs_gh_api_sensitive" "$__base_bash_libs_gh_api_display" "$__base_bash_libs_gh_api_attempt" \
                "$__base_bash_libs_gh_api_max_attempts" "$__base_bash_libs_gh_api_reason"
            return $?
        fi
        __base_bash_libs_gh_api_remaining=$((__base_bash_libs_gh_api_max_elapsed - (__base_bash_libs_gh_api_now - __base_bash_libs_gh_api_start)))
        if ((__base_bash_libs_gh_api_delay >= __base_bash_libs_gh_api_remaining)); then
            __base_bash_libs_gh_api_reason="GitHub API retry stopped because the next safe wait would exhaust the total elapsed-time budget."
            __base_bash_libs_gh_api_finish__ "$__base_bash_libs_gh_api_status" "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr" \
                "$__base_bash_libs_gh_api_sensitive" "$__base_bash_libs_gh_api_display" "$__base_bash_libs_gh_api_attempt" \
                "$__base_bash_libs_gh_api_max_attempts" "$__base_bash_libs_gh_api_reason"
            return $?
        fi

        if ((__base_bash_libs_gh_api_sensitive)); then
            base_std_log_warn -l base_bash_libs.gh \
                "GitHub API call failed transiently for $__base_bash_libs_gh_api_display on attempt $__base_bash_libs_gh_api_attempt; retrying after ${__base_bash_libs_gh_api_delay}s (attempt $((__base_bash_libs_gh_api_attempt + 1)) of $__base_bash_libs_gh_api_max_attempts)."
        else
            base_std_log_warn -l base_bash_libs.gh \
                "GitHub API call failed transiently on attempt $__base_bash_libs_gh_api_attempt; retrying after ${__base_bash_libs_gh_api_delay}s (attempt $((__base_bash_libs_gh_api_attempt + 1)) of $__base_bash_libs_gh_api_max_attempts)."
        fi
        if ! __base_bash_libs_gh_api_call_hook__ sleep "$__base_bash_libs_gh_api_delay"; then
            if ((__base_bash_libs_gh_api_cancel_status != 0)); then
                __base_bash_libs_gh_api_cleanup_capture__ "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr"
                return "$__base_bash_libs_gh_api_cancel_status"
            fi
            __base_bash_libs_gh_api_reason="GitHub API retry stopped because the retry wait failed."
            __base_bash_libs_gh_api_finish__ "$__base_bash_libs_gh_api_status" "$__base_bash_libs_gh_api_stdout" "$__base_bash_libs_gh_api_stderr" \
                "$__base_bash_libs_gh_api_sensitive" "$__base_bash_libs_gh_api_display" "$__base_bash_libs_gh_api_attempt" \
                "$__base_bash_libs_gh_api_max_attempts" "$__base_bash_libs_gh_api_reason"
            return $?
        fi
        __base_bash_libs_gh_api_attempt=$((__base_bash_libs_gh_api_attempt + 1))
    done
}

base_gh_api_with_retry() {
    local __base_bash_libs_gh_api_owned_workspace="" __base_bash_libs_gh_api_guardian_pid=""
    local __base_bash_libs_gh_api_guardian_fd=""
    local __base_bash_libs_gh_api_active_sleep_pid="" __base_bash_libs_gh_api_cancel_status=0
    local __base_bash_libs_gh_api_cancel_signal=""
    local __base_bash_libs_gh_api_public_status=0
    local __base_bash_libs_gh_api_saved_hup_trap __base_bash_libs_gh_api_saved_int_trap
    local __base_bash_libs_gh_api_saved_quit_trap __base_bash_libs_gh_api_saved_term_trap

    __base_bash_libs_gh_api_saved_hup_trap="$(trap -p HUP || true)"
    __base_bash_libs_gh_api_saved_int_trap="$(trap -p INT || true)"
    __base_bash_libs_gh_api_saved_quit_trap="$(trap -p QUIT || true)"
    __base_bash_libs_gh_api_saved_term_trap="$(trap -p TERM || true)"
    __base_bash_libs_gh_api_trap_is_ignored__ "$__base_bash_libs_gh_api_saved_hup_trap" HUP ||
        trap '__base_bash_libs_gh_api_record_signal__ 129 HUP' HUP
    __base_bash_libs_gh_api_trap_is_ignored__ "$__base_bash_libs_gh_api_saved_int_trap" INT ||
        trap '__base_bash_libs_gh_api_record_signal__ 130 INT' INT
    __base_bash_libs_gh_api_trap_is_ignored__ "$__base_bash_libs_gh_api_saved_quit_trap" QUIT ||
        trap '__base_bash_libs_gh_api_record_signal__ 131 QUIT' QUIT
    __base_bash_libs_gh_api_trap_is_ignored__ "$__base_bash_libs_gh_api_saved_term_trap" TERM ||
        trap '__base_bash_libs_gh_api_record_signal__ 143 TERM' TERM

    if __base_bash_libs_gh_api_with_retry_impl__ "$@"; then
        __base_bash_libs_gh_api_public_status=0
    else
        __base_bash_libs_gh_api_public_status=$?
    fi
    if ((__base_bash_libs_gh_api_cancel_status != 0)); then
        __base_bash_libs_gh_api_public_status="$__base_bash_libs_gh_api_cancel_status"
    fi
    if [[ -n "$__base_bash_libs_gh_api_active_sleep_pid" ]]; then
        kill -KILL "$__base_bash_libs_gh_api_active_sleep_pid" 2> /dev/null || true
        wait "$__base_bash_libs_gh_api_active_sleep_pid" 2> /dev/null || true
    fi
    __base_bash_libs_gh_api_stop_capture_guardian__ "$__base_bash_libs_gh_api_guardian_pid" \
        "$__base_bash_libs_gh_api_guardian_fd"
    __base_bash_libs_gh_api_cleanup_workspace__ "$__base_bash_libs_gh_api_owned_workspace"
    if ((__base_bash_libs_gh_api_cancel_status != 0)); then
        __base_bash_libs_gh_api_public_status="$__base_bash_libs_gh_api_cancel_status"
    fi

    trap - HUP INT QUIT TERM
    # trap -p emits shell-quoted commands owned by Bash itself.
    # shellcheck disable=SC2294
    [[ -z "$__base_bash_libs_gh_api_saved_hup_trap" ]] || eval "$__base_bash_libs_gh_api_saved_hup_trap"
    # shellcheck disable=SC2294
    [[ -z "$__base_bash_libs_gh_api_saved_int_trap" ]] || eval "$__base_bash_libs_gh_api_saved_int_trap"
    # shellcheck disable=SC2294
    [[ -z "$__base_bash_libs_gh_api_saved_quit_trap" ]] || eval "$__base_bash_libs_gh_api_saved_quit_trap"
    # shellcheck disable=SC2294
    [[ -z "$__base_bash_libs_gh_api_saved_term_trap" ]] || eval "$__base_bash_libs_gh_api_saved_term_trap"

    case "$__base_bash_libs_gh_api_cancel_signal" in
    HUP | INT | QUIT | TERM)
        # Cleanup is complete and the exact caller disposition is active
        # again. Re-delivery preserves default termination and invokes
        # custom handlers; an explicitly ignored signal was never
        # intercepted above.
        kill "-$__base_bash_libs_gh_api_cancel_signal" "$BASHPID" 2> /dev/null || true
        ;;
    esac
    return "$__base_bash_libs_gh_api_public_status"
}
