# shellcheck shell=bash
#
# lib_process.sh - Reusable process supervision primitives for Bash scripts.
#

[[ -n "${BASE_BASH_LIBS_PROCESS_LOADED:-}" ]] && return 0
if [[ "${BASE_BASH_LIBS_STDLIB_LOADED:-}" != "1" ]]; then
    printf '%s\n' "Error: lib_process.sh requires lib_std.sh to be sourced first." >&2
    return 1 2> /dev/null || exit 1
fi
readonly BASE_BASH_LIBS_PROCESS_LOADED=1

# base_process_owner_alive - Check an owner/guardian parent relationship.
#
# A guardian should pass its owner's PID followed by its own PID. When the
# parent relationship is observable, equality is required so a recycled owner
# PID cannot keep a detached guardian alive. If `ps` cannot report the parent,
# the predicate falls back to a liveness probe for the owner PID.
base_process_owner_alive() {
    if (($# != 2)); then
        base_std_log_error -l base_bash_libs.process \
            "base_process_owner_alive: expected <owner_pid> <guardian_pid>."
        return 2
    fi
    [[ "$1" =~ ^[1-9][0-9]*$ && "$2" =~ ^[1-9][0-9]*$ ]] || {
        base_std_log_error -l base_bash_libs.process \
            "base_process_owner_alive: owner and guardian PIDs must be positive integers."
        return 2
    }
    __base_bash_libs_process_owner_alive__ "$1" "$2"
}

__base_bash_libs_process_owner_alive__() {
    local __base_bash_libs_process_owner_pid="$1"
    local __base_bash_libs_process_guardian_pid="$2"
    local __base_bash_libs_process_parent_pid=""

    if [[ -x /bin/ps ]]; then
        __base_bash_libs_process_parent_pid="$(
            LC_ALL=C /bin/ps -o ppid= -p "$__base_bash_libs_process_guardian_pid" 2> /dev/null
        )" || __base_bash_libs_process_parent_pid=""
    else
        __base_bash_libs_process_parent_pid="$(
            LC_ALL=C command ps -o ppid= -p "$__base_bash_libs_process_guardian_pid" 2> /dev/null
        )" || __base_bash_libs_process_parent_pid=""
    fi
    __base_bash_libs_process_parent_pid="${__base_bash_libs_process_parent_pid//[[:space:]]/}"
    if [[ "$__base_bash_libs_process_parent_pid" =~ ^[1-9][0-9]*$ ]]; then
        [[ "$__base_bash_libs_process_parent_pid" == "$__base_bash_libs_process_owner_pid" ]]
    elif builtin kill -0 "$__base_bash_libs_process_guardian_pid" 2> /dev/null; then
        # If `ps` cannot report a parent, require that the guardian itself is
        # still alive before falling back to the owner's liveness. A vanished
        # guardian must not report a stale owner relationship as true.
        builtin kill -0 "$__base_bash_libs_process_owner_pid" 2> /dev/null
    else
        return 1
    fi
}

__base_bash_libs_process_sleep_interval__() {
    if [[ -x /bin/sleep ]]; then
        /bin/sleep "$1"
    else
        command sleep "$1"
    fi
}

# Internal owner-guardian lifecycle used by asynchronous supervisors. The
# guardian owns a private FIFO, accepts an explicit stop message, and polls
# the real parent relationship of its BASHPID so a recycled owner PID cannot
# keep a detached helper alive. Cleanup runs only after the channel is closed,
# which lets callers remove the containing workspace safely.
__base_bash_libs_process_start_owner_guardian__() {
    (($# >= 6)) || return 1
    local __base_bash_libs_process_guardian_pid_name="$1"
    local __base_bash_libs_process_guardian_fd_name="$2"
    local __base_bash_libs_process_guardian_owner_pid="$3"
    local __base_bash_libs_process_guardian_control_path="$4"
    local __base_bash_libs_process_guardian_ready_path="$5"
    local __base_bash_libs_process_guardian_cleanup_fn="$6"
    shift 6
    local -a __base_bash_libs_process_guardian_cleanup_args=("$@")
    local __base_bash_libs_process_guardian_pid __base_bash_libs_process_guardian_fd
    local __base_bash_libs_process_guardian_monitor_was_enabled=0
    local __base_bash_libs_process_guardian_probe

    [[ "$__base_bash_libs_process_guardian_owner_pid" =~ ^[1-9][0-9]*$ ]] || return 1
    [[ -p "$__base_bash_libs_process_guardian_control_path" ]] || return 1
    [[ -n "$__base_bash_libs_process_guardian_ready_path" ]] || return 1
    if [[ -n "$__base_bash_libs_process_guardian_cleanup_fn" ]] &&
        ! base_std_function_exists "$__base_bash_libs_process_guardian_cleanup_fn"; then
        return 1
    fi
    if ! exec {__base_bash_libs_process_guardian_fd}<> "$__base_bash_libs_process_guardian_control_path"; then
        return 1
    fi

    [[ $- == *m* ]] && __base_bash_libs_process_guardian_monitor_was_enabled=1
    set +m
    (
        local __base_bash_libs_process_guardian_read_fd
        local __base_bash_libs_process_guardian_read_status=0
        local __base_bash_libs_process_guardian_command=""
        local __base_bash_libs_process_guardian_reason=channel
        local __base_bash_libs_process_guardian_self_pid="$BASHPID"

        trap - EXIT
        trap '' HUP INT QUIT TERM
        exec {__base_bash_libs_process_guardian_fd}>&-
        if ! exec {__base_bash_libs_process_guardian_read_fd}< \
            "$__base_bash_libs_process_guardian_control_path"; then
            command rm -f -- "$__base_bash_libs_process_guardian_control_path" \
                "$__base_bash_libs_process_guardian_ready_path"
            [[ -z "$__base_bash_libs_process_guardian_cleanup_fn" ]] ||
                "$__base_bash_libs_process_guardian_cleanup_fn" error \
                    "${__base_bash_libs_process_guardian_cleanup_args[@]}" || true
            exit 1
        fi
        if ! : > "$__base_bash_libs_process_guardian_ready_path"; then
            exec {__base_bash_libs_process_guardian_read_fd}<&-
            command rm -f -- "$__base_bash_libs_process_guardian_control_path" \
                "$__base_bash_libs_process_guardian_ready_path"
            [[ -z "$__base_bash_libs_process_guardian_cleanup_fn" ]] ||
                "$__base_bash_libs_process_guardian_cleanup_fn" error \
                    "${__base_bash_libs_process_guardian_cleanup_args[@]}" || true
            exit 1
        fi
        while :; do
            if IFS= read -r -t 1 -u "$__base_bash_libs_process_guardian_read_fd" \
                __base_bash_libs_process_guardian_command; then
                __base_bash_libs_process_guardian_reason=stop
                break
            else
                __base_bash_libs_process_guardian_read_status=$?
            fi
            ((__base_bash_libs_process_guardian_read_status > 128)) || break
            if ! __base_bash_libs_process_owner_alive__ \
                "$__base_bash_libs_process_guardian_owner_pid" \
                "$__base_bash_libs_process_guardian_self_pid"; then
                __base_bash_libs_process_guardian_reason=owner-gone
                break
            fi
        done
        exec {__base_bash_libs_process_guardian_read_fd}<&-
        # Remove the channel before caller cleanup so a callback can safely
        # remove its containing directory.
        command rm -f -- "$__base_bash_libs_process_guardian_control_path" \
            "$__base_bash_libs_process_guardian_ready_path"
        [[ -z "$__base_bash_libs_process_guardian_cleanup_fn" ]] ||
            "$__base_bash_libs_process_guardian_cleanup_fn" \
                "$__base_bash_libs_process_guardian_reason" \
                "${__base_bash_libs_process_guardian_cleanup_args[@]}" || true
    ) < /dev/null > /dev/null 2>&1 &
    __base_bash_libs_process_guardian_pid=$!
    if ((__base_bash_libs_process_guardian_monitor_was_enabled)); then
        set -m
    else
        set +m
    fi
    for ((__base_bash_libs_process_guardian_probe = 0;  \
    __base_bash_libs_process_guardian_probe < 100;  \
    __base_bash_libs_process_guardian_probe++)); do
        [[ -e "$__base_bash_libs_process_guardian_ready_path" ]] && break
        builtin kill -0 "$__base_bash_libs_process_guardian_pid" 2> /dev/null || break
        __base_bash_libs_process_sleep_interval__ 0.01 || break
    done
    if [[ ! -e "$__base_bash_libs_process_guardian_ready_path" ]]; then
        builtin kill -KILL "$__base_bash_libs_process_guardian_pid" 2> /dev/null || true
        wait "$__base_bash_libs_process_guardian_pid" 2> /dev/null || true
        exec {__base_bash_libs_process_guardian_fd}>&-
        return 1
    fi
    printf -v "$__base_bash_libs_process_guardian_pid_name" '%s' \
        "$__base_bash_libs_process_guardian_pid"
    printf -v "$__base_bash_libs_process_guardian_fd_name" '%s' \
        "$__base_bash_libs_process_guardian_fd"
}

__base_bash_libs_process_stop_owner_guardian__() {
    local __base_bash_libs_process_guardian_pid="${1-}"
    local __base_bash_libs_process_guardian_fd="${2-}"
    local __base_bash_libs_process_guardian_probe=0

    if [[ "$__base_bash_libs_process_guardian_fd" =~ ^[1-9][0-9]*$ ]]; then
        { printf 'stop\n' 1>&"$__base_bash_libs_process_guardian_fd"; } 2> /dev/null || true
        exec {__base_bash_libs_process_guardian_fd}>&-
    fi
    if [[ "$__base_bash_libs_process_guardian_pid" =~ ^[1-9][0-9]*$ ]]; then
        # A detached guardian can become unreapable if the caller is already
        # unwinding a signal trap. Bound the wait so teardown cannot hang.
        while ((__base_bash_libs_process_guardian_probe < 200)) &&
            builtin kill -0 "$__base_bash_libs_process_guardian_pid" 2> /dev/null; do
            wait "$__base_bash_libs_process_guardian_pid" 2> /dev/null && break
            builtin kill -0 "$__base_bash_libs_process_guardian_pid" 2> /dev/null || break
            __base_bash_libs_process_sleep_interval__ 0.01 || true
            __base_bash_libs_process_guardian_probe=$((\
                __base_bash_libs_process_guardian_probe + 1))
        done
        if builtin kill -0 "$__base_bash_libs_process_guardian_pid" 2> /dev/null; then
            builtin kill -KILL "$__base_bash_libs_process_guardian_pid" 2> /dev/null || true
        fi
        wait "$__base_bash_libs_process_guardian_pid" 2> /dev/null || true
    fi
}
