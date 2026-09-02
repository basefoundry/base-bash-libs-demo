#!/usr/bin/env bats

load ../../tests/test_helper.sh

readonly STDLIB_PATH="$BASE_BASH_DIR/std/lib_std.sh"

create_script() {
    local script_path="$1"
    local source_line init_lines content
    shift

    content="$(cat)"
    source_line="source \"$STDLIB_PATH\""
    if [[ "$content" == *"$source_line"* && "$content" != *"base-bash-libs: passive-source"* ]]; then
        init_lines=$'declare -a base_bash_libs_test_args=()\nbase_init base_bash_libs_test_args -- "$@"\nset -- "${base_bash_libs_test_args[@]}"'
        content="${content/"$source_line"/"$source_line"$'\n'"$init_lines"}"
    fi
    printf '%s\n' "$content" > "$script_path"
    chmod +x "$script_path"
}

file_mode() {
    if stat -c '%a' "$1" >/dev/null 2>&1; then
        stat -c '%a' "$1"
    else
        stat -f '%Lp' "$1"
    fi
}

normalize_tty_output() {
    local text="$1"
    text="${text//$'\r'/}"
    text="${text//$'\b'/}"
    printf '%s' "$text"
}

run_tty_script() {
    local script_path="$1"
    local command
    shift

    command -v script >/dev/null 2>&1 || skip "The 'script' command is required for tty tests."

    if script --version >/dev/null 2>&1; then
        printf -v command '%q ' "$script_path" "$@"
        bats_run script -q -e -c "${command% }" /dev/null
    else
        bats_run script -q /dev/null "$script_path" "$@"
    fi
}

run_pty_command() {
    local input="$1"
    local driver="$TEST_TMPDIR/pty-driver.py"
    shift

    cat > "$driver" <<'PY'
import errno
import os
import pty
import select
import signal
import sys
import time

input_bytes = sys.argv[1].encode()
command = sys.argv[2:]

pid, fd = pty.fork()
if pid == 0:
    os.execvp(command[0], command)

os.write(fd, input_bytes)
output = bytearray()
status = None
deadline = time.monotonic() + 10

while True:
    if time.monotonic() > deadline:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        status = 124
        break

    readable, _, _ = select.select([fd], [], [], 0.05)
    if readable:
        try:
            chunk = os.read(fd, 4096)
        except OSError as exc:
            if exc.errno == errno.EIO:
                chunk = b""
            else:
                raise
        if chunk:
            output.extend(chunk)

    waited, child_status = os.waitpid(pid, os.WNOHANG)
    if waited:
        if os.WIFEXITED(child_status):
            status = os.WEXITSTATUS(child_status)
        elif os.WIFSIGNALED(child_status):
            status = 128 + os.WTERMSIG(child_status)
        else:
            status = 1
        while True:
            readable, _, _ = select.select([fd], [], [], 0)
            if not readable:
                break
            try:
                chunk = os.read(fd, 4096)
            except OSError as exc:
                if exc.errno == errno.EIO:
                    break
                raise
            if not chunk:
                break
            output.extend(chunk)
        break

sys.stdout.buffer.write(output)
sys.exit(status if status is not None else 1)
PY

    bats_run python3 "$driver" "$input" "$@"
}

run_pty_signal_command() {
    local signal_name="$1" main_pid_file="$2" ready_file="$3"
    local driver="$TEST_TMPDIR/pty-signal-driver.py"
    shift 3

    cat > "$driver" <<'PY'
import errno
import os
import pty
import select
import signal
import sys
import time

signal_name = sys.argv[1]
main_pid_file = sys.argv[2]
ready_file = sys.argv[3]
command = sys.argv[4:]

pid, fd = pty.fork()
if pid == 0:
    os.execvp(command[0], command)

deadline = time.monotonic() + 10
while not os.path.exists(ready_file):
    if time.monotonic() > deadline:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        sys.exit(124)
    time.sleep(0.002)

with open(main_pid_file, encoding="ascii") as stream:
    main_pid = int(stream.read())
if signal_name == "CTRL_C":
    os.write(fd, b"\x03")
else:
    os.kill(main_pid, getattr(signal, "SIG" + signal_name))

output = bytearray()
status = None
deadline = time.monotonic() + 10
while status is None:
    if time.monotonic() > deadline:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        status = 124
        break
    readable, _, _ = select.select([fd], [], [], 0.05)
    if readable:
        try:
            chunk = os.read(fd, 4096)
        except OSError as exc:
            if exc.errno == errno.EIO:
                chunk = b""
            else:
                raise
        if chunk:
            output.extend(chunk)
    waited, child_status = os.waitpid(pid, os.WNOHANG)
    if waited:
        if os.WIFEXITED(child_status):
            status = os.WEXITSTATUS(child_status)
        elif os.WIFSIGNALED(child_status):
            status = 128 + os.WTERMSIG(child_status)
        else:
            status = 1

while True:
    readable, _, _ = select.select([fd], [], [], 0)
    if not readable:
        break
    try:
        chunk = os.read(fd, 4096)
    except OSError as exc:
        if exc.errno == errno.EIO:
            break
        raise
    if not chunk:
        break
    output.extend(chunk)

os.close(fd)
sys.stdout.buffer.write(output)
sys.exit(status if status is not None else 1)
PY

    bats_run python3 "$driver" "$signal_name" "$main_pid_file" \
        "$ready_file" "$@"
}

create_timeout_signal_disposition_script() {
    local script_path="$1"

    create_script "$script_path" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
disposition="\$1"
main_pid_file="\$2"
ready_file="\$3"
marker_file="\$4"
child_pid_file="\$5"
printf '%s\n' "\$BASHPID" >| "\$main_pid_file"

case "\$disposition" in
    custom)
        trap 'printf "handled\\n" >| "\$marker_file"' TERM
        ;;
    ignored)
        trap '' TERM
        ;;
    *)
        exit 64
        ;;
esac
before_trap="\$(trap -p TERM)"

signal_worker() {
    if [[ "\$disposition" == custom ]]; then
        trap '' TERM
        (trap '' TERM; while :; do /bin/sleep 1; done) &
        printf '%s\n' "\$!" >| "\$child_pid_file"
        : >| "\$ready_file"
        wait
    else
        : >| "\$ready_file"
        /bin/sleep 0.2
        return 42
    fi
}

if __base_bash_libs_std_run_with_timeout_fallback__ 30 signal_worker; then
    rc=0
else
    rc=\$?
fi
after_trap="\$(trap -p TERM)"
if [[ "\$before_trap" == "\$after_trap" ]]; then
    state=preserved
else
    state=changed
fi
printf 'rc=%s state=%s\n' "\$rc" "\$state"
EOF
}

setup() {
    setup_test_tmpdir
    PATH="$BASE_TEST_ORIG_PATH"
    unset BASE_BASH_LIBS_DRY_RUN BASE_BASH_LIBS_DRY_RUN BASE_BASH_LIBS_LOG_DEBUG BASE_BASH_LIBS_LOG_UTC NO_COLOR BASE_BASH_LIBS_BOOTSTRAP_SOURCE BASE_BASH_LIBS_PRIMARY_LOG
    source "$STDLIB_PATH"
    declare -a setup_args=()
    base_init setup_args -- "$@"
}

teardown() {
    PATH="$BASE_TEST_ORIG_PATH"
}

@test "sourcing stdlib is passive and preserves caller state" {
    bats_run bash -c '
        set -euo pipefail
        stdlib_path="$1"
        set -- "argument with spaces" "" "literal-*"
        IFS="| "
        OPTIND=7
        umask 027
        shopt -s extglob nullglob nocasematch
        trap ":" EXIT HUP INT TERM
        before_args=$(printf "%s\\n" "$#" "${1-}" "${2-}" "${3-}")
        before_set=$(set +o)
        before_shopt=$(shopt -p)
        before_traps=$(trap -p)
        before_exports=$(export -p)
        before_cwd=$(pwd -P)
        source "$stdlib_path"
        after_args=$(printf "%s\\n" "$#" "${1-}" "${2-}" "${3-}")
        [[ "$before_args" == "$after_args" ]]
        [[ "$before_set" == "$(set +o)" ]]
        [[ "$before_shopt" == "$(shopt -p)" ]]
        [[ "$before_traps" == "$(trap -p)" ]]
        [[ "$before_exports" == "$(export -p)" ]]
        [[ "$before_cwd" == "$(pwd -P)" ]]
        [[ ! -v BASE_BASH_LIBS_SCRIPT_ARGS && ! -v BASE_BASH_LIBS_SCRIPT_DIR ]]
        [[ ! -v BASE_BASH_LIBS_STD_LOG_LEVELS && ! -v __base_bash_libs_std_cleanup_hooks ]]
        printf "passive=yes\\nargs=%s\\n" "$#"
    ' bash "$STDLIB_PATH"

    [ "$status" -eq 0 ]
    [[ "$output" == *"passive=yes"* ]]
    [[ "$output" == *"args=3"* ]]
    [[ "$output" != *"unbound variable"* ]]
}

@test "explicit init filters args, publishes context, and is idempotent" {
    local script="$TEST_TMPDIR/explicit-init.sh"
    local expected_dir

    create_script "$script" <<EOF
#!/usr/bin/env bash
# base-bash-libs: passive-source
source "$STDLIB_PATH"
set -- --debug-wrapper alpha --color -- --debug-wrapper omega
before="\$*"
declare -a filtered=()
base_init filtered --source "\$0" -- "\$@"
[[ "\$*" == "\$before" ]]
printf 'filtered=%s\n' "\${filtered[*]}"
printf 'original=%s\n' "\${BASE_BASH_LIBS_SCRIPT_ARGS[*]}"
printf 'source-dir=%s\n' "\$BASE_BASH_LIBS_SCRIPT_DIR"
if base_init filtered --source "\$0" -- "\$@"; then
    printf 'repeat=same\n'
else
    exit 41
fi
if base_init filtered --source "\$0" -- changed; then
    exit 42
else
    printf 'different=diagnosed\n'
fi
EOF

    expected_dir="$(cd "$(dirname "$script")" && pwd -P)"
    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"filtered=alpha -- --debug-wrapper omega"* ]]
    [[ "$output" == *"original=--debug-wrapper alpha --color -- --debug-wrapper omega"* ]]
    [[ "$output" == *"source-dir=$expected_dir"* ]]
    [[ "$output" == *"repeat=same"* ]]
    [[ "$output" == *"different=diagnosed"* ]]
    [[ "$output" != *"unbound variable"* ]]
}

@test "stdlib source guard rejects caller-owned incompatible metadata" {
    bats_run bash -c '
        BASE_BASH_LIBS_STD_SOURCE_GUARD=1
        BASE_BASH_LIBS_STD_SOURCE_VERSION=0.0.0
        source "$1"
    ' bash "$STDLIB_PATH"

    [ "$status" -eq 1 ]
    [[ "$output" == *"incompatible base-bash-libs stdlib versions"* ]]
}

@test "deprecated --verbose-wrapper preserves original args and enables VERBOSE compatibility" {
    local script="$TEST_TMPDIR/check-init.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
printf 'orig=%s\n' "\${BASE_BASH_LIBS_SCRIPT_ARGS[*]}"
printf 'argv=%s\n' "\$*"
printf 'debug=%s\n' "\${BASE_BASH_LIBS_LOG_DEBUG:-}"
printf 'utc=%s\n' "\${BASE_BASH_LIBS_LOG_UTC:-}"
printf 'color=%s\n' "\${BASE_BASH_LIBS_STD_COLOR_RED:-}"
printf 'terminal-level=%s\n' "\${BASE_BASH_LIBS_STD_LOGGER_LEVELS[default]}"
printf 'library-level=%s\n' "\${BASE_BASH_LIBS_STD_LOG_CATEGORY_LEVELS[base_bash_libs]}"
EOF

    bats_run bash "$script" --verbose-wrapper --utc-wrapper --color alpha beta

    [ "$status" -eq 0 ]
    [[ "$output" == *"orig=--verbose-wrapper --utc-wrapper --color alpha beta"* ]]
    [[ "$output" == *"argv=alpha beta"* ]]
    [[ "$output" == *"debug=1"* ]]
    [[ "$output" == *"utc=1"* ]]
    [[ "$output" == *"color="* ]]
    [[ "$output" == *"terminal-level=5"* ]]
    [[ "$output" == *"library-level=5"* ]]
    [[ "$output" != *"deprecated"* ]]
    [[ "$output" != *"Command line:"* ]]
}

@test "--debug-wrapper enables caller and reusable-library DEBUG" {
    local script="$TEST_TMPDIR/check-debug-init.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
printf 'orig=%s\n' "\${BASE_BASH_LIBS_SCRIPT_ARGS[*]}"
printf 'argv=%s\n' "\$*"
printf 'debug=%s\n' "\${BASE_BASH_LIBS_LOG_DEBUG:-}"
printf 'terminal-level=%s\n' "\${BASE_BASH_LIBS_STD_LOGGER_LEVELS[default]}"
printf 'library-level=%s\n' "\${BASE_BASH_LIBS_STD_LOG_CATEGORY_LEVELS[base_bash_libs]}"
EOF

    bats_run bash "$script" --debug-wrapper alpha beta

    [ "$status" -eq 0 ]
    [[ "$output" == *"orig=--debug-wrapper alpha beta"* ]]
    [[ "$output" == *"argv=alpha beta"* ]]
    [[ "$output" == *"debug=1"* ]]
    [[ "$output" == *"terminal-level=4"* ]]
    [[ "$output" == *"library-level=4"* ]]
}

@test "stdlib never logs process arguments automatically" {
    local script="$TEST_TMPDIR/check-argv-logging.sh"
    local primary_log="$TEST_TMPDIR/check-argv-logging.log"
    local primary_content secret
    local separate_secret="separate-secret-191"
    local inline_secret="inline-secret-191"
    local positional_secret="positional-secret-191"
    local url_secret="url-secret-191"

    create_script "$script" <<EOF
#!/usr/bin/env bash
export BASE_BASH_LIBS_PRIMARY_LOG="$primary_log"
source "$STDLIB_PATH"
base_std_log_debug -l base_bash_libs.std "safe explicit diagnostic"
printf 'argv-count=%s\n' "\$#"
EOF

    bats_run bash "$script" \
        --debug-wrapper \
        --api-token "$separate_secret" \
        "--token=$inline_secret" \
        "$positional_secret" \
        "https://user:$url_secret@example.invalid/path"

    [ "$status" -eq 0 ]
    [[ "$output" == *"safe explicit diagnostic"* ]]
    [[ "$output" == *"argv-count=5"* ]]
    [[ "$output" != *"Command line:"* ]]

    primary_content="$(cat "$primary_log")"
    [[ "$primary_content" == *"safe explicit diagnostic"* ]]
    [[ "$primary_content" != *"Command line:"* ]]

    for secret in \
        "$separate_secret" \
        "$inline_secret" \
        "$positional_secret" \
        "$url_secret"; do
        [[ "$output" != *"$secret"* ]]
        [[ "$primary_content" != *"$secret"* ]]
    done
}

@test "sourcing stdlib stops filtering wrapper flags after --" {
    local script="$TEST_TMPDIR/check-init-escape.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
printf 'argv=%s\n' "\$*"
EOF

    bats_run bash "$script" --color alpha -- --color omega

    [ "$status" -eq 0 ]
    [[ "$output" == *"argv=alpha -- --color omega"* ]]
}

@test "bootstrap source override controls BASE_BASH_LIBS_SCRIPT_DIR" {
    local command_dir="$TEST_TMPDIR/commands/demo"
    local script="$TEST_TMPDIR/bootstrap-dir.sh"
    local expected_dir

    mkdir -p "$command_dir"

    create_script "$script" <<EOF
#!/usr/bin/env bash
export BASE_BASH_LIBS_BOOTSTRAP_SOURCE="$command_dir/demo.sh"
source "$STDLIB_PATH"
printf 'script_dir=%s\n' "\$BASE_BASH_LIBS_SCRIPT_DIR"
EOF

    expected_dir="$(cd "$command_dir" && pwd -P)"

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"script_dir=$expected_dir"* ]]
}

@test "stdlib supports a top-level strict shell without an outer BASH_SOURCE frame" {
    local expected_dir

    expected_dir="$(cd "$TEST_TMPDIR" && pwd -P)"
    bats_run bash -c '
        set -euo pipefail
        cd -- "$2"
        source "$1"
        declare -a app_args=()
        base_init app_args -- "$@"
        source_dir=""
        base_std_get_my_source_dir source_dir
        [[ "$-" == *e* && "$-" == *u* ]]
        shopt -qo pipefail
        printf "script_dir=%s\nsource_dir=%s\nstrict=preserved\n" "$BASE_BASH_LIBS_SCRIPT_DIR" "$source_dir"
    ' bash "$STDLIB_PATH" "$TEST_TMPDIR"

    [ "$status" -eq 0 ]
    [[ "$output" == *"script_dir=$expected_dir"* ]]
    [[ "$output" == *"source_dir=$expected_dir"* ]]
    [[ "$output" == *"strict=preserved"* ]]
    [[ "$output" != *"unbound variable"* ]]
}

@test "stdlib handles empty arrays in a strict child with no positional arguments" {
    local script="$TEST_TMPDIR/strict-empty-arrays.sh"
    local directory="$TEST_TMPDIR/strict-directory"

    create_script "$script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$STDLIB_PATH"
base_std_safe_mkdir "$directory"
temp_path=""
TMPDIR="$TEST_TMPDIR" base_std_make_temp_file temp_path strict-empty
base_std_unregister_cleanup_path "\$temp_path"
rm -f -- "\$temp_path"
printf 'args=%s strict=preserved\n' "\$#"
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [ -d "$directory" ]
    [[ "$output" == *"args=0 strict=preserved"* ]]
    [[ "$output" != *"unbound variable"* ]]
}

@test "stdlib exposes readonly package version from root VERSION" {
    local expected_version

    IFS= read -r expected_version < "$BASE_REPO_ROOT/VERSION"

    [ "${BASE_BASH_LIBS_VERSION:-}" = "$expected_version" ]
    readonly -p BASE_BASH_LIBS_VERSION >/dev/null
}

@test "base_require_version accepts the loaded version and older versions" {
    local stdout_file="$TEST_TMPDIR/version-check.out"

    base_require_version "$BASE_BASH_LIBS_VERSION" >"$stdout_file"
    base_require_version "0.1.0" >>"$stdout_file"

    [ ! -s "$stdout_file" ]
}

@test "base_require_version returns status 1 when the loaded version is too old" {
    local script="$TEST_TMPDIR/version-too-old.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_require_version "999.0.0"
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"base-bash-libs 999.0.0 or newer is required"* ]]
    [[ "$output" == *"loaded version is $BASE_BASH_LIBS_VERSION"* ]]
}

@test "base_require_version orders prereleases before a newer stable release" {
    local script="$TEST_TMPDIR/version-prerelease.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_require_version "2.0.0-rc.1"
base_require_version "2.0.0-alpha.1"
if base_require_version "2.0.1"; then
    exit 3
fi
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"base-bash-libs 2.0.1 or newer is required"* ]]
}

@test "base_require_version returns status 2 for invalid version strings" {
    local script="$TEST_TMPDIR/version-invalid.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_require_version "1.two.0"
EOF

    bats_run bash "$script"

    [ "$status" -eq 2 ]
    [[ "$output" == *"base_require_version expects supported SemVer versions"* ]]
}

@test "stdlib exposes readonly loaded marker" {
    [ "${BASE_BASH_LIBS_STDLIB_LOADED:-}" = "1" ]
    readonly -p BASE_BASH_LIBS_STDLIB_LOADED >/dev/null
}

@test "base_std_is_interactive is false in a non-interactive subprocess" {
    local script="$TEST_TMPDIR/non-interactive.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
if base_std_is_interactive; then
    echo "interactive=yes"
else
    echo "interactive=no"
fi
EOF

    bats_run bash "$script" </dev/null

    [ "$status" -eq 0 ]
    [[ "$output" == *"interactive=no"* ]]
}

@test "base_std_is_interactive is true when run through a tty" {
    local script="$TEST_TMPDIR/tty-interactive.sh"
    local normalized

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
if base_std_is_interactive; then
    echo "interactive=yes"
else
    echo "interactive=no"
fi
EOF

    run_tty_script "$script"
    normalized="$(normalize_tty_output "$output")"

    [ "$status" -eq 0 ]
    [[ "$normalized" == *"interactive=yes"* ]]
}

@test "stdlib exposes passive bash version check helper" {
    base_std_check_bash_version
    [ "$?" -eq 0 ]
}

@test "stdlib passive bash version check requires Bash 4.2 or newer" {
    local script="$TEST_TMPDIR/bash-version.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
BASE_TEST_BASH_VERSION=41 base_std_check_bash_version
EOF

    bats_run "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"requires Bash 4.2 or higher"* ]]
}

@test "stdlib passive bash version check rejects Bash 3.10 arithmetically" {
    local script="$TEST_TMPDIR/bash-version-3-10.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
BASE_TEST_BASH_VERSION=310 base_std_check_bash_version
EOF

    bats_run "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"requires Bash 4.2 or higher"* ]]
}

@test "sourcing stdlib fails cleanly under unsupported /bin/bash" {
    [[ -x /bin/bash ]] || skip "/bin/bash is not available."

    if ! /bin/bash -c '((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 2)))'; then
        skip "/bin/bash is supported on this host."
    fi

    bats_run /bin/bash -c 'source "$1"; rc=$?; printf "source-rc=%s\n" "$rc"; exit "$rc"' bash "$STDLIB_PATH"

    [ "$status" -eq 1 ]
    [[ "$output" == *"requires Bash 4.2 or higher"* ]]
    [[ "$output" == *"Your version"* ]]
    [[ "$output" == *"source-rc=1"* ]]
    [[ "$output" != *"syntax error"* ]]
}

@test "color initialization honors tty mode when --color is passed" {
    local script="$TEST_TMPDIR/tty-colors.sh"
    local normalized

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
if [[ -n "\${BASE_BASH_LIBS_STD_COLOR_RED:-}" ]]; then
    echo "colors=enabled"
else
    echo "colors=disabled"
fi
EOF

    run_tty_script "$script" --color
    normalized="$(normalize_tty_output "$output")"

    [ "$status" -eq 0 ]
    [[ "$normalized" == *"colors=enabled"* ]]
}

@test "color initialization uses stderr terminal for log colors" {
    local script="$TEST_TMPDIR/stderr-colors.sh"
    local stdout_file="$TEST_TMPDIR/stdout.txt"
    local normalized

    create_script "$script" <<EOF
#!/usr/bin/env bash
exec >"\$1"
source "$STDLIB_PATH"
if [[ -n "\${BASE_BASH_LIBS_STD_COLOR_RED:-}" ]]; then
    printf 'colors=enabled\n' >&2
else
    printf 'colors=disabled\n' >&2
fi
EOF

    run_tty_script "$script" "$stdout_file" --color
    normalized="$(normalize_tty_output "$output")"

    [ "$status" -eq 0 ]
    [[ "$normalized" == *"colors=enabled"* ]]
    [ ! -s "$stdout_file" ]
}

@test "NO_COLOR disables explicit tty color output" {
    local script="$TEST_TMPDIR/no-color.sh"
    local normalized

    create_script "$script" <<EOF
#!/usr/bin/env bash
export NO_COLOR=1
source "$STDLIB_PATH"
if [[ -n "\${BASE_BASH_LIBS_STD_COLOR_RED:-}" ]]; then
    echo "colors=enabled"
else
    echo "colors=disabled"
fi
EOF

    run_tty_script "$script" --color
    normalized="$(normalize_tty_output "$output")"

    [ "$status" -eq 0 ]
    [[ "$normalized" == *"colors=disabled"* ]]
}

@test "base_std_import loads package-relative libraries independent of cwd and is idempotent" {
    local script="$TEST_TMPDIR/base_std_import-driver.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_import str/lib_str.sh
base_std_import str/lib_str.sh
value='  package-relative  '
base_str_trim value
printf 'value=<%s> state=%s\n' "\$value" "\${__base_bash_libs_std_import_state[*]}"
EOF

    bats_run bash -c "cd \"$TEST_TMPDIR\" && \"$script\""

    [ "$status" -eq 0 ]
    [[ "$output" == *"value=<package-relative>"* ]]
    [[ "$output" == *"loaded"* ]]
}

@test "base_std_import returns a recoverable failure when a library is missing" {
    local script="$TEST_TMPDIR/base_std_import-missing.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_import missing.sh
printf 'after=%s\n' "\$?"
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"module 'missing.sh' does not exist"* ]]
    [[ "$output" == *"after=1"* ]]
}

@test "base_std_import failure does not leave relative base_std_import directory on the stack" {
    local package_dir="$TEST_TMPDIR/package"
    local script_dir="$TEST_TMPDIR/driver"
    local helper_dir="$package_dir/lib/bash/helpers"
    local run_dir="$TEST_TMPDIR/run"
    local script="$script_dir/base_std_import-failing-helper.sh"
    local cwd_file="$TEST_TMPDIR/base_std_import-exit-pwd.txt"
    local dirs_file="$TEST_TMPDIR/base_std_import-exit-dirs.txt"

    mkdir -p "$helper_dir" "$run_dir" "$script_dir"
    cp -R "$BASE_REPO_ROOT/lib/bash" "$package_dir/lib/"
    cp "$BASE_REPO_ROOT/VERSION" "$package_dir/VERSION"
    cat > "$helper_dir/failing.sh" <<EOF
trap 'pwd > "$cwd_file"; dirs -p > "$dirs_file"' EXIT
base_std_exit_if_error 7 "helper failed during base_std_import"
EOF
    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$package_dir/lib/bash/std/lib_std.sh"
base_std_import helpers/failing.sh
EOF

    bats_run bash -c "cd \"$run_dir\" && \"$script\""

    [ "$status" -eq 7 ]
    [ "$(cat "$cwd_file")" = "$run_dir" ]
    [ "$(head -n 1 "$dirs_file")" = "$run_dir" ]
    [[ "$(cat "$dirs_file")" != *"$script_dir"* ]]
}

@test "base_std_import rejects absolute, traversal, and package-escaping symlink paths" {
    local package_dir="$TEST_TMPDIR/safety package"
    local outside="$TEST_TMPDIR/outside.sh"
    local escaped="$package_dir/lib/bash/escape/lib_escape.sh"

    mkdir -p "$package_dir/lib"
    cp -R "$BASE_REPO_ROOT/lib/bash" "$package_dir/lib/"
    cp "$BASE_REPO_ROOT/VERSION" "$package_dir/VERSION"
    printf 'printf escaped\n' > "$outside"
    mkdir -p "$(dirname "$escaped")"
    ln -s "$outside" "$escaped"

    run bash -c '
        source "$1"
        base_std_import "$2"; printf "absolute=%s\n" "$?"
        base_std_import ../outside.sh; printf "traversal=%s\n" "$?"
        base_std_import escape/lib_escape.sh; printf "escape=%s\n" "$?"
    ' bash "$package_dir/lib/bash/std/lib_std.sh" "$outside"

    [ "$status" -eq 0 ]
    [[ "$output" == *"absolute=2"* ]]
    [[ "$output" == *"traversal=2"* ]]
    [[ "$output" == *"escape=2"* ]]
}

@test "base_std_import promotes top-level module declarations to globals" {
    local package_dir="$TEST_TMPDIR/scope package"
    local module_dir="$package_dir/lib/bash/test"
    local module="$module_dir/lib_scope.sh"

    mkdir -p "$package_dir/lib" "$module_dir"
    cp -R "$BASE_REPO_ROOT/lib/bash" "$package_dir/lib/"
    cp "$BASE_REPO_ROOT/VERSION" "$package_dir/VERSION"
    cat > "$module" <<'EOF'
declare -A BASE_BASH_LIBS_SCOPE_TEST=([state]=global)
EOF

    run bash -c '
        source "$1/lib/bash/std/lib_std.sh"
        base_std_import test/lib_scope.sh
        declare -p BASE_BASH_LIBS_SCOPE_TEST
    ' bash "$package_dir"
    [ "$status" -eq 0 ]
    [[ "$output" == *"declare -A BASE_BASH_LIBS_SCOPE_TEST"* ]]
}

@test "copy-only library artifacts report embedded release identity without VERSION" {
    local artifact_dir="$TEST_TMPDIR/copy artifact"
    local output

    mkdir -p "$artifact_dir/lib"
    cp -R "$BASE_REPO_ROOT/lib/bash" "$artifact_dir/lib/"
    rm -f "$artifact_dir/VERSION"

    output="$(cd "$TEST_TMPDIR" && bash -c '
        source "$1/lib/bash/std/lib_std.sh"
        base_std_import str/lib_str.sh
        printf "version=%s provenance=%s commit=%s dirty=%s\n" \
            "$BASE_BASH_LIBS_VERSION" "$BASE_BASH_LIBS_PROVENANCE" \
            "$BASE_BASH_LIBS_COMMIT" "$BASE_BASH_LIBS_DIRTY_STATE"
    ' bash "$artifact_dir")"

    [[ "$output" == *"version=2.0.0"* ]]
    [[ "$output" == *"provenance=release-artifact"* ]]
    [[ "$output" == *"commit=unknown"* ]]
    [[ "$output" == *"dirty=unknown"* ]]
}

@test "symlinked package roots and spaced paths keep one physical package identity" {
    local link_path="$TEST_TMPDIR/spaced package"
    local output

    ln -s "$BASE_REPO_ROOT" "$link_path"
    output="$(cd "$TEST_TMPDIR" && bash -c '
        source "$1/lib/bash/std/lib_std.sh"
        base_std_import str/lib_str.sh
        printf "root=%s version=%s\n" "$BASE_BASH_LIBS_STD_ROOT" "$BASE_BASH_LIBS_VERSION"
    ' bash "$link_path")"

    [[ "$output" == *"root=$BASE_REPO_ROOT"* ]]
    [[ "$output" == *"version=2.0.0"* ]]
}

@test "mixed-major stdlib inputs fail with migration guidance" {
    local other_root="$TEST_TMPDIR/v2-input"
    local output

    mkdir -p "$other_root/lib"
    cp -R "$BASE_REPO_ROOT/lib/bash" "$other_root/lib/"
    printf '1.4.0\n' > "$other_root/VERSION"
    sed 's/^version=.*/version=1.4.0/' \
        "$BASE_REPO_ROOT/lib/bash/base-bash-libs.release" \
        > "$other_root/lib/bash/base-bash-libs.release"

    output="$(bash -c '
        source "$1/lib/bash/std/lib_std.sh"
        source "$2/lib/bash/std/lib_std.sh"
    ' bash "$BASE_REPO_ROOT" "$other_root" 2>&1 || true)"

    [[ "$output" == *"mixed-major base-bash-libs module graph refused"* ]]
    [[ "$output" == *"v1 inputs are not fallback-loaded by v2"* ]]
}

@test "base_std_add_to_path appends an existing directory only once" {
    mkdir -p "$TEST_TMPDIR/bin"
    PATH="/usr/bin:/bin"

    base_std_add_to_path "$TEST_TMPDIR/bin"
    base_std_add_to_path "$TEST_TMPDIR/bin"

    [ "$PATH" = "/usr/bin:/bin:$TEST_TMPDIR/bin" ]
}

@test "base_std_add_to_path prepends when requested" {
    mkdir -p "$TEST_TMPDIR/bin"
    PATH="/usr/bin:/bin"

    base_std_add_to_path -p "$TEST_TMPDIR/bin"

    [ "$PATH" = "$TEST_TMPDIR/bin:/usr/bin:/bin" ]
}

@test "base_std_add_to_path skips missing directories unless -n is used" {
    PATH="/usr/bin:/bin"

    base_std_add_to_path "$TEST_TMPDIR/missing"
    [ "$PATH" = "/usr/bin:/bin" ]

    base_std_add_to_path -n "$TEST_TMPDIR/missing"
    [ "$PATH" = "/usr/bin:/bin:$TEST_TMPDIR/missing" ]
}

@test "base_std_add_to_path rejects invalid options" {
    local stderr_file="$TEST_TMPDIR/add-to-path.err"
    local rc

    if base_std_add_to_path -z 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 1 ]
    [[ "$(cat "$stderr_file")" == *"base_std_add_to_path: invalid option"* ]]
}

@test "base_std_add_to_path preserves caller OPTIND and batch prepend order" {
    local first="$TEST_TMPDIR/first"
    local second="$TEST_TMPDIR/second"
    local OPTIND=9

    mkdir -p "$first" "$second"
    PATH="/base"

    base_std_add_to_path -p "$first" "$second"

    [ "$OPTIND" -eq 9 ]
    [ "$PATH" = "$first:$second:/base" ]
}

@test "base_std_dedupe_path removes duplicates and empty entries" {
    PATH="/one:/two:/one::/three:/two"

    base_std_dedupe_path

    [ "$PATH" = "/one:/two:/three" ]
}

@test "base_std_print_path emits one path entry per line" {
    PATH="/one:/two:/three"

    bats_run base_std_print_path

    [ "$status" -eq 0 ]
    [ "$output" = $'/one\n/two\n/three' ]
}

@test "__base_bash_libs_std_join_message__ joins fragments with single spaces" {
    local joined

    joined="$(__base_bash_libs_std_join_message__ alpha beta "gamma delta")"

    [ "$joined" = "alpha beta gamma delta" ]
}

@test "log initialization defaults reusable-library categories to INFO" {
    [ "${BASE_BASH_LIBS_STD_LOG_LEVELS[ERROR]}" -eq 1 ]
    [ "${BASE_BASH_LIBS_STD_LOG_LEVELS[VERBOSE]}" -eq 5 ]
    [ "${BASE_BASH_LIBS_STD_LOGGER_LEVELS[default]}" -eq 3 ]
    [ "${BASE_BASH_LIBS_STD_LOG_CATEGORY_LEVELS[default]}" -eq 5 ]
    [ "${BASE_BASH_LIBS_STD_LOG_CATEGORY_LEVELS[base_bash_libs]}" -eq 3 ]
    [ -z "${BASE_BASH_LIBS_STD_COLOR_RED:-}" ]
}

@test "base_std_set_log_level updates loggers and rejects invalid input without changing levels" {
    local stderr_file="$TEST_TMPDIR/set-log-level.err"
    local rc

    base_std_set_log_level DEBUG
    [ "${BASE_BASH_LIBS_STD_LOGGER_LEVELS[default]}" -eq 4 ]
    base_std_set_log_level -l custom DEBUG
    [ "${BASE_BASH_LIBS_STD_LOGGER_LEVELS[custom]}" -eq 4 ]

    if base_std_set_log_level -l 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [[ "$(cat "$stderr_file")" == *"Option '-l' needs an argument"* ]]

    if base_std_set_log_level NOPE 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "${BASE_BASH_LIBS_STD_LOGGER_LEVELS[default]}" -eq 4 ]
    [[ "$(cat "$stderr_file")" == *"Unknown log level 'NOPE'"* ]]

    if base_std_set_log_level -l custom NOPE 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "${BASE_BASH_LIBS_STD_LOGGER_LEVELS[custom]}" -eq 4 ]
    [[ "$(cat "$stderr_file")" == *"Unknown log level 'NOPE' for logger 'custom'"* ]]
}

@test "base_std_set_log_category_level updates categories and rejects invalid input without changing levels" {
    local stderr_file="$TEST_TMPDIR/set-log-category-level.err"
    local rc

    base_std_set_log_category_level -l base.library DEBUG
    [ "${BASE_BASH_LIBS_STD_LOG_CATEGORY_LEVELS[base.library]}" -eq 4 ]

    if base_std_set_log_category_level -l base.library 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "${BASE_BASH_LIBS_STD_LOG_CATEGORY_LEVELS[base.library]}" -eq 4 ]
    [ -s "$stderr_file" ]

    if base_std_set_log_category_level -l base.library NOPE 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "${BASE_BASH_LIBS_STD_LOG_CATEGORY_LEVELS[base.library]}" -eq 4 ]
    [[ "$(cat "$stderr_file")" == *"Unknown log level 'NOPE'"* ]]
}

@test "log category resolution prefers exact then nearest parent then default" {
    local stderr_file="$TEST_TMPDIR/log-category-hierarchy.err"

    base_std_set_log_level DEBUG
    base_std_set_log_category_level -l product INFO
    base_std_set_log_category_level -l product.library DEBUG
    base_std_set_log_category_level -l product.library.exact INFO

    {
        base_std_log_debug -l product.library.worker "nearest parent enabled"
        base_std_log_debug -l product.library.exact "exact override hidden"
        base_std_log_debug -l product.library.sibling "sibling remains enabled"
        base_std_log_debug -l product.other "broader parent hidden"
        base_std_log_debug -l unrelated "default category enabled"
    } 2>"$stderr_file"

    [[ "$(cat "$stderr_file")" == *"nearest parent enabled"* ]]
    [[ "$(cat "$stderr_file")" != *"exact override hidden"* ]]
    [[ "$(cat "$stderr_file")" == *"sibling remains enabled"* ]]
    [[ "$(cat "$stderr_file")" != *"broader parent hidden"* ]]
    [[ "$(cat "$stderr_file")" == *"default category enabled"* ]]
}

@test "unconfigured named terminal loggers inherit default and explicit overrides win" {
    local stderr_file="$TEST_TMPDIR/log-terminal-inheritance.err"

    base_std_set_log_level DEBUG
    base_std_set_log_level -l explicit INFO

    {
        base_std_log_debug -l inherited "inherited terminal debug"
        base_std_log_debug -l explicit "explicit terminal override"
    } 2>"$stderr_file"

    [[ "$(cat "$stderr_file")" == *"inherited terminal debug"* ]]
    [[ "$(cat "$stderr_file")" != *"explicit terminal override"* ]]
}

@test "base_std_log_is_enabled requires both category acceptance and an accepting sink" {
    local primary_log="$TEST_TMPDIR/log-is-enabled-primary.log"

    base_std_log_is_enabled INFO
    ! base_std_log_is_enabled DEBUG

    BASE_BASH_LIBS_PRIMARY_LOG="$primary_log"
    base_std_log_is_enabled DEBUG
    ! base_std_log_is_enabled VERBOSE

    base_std_set_log_category_level -l base.library INFO
    ! base_std_log_is_enabled -l base.library DEBUG

    base_std_set_log_category_level -l base.library DEBUG
    base_std_log_is_enabled -l base.library DEBUG

    unset BASE_BASH_LIBS_PRIMARY_LOG
    ! base_std_log_is_enabled -l base.library DEBUG
    base_std_set_log_level DEBUG
    base_std_log_is_enabled -l base.library DEBUG
}

@test "base_std_log_is_enabled validates primary sink paths without modifying them" {
    local primary_log="$TEST_TMPDIR/eligible-primary.log"
    local existing_log="$TEST_TMPDIR/existing-eligible-primary.log"
    local missing_parent_log="$TEST_TMPDIR/missing/primary.log"
    local directory_log="$TEST_TMPDIR/directory-primary"
    local symlink_target="$TEST_TMPDIR/symlink-target.log"
    local symlink_log="$TEST_TMPDIR/symlink-primary.log"
    local fifo_log="$TEST_TMPDIR/fifo-primary.log"
    local stderr_file="$TEST_TMPDIR/unusable-primary.err"

    BASE_BASH_LIBS_PRIMARY_LOG="$primary_log"
    base_std_log_is_enabled DEBUG
    [ ! -e "$primary_log" ]

    printf 'existing eligible content\n' >"$existing_log"
    chmod 644 "$existing_log"
    BASE_BASH_LIBS_PRIMARY_LOG="$existing_log"
    base_std_log_is_enabled DEBUG
    [ "$(file_mode "$existing_log")" = "644" ]

    mkdir "$directory_log"
    BASE_BASH_LIBS_PRIMARY_LOG="$directory_log"
    ! base_std_log_is_enabled DEBUG

    printf 'symlink target\n' >"$symlink_target"
    ln -s "$symlink_target" "$symlink_log"
    BASE_BASH_LIBS_PRIMARY_LOG="$symlink_log"
    ! base_std_log_is_enabled DEBUG

    mkfifo "$fifo_log"
    BASE_BASH_LIBS_PRIMARY_LOG="$fifo_log"
    ! base_std_log_is_enabled DEBUG
    base_std_log_debug "fifo must not block" 2>"$stderr_file"
    [ ! -s "$stderr_file" ]

    BASE_BASH_LIBS_PRIMARY_LOG="$missing_parent_log"
    ! base_std_log_is_enabled DEBUG
    base_std_log_debug "missing parent must stay silent" 2>"$stderr_file"
    [ ! -e "$missing_parent_log" ]
    [ ! -s "$stderr_file" ]
    [ "$(cat "$symlink_target")" = "symlink target" ]
}

@test "primary sink creates and hardens regular files to mode 0600" {
    local new_log="$TEST_TMPDIR/new-private-primary.log"
    local existing_log="$TEST_TMPDIR/existing-primary.log"
    local option_log="$TEST_TMPDIR/-option-primary.log"
    local stderr_file="$TEST_TMPDIR/private-primary.err"
    local original_dir original_umask

    original_umask="$(umask)"
    umask 000
    BASE_BASH_LIBS_PRIMARY_LOG="$new_log" base_std_log_debug "new private record" 2>"$stderr_file"
    umask "$original_umask"

    [ ! -s "$stderr_file" ]
    [ "$(file_mode "$new_log")" = "600" ]
    [[ "$(cat "$new_log")" == *"new private record"* ]]

    printf 'existing sentinel\n' >"$existing_log"
    chmod 666 "$existing_log"
    BASE_BASH_LIBS_PRIMARY_LOG="$existing_log" \
        base_std_log_debug "existing private record" 2>"$stderr_file"

    [ ! -s "$stderr_file" ]
    [ "$(file_mode "$existing_log")" = "600" ]
    [[ "$(cat "$existing_log")" == "existing sentinel"* ]]
    [[ "$(cat "$existing_log")" == *"existing private record"* ]]

    original_dir="$PWD"
    cd "$TEST_TMPDIR" || return 1
    BASE_BASH_LIBS_PRIMARY_LOG="-option-primary.log" \
        base_std_log_debug "option-like private record" 2>"$stderr_file"
    cd "$original_dir" || return 1

    [ ! -s "$stderr_file" ]
    [ "$(file_mode "$option_log")" = "600" ]
    [[ "$(cat "$option_log")" == *"option-like private record"* ]]
}

@test "unusable primary sinks stay silent without disabling the terminal" {
    local directory_log="$TEST_TMPDIR/unusable-primary"
    local stderr_file="$TEST_TMPDIR/unusable-terminal.err"

    mkdir "$directory_log"

    BASE_BASH_LIBS_PRIMARY_LOG="$directory_log" \
        base_std_log_debug "hidden unusable record" 2>"$stderr_file"
    [ ! -s "$stderr_file" ]

    BASE_BASH_LIBS_PRIMARY_LOG="$directory_log"
    ! base_std_log_is_enabled DEBUG
    base_std_set_log_level DEBUG
    base_std_log_is_enabled DEBUG
    base_std_log_debug "terminal-only debug" 2>"$stderr_file"

    [[ "$(cat "$stderr_file")" == *"DEBUG"*"terminal-only debug"* ]]
    [[ "$(cat "$stderr_file")" != *"Is a directory"* ]]
    [[ "$(cat "$stderr_file")" != *"No such file or directory"* ]]
}

@test "primary sink setup failures keep every failed path disabled" {
    local first_log="$TEST_TMPDIR/first-raced-primary.log"
    local second_log="$TEST_TMPDIR/second-raced-primary.log"
    local stderr_file="$TEST_TMPDIR/raced-primary.err"

    __base_bash_libs_std_log_primary_sink_is_usable__ "$first_log"
    __base_bash_libs_std_log_primary_sink_is_usable__ "$second_log"
    __base_bash_libs_std_log_primary_sink_prepare__() {
        printf 'synthetic primary sink setup failure\n' >&2
        return 1
    }

    BASE_BASH_LIBS_PRIMARY_LOG="$first_log" \
        __base_bash_libs_std_log_primary_sink_write__ record "first must not persist" 2>"$stderr_file"
    BASE_BASH_LIBS_PRIMARY_LOG="$second_log" \
        __base_bash_libs_std_log_primary_sink_write__ record "second must not persist" 2>>"$stderr_file"

    [ ! -s "$stderr_file" ]
    [ "${BASE_BASH_LIBS_STD_LOG_FAILED_SINKS[$first_log]}" = "1" ]
    [ "${BASE_BASH_LIBS_STD_LOG_FAILED_SINKS[$second_log]}" = "1" ]

    [ ! -e "$first_log" ]
    [ ! -e "$second_log" ]
    ! __base_bash_libs_std_log_primary_sink_is_usable__ "$first_log"
    ! __base_bash_libs_std_log_primary_sink_is_usable__ "$second_log"
}

@test "read-only primary sink is ignored when the test identity cannot write it" {
    local primary_log="$TEST_TMPDIR/read-only-primary.log"
    local stderr_file="$TEST_TMPDIR/read-only-primary.err"

    printf 'read-only sentinel\n' >"$primary_log"
    chmod 400 "$primary_log"
    [[ ! -w "$primary_log" ]] || skip "The test identity can write mode-0400 files."

    BASE_BASH_LIBS_PRIMARY_LOG="$primary_log"
    ! base_std_log_is_enabled DEBUG
    base_std_log_debug "must not persist" 2>"$stderr_file"

    [ ! -s "$stderr_file" ]
    [ "$(file_mode "$primary_log")" = "400" ]
    [ "$(cat "$primary_log")" = "read-only sentinel" ]
}

@test "base_std_log_is_enabled rejects malformed and invalid input without changing logging state" {
    local stderr_file="$TEST_TMPDIR/log-is-enabled-invalid.err"
    local rc

    base_std_set_log_category_level -l base.library DEBUG
    base_std_set_log_level DEBUG

    if base_std_log_is_enabled -l 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "${BASE_BASH_LIBS_STD_LOG_CATEGORY_LEVELS[base.library]}" -eq 4 ]
    [ "${BASE_BASH_LIBS_STD_LOGGER_LEVELS[default]}" -eq 4 ]
    [ -s "$stderr_file" ]

    if base_std_log_is_enabled -l base.library NOPE 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "${BASE_BASH_LIBS_STD_LOG_CATEGORY_LEVELS[base.library]}" -eq 4 ]
    [ "${BASE_BASH_LIBS_STD_LOGGER_LEVELS[default]}" -eq 4 ]
    [[ "$(cat "$stderr_file")" == *"NOPE"* ]]
}

@test "__base_bash_libs_std_print_log__ requires a log level" {
    ! __base_bash_libs_std_print_log__
}

@test "__base_bash_libs_std_print_log__ formats timestamps without command substitution" {
    bats_run grep -nE 'timestamp="\$\((TZ=UTC0 )?printf' "$STDLIB_PATH"

    [ "$status" -eq 1 ]
    [ "$output" = "" ]
}

@test "__base_bash_libs_std_print_log__ emits structured records through one final printf" {
    bats_run grep -nF 'printf '"'"'%b%s%b\n'"'"' "$__base_bash_libs_std_log_record_color" "$__base_bash_libs_std_log_record_line" "$BASE_BASH_LIBS_STD_COLOR_OFF"' "$STDLIB_PATH"

    [ "$status" -eq 0 ]
}

@test "log wrappers respect the configured log level" {
    local stderr_file="$TEST_TMPDIR/log-wrappers.err"

    : > "$stderr_file"
    base_std_log_debug hidden 2>"$stderr_file"
    [ ! -s "$stderr_file" ]

    base_std_set_log_level VERBOSE
    {
        base_std_log_fatal "fatal message"
        base_std_log_error "error message"
        base_std_log_warn "warn message"
        base_std_log_info "info message"
        base_std_log_debug "debug message"
        base_std_log_verbose "verbose message"
    } 2>"$stderr_file"

    [[ "$(cat "$stderr_file")" == *"FATAL"* ]]
    [[ "$(cat "$stderr_file")" == *"ERROR"* ]]
    [[ "$(cat "$stderr_file")" == *"WARN"* ]]
    [[ "$(cat "$stderr_file")" == *"INFO"* ]]
    [[ "$(cat "$stderr_file")" == *"DEBUG"* ]]
    [[ "$(cat "$stderr_file")" == *"VERBOSE"* ]]
}

@test "log wrappers persist the DEBUG diagnostic stream without changing terminal verbosity" {
    local stderr_file="$TEST_TMPDIR/log-primary.err"
    local primary_log="$TEST_TMPDIR/primary.log"

    BASE_BASH_LIBS_PRIMARY_LOG="$primary_log" base_std_log_debug "persisted debug" 2>"$stderr_file"
    [ ! -s "$stderr_file" ]
    [[ "$(cat "$primary_log")" == *"DEBUG"*"persisted debug"* ]]

    BASE_BASH_LIBS_PRIMARY_LOG="$primary_log" base_std_log_info "terminal info" 2>>"$stderr_file"
    [[ "$(cat "$stderr_file")" == *"INFO"*"terminal info"* ]]
    [[ "$(cat "$primary_log")" == *"INFO"*"terminal info"* ]]
}

@test "category gates apply before terminal and persistent sink decisions" {
    local stderr_file="$TEST_TMPDIR/log-category-sinks.err"
    local primary_log="$TEST_TMPDIR/log-category-sinks.log"

    base_std_set_log_category_level -l base.library INFO
    BASE_BASH_LIBS_PRIMARY_LOG="$primary_log" \
        base_std_log_debug -l base.library "blocked library debug" 2>"$stderr_file"

    [ ! -s "$stderr_file" ]
    [ ! -s "$primary_log" ]

    base_std_set_log_category_level -l base.library DEBUG
    BASE_BASH_LIBS_PRIMARY_LOG="$primary_log" \
        base_std_log_debug -l base.library "persisted library debug" 2>"$stderr_file"

    [ ! -s "$stderr_file" ]
    [[ "$(cat "$primary_log")" == *"DEBUG"*"persisted library debug"* ]]
    [[ "$(cat "$primary_log")" != *"blocked library debug"* ]]
}

@test "__base_bash_libs_std_print_log__ uses local timestamps by default" {
    local stderr_file="$TEST_TMPDIR/log-local-time.err"
    local expected_before expected_after output

    expected_before="$(TZ=Pacific/Honolulu printf '%(%Y-%m-%d %H:%M:%S %z)T' -1)"
    TZ=Pacific/Honolulu base_std_log_info "local timestamp" 2>"$stderr_file"
    expected_after="$(TZ=Pacific/Honolulu printf '%(%Y-%m-%d %H:%M:%S %z)T' -1)"
    output="$(cat "$stderr_file")"

    [[ "$output" == "$expected_before"* || "$output" == "$expected_after"* ]]
    [[ "$output" == *"local timestamp"* ]]
}

@test "__base_bash_libs_std_print_log__ honors BASE_BASH_LIBS_LOG_UTC for Bash timestamps" {
    local stderr_file="$TEST_TMPDIR/log-utc-time.err"
    local expected_before expected_after output local_before local_after

    expected_before="$(TZ=UTC printf '%(%Y-%m-%d %H:%M:%S)T UTC' -1)"
    local_before="$(TZ=Pacific/Honolulu printf '%(%Y-%m-%d %H:%M:%S %z)T' -1)"
    TZ=Pacific/Honolulu BASE_BASH_LIBS_LOG_UTC=1 base_std_log_info "utc timestamp" 2>"$stderr_file"
    expected_after="$(TZ=UTC printf '%(%Y-%m-%d %H:%M:%S)T UTC' -1)"
    local_after="$(TZ=Pacific/Honolulu printf '%(%Y-%m-%d %H:%M:%S %z)T' -1)"
    output="$(cat "$stderr_file")"

    [[ "$expected_before" != "$local_before" || "$expected_after" != "$local_after" ]]
    [[ "$output" == "$expected_before"* || "$output" == "$expected_after"* ]]
    [[ "$output" == *"utc timestamp"* ]]
}

@test "__base_bash_libs_std_print_log__ bounds stdlib caller stack walking" {
    local script="$TEST_TMPDIR/log-bounded-caller.sh"
    local caller_log="$TEST_TMPDIR/caller-count.log"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
caller_log="$caller_log"
: > "\$caller_log"
caller() {
    printf 'call\n' >> "\$caller_log"
    caller_count="\$(wc -l < "\$caller_log")"
    if ((caller_count > 20)); then
        return 1
    fi
    printf '%s stdlib_frame %s\n' "\$1" "\$__LIB_STD_PATH__"
}
__base_bash_libs_std_print_log__ INFO "bounded stack walk" >/dev/null
printf 'caller_count=%s\n' "\$(( \$(wc -l < "\$caller_log") ))"
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"caller_count=20"* ]]
}

@test "file logging helpers inherit default terminal levels for named categories" {
    local target="$TEST_TMPDIR/log-target.txt"
    local stderr_file="$TEST_TMPDIR/log-file.err"

    printf 'hello file\n' > "$target"

    base_std_log_debug_file "$target" 2>"$stderr_file"
    [ ! -s "$stderr_file" ]

    base_std_set_log_level DEBUG
    base_std_log_debug_file "$target" 2>"$stderr_file"
    [[ "$(cat "$stderr_file")" == *"Contents of file '$target':"* ]]
    [[ "$(cat "$stderr_file")" == *"hello file"* ]]

    __base_bash_libs_std_print_log_file__ INFO -l missing "$target" 2>"$stderr_file"
    [[ "$(cat "$stderr_file")" == *"Contents of file '$target':"* ]]
    [[ "$(cat "$stderr_file")" == *"hello file"* ]]
    [[ "$(cat "$stderr_file")" != *"Unknown logger"* ]]
}

@test "deprecated VERBOSE file logging remains behaviorally compatible" {
    local target="$TEST_TMPDIR/log-verbose-target.txt"
    local stderr_file="$TEST_TMPDIR/log-verbose-file.err"

    printf 'verbose file contents\n' > "$target"
    base_std_set_log_level VERBOSE

    base_std_log_verbose_file "$target" 2>"$stderr_file"

    [[ "$(cat "$stderr_file")" == *"VERBOSE"*"Contents of file '$target':"* ]]
    [[ "$(cat "$stderr_file")" == *"verbose file contents"* ]]
}

@test "file logging helpers apply category gates and sink decisions" {
    local target="$TEST_TMPDIR/log-category-target.txt"
    local stderr_file="$TEST_TMPDIR/log-category-file.err"
    local primary_log="$TEST_TMPDIR/log-category-file.log"

    printf 'category file contents\n' > "$target"
    base_std_set_log_category_level -l base.files INFO

    BASE_BASH_LIBS_PRIMARY_LOG="$primary_log" \
        base_std_log_debug_file -l base.files "$target" 2>"$stderr_file"

    [ ! -s "$stderr_file" ]
    [ ! -s "$primary_log" ]

    base_std_set_log_category_level -l base.files DEBUG
    BASE_BASH_LIBS_PRIMARY_LOG="$primary_log" \
        base_std_log_debug_file -l base.files "$target" 2>"$stderr_file"

    [ ! -s "$stderr_file" ]
    [[ "$(cat "$primary_log")" == *"DEBUG"*"Contents of file '$target':"* ]]
    [[ "$(cat "$primary_log")" == *"category file contents"* ]]
}

@test "file logging helpers separate unterminated contents from later records" {
    local target="$TEST_TMPDIR/log-unterminated-target.txt"
    local stderr_file="$TEST_TMPDIR/log-unterminated.err"
    local primary_log="$TEST_TMPDIR/log-unterminated.log"

    printf 'unterminated contents' > "$target"
    base_std_set_log_level DEBUG

    BASE_BASH_LIBS_PRIMARY_LOG="$primary_log" \
        base_std_log_debug_file "$target" 2>"$stderr_file"
    BASE_BASH_LIBS_PRIMARY_LOG="$primary_log" \
        base_std_log_info "next structured record" 2>>"$stderr_file"

    [[ "$(cat "$stderr_file")" == *$'unterminated contents\n'*"next structured record"* ]]
    [[ "$(cat "$primary_log")" == *$'unterminated contents\n'*"next structured record"* ]]
}

@test "file logging hardens an existing primary sink before appending" {
    local target="$TEST_TMPDIR/log-private-target.txt"
    local stderr_file="$TEST_TMPDIR/log-private-file.err"
    local primary_log="$TEST_TMPDIR/log-private-file.log"

    printf 'existing sink content\n' >"$primary_log"
    chmod 644 "$primary_log"
    printf 'private file contents\n' >"$target"
    base_std_set_log_category_level -l base.files DEBUG

    BASE_BASH_LIBS_PRIMARY_LOG="$primary_log" \
        base_std_log_debug_file -l base.files "$target" 2>"$stderr_file"

    [ ! -s "$stderr_file" ]
    [ "$(file_mode "$primary_log")" = "600" ]
    [[ "$(cat "$primary_log")" == "existing sink content"* ]]
    [[ "$(cat "$primary_log")" == *"Contents of file '$target':"* ]]
    [[ "$(cat "$primary_log")" == *"private file contents"* ]]
}

@test "enter and leave logging helpers include the caller name" {
    local stderr_file="$TEST_TMPDIR/enter-leave.err"

    trace_me() {
        base_std_log_info_enter
        base_std_log_debug_enter
        base_std_log_verbose_enter
        base_std_log_info_leave
        base_std_log_debug_leave
        base_std_log_verbose_leave
    }

    base_std_set_log_level VERBOSE
    trace_me 2>"$stderr_file"

    [[ "$(cat "$stderr_file")" == *"VERBOSE"*"Entering function trace_me"* ]]
    [[ "$(cat "$stderr_file")" == *"VERBOSE"*"Leaving function trace_me"* ]]
}

@test "top-level logging stack helpers are nounset-safe" {
    bats_run bash -c '
        set -euo pipefail
        source "$1"
        declare -a app_args=()
        base_init app_args -- "$@"
        base_std_log_info_enter
        base_std_log_info_leave
        printf "after-log\n"
    ' bash "$STDLIB_PATH"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Entering function main"* ]]
    [[ "$output" == *"Leaving function main"* ]]
    [[ "$output" == *"after-log"* ]]
    [[ "$output" != *"unbound variable"* ]]
}

@test "top-level logging usage errors remain diagnostic under strict options" {
    bats_run bash -c '
        set -euo pipefail
        source "$1"
        declare -a app_args=()
        base_init app_args -- "$@"
        base_std_set_log_level NOT_A_LEVEL
        printf "after-log-error\n"
    ' bash "$STDLIB_PATH"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown log level 'NOT_A_LEVEL'"* ]]
    [[ "$output" != *"unbound variable"* ]]
    [[ "$output" != *"after-log-error"* ]]
}

@test "print helpers emit expected text" {
    local stderr_file="$TEST_TMPDIR/print.err"
    local stdout_file="$TEST_TMPDIR/print.out"

    {
        base_std_print_error "bad news"
        base_std_print_warn "careful"
        base_std_print_info "heads up"
        base_std_print_success "all good"
    } 2>"$stderr_file"

    {
        base_std_print_bold "strong text"
        base_std_print_message "line one" "line two"
    } >"$stdout_file"

    [[ "$(cat "$stderr_file")" == *"ERROR: bad news"* ]]
    [[ "$(cat "$stderr_file")" == *"WARN: careful"* ]]
    [[ "$(cat "$stderr_file")" == *"heads up"* ]]
    [[ "$(cat "$stderr_file")" == *"SUCCESS: all good"* ]]
    [ "$(cat "$stdout_file")" = $'strong text\nline one\nline two' ]
}

@test "base_std_print_tty is silent without a tty" {
    local stdout_file="$TEST_TMPDIR/tty.out"

    base_std_print_tty "hidden output" >"$stdout_file"

    [ ! -s "$stdout_file" ]
}

@test "base_std_print_tty emits output when a tty is present" {
    local script="$TEST_TMPDIR/print-tty.sh"
    local normalized

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_print_tty "tty output"
EOF

    run_tty_script "$script"
    normalized="$(normalize_tty_output "$output")"

    [ "$status" -eq 0 ]
    [[ "$normalized" == *"tty output"* ]]
}

@test "base_std_dump_trace prints the active function stack" {
    local script="$TEST_TMPDIR/dump-trace.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
inner_trace() {
    base_std_dump_trace
}
outer_trace() {
    inner_trace
}
outer_trace
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Encountered a fatal error"* ]]
    [[ "$output" == *"inner_trace"* ]]
    [[ "$output" == *"outer_trace"* ]]
}

@test "logging stack parsing is independent of and preserves caller IFS" {
    local script="$TEST_TMPDIR/log-stack-ifs.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
stack_with_custom_ifs() {
    IFS=:
    base_std_log_info "custom IFS log"
    base_std_dump_trace
    printf 'ifs=<%s>\n' "\$IFS"
}
stack_with_custom_ifs
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"log-stack-ifs.sh:"*"custom IFS log"* ]]
    [[ "$output" == *"stack_with_custom_ifs"* ]]
    [[ "$output" == *"ifs=<:>"* ]]
}

@test "base_std_exit_if_error returns success for zero and empty input" {
    local rc

    if base_std_exit_if_error; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]

    base_std_exit_if_error 0 "unused"
    [ "$?" -eq 0 ]
}

@test "base_std_exit_if_error exits with the provided code and message" {
    local script="$TEST_TMPDIR/exit-if-error.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_exit_if_error 7 "boom"
echo "after"
EOF

    bats_run bash "$script"

    [ "$status" -eq 7 ]
    [[ "$output" == *"boom"* ]]
    [[ "$output" != *"after"* ]]
}

@test "base_std_exit_if_error preserves its requested status with errexit and pipefail" {
    local script="$TEST_TMPDIR/exit-if-error-strict.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$STDLIB_PATH"
base_std_exit_if_error 7 "strict boom"
printf 'after\n'
EOF

    bats_run bash "$script"

    [ "$status" -eq 7 ]
    [[ "$output" == *"strict boom"* ]]
    [[ "$output" == *"Encountered a fatal error"* ]]
    [[ "$output" != *"after"* ]]
}

@test "base_std_exit_if_error normalizes non-numeric exit codes" {
    local script="$TEST_TMPDIR/exit-if-error-nonnumeric.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_exit_if_error nope "bad code"
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"is not a valid exit code"* ]]
    [[ "$output" == *"bad code"* ]]
}

@test "base_std_fatal_error preserves the last non-zero status" {
    local script="$TEST_TMPDIR/fatal-error.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
bash -c 'exit 7'
base_std_fatal_error "fatal boom"
EOF

    bats_run bash "$script"

    [ "$status" -eq 7 ]
    [[ "$output" == *"fatal boom"* ]]
}

@test "stdlib exposes base_std_run without compatibility aliases" {
    local script="$TEST_TMPDIR/std-run-api.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
printf 'base_std_run=%s\n' "\$(type -t base_std_run || true)"
printf 'base_std_run_or_exit=%s\n' "\$(type -t base_std_run_or_exit || true)"
printf 'run=%s\n' "\$(type -t run || true)"
printf 'std_run_with_timeout=%s\n' "\$(type -t std_run_with_timeout || true)"
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"base_std_run=function"* ]]
    [[ "$output" == *"base_std_run_or_exit=function"* ]]
    [[ "$output" == *$'run=\n'* ]]
    [[ "$output" == *"std_run_with_timeout="* ]]
    [[ "$output" != *"std_run_with_timeout=function"* ]]
}

@test "command display helpers validate labels and keep protected argv opaque" {
    local rendered
    local unsafe_display

    __base_bash_libs_std_is_safe_display__ "upload release asset"
    for unsafe_display in \
        "" \
        "-option-like" \
        $'line\nbreak' \
        $'carriage\rreturn' \
        $'tab\tlabel' \
        $'delete\177label' \
        $'next-line-\302\205' \
        $'line-separator-\342\200\250' \
        $'paragraph-separator-\342\200\251' \
        $'bidi-override-\342\200\256'; do
        if __base_bash_libs_std_is_safe_display__ "$unsafe_display"; then
            return 1
        fi
    done

    __base_bash_libs_std_render_command_display__ rendered 1 "upload release asset" \
        '[sensitive command; arguments hidden]' \
        "CANARY spaced value" "--token=CANARY-inline"
    [ "$rendered" = "upload release asset [sensitive command; arguments hidden]" ]
    [[ "$rendered" != *"CANARY"* ]]

    __base_bash_libs_std_render_command_display__ rendered 1 "" \
        '[sensitive command; arguments hidden]' "CANARY-default"
    [ "$rendered" = "[sensitive command; arguments hidden]" ]

    __base_bash_libs_std_render_command_display__ rendered 0 "" \
        '[sensitive command; arguments hidden]' printf '%s\n' "value with spaces"
    [ "$rendered" = 'printf %s\\n value\ with\ spaces' ]

    local LC_ALL=C
    readonly LC_ALL
    __base_bash_libs_std_is_safe_display__ "readonly locale remains supported" \
        2>"$TEST_TMPDIR/safe-display-readonly-locale.err"
    [ ! -s "$TEST_TMPDIR/safe-display-readonly-locale.err" ]
}

@test "base_std_run returns an error when no command is provided" {
    local stderr_file="$TEST_TMPDIR/run-empty.err"
    local rc

    if base_std_run 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 1 ]
    [[ "$(cat "$stderr_file")" == *"base_std_run: No command provided."* ]]
}

@test "base_std_run rejects unknown long options before command execution" {
    local stderr_file="$TEST_TMPDIR/run-unknown-option.err"
    local rc

    if base_std_run --typo echo "should not run" 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 1 ]
    [[ "$(cat "$stderr_file")" == *"base_std_run: unknown runner option."* ]]
    [[ "$(cat "$stderr_file")" != *"--typo"* ]]
    [[ "$(cat "$stderr_file")" == *"Use -- before commands that begin with --."* ]]
}

@test "base_std_run allows command names beginning with -- after option terminator" {
    local fake_bin="$TEST_TMPDIR/bin"
    local output_file="$TEST_TMPDIR/option-like-command.out"

    mkdir -p "$fake_bin"
    create_script "$fake_bin/--record-command" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" > "$2"
EOF

    PATH="$fake_bin:$PATH" base_std_run -- --record-command "ran" "$output_file"

    [ "$(cat "$output_file")" = "ran" ]
}

@test "base_std_run rejects malformed sensitive controls without executing or exposing arguments" {
    local marker="$TEST_TMPDIR/sensitive-invalid.marker"
    local script="$TEST_TMPDIR/sensitive-invalid.sh"
    local stderr_file="$TEST_TMPDIR/sensitive-invalid.err"
    local canary="CANARY-malformed-control-secret"
    local rc

    create_script "$script" <<EOF
#!/usr/bin/env bash
printf 'executed\n' > "$marker"
EOF

    if base_std_run --safe-display "operation" -- "$script" "$canary" 2>>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]

    if base_std_run --sensitive --safe-display "" -- "$script" "$canary" 2>>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]

    if base_std_run --sensitive --safe-display "unicode-$canary"$'\342\200\250' -- "$script" 2>>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]

    if base_std_run --sensitive --safe-display $'unsafe\nlabel' -- "$script" "$canary" 2>>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]

    if base_std_run --sensitive "$script" "--token=$canary" 2>>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]

    if base_std_run --sensitive "--token=$canary" "$script" 2>>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]

    if base_std_run --sensitive --safe-display "-H$canary" -- "$script" 2>>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]

    if base_std_run --sensitive --safe-display "--token=$canary" -- "$script" 2>>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]

    if base_std_run --sensitive --safe-display -- "$script" "$canary" 2>>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]

    [ ! -e "$marker" ]
    [[ "$(cat "$stderr_file")" != *"$canary"* ]]
    [[ "$(cat "$stderr_file")" == *"--safe-display is valid only with --sensitive"* ]]
    [[ "$(cat "$stderr_file")" == *"--sensitive requires -- before the command"* ]]
    [[ "$(cat "$stderr_file")" == *"unknown runner option"* ]]
}

@test "base_std_run honors dry-run mode without executing the command" {
    local target="$TEST_TMPDIR/dry-run.txt"
    BASE_BASH_LIBS_DRY_RUN=true

    base_std_run touch "$target"

    [ "$?" -eq 0 ]
    [ ! -e "$target" ]
}

@test "base_std_run sensitive dry-run hides varied canaries from terminal and persistent diagnostics" {
    local marker="$TEST_TMPDIR/sensitive-dry-run.marker"
    local script="$TEST_TMPDIR/sensitive-dry-run.sh"
    local stderr_file="$TEST_TMPDIR/sensitive-dry-run.err"
    local primary_log="$TEST_TMPDIR/sensitive-dry-run.log"
    local diagnostic_file canary
    local -a canaries=(
        "CANARY spaced value"
        "CANARY-inline-value"
        "CANARY-header-value"
        "CANARY-url-userinfo"
        "CANARY-form-field"
    )

    create_script "$script" <<EOF
#!/usr/bin/env bash
printf 'executed\n' > "$marker"
EOF

    BASE_BASH_LIBS_DRY_RUN=1
    BASE_BASH_LIBS_PRIMARY_LOG="$primary_log" base_std_run \
        --sensitive --safe-display "upload release asset" \
        --timeout 30 --max-attempts 3 --retry-delay 2 -- \
        "$script" \
        "${canaries[0]}" \
        "--token=${canaries[1]}" \
        --header "Authorization: Bearer ${canaries[2]}" \
        "https://user:${canaries[3]}@example.test/path" \
        --field "password=${canaries[4]}" 2>"$stderr_file"
    unset BASE_BASH_LIBS_DRY_RUN

    [ ! -e "$marker" ]
    [ -s "$stderr_file" ]
    [ -s "$primary_log" ]
    for diagnostic_file in "$stderr_file" "$primary_log"; do
        grep -Fq "upload release asset [sensitive command; arguments hidden]" "$diagnostic_file"
        grep -Fq "30s timeout, 3 attempts, 2s retry delay" "$diagnostic_file"
        for canary in "${canaries[@]}"; do
            ! grep -Fq -- "$canary" "$diagnostic_file"
        done
    done
}

@test "base_std_run ordinary dry-run retains copy-pastable argument rendering" {
    local stderr_file="$TEST_TMPDIR/ordinary-dry-run.err"

    BASE_BASH_LIBS_DRY_RUN=1
    base_std_run printf '%s\n' "value with spaces" "--option=ordinary value" 2>"$stderr_file"
    unset BASE_BASH_LIBS_DRY_RUN

    [[ "$(cat "$stderr_file")" == *'printf %s\\n value\ with\ spaces --option=ordinary\ value'* ]]
    [[ "$(cat "$stderr_file")" != *"arguments hidden"* ]]
}

@test "base_std_run treats common truthy dry-run values as dry-run mode" {
    local case_name target value var_name

    for case_name in \
        "BASE_BASH_LIBS_DRY_RUN=1" \
        "BASE_BASH_LIBS_DRY_RUN=yes" \
        "BASE_BASH_LIBS_DRY_RUN=on" \
        "BASE_BASH_LIBS_DRY_RUN=true" \
        "BASE_BASH_LIBS_DRY_RUN=1" \
        "BASE_BASH_LIBS_DRY_RUN=yes" \
        "BASE_BASH_LIBS_DRY_RUN=on"; do
        unset BASE_BASH_LIBS_DRY_RUN BASE_BASH_LIBS_DRY_RUN
        var_name="${case_name%%=*}"
        value="${case_name#*=}"
        printf -v "$var_name" '%s' "$value"
        export "$var_name"
        target="$TEST_TMPDIR/dry-run-${var_name}-${value}.txt"

        base_std_run touch "$target"

        [ "$?" -eq 0 ]
        [ ! -e "$target" ]
    done
}

@test "base_std_run --no-exit returns the underlying failure status" {
    local stderr_file="$TEST_TMPDIR/run-no-exit.err"
    local rc

    if base_std_run --no-exit bash -c 'exit 7' 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 7 ]
    [[ "$(cat "$stderr_file")" == *"continuing"* ]]
}

@test "base_std_run --no-exit --quiet suppresses failure warning" {
    local stderr_file="$TEST_TMPDIR/run-no-exit-quiet.err"
    local rc

    if base_std_run --no-exit --quiet bash -c 'exit 7' 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 7 ]
    [ ! -s "$stderr_file" ]
}

@test "base_std_run returns the failure status by default" {
    local script="$TEST_TMPDIR/run-fail.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
if base_std_run bash -c 'exit 9'; then
    printf 'unexpected success\n'
else
    printf 'status=%s\n' "\$?"
fi
echo "after"
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Command failed (exit 9)"* ]]
    [[ "$output" == *"status=9"* ]]
    [[ "$output" == *"after"* ]]
}

@test "base_std_run_or_exit exits the script on failure" {
    local script="$TEST_TMPDIR/run-or-exit-fail.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_run_or_exit bash -c 'exit 9'
echo "after"
EOF

    bats_run bash "$script"

    [ "$status" -eq 9 ]
    [[ "$output" == *"Command failed (exit 9)"* ]]
    [[ "$output" != *"after"* ]]
}

@test "base_std_run --timeout returns 124 when the command times out" {
    local script="$TEST_TMPDIR/run-timeout.sh"
    local stderr_file="$TEST_TMPDIR/run-timeout.err"
    local rc_file="$TEST_TMPDIR/run-timeout.rc"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
if base_std_run --no-exit --quiet --timeout 1 /bin/sleep 2 2>"$stderr_file"; then
    printf '0\n' > "$rc_file"
else
    printf '%s\n' "\$?" > "$rc_file"
fi
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$(cat "$rc_file")" = "124" ]
    [ ! -s "$stderr_file" ]
}

@test "base_std_run preserves a natural 124 status instead of calling it a timeout" {
    local stderr_file="$TEST_TMPDIR/natural-124.err"
    local rc

    if base_std_run --no-exit --timeout 5 /bin/bash -c 'exit 124' 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 124 ]
    [[ "$(cat "$stderr_file")" == *"Command failed (exit 124)"* ]]
    [[ "$(cat "$stderr_file")" != *"Command timed out"* ]]
}

@test "base_std_run fallback preserves Bash function resolution over same-named executables" {
    local rc

    timeout_function_collision() { return 73; }
    base_std_command_path() {
        printf -v "$1" '%s' /bin/false
        return 0
    }

    if __base_bash_libs_std_run_with_timeout_fallback__ 5 timeout_function_collision; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 73 ]
}

@test "base_std_run fallback preserves piped stdin shell functions and exact fast status 127" {
    local script="$TEST_TMPDIR/run-timeout-pipe-status.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
fallback_reader() {
    local value
    IFS= read -r value
    printf 'read=%s\n' "\$value"
}
printf 'pipe-value\n' | __base_bash_libs_std_run_with_timeout_fallback__ 5 fallback_reader || exit 1
for ((iteration = 0; iteration < 20; iteration++)); do
    if __base_bash_libs_std_run_with_timeout_fallback__ 5 /bin/bash -c 'exit 127'; then
        rc=0
    else
        rc=\$?
    fi
    ((rc == 127)) || exit 1
done
printf 'statuses=exact\n'
EOF

    bats_run "$script"
    [ "$status" -eq 0 ]
    [[ "$output" == *"read=pipe-value"* ]]
    [[ "$output" == *"statuses=exact"* ]]
}

@test "base_std_run fallback refuses a foreground tty without executing" {
    local script="$TEST_TMPDIR/run-timeout-tty-refused.sh"
    local marker="$TEST_TMPDIR/run-timeout-tty-refused.marker"
    local normalized

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
if __base_bash_libs_std_run_with_timeout_fallback__ 1 /bin/touch "$marker"; then
    rc=0
else
    rc=\$?
fi
printf 'rc=%s\n' "\$rc"
EOF

    run_pty_command '' "$script"
    normalized="$(normalize_tty_output "$output")"

    [ "$status" -eq 0 ]
    [[ "$normalized" == *"rc=125"* ]]
    [[ "$normalized" == *"TIMEOUT ERROR"* ]]
    [[ "$normalized" != *"Terminated:"* ]]
    [[ "$normalized" != *"Killed:"* ]]
    [ ! -e "$marker" ]
}

@test "base_std_run fallback reads from read-only foreground tty and preserves caller state" {
    skip "Foreground-tty hard timeout supervision is intentionally fail-closed in v2."
    ps -eo pid=,ppid= >/dev/null 2>&1 ||
        skip "The process-listing command is unavailable in this environment."

    local script="$TEST_TMPDIR/run-timeout-readonly-tty.sh" normalized

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
exec 0</dev/tty
trap ':' HUP
trap ':' INT
trap ':' QUIT
trap ':' TERM
before_traps="\$(trap -p HUP INT QUIT TERM)"
[[ \$- == *m* ]] && before_monitor=on || before_monitor=off
tty_reader() {
    local value
    IFS= read -r value
    printf 'read=%s\n' "\$value"
}
if __base_bash_libs_std_run_with_timeout_fallback__ 20 tty_reader; then
    rc=0
else
    rc=\$?
fi
after_traps="\$(trap -p HUP INT QUIT TERM)"
[[ \$- == *m* ]] && after_monitor=on || after_monitor=off
if [[ "\$before_traps" == "\$after_traps" &&
    "\$before_monitor" == "\$after_monitor" ]]; then
    state=preserved
else
    state=changed
fi
printf 'rc=%s state=%s monitor=%s\n' "\$rc" "\$state" "\$after_monitor"
EOF

    run_pty_command $'readonly-value\n' "$script"
    normalized="$(normalize_tty_output "$output")"

    [ "$status" -eq 0 ]
    [[ "$normalized" == *"read=readonly-value"* ]]
    [[ "$normalized" == *"rc=0 state=preserved monitor=off"* ]]
    [[ "$normalized" != *"read error"* ]]
    [[ "$normalized" != *"Terminated:"* ]]
    [[ "$normalized" != *"Killed:"* ]]
}

@test "base_std_run fallback keeps foreground and background tty fast paths quiet" {
    skip "Foreground-tty hard timeout supervision is intentionally fail-closed in v2."
    ps -eo pid=,ppid= >/dev/null 2>&1 ||
        skip "The process-listing command is unavailable in this environment."

    local script="$TEST_TMPDIR/run-timeout-tty-fast.sh" normalized mode

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
mode="\${1-}"
[[ "\$mode" != on ]] || set -m
failures=0
for ((iteration = 0; iteration < 20; iteration++)); do
    if __base_bash_libs_std_run_with_timeout_fallback__ 5 true; then
        rc=0
    else
        rc=\$?
    fi
    ((rc == 0)) || failures=\$((failures + 1))
done
if [[ "\$mode" == on ]]; then
    exec {tty_input}<&0
    (
        __base_bash_libs_std_run_with_timeout_fallback__ 5 true <&"\$tty_input"
    ) &
    background_pid=\$!
    if wait "\$background_pid"; then
        background_rc=0
    else
        background_rc=\$?
    fi
else
    background_rc=0
fi
printf 'failures=%s background=%s monitor=%s\n' \
    "\$failures" "\$background_rc" \
    "\$( [[ \$- == *m* ]] && printf on || printf off )"
EOF

    for mode in off on; do
        if [[ "$mode" == on ]]; then
            run_pty_command '' "$script" on
        else
            run_pty_command '' "$script"
        fi
        normalized="$(normalize_tty_output "$output")"
        [ "$status" -eq 0 ]
        [[ "$normalized" == *"failures=0 background=0 monitor=$mode"* ]]
        [[ "$normalized" != *"read error"* ]]
        [[ "$normalized" != *"Terminated:"* ]]
        [[ "$normalized" != *"Killed:"* ]]
        [[ "$normalized" != *"fg:"* ]]
    done
}

@test "base_std_run fallback directly cancels a resistant foreground tty tree" {
    skip "Foreground-tty hard timeout supervision is intentionally fail-closed in v2."
    ps -eo pid=,ppid= >/dev/null 2>&1 ||
        skip "The process-listing command is unavailable in this environment."

    local script="$TEST_TMPDIR/run-timeout-tty-signals.sh"
    local signal_name expected expected_output main_pid_file ready_file child_pid_file
    local normalized child_pid

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
main_pid_file="\$1"
ready_file="\$2"
child_pid_file="\$3"
trap - HUP INT QUIT TERM
printf '%s\n' "\$BASHPID" > "\$main_pid_file"
resistant_reader() {
    trap '' HUP INT QUIT TERM
    (trap '' HUP INT QUIT TERM; while :; do /bin/sleep 1; done) &
    printf '%s\n' "\$!" > "\$child_pid_file"
    : > "\$ready_file"
    local value
    IFS= read -r value
    while :; do /bin/sleep 1; done
}
if __base_bash_libs_std_run_with_timeout_fallback__ 30 resistant_reader; then
    rc=0
else
    rc=\$?
fi
printf 'rc=%s\n' "\$rc"
EOF

    for signal_name in HUP INT QUIT TERM CTRL_C; do
        expected_output=""
        case "$signal_name" in
            HUP) expected=129 ;;
            INT | CTRL_C) expected=130 ;;
            # Non-interactive Bash ignores SIGQUIT after `trap - QUIT`, so a
            # successful redelivery resumes and exposes the exact 131 return.
            QUIT) expected=0; expected_output="rc=131" ;;
            TERM) expected=143 ;;
        esac
        main_pid_file="$TEST_TMPDIR/tty-$signal_name.main"
        ready_file="$TEST_TMPDIR/tty-$signal_name.ready"
        child_pid_file="$TEST_TMPDIR/tty-$signal_name.child"

        run_pty_signal_command "$signal_name" "$main_pid_file" "$ready_file" \
            "$script" "$main_pid_file" "$ready_file" "$child_pid_file"
        normalized="$(normalize_tty_output "$output")"
        child_pid="$(cat "$child_pid_file")"

        if [ "$status" -ne "$expected" ]; then
            printf 'signal=%s expected=%s actual=%s output=%q\n' \
                "$signal_name" "$expected" "$status" "$normalized" >&3
            return 1
        fi
        if [[ -n "$expected_output" ]]; then
            [[ "$normalized" == *"$expected_output"* ]]
        else
            [[ "$normalized" != *"rc="* ]]
        fi
        [[ "$normalized" != *"read error"* ]]
        [[ "$normalized" != *"Terminated:"* ]]
        [[ "$normalized" != *"Killed:"* ]]
        if kill -0 "$child_pid" 2>/dev/null; then
            kill -KILL "$child_pid" 2>/dev/null || true
            return 1
        fi
    done
}

@test "base_std_run fallback composes custom and ignored TERM dispositions without a tty" {
    local script="$TEST_TMPDIR/run-timeout-signal-disposition.sh"
    local disposition main_pid_file ready_file marker_file child_pid_file
    local stdout_file stderr_file target_pid main_pid target_status actual_output
    local child_pid probe

    create_timeout_signal_disposition_script "$script"

    for disposition in custom ignored; do
        main_pid_file="$TEST_TMPDIR/non-tty-$disposition.main"
        ready_file="$TEST_TMPDIR/non-tty-$disposition.ready"
        marker_file="$TEST_TMPDIR/non-tty-$disposition.marker"
        child_pid_file="$TEST_TMPDIR/non-tty-$disposition.child"
        stdout_file="$TEST_TMPDIR/non-tty-$disposition.out"
        stderr_file="$TEST_TMPDIR/non-tty-$disposition.err"

        "$script" "$disposition" "$main_pid_file" "$ready_file" \
            "$marker_file" "$child_pid_file" </dev/null \
            >"$stdout_file" 2>"$stderr_file" &
        target_pid=$!
        for ((probe = 0; probe < 1000; probe++)); do
            [[ -s "$main_pid_file" && -e "$ready_file" ]] && break
            /bin/sleep 0.002
        done
        if [[ ! -s "$main_pid_file" || ! -e "$ready_file" ]]; then
            kill -KILL "$target_pid" 2>/dev/null || true
            wait "$target_pid" 2>/dev/null || true
            return 1
        fi
        main_pid="$(cat "$main_pid_file")"
        kill -TERM "$main_pid"
        if wait "$target_pid"; then
            target_status=0
        else
            target_status=$?
        fi
        actual_output="$(cat "$stdout_file")"

        [ "$target_status" -eq 0 ]
        [ ! -s "$stderr_file" ]
        if [[ "$disposition" == custom ]]; then
            [[ "$actual_output" == *"rc=143 state=preserved"* ]]
            [ "$(cat "$marker_file")" = handled ]
            child_pid="$(cat "$child_pid_file")"
            for ((probe = 0; probe < 100; probe++)); do
                kill -0 "$child_pid" 2>/dev/null || break
                /bin/sleep 0.01
            done
            if kill -0 "$child_pid" 2>/dev/null; then
                kill -KILL "$child_pid" 2>/dev/null || true
                return 1
            fi
        else
            [[ "$actual_output" == *"rc=42 state=preserved"* ]]
            [ ! -e "$marker_file" ]
            [ ! -e "$child_pid_file" ]
        fi
    done
}

@test "base_std_run fallback composes custom and ignored TERM dispositions on an active tty" {
    skip "Foreground-tty hard timeout supervision is intentionally fail-closed in v2."
    ps -eo pid=,ppid= >/dev/null 2>&1 ||
        skip "The process-listing command is unavailable in this environment."

    local script="$TEST_TMPDIR/run-timeout-tty-signal-disposition.sh"
    local disposition main_pid_file ready_file marker_file child_pid_file
    local normalized child_pid probe

    create_timeout_signal_disposition_script "$script"

    for disposition in custom ignored; do
        main_pid_file="$TEST_TMPDIR/tty-$disposition.main"
        ready_file="$TEST_TMPDIR/tty-$disposition.ready"
        marker_file="$TEST_TMPDIR/tty-$disposition.marker"
        child_pid_file="$TEST_TMPDIR/tty-$disposition.child"

        run_pty_signal_command TERM "$main_pid_file" "$ready_file" \
            "$script" "$disposition" "$main_pid_file" "$ready_file" \
            "$marker_file" "$child_pid_file"
        normalized="$(normalize_tty_output "$output")"

        [ "$status" -eq 0 ]
        [[ "$normalized" != *"read error"* ]]
        [[ "$normalized" != *"Terminated:"* ]]
        [[ "$normalized" != *"Killed:"* ]]
        if [[ "$disposition" == custom ]]; then
            [[ "$normalized" == *"rc=143 state=preserved"* ]]
            [ "$(cat "$marker_file")" = handled ]
            child_pid="$(cat "$child_pid_file")"
            for ((probe = 0; probe < 100; probe++)); do
                kill -0 "$child_pid" 2>/dev/null || break
                /bin/sleep 0.01
            done
            if kill -0 "$child_pid" 2>/dev/null; then
                kill -KILL "$child_pid" 2>/dev/null || true
                return 1
            fi
        else
            [[ "$normalized" == *"rc=42 state=preserved"* ]]
            [ ! -e "$marker_file" ]
            [ ! -e "$child_pid_file" ]
        fi
    done
}

@test "base_std_run fallback preserves caller traps monitor state and unrelated readonly names" {
    local before_trap after_trap before_monitor after_monitor rc
    readonly command_status=99 timeout_status_file=/dev/null
    trap ':' HUP
    before_trap="$(trap -p HUP)"
    [[ $- == *m* ]] && before_monitor=1 || before_monitor=0

    if __base_bash_libs_std_run_with_timeout_fallback__ 5 /bin/bash -c 'exit 42'; then
        rc=0
    else
        rc=$?
    fi

    after_trap="$(trap -p HUP)"
    [[ $- == *m* ]] && after_monitor=1 || after_monitor=0
    trap - HUP
    [ "$rc" -eq 42 ]
    [ "$after_trap" = "$before_trap" ]
    [ "$after_monitor" -eq "$before_monitor" ]
}

@test "base_std_run fallback supports noclobber and preserves its caller state" {
    local script="$TEST_TMPDIR/run-timeout-noclobber.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
set -C
[[ -o noclobber ]] && before=on || before=off
if __base_bash_libs_std_run_with_timeout_fallback__ 5 /bin/bash -c 'exit 42'; then
    fast_rc=0
else
    fast_rc=\$?
fi
if __base_bash_libs_std_run_with_timeout_fallback__ 1 /bin/bash -c \
    'trap "" TERM; /bin/sleep 3'; then
    timeout_rc=0
else
    timeout_rc=\$?
fi
[[ -o noclobber ]] && after=on || after=off
printf 'fast=%s timeout=%s before=%s after=%s\n' \
    "\$fast_rc" "\$timeout_rc" "\$before" "\$after"
EOF

    bats_run "$script"

    [ "$status" -eq 0 ]
    [ "$output" = "fast=42 timeout=124 before=on after=on" ]
}

@test "base_std_run fallback timeout kills commands that ignore TERM" {
    local fake_bin="$TEST_TMPDIR/no-timeout-bin"
    local marker_file="$TEST_TMPDIR/term-ignored.marker"
    local rc_file="$TEST_TMPDIR/term-ignored.rc"
    local script="$TEST_TMPDIR/term-ignored-timeout.sh"

    mkdir -p "$fake_bin"
    ln -s "$(command -v mktemp)" "$fake_bin/mktemp"
    ln -s "$(command -v rm)" "$fake_bin/rm"
    ln -s "$(command -v sleep)" "$fake_bin/sleep"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
PATH="$fake_bin"
if base_std_run --no-exit --quiet --timeout 1 /bin/bash -c 'trap "" TERM; sleep 3; printf completed > "\$1"' _ "$marker_file"; then
    printf '0\n' > "$rc_file"
else
    printf '%s\n' "\$?" > "$rc_file"
fi
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$(cat "$rc_file")" = "124" ]
    [ ! -e "$marker_file" ]
}

@test "base_std_run fallback sidecars preserve an inherited EXIT trap in command substitution" {
    local fake_bin="$TEST_TMPDIR/no-timeout-bin"
    local caller_dir="$TEST_TMPDIR/caller-owned"
    local script="$TEST_TMPDIR/timeout-command-substitution.sh"

    mkdir -p "$fake_bin"
    ln -s "$(command -v mktemp)" "$fake_bin/mktemp"
    ln -s "$(command -v rm)" "$fake_bin/rm"
    ln -s "$(command -v sleep)" "$fake_bin/sleep"
    mkdir -p "$caller_dir"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
export TMPDIR="$TEST_TMPDIR"
caller_dir="$caller_dir"
trap 'rm -rf -- "\$caller_dir"' EXIT
value="\$(PATH="$fake_bin" base_std_run --no-exit --quiet --timeout 5 /bin/echo fallback)" || exit \$?
[[ -d "\$caller_dir" ]] || exit 91
printf 'value=%s\ncaller-dir=present\n' "\$value"
trap - EXIT
EOF

    bats_run "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"value=fallback"* ]]
    [[ "$output" == *"caller-dir=present"* ]]
    ! compgen -G "$TEST_TMPDIR/base-bash-libs-timeout.*" >/dev/null
    ! compgen -G "$TEST_TMPDIR/base-bash-libs-timeout-status.*" >/dev/null
}

@test "base_std_run fallback fast success leaves no watchdog sleep descendants" {
    local before_file="$TEST_TMPDIR/watchdog-before.txt"
    local after_file="$TEST_TMPDIR/watchdog-after.txt"
    local iteration pid

    pgrep -f '^/bin/sleep 29$' > "$before_file" 2>/dev/null || true
    for ((iteration = 0; iteration < 40; iteration++)); do
        __base_bash_libs_std_run_with_timeout_fallback__ 29 true
    done
    /bin/sleep 0.1
    pgrep -f '^/bin/sleep 29$' > "$after_file" 2>/dev/null || true

    while IFS= read -r pid; do
        [[ -n "$pid" ]] || continue
        grep -Fxq "$pid" "$before_file" || return 1
    done < "$after_file"
}

@test "base_std_run fallback timeout terminates descendants" {
    ps -eo pid=,ppid= >/dev/null 2>&1 || skip "The process-listing command is unavailable in this environment."

    local fake_bin="$TEST_TMPDIR/no-timeout-process-group-bin"
    local child_pid_file="$TEST_TMPDIR/timeout-descendant.pid"
    local script="$TEST_TMPDIR/timeout-descendant.sh"
    local child_pid rc

    mkdir -p "$fake_bin"
    ln -s "$(command -v mktemp)" "$fake_bin/mktemp"
    ln -s "$(command -v rm)" "$fake_bin/rm"
    ln -s "$(command -v sleep)" "$fake_bin/sleep"
    command -v pgrep >/dev/null 2>&1 || skip "The 'pgrep' command is required for descendant timeout coverage."
    ln -s "$(command -v pgrep)" "$fake_bin/pgrep"

    create_script "$script" <<'EOF'
#!/usr/bin/env bash
trap '' TERM
sleep 30 &
child_pid=$!
printf '%s\n' "$child_pid" > "$1"
wait "$child_pid"
EOF

    if PATH="$fake_bin" base_std_run --no-exit --quiet --timeout 1 /bin/bash "$script" "$child_pid_file"; then
        rc=0
    else
        rc=$?
    fi

    child_pid="$(cat "$child_pid_file")"
    sleep 1.2

    [ "$rc" -eq 124 ]
    if kill -0 "$child_pid" 2>/dev/null; then
        kill -KILL "$child_pid" 2>/dev/null || true
        return 1
    fi
}

@test "base_std_run --max-attempts retries until the command succeeds" {
    local counter_file="$TEST_TMPDIR/retry-count.txt"
    local script="$TEST_TMPDIR/retry-eventual-success.sh"

    create_script "$script" <<'EOF'
#!/usr/bin/env bash
count=0
[[ -f "$1" ]] && count="$(cat "$1")"
count=$((count + 1))
printf '%s\n' "$count" > "$1"
((count >= 3))
EOF

    base_std_run --no-exit --quiet --max-attempts 3 bash "$script" "$counter_file"

    [ "$?" -eq 0 ]
    [ "$(cat "$counter_file")" = "3" ]
}

@test "base_std_run sensitive retries and final failure keep terminal and persistent diagnostics secret-safe" {
    local counter_file="$TEST_TMPDIR/sensitive-retry-count.txt"
    local script="$TEST_TMPDIR/sensitive-retry.sh"
    local stderr_file="$TEST_TMPDIR/sensitive-retry.err"
    local primary_log="$TEST_TMPDIR/sensitive-retry.log"
    local canary="CANARY-retry-final-secret"
    local diagnostic_file rc

    create_script "$script" <<'EOF'
#!/usr/bin/env bash
count=0
[[ -f "$1" ]] && read -r count < "$1"
count=$((count + 1))
printf '%s\n' "$count" > "$1"
exit 73
EOF

    if BASE_BASH_LIBS_PRIMARY_LOG="$primary_log" base_std_run \
        --no-exit --max-attempts 2 \
        --sensitive --safe-display "publish release metadata" -- \
        "$script" "$counter_file" "value with $canary" "--token=$canary" 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 73 ]
    [ "$(cat "$counter_file")" = "2" ]
    for diagnostic_file in "$stderr_file" "$primary_log"; do
        grep -Fq "publish release metadata [sensitive command; arguments hidden]" "$diagnostic_file"
        grep -Fq "attempt 1 of 2; retrying" "$diagnostic_file"
        grep -Fq "failed after 2 attempts (exit 73)" "$diagnostic_file"
        ! grep -Fq -- "$canary" "$diagnostic_file"
    done
}

@test "base_std_run immutable display survives hostile shell-function variable collisions" {
    local stderr_file="$TEST_TMPDIR/sensitive-function-collision.err"
    local primary_log="$TEST_TMPDIR/sensitive-function-collision.log"
    local canary="CANARY-dynamic-scope-display-secret"
    local collision_invocations=0 diagnostic_file rc

    hostile_display_command() {
        collision_invocations=$((collision_invocations + 1))
        printable_command="$canary"
        command_display="$canary"
        __base_bash_libs_std_run_command_display="$canary"
        timeout_seconds="$canary"
        timeout_path="$canary"
        max_attempts=99
        retry_delay=99
        quiet=1
        exit_on_failure=1
        __base_bash_libs_std_run_immutable_command_display="$canary"
        __base_bash_libs_std_run_policy_exit_on_failure=1
        __base_bash_libs_std_run_policy_quiet=1
        __base_bash_libs_std_run_policy_timeout_seconds="$canary"
        __base_bash_libs_std_run_policy_timeout_path="$canary"
        __base_bash_libs_std_run_policy_max_attempts=99
        __base_bash_libs_std_run_policy_retry_delay=99
        __base_bash_libs_std_run_attempt_number=99
        __base_bash_libs_std_run_exit_code="$canary"
        __base_bash_libs_std_run_message="$canary"
        return 124
    }

    if BASE_BASH_LIBS_PRIMARY_LOG="$primary_log" base_std_run \
        --no-exit --max-attempts 2 \
        --sensitive --safe-display "run protected shell function" -- \
        hostile_display_command "--token=$canary" 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    unset -f hostile_display_command

    [ "$rc" -eq 124 ]
    [ "$collision_invocations" -eq 2 ]
    for diagnostic_file in "$stderr_file" "$primary_log"; do
        grep -Fq "Command failed (exit 124)" "$diagnostic_file"
        grep -Fq "attempt 1 of 2; retrying" "$diagnostic_file"
        grep -Fq "failed after 2 attempts (exit 124)" "$diagnostic_file"
        grep -Fq "run protected shell function [sensitive command; arguments hidden]" "$diagnostic_file"
        ! grep -Fq -- "$canary" "$diagnostic_file"
    done
}

@test "base_std_run_or_exit protected fatal path preserves status and hides argv" {
    local command_script="$TEST_TMPDIR/sensitive-fatal-command.sh"
    local runner_script="$TEST_TMPDIR/sensitive-fatal-runner.sh"
    local primary_log="$TEST_TMPDIR/sensitive-fatal.log"
    local canary="CANARY-default-fatal-secret"

    create_script "$command_script" <<'EOF'
#!/usr/bin/env bash
exit 255
EOF
    create_script "$runner_script" <<'EOF'
#!/usr/bin/env bash
source "$1"
declare -a runner_args=()
base_init runner_args --
primary_log="$2"
command_script="$3"
canary="$4"
BASE_BASH_LIBS_PRIMARY_LOG="$primary_log"
export BASE_BASH_LIBS_PRIMARY_LOG
base_std_run_or_exit --sensitive --safe-display "publish protected release" -- \
    "$command_script" "value with $canary" "--token=$canary"
printf 'after\n'
EOF

    bats_run bash "$runner_script" "$STDLIB_PATH" "$primary_log" "$command_script" "$canary"

    [ "$status" -eq 255 ]
    [[ "$output" == *"Command failed (exit 255)"* ]]
    [[ "$output" == *"publish protected release [sensitive command; arguments hidden]"* ]]
    [[ "$output" == *"Encountered a fatal error"* ]]
    [[ "$output" != *"$canary"* ]]
    [[ "$output" != *"after"* ]]
    grep -Fq "Command failed (exit 255)" "$primary_log"
    grep -Fq "publish protected release [sensitive command; arguments hidden]" "$primary_log"
    ! grep -Fq -- "$canary" "$primary_log"
}

@test "base_std_run sensitive timeout retains status and timing without exposing arguments" {
    local script="$TEST_TMPDIR/sensitive-timeout.sh"
    local stderr_file="$TEST_TMPDIR/sensitive-timeout.err"
    local primary_log="$TEST_TMPDIR/sensitive-timeout.log"
    local canary="CANARY-timeout-secret"
    local diagnostic_file rc

    create_script "$script" <<'EOF'
#!/usr/bin/env bash
sleep 3
EOF

    if BASE_BASH_LIBS_PRIMARY_LOG="$primary_log" base_std_run \
        --no-exit --timeout 1 \
        --sensitive --safe-display "wait for protected service" -- \
        "$script" "value with $canary" "https://user:$canary@example.test" 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 124 ]
    for diagnostic_file in "$stderr_file" "$primary_log"; do
        grep -Fq "Command timed out after 1s" "$diagnostic_file"
        grep -Fq "wait for protected service [sensitive command; arguments hidden]" "$diagnostic_file"
        ! grep -Fq -- "$canary" "$diagnostic_file"
    done
}

@test "base_std_run combines per-attempt timeout with retry" {
    local counter_file="$TEST_TMPDIR/timeout-retry-count.txt"
    local output_file="$TEST_TMPDIR/timeout-retry-output.txt"
    local script="$TEST_TMPDIR/timeout-retry.sh"

    create_script "$script" <<'EOF'
#!/usr/bin/env bash
count=0
[[ -f "$1" ]] && count="$(cat "$1")"
count=$((count + 1))
printf '%s\n' "$count" > "$1"
if ((count == 1)); then
    sleep 2
else
    printf 'ok\n' > "$2"
fi
EOF

    base_std_run --no-exit --quiet --timeout 1 --max-attempts 2 bash "$script" "$counter_file" "$output_file"

    [ "$?" -eq 0 ]
    [ "$(cat "$counter_file")" = "2" ]
    [ "$(cat "$output_file")" = "ok" ]
}

@test "base_std_run discovers timeout binary once across retries" {
    local fake_bin="$TEST_TMPDIR/timeout-bin"
    local lookup_file="$TEST_TMPDIR/timeout-lookups.txt"
    local counter_file="$TEST_TMPDIR/timeout-discovery-count.txt"
    local script="$TEST_TMPDIR/timeout-discovery-command.sh"
    local rc
    local -a lookups=()

    mkdir -p "$fake_bin"
    create_script "$fake_bin/timeout" <<'EOF'
#!/usr/bin/env bash
if [[ "${1-}" == --version ]]; then
    printf 'timeout (GNU coreutils) 9.5\n'
    exit 0
fi
[[ "${1-}" == --foreground && "${2-}" == --signal=KILL ]] || exit 125
shift 3
"$@"
EOF
    create_script "$script" <<'EOF'
#!/usr/bin/env bash
count=0
[[ -f "$1" ]] && count="$(cat "$1")"
count=$((count + 1))
printf '%s\n' "$count" > "$1"
((count >= 3))
EOF

    eval "$(declare -f base_std_command_path | sed '1s/base_std_command_path/__orig_std_command_path/')"
    base_std_command_path() {
        if [[ "${2-}" == "timeout" || "${2-}" == "gtimeout" ]]; then
            printf '%s\n' "$2" >> "$lookup_file"
        fi
        __orig_std_command_path "$@"
    }

    PATH="$fake_bin:$PATH" base_std_run --no-exit --quiet --timeout 5 --max-attempts 3 /bin/bash "$script" "$counter_file"
    rc=$?
    unset -f base_std_command_path __orig_std_command_path

    [ "$rc" -eq 0 ]
    mapfile -t lookups < "$lookup_file"
    [ "${#lookups[@]}" -eq 1 ]
    [ "${lookups[0]}" = "timeout" ]
    [ "$(cat "$counter_file")" = "3" ]
}

@test "base_std_run capability detection prefers verified GNU gtimeout after rejecting another timeout" {
    local fake_bin="$TEST_TMPDIR/timeout-capability-bin"
    local detected=""

    mkdir -p "$fake_bin"
    create_script "$fake_bin/timeout" <<'EOF'
#!/bin/bash
printf 'timeout (BusyBox) 1.36.0\n'
EOF
    create_script "$fake_bin/gtimeout" <<'EOF'
#!/bin/bash
if [[ "${1-}" == --version ]]; then
    printf 'timeout (GNU coreutils) 9.5\n'
    exit 0
fi
exit 125
EOF

    PATH="$fake_bin" __base_bash_libs_std_timeout_backend_detect__ detected

    [ "$detected" = "$fake_bin/gtimeout" ]
}

@test "base_std_run capability detection falls back to Bash when timeout tools are unavailable" {
    local fake_bin="$TEST_TMPDIR/no-timeout-tools"
    local detected="sentinel"

    mkdir -p "$fake_bin"
    PATH="$fake_bin" __base_bash_libs_std_timeout_backend_detect__ detected

    [ -z "$detected" ]
}

@test "base_std_run reports external timeout-clock failures as infrastructure without retrying" {
    local fake_bin="$TEST_TMPDIR/broken-timeout-clock"
    local counter_file="$TEST_TMPDIR/broken-timeout-counter"
    local stderr_file="$TEST_TMPDIR/broken-timeout.err"
    local rc

    mkdir -p "$fake_bin"
    create_script "$fake_bin/timeout" <<'EOF'
#!/bin/bash
if [[ "${1-}" == --version ]]; then
    printf 'timeout (GNU coreutils) 9.5\n'
    exit 0
fi
exit 7
EOF
    create_script "$TEST_TMPDIR/should-not-run.sh" <<'EOF'
#!/usr/bin/env bash
count=0
[[ -f "$1" ]] && count="$(cat "$1")"
printf '%s\n' "$((count + 1))" > "$1"
/bin/sleep 3
EOF
    ln -s "$(command -v mktemp)" "$fake_bin/mktemp"
    ln -s "$(command -v rm)" "$fake_bin/rm"

    if PATH="$fake_bin" base_std_run --no-exit --max-attempts 3 --timeout 1 \
        /bin/bash "$TEST_TMPDIR/should-not-run.sh" "$counter_file" \
        2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 125 ]
    [ "$(cat "$counter_file")" = "1" ]
    [[ "$(cat "$stderr_file")" == *"could not be supervised safely"* ]]
    [[ "$(cat "$stderr_file")" != *"attempt 1 of 3; retrying"* ]]
}

@test "base_std_run external GNU clock still keeps TERM-KILL ownership in the framework" {
    local fake_bin="$TEST_TMPDIR/working-timeout-clock"
    local marker_file="$TEST_TMPDIR/external-clock.marker"
    local observation_file="$TEST_TMPDIR/external-clock.argv"
    local stderr_file="$TEST_TMPDIR/external-clock.err"
    local rc

    mkdir -p "$fake_bin"
    create_script "$fake_bin/timeout" <<'EOF'
#!/bin/bash
if [[ "${1-}" == --version ]]; then
    printf 'timeout (GNU coreutils) 9.5\n'
    exit 0
fi
[[ "${1-}" == --foreground && "${2-}" == --signal=KILL ]] || exit 125
printf '%s\n' "${*:4}" > "$BASE_TEST_TIMEOUT_CLOCK_ARGS"
duration="${3%s}"
shift 3
if IFS= read -r -n 1 -t "$duration" byte; then
    "$@"
else
    exit 124
fi
EOF
    create_script "$TEST_TMPDIR/external-clock-command.sh" <<EOF
#!/usr/bin/env bash
trap '' TERM
/bin/sleep 3
printf 'completed\n' > "$marker_file"
EOF

    if BASE_TEST_TIMEOUT_CLOCK_ARGS="$observation_file" \
        PATH="$fake_bin:$BASE_TEST_ORIG_PATH" \
        base_std_run --no-exit --quiet --timeout 1 \
        /bin/bash "$TEST_TMPDIR/external-clock-command.sh" \
        2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 124 ]
    [ ! -e "$marker_file" ]
    [ ! -s "$stderr_file" ]
    grep -Fq '/bin/dd' "$observation_file"
    ! grep -Fq 'external-clock-command' "$observation_file"
}

@test "base_std_run timeout returns infrastructure status when control-channel setup fails" {
    local fake_bin="$TEST_TMPDIR/no-timeout-bin"
    local stderr_file="$TEST_TMPDIR/timeout-marker-failure.err"
    local rc

    mkdir -p "$fake_bin"

    eval "$(declare -f __base_bash_libs_std_make_internal_temp_file__ | sed '1s/__base_bash_libs_std_make_internal_temp_file__/__orig_std_make_internal_temp_file__/')"
    __base_bash_libs_std_make_internal_temp_file__() {
        return 1
    }

    if PATH="$fake_bin" base_std_run --no-exit --quiet --timeout 5 /bin/echo fallback 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    unset -f __base_bash_libs_std_make_internal_temp_file__ __orig_std_make_internal_temp_file__

    [ "$rc" -eq 125 ]
}

@test "base_std_run timeout control channels are canceled after fast completion" {
    local fake_bin="$TEST_TMPDIR/no-timeout-bin"
    local output_file="$TEST_TMPDIR/timeout-kill-output.txt"
    local rc

    mkdir -p "$fake_bin"
    ln -s "$(command -v mktemp)" "$fake_bin/mktemp"
    ln -s "$(command -v rm)" "$fake_bin/rm"
    ln -s "$(command -v sleep)" "$fake_bin/sleep"

    PATH="$fake_bin" base_std_run --no-exit --quiet --timeout 5 /bin/echo fallback > "$output_file"
    rc=$?

    [ "$rc" -eq 0 ]
    [ "$(cat "$output_file")" = "fallback" ]
    ! compgen -G "$TEST_TMPDIR/base-bash-libs-timeout-clock.*" >/dev/null
    ! compgen -G "$TEST_TMPDIR/base-bash-libs-timeout-status.*" >/dev/null
}

@test "base_std_run rejects invalid execution policy options" {
    local stderr_file="$TEST_TMPDIR/run-policy-invalid.err"
    local rc

    if base_std_run --timeout 0 true 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [[ "$(cat "$stderr_file")" == *"base_std_run: timeout seconds must be a positive integer."* ]]

    : > "$stderr_file"
    if base_std_run --max-attempts 0 true 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [[ "$(cat "$stderr_file")" == *"base_std_run: max attempts must be a positive integer."* ]]

    : > "$stderr_file"
    if base_std_run --retry-delay nope true 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [[ "$(cat "$stderr_file")" == *"base_std_run: retry delay seconds must be a non-negative integer."* ]]
}

@test "base_std_run dry-run reports timeout and retry policy without executing" {
    local target="$TEST_TMPDIR/dry-run-policy.txt"
    local stderr_file="$TEST_TMPDIR/dry-run-policy.err"

    BASE_BASH_LIBS_DRY_RUN=true

    base_std_run --timeout 30 --max-attempts 3 --retry-delay 2 touch "$target" 2>"$stderr_file"

    [ "$?" -eq 0 ]
    [ ! -e "$target" ]
    [[ "$(cat "$stderr_file")" == *"30s timeout"* ]]
    [[ "$(cat "$stderr_file")" == *"3 attempts"* ]]
    [[ "$(cat "$stderr_file")" == *"2s retry delay"* ]]
}

@test "base_std_run dry-run stays visible with quiet and disabled INFO while stdout stays clean" {
    local stdout_file="$TEST_TMPDIR/dry-run-always-visible.out"
    local stderr_file="$TEST_TMPDIR/dry-run-always-visible.err"
    local primary_log="$TEST_TMPDIR/dry-run-always-visible.log"

    base_std_set_log_level FATAL
    base_std_set_log_category_level -l base_bash_libs FATAL
    BASE_BASH_LIBS_DRY_RUN=1 BASE_BASH_LIBS_PRIMARY_LOG="$primary_log" \
        base_std_run --no-exit --quiet --timeout 5 printf '%s\n' 'planned value' \
        >"$stdout_file" 2>"$stderr_file"

    [ ! -s "$stdout_file" ]
    [ "$(grep -c 'DRY-RUN' "$stderr_file")" -eq 1 ]
    grep -Fq 'planned\ value' "$stderr_file"
    grep -Fq '5s timeout' "$stderr_file"
    [ "$(grep -c 'DRY-RUN' "$primary_log")" -eq 1 ]
}

@test "base_std_safe_mkdir creates directories and tolerates existing paths with -p" {
    local first="$TEST_TMPDIR/a"
    local second="$TEST_TMPDIR/b/c"

    base_std_safe_mkdir "$first"
    base_std_safe_mkdir -p "$second"
    base_std_safe_mkdir -p "$second"

    [ -d "$first" ]
    [ -d "$second" ]
}

@test "base_std_safe_mkdir preserves caller OPTIND" {
    local directory="$TEST_TMPDIR/optind-directory"
    local OPTIND=11

    base_std_safe_mkdir "$directory"

    [ "$OPTIND" -eq 11 ]
    [ -d "$directory" ]
}

@test "base_std_safe_mkdir warns when no directories are provided" {
    local stderr_file="$TEST_TMPDIR/safe-mkdir-empty.err"

    base_std_safe_mkdir 2>"$stderr_file"

    [[ "$(cat "$stderr_file")" == *"base_std_safe_mkdir: No directories provided to create."* ]]
}

@test "base_std_safe_mkdir rejects invalid options" {
    local stderr_file="$TEST_TMPDIR/safe-mkdir-option.err"
    local rc

    if (cd "$TEST_TMPDIR" && base_std_safe_mkdir -z 2>"$stderr_file"); then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 1 ]
    [[ "$(cat "$stderr_file")" == *"base_std_safe_mkdir: invalid option '-z'"* ]]
    [ ! -e "$TEST_TMPDIR/-z" ]
}

@test "base_std_safe_mkdir returns when directory creation fails" {
    local script="$TEST_TMPDIR/safe-mkdir-fail.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_safe_mkdir /dev/null/blocked
printf 'after=%s\n' "\$?"
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Failed to create directories"* ]]
    [[ "$output" == *"after=1"* ]]
}

@test "base_std_safe_touch creates files" {
    local target="$TEST_TMPDIR/touched.txt"

    base_std_safe_touch "$target"

    [ -f "$target" ]
}

@test "base_std_safe_touch treats option-like paths literally" {
    local target="$TEST_TMPDIR/-r"

    (cd "$TEST_TMPDIR" && base_std_safe_touch "-r")

    [ -f "$target" ]
}

@test "base_std_safe_touch warns when no files are provided" {
    local stderr_file="$TEST_TMPDIR/safe-touch.err"

    base_std_safe_touch 2>"$stderr_file"

    [ "$?" -eq 0 ]
    [[ "$(cat "$stderr_file")" == *"base_std_safe_touch: No files provided to touch."* ]]
}

@test "base_std_safe_touch returns when a file cannot be touched" {
    local script="$TEST_TMPDIR/safe-touch-fail.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_safe_touch /dev/null/blocked
printf 'after=%s\n' "\$?"
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Failed to touch the following files"* ]]
    [[ "$output" == *"after=1"* ]]
}

@test "base_std_safe_truncate truncates files to zero bytes" {
    local target="$TEST_TMPDIR/truncate.txt"

    printf 'content\n' > "$target"
    base_std_safe_truncate "$target"

    [ ! -s "$target" ]
}

@test "base_std_safe_truncate warns when no files are provided" {
    local stderr_file="$TEST_TMPDIR/safe-truncate.err"

    base_std_safe_truncate 2>"$stderr_file"

    [ "$?" -eq 0 ]
    [[ "$(cat "$stderr_file")" == *"base_std_safe_truncate: No files provided to truncate."* ]]
}

@test "base_std_safe_truncate returns when a file cannot be truncated" {
    local script="$TEST_TMPDIR/safe-truncate-fail.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_safe_truncate /dev/null/blocked
printf 'after=%s\n' "\$?"
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Failed to truncate the following files"* ]]
    [[ "$output" == *"after=1"* ]]
}

@test "cleanup hooks run on exit without replacing an existing EXIT trap" {
    local script="$TEST_TMPDIR/cleanup-hooks.sh"
    local log_file="$TEST_TMPDIR/cleanup-hooks.log"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
trap 'printf "existing\n" >> "$log_file"' EXIT
cleanup_one() { printf "cleanup-one\n" >> "$log_file"; }
cleanup_two() { printf "cleanup-two\n" >> "$log_file"; }
base_std_register_cleanup_hook cleanup_one
base_std_register_cleanup_hook cleanup_two
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [ "$(cat "$log_file")" = $'existing\ncleanup-two\ncleanup-one' ]
}

@test "cleanup hooks preserve multi-line existing EXIT traps" {
    local script="$TEST_TMPDIR/cleanup-multiline-trap.sh"
    local log_file="$TEST_TMPDIR/cleanup-multiline-trap.log"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
trap '
printf "existing-one\n" >> "$log_file"
printf "existing-two\n" >> "$log_file"
' EXIT
cleanup_one() { printf "cleanup-one\n" >> "$log_file"; }
base_std_register_cleanup_hook cleanup_one
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [ "$(cat "$log_file")" = $'existing-one\nexisting-two\ncleanup-one' ]
}

@test "cleanup hooks still run when the existing EXIT trap exits" {
    local script="$TEST_TMPDIR/cleanup-exit-trap.sh"
    local log_file="$TEST_TMPDIR/cleanup-exit-trap.log"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
trap 'exit 9' EXIT
cleanup_one() { printf "cleanup-one\\n" >> "$log_file"; }
base_std_register_cleanup_hook cleanup_one
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [ "$(cat "$log_file")" = "cleanup-one" ]
}

@test "cleanup hooks still run when the existing EXIT trap returns" {
    local script="$TEST_TMPDIR/cleanup-return-trap.sh"
    local log_file="$TEST_TMPDIR/cleanup-return-trap.log"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
trap 'return 9' EXIT
cleanup_one() { printf "cleanup-one\\n" >> "$log_file"; }
base_std_register_cleanup_hook cleanup_one
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [ "$(cat "$log_file")" = "cleanup-one" ]
}

@test "cleanup hook registration ignores duplicates and supports removal" {
    local script="$TEST_TMPDIR/cleanup-hook-remove.sh"
    local log_file="$TEST_TMPDIR/cleanup-hook-remove.log"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
cleanup_keep() { printf "keep\n" >> "$log_file"; }
cleanup_drop() { printf "drop\n" >> "$log_file"; }
base_std_register_cleanup_hook cleanup_keep
base_std_register_cleanup_hook cleanup_keep
base_std_register_cleanup_hook cleanup_drop
base_std_unregister_cleanup_hook cleanup_drop
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [ "$(cat "$log_file")" = "keep" ]
}

@test "removing the final cleanup registration restores the caller EXIT trap" {
    local script="$TEST_TMPDIR/cleanup-restore-trap.sh"
    local log_file="$TEST_TMPDIR/cleanup-restore-trap.log"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
trap 'printf "caller\n" >> "$log_file"' EXIT
before_trap="\$(trap -p EXIT)"
cleanup_transient() { printf 'unexpected\n' >> "$log_file"; }
base_std_register_cleanup_hook cleanup_transient
dispatcher_trap="\$(trap -p EXIT)"
[[ "\$dispatcher_trap" != "\$before_trap" ]]
base_std_unregister_cleanup_hook cleanup_transient
after_trap="\$(trap -p EXIT)"
[[ "\$after_trap" == "\$before_trap" ]]
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [ "$(cat "$log_file")" = "caller" ]
}

@test "cleanup unregistration restores a caller-replaced EXIT trap" {
    local script="$TEST_TMPDIR/cleanup-caller-replaced-trap.sh"
    local log_file="$TEST_TMPDIR/cleanup-caller-replaced-trap.log"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
trap 'printf "original\n" >> "$log_file"' EXIT
cleanup_transient() { printf 'unexpected\n' >> "$log_file"; }
base_std_register_cleanup_hook cleanup_transient
trap 'printf "replacement\n" >> "$log_file"' EXIT
    base_std_unregister_cleanup_hook cleanup_transient
    after_trap="\$(trap -p EXIT)"
    [[ "\$after_trap" == *"replacement"* ]]
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [ "$(cat "$log_file")" = "replacement" ]
}

@test "cleanup path registration removes files and directories on exit" {
    local script="$TEST_TMPDIR/cleanup-paths.sh"
    local target_file="$TEST_TMPDIR/cleanup-file.txt"
    local target_dir="$TEST_TMPDIR/cleanup-dir"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
mkdir -p "$target_dir"
printf 'sample\n' > "$target_file"
printf 'nested\n' > "$target_dir/nested.txt"
base_std_register_cleanup_path "$target_file" "$target_dir"
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [ ! -e "$target_file" ]
    [ ! -e "$target_dir" ]
}

@test "duplicate cleanup path registration is idempotent" {
    local script="$TEST_TMPDIR/cleanup-path-duplicate.sh"
    local target="$TEST_TMPDIR/cleanup-path-duplicate-target"

    printf 'temporary\n' > "$target"
    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_register_cleanup_path "$target"
base_std_register_cleanup_path "$target"
[[ \${#__base_bash_libs_std_cleanup_paths[@]} -eq 1 ]] || exit 44
[[ \${#__base_bash_libs_std_cleanup_entries[@]} -eq 1 ]] || exit 45
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [ ! -e "$target" ]
}

@test "cleanup path registration rejects dangerous paths" {
    local stderr_file="$TEST_TMPDIR/cleanup-path.err"
    local rc

    if base_std_register_cleanup_path "" "/" 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 1 ]
    [[ "$(cat "$stderr_file")" == *"base_std_register_cleanup_path: refusing to register unsafe cleanup path"* ]]
}

@test "cleanup path registration rejects relative paths" {
    local script="$TEST_TMPDIR/cleanup-relative.sh"
    local stderr_file="$TEST_TMPDIR/cleanup-relative.err"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_register_cleanup_path "relative-path" 2>"$stderr_file"
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$(cat "$stderr_file")" == *"base_std_register_cleanup_path: refusing to register unsafe cleanup path 'relative-path'."* ]]
}

@test "cleanup path registration keeps valid paths from mixed batches" {
    local target_file="$TEST_TMPDIR/cleanup-valid-file.txt"
    local target_dir="$TEST_TMPDIR/cleanup-valid-dir"
    local stderr_file="$TEST_TMPDIR/cleanup-mixed.err"
    local rc=0

    printf 'sample\n' > "$target_file"
    mkdir -p "$target_dir"

    base_std_register_cleanup_path "$target_file" "/" "$target_dir" 2>"$stderr_file" || rc=$?

    [ "$rc" -eq 1 ]
    [[ "$(cat "$stderr_file")" == *"base_std_register_cleanup_path: refusing to register unsafe cleanup path '/'"* ]]
    [[ " ${__base_bash_libs_std_cleanup_paths[*]} " == *" $target_file "* ]]
    [[ " ${__base_bash_libs_std_cleanup_paths[*]} " == *" $target_dir "* ]]
    [[ " ${__base_bash_libs_std_cleanup_paths[*]} " != *" / "* ]]
}

@test "cleanup path registration supports unregistering eager cleanup paths" {
    local keep_file="$TEST_TMPDIR/cleanup-keep-file.txt"
    local drop_file="$TEST_TMPDIR/cleanup-drop-file.txt"

    printf 'keep\n' > "$keep_file"
    printf 'drop\n' > "$drop_file"

    base_std_register_cleanup_path "$keep_file" "$drop_file"
    rm -f -- "$drop_file"
    base_std_unregister_cleanup_path "$drop_file"

    [[ " ${__base_bash_libs_std_cleanup_paths[*]} " == *" $keep_file "* ]]
    [[ " ${__base_bash_libs_std_cleanup_paths[*]} " != *" $drop_file "* ]]
}

@test "cleanup path unregister rejects dangerous paths without clearing valid registrations" {
    local target_file="$TEST_TMPDIR/cleanup-unregister-valid-file.txt"
    local stderr_file="$TEST_TMPDIR/cleanup-unregister-mixed.err"
    local rc=0

    printf 'sample\n' > "$target_file"
    base_std_register_cleanup_path "$target_file"

    base_std_unregister_cleanup_path "/" 2>"$stderr_file" || rc=$?

    [ "$rc" -eq 1 ]
    [[ "$(cat "$stderr_file")" == *"base_std_unregister_cleanup_path: refusing to unregister unsafe cleanup path '/'"* ]]
    [[ " ${__base_bash_libs_std_cleanup_paths[*]} " == *" $target_file "* ]]
}

@test "cleanup registrations run hooks in LIFO order" {
    local script="$TEST_TMPDIR/cleanup-lifo.sh"
    local log_file="$TEST_TMPDIR/cleanup-lifo.log"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
cleanup_outer() { printf 'outer\\n' >> "$log_file"; }
cleanup_inner() { printf 'inner\\n' >> "$log_file"; }
base_std_register_cleanup_hook cleanup_outer
base_std_register_cleanup_hook cleanup_inner
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [ "$(cat "$log_file")" = $'inner\nouter' ]
}

@test "cleanup unwinds nested path and hook resources in one LIFO stack" {
    local script="$TEST_TMPDIR/cleanup-nested.sh"
    local resource="$TEST_TMPDIR/cleanup-nested-resource"

    mkdir -p "$resource"
    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_register_cleanup_path "$resource"
cleanup_child() { printf 'child\\n' > "$resource/child-marker"; }
base_std_register_cleanup_hook cleanup_child
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [ ! -e "$resource" ]
}

@test "cleanup refuses a symlink swap after registration" {
    local script="$TEST_TMPDIR/cleanup-symlink-swap.sh"
    local root="$TEST_TMPDIR/symlink-swap-root"
    local registered="$root/registered"
    local moved="$root/moved"
    local victim="$root/victim"

    mkdir -p "$registered" "$victim"
    printf 'must-survive\n' > "$victim/important.txt"
    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_register_cleanup_path "$registered"
mv "$registered" "$moved"
ln -s "$victim" "$registered"
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [ -L "$registered" ]
    [ -d "$moved" ]
    [ -f "$victim/important.txt" ]
    [[ "$output" == *"changed identity; refusing to remove it"* ]]
}

@test "cleanup refuses a renamed-parent substitution after registration" {
    local script="$TEST_TMPDIR/cleanup-renamed-parent.sh"
    local root="$TEST_TMPDIR/renamed-parent-root"
    local parent="$root/parent"
    local moved_parent="$root/moved-parent"
    local replacement="$root/replacement"
    local target="$parent/target"

    mkdir -p "$target" "$replacement/target"
    printf 'must-survive\n' > "$replacement/target/important.txt"
    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_register_cleanup_path "$target"
mv "$parent" "$moved_parent"
mkdir -p "$parent"
mv "$replacement/target" "$parent/target"
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [ -d "$moved_parent/target" ]
    [ -f "$parent/target/important.txt" ]
    [[ "$output" == *"changed identity; refusing to remove it"* ]]
}

@test "later caller EXIT traps compose with cleanup and preserve primary status" {
    local script="$TEST_TMPDIR/cleanup-later-exit.sh"
    local target="$TEST_TMPDIR/cleanup-later-exit-target"
    local log_file="$TEST_TMPDIR/cleanup-later-exit.log"

    printf 'temporary\n' > "$target"
    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_register_cleanup_path "$target"
trap 'printf "caller\\n" >> "$log_file"' EXIT
exit 23
EOF

    bats_run bash "$script"

    [ "$status" -eq 23 ]
    [ "$(cat "$log_file")" = "caller" ]
    [ ! -e "$target" ]
}

@test "caller DEBUG traps compose before and after cleanup registration" {
    local script="$TEST_TMPDIR/cleanup-debug-trap.sh"
    local log_file="$TEST_TMPDIR/cleanup-debug-trap.log"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
trap 'printf "before-debug\\n" >> "$log_file"' DEBUG
cleanup_once() { printf 'cleanup\\n' >> "$log_file"; }
base_std_register_cleanup_hook cleanup_once
trap 'printf "after-debug\\n" >> "$log_file"' DEBUG
:
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [ "$(grep -c '^before-debug$' "$log_file")" -ge 1 ]
    [ "$(tail -n 1 "$log_file")" = "cleanup" ]
    [ "$(grep -c '^after-debug$' "$log_file")" -ge 1 ]
}

@test "signals compose with caller traps and cleanup exactly once" {
    local script="$TEST_TMPDIR/cleanup-signal.sh"
    local target="$TEST_TMPDIR/cleanup-signal-target"
    local log_file="$TEST_TMPDIR/cleanup-signal.log"

    printf 'temporary\n' > "$target"
    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
trap 'printf "caller-term\\n" >> "$log_file"' TERM
cleanup_once() { printf 'cleanup\\n' >> "$log_file"; }
base_std_register_cleanup_path "$target"
base_std_register_cleanup_hook cleanup_once
kill -TERM "\$\$"
EOF

    bats_run bash "$script"

    [ "$status" -eq 143 ]
    [ "$(cat "$log_file")" = $'caller-term\ncleanup' ]
    [ ! -e "$target" ]
}

@test "later caller TERM traps compose with cleanup" {
    local script="$TEST_TMPDIR/cleanup-later-term.sh"
    local target="$TEST_TMPDIR/cleanup-later-term-target"
    local log_file="$TEST_TMPDIR/cleanup-later-term.log"

    printf 'temporary\n' > "$target"
    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_register_cleanup_path "$target"
trap 'printf "later-term\\n" >> "$log_file"' TERM
kill -TERM "\$\$"
EOF

    bats_run bash "$script"

    [ "$status" -eq 143 ]
    [ "$(cat "$log_file")" = "later-term" ]
    [ ! -e "$target" ]
}

@test "a signal arriving during cleanup is latched without rerunning resources" {
    local script="$TEST_TMPDIR/cleanup-concurrent-signal.sh"
    local log_file="$TEST_TMPDIR/cleanup-concurrent-signal.log"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
cleanup_first() {
    (sleep 0.05; kill -TERM "\$\$") &
    local signal_pid=\$!
    sleep 0.15
    wait "\$signal_pid"
    printf 'first\\n' >> "$log_file"
}
cleanup_second() { printf 'second\\n' >> "$log_file"; }
base_std_register_cleanup_hook cleanup_first
base_std_register_cleanup_hook cleanup_second
EOF

    bats_run bash "$script"

    [ "$status" -eq 143 ]
    [ "$(cat "$log_file")" = $'second\nfirst' ]
}

@test "cleanup keeps the primary status when a cleanup hook fails" {
    local script="$TEST_TMPDIR/cleanup-secondary-failure.sh"
    local log_file="$TEST_TMPDIR/cleanup-secondary-failure.log"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
cleanup_fails() { printf 'failed-hook\\n' >> "$log_file"; return 9; }
cleanup_runs() { printf 'next-hook\\n' >> "$log_file"; }
base_std_register_cleanup_hook cleanup_fails
base_std_register_cleanup_hook cleanup_runs
exit 37
EOF

    bats_run bash "$script"

    [ "$status" -eq 37 ]
    [ "$(cat "$log_file")" = $'next-hook\nfailed-hook' ]
}

@test "unsafe cleanup opt-in is explicit and still rejects protected roots" {
    local script="$TEST_TMPDIR/cleanup-unsafe.sh"
    local link="$TEST_TMPDIR/cleanup-unsafe-link"
    local target="$TEST_TMPDIR/cleanup-unsafe-target"
    local stderr_file="$TEST_TMPDIR/cleanup-unsafe.err"
    local rc=0

    mkdir -p "$target"
    ln -s "$target" "$link"
    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_register_cleanup_path --unsafe "$link"
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [ ! -e "$link" ]
    [ -d "$target" ]

    base_std_register_cleanup_path --unsafe /tmp 2>"$stderr_file" || rc=$?
    [ "$rc" -eq 1 ]
    [[ "$(cat "$stderr_file")" == *"broad or protected path"* ]]

    rc=0
    base_std_register_cleanup_path --unsafe "$HOME" /usr 2>"$stderr_file" || rc=$?
    [ "$rc" -eq 1 ]
}

@test "base_std_make_temp_file creates a file under TMPDIR and cleans it up" {
    local script="$TEST_TMPDIR/temp-file.sh"
    local temp_root="$TEST_TMPDIR/temp-root"
    local path_file="$TEST_TMPDIR/temp-file.path"
    local created_path

    mkdir -p "$temp_root"
    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
TMPDIR="$temp_root"
base_std_make_temp_file temp_file sample
[[ -f "\$temp_file" ]] || exit 44
printf '%s\n' "\$temp_file" > "$path_file"
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    created_path="$(cat "$path_file")"
    [[ "$created_path" == "$temp_root"/sample.* ]]
    [ ! -e "$created_path" ]
}

@test "base_std_make_temp_file accepts TMPDIR=/" {
    local script="$TEST_TMPDIR/temp-file-root.sh"
    local path_file="$TEST_TMPDIR/temp-file-root.path"
    local created_path

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
TMPDIR=/
mktemp() {
    [[ "\$1" == "/root-temp.XXXXXXXXXX" ]] || return 44
    : > "$TEST_TMPDIR/root-temp-file"
    printf '%s\n' "$TEST_TMPDIR/root-temp-file"
}
base_std_make_temp_file temp_file root-temp
[[ -f "\$temp_file" ]] || exit 44
printf '%s\n' "\$temp_file" > "$path_file"
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    created_path="$(cat "$path_file")"
    [ "$created_path" = "$TEST_TMPDIR/root-temp-file" ]
    [ ! -e "$created_path" ]
}

@test "base_std_make_temp_file resolves relative and trailing-slash TMPDIR values" {
    local script="$TEST_TMPDIR/temp-file-relative.sh"
    local temp_root="$TEST_TMPDIR/temp-relative-root"
    local path_file="$TEST_TMPDIR/temp-file-relative.path"
    local created_path expected_root

    mkdir -p "$temp_root"
    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
cd "$TEST_TMPDIR"
TMPDIR="$(basename "$temp_root")///"
base_std_make_temp_file temp_file relative-temp
[[ -f "\$temp_file" ]] || exit 44
printf '%s\n' "\$temp_file" > "$path_file"
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    created_path="$(cat "$path_file")"
    expected_root="$(cd "$temp_root" && pwd -P)"
    [[ "$created_path" == "$expected_root"/relative-temp.* ]]
    [ ! -e "$created_path" ]
}

@test "base_std_make_temp_dir creates a directory under TMPDIR and cleans it up" {
    local script="$TEST_TMPDIR/temp-dir.sh"
    local temp_root="$TEST_TMPDIR/temp-dir-root"
    local path_file="$TEST_TMPDIR/temp-dir.path"
    local created_path

    mkdir -p "$temp_root"
    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
TMPDIR="$temp_root"
base_std_make_temp_dir temp_dir workspace
[[ -d "\$temp_dir" ]] || exit 44
printf '%s\n' "\$temp_dir" > "$path_file"
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    created_path="$(cat "$path_file")"
    [[ "$created_path" == "$temp_root"/workspace.* ]]
    [ ! -e "$created_path" ]
}

@test "private temp dir helper supports reserved output without public-name collision" {
    local temp_root="$TEST_TMPDIR/private-temp-dir-root"
    local -r gh_api_capture_workspace="caller-owned-readonly"
    local __base_bash_libs_gh_api_capture_workspace=""

    mkdir -p "$temp_root"
    TMPDIR="$temp_root" __base_bash_libs_std_make_internal_temp_dir__ --keep \
        __base_bash_libs_gh_api_capture_workspace private-workspace

    [ "$gh_api_capture_workspace" = "caller-owned-readonly" ]
    [[ "$__base_bash_libs_gh_api_capture_workspace" == "$temp_root"/private-workspace.* ]]
    [ -d "$__base_bash_libs_gh_api_capture_workspace" ]
    rmdir -- "$__base_bash_libs_gh_api_capture_workspace"
}

@test "base_std_make_temp_file --keep leaves the created file in place" {
    local script="$TEST_TMPDIR/temp-file-keep.sh"
    local temp_root="$TEST_TMPDIR/temp-keep-root"
    local path_file="$TEST_TMPDIR/temp-file-keep.path"
    local created_path

    mkdir -p "$temp_root"
    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
TMPDIR="$temp_root"
base_std_make_temp_file --keep temp_file kept
printf '%s\n' "\$temp_file" > "$path_file"
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    created_path="$(cat "$path_file")"
    [[ "$created_path" == "$temp_root"/kept.* ]]
    [ -f "$created_path" ]
}

@test "std_make_temp helpers support shadowing-prone output variable names" {
    local temp_root="$TEST_TMPDIR/temp-shadow-root"
    local temp_path=""
    local result_name=""

    mkdir -p "$temp_root"
    TMPDIR="$temp_root" base_std_make_temp_file --keep temp_path shadow-file
    TMPDIR="$temp_root" base_std_make_temp_dir --keep result_name shadow-dir

    [[ "$temp_path" == "$temp_root"/shadow-file.* ]]
    [ -f "$temp_path" ]
    [[ "$result_name" == "$temp_root"/shadow-dir.* ]]
    [ -d "$result_name" ]
}

@test "std_make_temp helpers reject invalid result variable names" {
    local stderr_file="$TEST_TMPDIR/temp-invalid.err"
    local rc

    if base_std_make_temp_file "not-valid" 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 1 ]
    [[ "$(cat "$stderr_file")" == *"base_std_make_temp_file: result variable name must be a valid Bash variable name."* ]]

    if base_std_make_temp_dir "also-not-valid" 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 1 ]
    [[ "$(cat "$stderr_file")" == *"base_std_make_temp_dir: result variable name must be a valid Bash variable name."* ]]
}

@test "named output helpers reject readonly variables before side effects" {
    local output="unchanged"
    local temp_root="$TEST_TMPDIR/readonly-output"
    local stderr_file="$TEST_TMPDIR/readonly-output.err"
    local rc

    mkdir -p "$temp_root"
    readonly output

    if base_std_command_path output bash 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "$output" = "unchanged" ]
    [[ "$(cat "$stderr_file")" == *"result variable 'output' is readonly"* ]]

    : > "$stderr_file"
    if TMPDIR="$temp_root" base_std_make_temp_file output readonly-temp 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ -z "$(find "$temp_root" -mindepth 1 -maxdepth 1 -print -quit)" ]
    [[ "$(cat "$stderr_file")" == *"result variable 'output' is readonly"* ]]
}

@test "readonly caller locals do not collide with logging diagnostics" {
    local output="unchanged"
    local stderr_file="$TEST_TMPDIR/readonly-logging-locals.err"
    local rc
    local -r logger="caller-logger" color="caller-color" message="caller-message"
    local -r source_path="caller-source"

    readonly output
    if base_std_command_path output bash 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 1 ]
    [ "$output" = "unchanged" ]
    [ "$logger" = "caller-logger" ]
    [ "$color" = "caller-color" ]
    [ "$message" = "caller-message" ]
    [ "$source_path" = "caller-source" ]
    [[ "$(cat "$stderr_file")" == *"base_std_command_path: result variable 'output' is readonly."* ]]
    [[ "$(cat "$stderr_file")" != *"readonly variable"* ]]
    [[ "$(cat "$stderr_file")" != *"local:"* ]]
}

@test "named std helpers reject exact internal holder names before locals or side effects" {
    local -r __base_bash_libs_std_command_result_name=command_target
    local -r __base_bash_libs_std_temp_result_name=temp_target
    local -r __base_bash_libs_std_source_result_name=source_target
    local command_target="keep-command" temp_target="keep-temp" source_target="keep-source"
    local temp_root="$TEST_TMPDIR/std-internal-holder"
    local stderr_file="$TEST_TMPDIR/std-internal-holder.err"
    local rc

    mkdir -p "$temp_root"
    if base_std_command_path __base_bash_libs_std_command_result_name bash 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "$command_target" = "keep-command" ]

    if TMPDIR="$temp_root" base_std_make_temp_file --keep __base_bash_libs_std_temp_result_name reserved 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "$temp_target" = "keep-temp" ]
    [ -z "$(find "$temp_root" -mindepth 1 -maxdepth 1 -print -quit)" ]

    if base_std_get_my_source_dir __base_bash_libs_std_source_result_name 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 1 ]
    [ "$source_target" = "keep-source" ]
    [[ "$(cat "$stderr_file")" == *"uses the reserved '__' internal namespace"* ]]
    [[ "$(cat "$stderr_file")" != *"readonly variable"* ]]
    [[ "$(cat "$stderr_file")" != *"local:"* ]]
}

@test "readonly result names cannot collide with validation or diagnostic locals" {
    local candidate

    for candidate in var_name var_name_re function_name output_name declaration attributes logger color message source_path; do
        bats_run "$BASH" -c '
            source "$1"
            declare -a app_args=()
            base_init app_args --
            printf -v "$2" %s unchanged
            readonly "$2"
            base_std_command_path "$2" bash
            case $? in
                1) ;;
                *) exit 99 ;;
            esac
            printf "value=%s\n" "${!2}"
            exit 1
        ' bash "$STDLIB_PATH" "$candidate"

        [ "$status" -eq 1 ]
        [[ "$output" == *"result variable '$candidate' is readonly"* ]]
        [[ "$output" == *"value=unchanged"* ]]
        [[ "$output" != *"readonly variable"* ]]
        [[ "$output" != *"local:"* ]]
    done
}

@test "base_std_command_path stores executable paths and returns nonzero for missing commands" {
    local command_path=""

    base_std_command_path command_path bash

    [ -n "$command_path" ]
    [ -x "$command_path" ]

    if base_std_command_path command_path "__base_missing_command__$RANDOM"; then
        return 1
    fi

    [ "$command_path" = "" ]
}

@test "base_std_command_path supports shadowing-prone output variable names" {
    local result_name=""
    local command_name=""
    local resolved_path=""

    base_std_command_path result_name bash
    base_std_command_path command_name bash
    base_std_command_path resolved_path bash

    [ -x "$result_name" ]
    [ -x "$command_name" ]
    [ -x "$resolved_path" ]
}

@test "base_std_command_path rejects invalid result variable names" {
    local stderr_file="$TEST_TMPDIR/command-path.err"
    local rc

    if base_std_command_path "not-valid" bash 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 1 ]
    [[ "$(cat "$stderr_file")" == *"base_std_command_path: result variable name must be a valid Bash variable name."* ]]
}

@test "base_std_function_exists checks defined Bash functions" {
    local missing_name="__missing_function__$RANDOM"

    sample_introspection_function() { return 0; }

    base_std_function_exists sample_introspection_function
    if base_std_function_exists "$missing_name"; then
        return 1
    fi
    if base_std_function_exists "not-valid"; then
        return 1
    fi
}

@test "base_std_assert_function_exists accepts defined functions and exits for missing ones" {
    local script="$TEST_TMPDIR/assert-function-exists.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
defined_function() { return 0; }
base_std_assert_function_exists defined_function missing_function
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Required functions are not defined: missing_function"* ]]
}

@test "base_std_assert_function_exists rejects invalid names without echoing values" {
    local script="$TEST_TMPDIR/assert-function-invalid.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
secret="not-valid"
base_std_assert_function_exists "\$secret"
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"base_std_assert_function_exists expects function names"* ]]
    [[ "$output" != *"not-valid"* ]]
}

@test "base_std_assert_variable_name accepts valid Bash variable names" {
    base_std_assert_variable_name value_name _value_name VALUE_NAME value_name_2 __internal_syntax_name
}

@test "named assertions reject reserved caller sources before local declarations" {
    local -ar __base_bash_libs_std_assert_indexed_name=(alpha)
    local -Ar __base_bash_libs_std_assert_associative_name=([alpha]=one)
    local -r __base_bash_libs_std_assert_not_null_name=present
    local -r __base_bash_libs_std_assert_integer_name=7
    local -r __base_bash_libs_std_range_name=5
    local stderr_file="$TEST_TMPDIR/assert-reserved-names.err"
    assert_reserved_name_rejected() {
        local assertion_status
        if "$@" 2>"$stderr_file"; then
            assertion_status=0
        else
            assertion_status=$?
        fi
        [ "$assertion_status" -eq 1 ]
        [[ "$(cat "$stderr_file")" == *"uses the reserved '__' internal namespace"* ]]
        [[ "$(cat "$stderr_file")" != *"readonly variable"* ]]
        [[ "$(cat "$stderr_file")" != *"local:"* ]]
    }

    assert_reserved_name_rejected base_std_assert_indexed_array __base_bash_libs_std_assert_indexed_name
    assert_reserved_name_rejected base_std_assert_associative_array __base_bash_libs_std_assert_associative_name
    assert_reserved_name_rejected base_std_assert_not_null __base_bash_libs_std_assert_not_null_name
    assert_reserved_name_rejected base_std_assert_integer __base_bash_libs_std_assert_integer_name
    assert_reserved_name_rejected base_std_assert_integer_range __base_bash_libs_std_range_name 1 10
}

@test "named assertions support historically shadowing-prone caller names" {
    local -a var_name=(alpha)
    local unset_vars=present
    local value=7

    base_std_assert_indexed_array var_name
    unset var_name
    local -A var_name=([alpha]=one)
    base_std_assert_associative_array var_name
    base_std_assert_not_null unset_vars
    base_std_assert_integer value
    base_std_assert_integer_range value 1 10
}

@test "base_std_assert_variable_name exits for invalid variable names without echoing values" {
    local script="$TEST_TMPDIR/assert-variable-name-invalid.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
secret="not-valid"
base_std_assert_variable_name value_name "\$secret"
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"base_std_assert_variable_name expects valid Bash variable names"* ]]
    [[ "$output" != *"not-valid"* ]]
}

@test "base_std_assert_indexed_array accepts declared indexed arrays" {
    local -a values=("alpha")

    base_std_assert_indexed_array values
}

@test "base_std_assert_indexed_array rejects scalar and associative variables" {
    local script="$TEST_TMPDIR/assert-indexed-array-invalid.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
values="alpha"
base_std_assert_indexed_array values
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Variable 'values' must be an indexed array declared by the caller."* ]]

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
declare -A values=([alpha]="one")
base_std_assert_indexed_array values
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Variable 'values' must be an indexed array declared by the caller."* ]]
}

@test "base_std_assert_associative_array accepts declared associative arrays" {
    local -A values=([alpha]="one")

    base_std_assert_associative_array values
}

@test "base_std_assert_associative_array rejects scalar and indexed variables" {
    local script="$TEST_TMPDIR/assert-associative-array-invalid.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
values="alpha"
base_std_assert_associative_array values
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Variable 'values' must be an associative array declared by the caller."* ]]

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
declare -a values=("alpha")
base_std_assert_associative_array values
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Variable 'values' must be an associative array declared by the caller."* ]]
}

@test "base_std_assert_not_null accepts populated variables" {
    local user_name="admin"
    local token="secret"

    base_std_assert_not_null user_name token
}

@test "base_std_assert_not_null exits for unset or empty variables" {
    local script="$TEST_TMPDIR/assert-not-null.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
user_name="admin"
token=""
base_std_assert_not_null user_name token missing_var
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"These required variables are not set or are empty"* ]]
}

@test "base_std_assert_not_null rejects value-like arguments without echoing them" {
    local script="$TEST_TMPDIR/assert-not-null-value.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
token="secret token with spaces"
base_std_assert_not_null "\$token"
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"base_std_assert_not_null expects variable names, not values"* ]]
    [[ "$output" != *"secret token with spaces"* ]]
}

@test "base_std_assert_integer accepts integers and rejects invalid values" {
    local count=42
    local signed=-3
    local script="$TEST_TMPDIR/assert-integer.sh"

    base_std_assert_integer count signed

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
count="not-an-int"
base_std_assert_integer count
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"is not a valid integer"* ]]
}

@test "base_std_assert_integer rejects invalid variable names without echoing values" {
    local script="$TEST_TMPDIR/assert-integer-name.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
secret="not-a-var-name"
base_std_assert_integer "\$secret"
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"base_std_assert_integer expects variable names"* ]]
    [[ "$output" != *"not-a-var-name"* ]]
    [[ "$output" != *"invalid variable name"* ]]
}

@test "base_std_assert_integer_range enforces range bounds" {
    local count=5
    local script="$TEST_TMPDIR/assert-range.sh"

    base_std_assert_integer_range count 1 10

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
count=11
base_std_assert_integer_range count 1 10
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"is out of range [1, 10]"* ]]
}

@test "base_std_assert_integer_range rejects invalid variable names without echoing values" {
    local script="$TEST_TMPDIR/assert-range-name.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
secret="bad-range-name"
base_std_assert_integer_range "\$secret" 1 10
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"base_std_assert_integer_range expects a variable name"* ]]
    [[ "$output" != *"bad-range-name"* ]]
    [[ "$output" != *"invalid variable name"* ]]
}

@test "base_std_assert_integer_range rejects non-integer bounds directly" {
    local script="$TEST_TMPDIR/assert-range-bounds.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
count=5
base_std_assert_integer_range count low 10
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"base_std_assert_integer_range minimum bound 'low' is not a valid integer."* ]]
    [[ "$output" != *"Variable 'min'"* ]]

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
count=5
base_std_assert_integer_range count 1 high
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"base_std_assert_integer_range maximum bound 'high' is not a valid integer."* ]]
    [[ "$output" != *"Variable 'max'"* ]]
}

@test "base_std_assert_arg_count accepts exact and ranged matches" {
    base_std_assert_arg_count 2 2
    base_std_assert_arg_count 2 1 3
}

@test "integer validation uses decimal semantics for leading zeroes" {
    local script="$TEST_TMPDIR/assert-decimal-integers.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
value=08
base_std_assert_integer_range value 0 10
base_std_assert_arg_count 08 8
base_std_exit_if_error 08 "decimal exit code"
EOF

    bats_run bash "$script"

    [ "$status" -eq 8 ]
    [[ "$output" == *"decimal exit code"* ]]
    [[ "$output" != *"value too great for base"* ]]
}

@test "integer ranges reject inverted bounds" {
    local script="$TEST_TMPDIR/assert-inverted-range.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
value=5
base_std_assert_integer_range value 10 1
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot exceed maximum"* ]]
}

@test "base_std_assert_arg_count exits when the count is out of range" {
    bats_run base_std_assert_arg_count 4 1 3

    [ "$status" -eq 1 ]
    [[ "$output" == *"Argument count mismatch"* ]]
}

@test "base_std_assert_arg_count exits on incorrect usage" {
    bats_run base_std_assert_arg_count 1

    [ "$status" -eq 1 ]
    [[ "$output" == *"Incorrect usage"* ]]
}

@test "base_std_assert_command_exists validates commands and warns on empty input" {
    local stderr_file="$TEST_TMPDIR/assert-command.err"

    base_std_assert_command_exists bash mkdir

    base_std_assert_command_exists 2>"$stderr_file"
    [ "$?" -eq 0 ]
    [[ "$(cat "$stderr_file")" == *"base_std_assert_command_exists: No commands provided to check."* ]]
}

@test "base_std_assert_command_exists exits for missing commands" {
    local script="$TEST_TMPDIR/assert-command-fail.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_assert_command_exists definitely_missing_command_name
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"were not found in your PATH"* ]]
}

@test "base_std_assert_file_exists validates files and warns on empty input" {
    local target="$TEST_TMPDIR/file.txt"
    local stderr_file="$TEST_TMPDIR/assert-file.err"

    touch "$target"
    base_std_assert_file_exists "$target"

    base_std_assert_file_exists 2>"$stderr_file"
    [ "$?" -eq 0 ]
    [[ "$(cat "$stderr_file")" == *"base_std_assert_file_exists: No files provided to check."* ]]
}

@test "base_std_assert_file_exists exits for missing files" {
    local script="$TEST_TMPDIR/assert-file-fail.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_assert_file_exists "$TEST_TMPDIR/missing.txt"
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"do not exist or are not regular files"* ]]
}

@test "base_std_assert_executable validates executable paths and warns on empty input" {
    local target="$TEST_TMPDIR/tool.sh"
    local stderr_file="$TEST_TMPDIR/assert-executable.err"

    create_script "$target" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

    base_std_assert_executable "$target"

    base_std_assert_executable 2>"$stderr_file"
    [ "$?" -eq 0 ]
    [[ "$(cat "$stderr_file")" == *"base_std_assert_executable: No executable paths provided to check."* ]]
}

@test "base_std_assert_executable exits for missing or non-executable paths" {
    local script="$TEST_TMPDIR/assert-executable-fail.sh"
    local target="$TEST_TMPDIR/not-executable.sh"

    printf '#!/usr/bin/env bash\n' > "$target"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_assert_executable "$TEST_TMPDIR/missing-tool" "$target"
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"do not exist, are not regular files, or are not executable"* ]]
    [[ "$output" == *"$TEST_TMPDIR/missing-tool"* ]]
    [[ "$output" == *"$target"* ]]
}

@test "base_std_assert_dir_exists validates directories and warns on empty input" {
    local target="$TEST_TMPDIR/dir"
    local stderr_file="$TEST_TMPDIR/assert-dir.err"

    mkdir -p "$target"
    base_std_assert_dir_exists "$target"

    base_std_assert_dir_exists 2>"$stderr_file"
    [ "$?" -eq 0 ]
    [[ "$(cat "$stderr_file")" == *"base_std_assert_dir_exists: No directories provided to check."* ]]
}

@test "base_std_assert_dir_exists exits for missing directories" {
    local script="$TEST_TMPDIR/assert-dir-fail.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_assert_dir_exists "$TEST_TMPDIR/missing-dir"
EOF

    bats_run bash "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"These required directories do not exist"* ]]
}

@test "base_std_safe_cd changes directories and returns on failure" {
    local target="$TEST_TMPDIR/go-here"
    local script="$TEST_TMPDIR/safe-cd-fail.sh"

    mkdir -p "$target"
    base_std_safe_cd "$target"
    [ "$PWD" = "$target" ]

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_safe_cd "$TEST_TMPDIR/missing-dir"
echo "after"
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Can't cd to"* ]]
    [[ "$output" == *"after"* ]]
}

@test "base_std_safe_unalias removes aliases and ignores missing ones" {
    alias ll='ls -l'

    base_std_safe_unalias ll missing_alias

    ! alias ll >/dev/null 2>&1
}

@test "base_std_get_my_source_dir returns the caller script directory" {
    local script="$TEST_TMPDIR/get-source-dir.sh"
    local expected_dir

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
caller_dir=""
base_std_get_my_source_dir caller_dir
printf 'dir=%s\n' "\$caller_dir"
EOF

    expected_dir="$(cd "$TEST_TMPDIR" && pwd -P)"

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"dir=$expected_dir"* ]]
}

@test "base_std_get_my_source_dir supports shadowing-prone output variable names" {
    local script="$TEST_TMPDIR/get-source-dir-shadow.sh"
    local expected_dir

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
source_dir=""
result_name=""
base_std_get_my_source_dir source_dir
base_std_get_my_source_dir result_name
printf 'source_dir=%s\n' "\$source_dir"
printf 'result_name=%s\n' "\$result_name"
EOF

    expected_dir="$(cd "$TEST_TMPDIR" && pwd -P)"

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"source_dir=$expected_dir"* ]]
    [[ "$output" == *"result_name=$expected_dir"* ]]
}

@test "base_std_get_my_source_dir returns for invalid result variable names" {
    local script="$TEST_TMPDIR/get-source-dir-invalid.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_get_my_source_dir "bad-name"
echo "after"
EOF

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"base_std_get_my_source_dir: result variable name must be a valid Bash variable name"* ]]
    [[ "$output" != *"invalid variable name"* ]]
    [[ "$output" == *"after"* ]]
}

@test "base_std_ask_yes_no accepts yes input" {
    local script="$TEST_TMPDIR/ask-yes.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
if base_std_ask_yes_no "Proceed"; then
    echo "answer=yes"
else
    echo "answer=no"
fi
EOF

    run_pty_command $'y\n' "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"answer=yes"* ]]
}

@test "base_std_ask_yes_no accepts no input" {
    local script="$TEST_TMPDIR/ask-no.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
if base_std_ask_yes_no "Proceed"; then
    echo "answer=yes"
else
    echo "answer=no"
fi
EOF

    run_pty_command $'n\n' "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"answer=no"* ]]
}

@test "base_std_ask_yes_no accepts the displayed no default on Enter" {
    local script="$TEST_TMPDIR/ask-default-no.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
if base_std_ask_yes_no "Proceed"; then
    echo "answer=yes"
else
    echo "answer=no"
fi
EOF

    run_pty_command $'\n' "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"answer=no"* ]]
}

@test "base_std_ask_yes_no accepts the displayed yes default on Enter" {
    local script="$TEST_TMPDIR/ask-default-yes.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
if base_std_ask_yes_no "Proceed" yes; then
    echo "answer=yes"
else
    echo "answer=no"
fi
EOF

    run_pty_command $'\n' "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"answer=yes"* ]]
}

@test "base_std_ask_yes_no reads from terminal when stdin is redirected" {
    local script="$TEST_TMPDIR/ask-tty.sh"
    local normalized

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
if base_std_ask_yes_no "Proceed"; then
    echo "answer=yes"
else
    echo "answer=no"
fi
printf 'stdin='
cat
EOF

    run_pty_command $'y\n' bash -c "printf 'n\npayload\n' | \"$script\""
    normalized="${output//$'\r'/}"

    [ "$status" -eq 0 ]
    [[ "$normalized" == *"answer=yes"* ]]
    [[ "$normalized" == *"stdin=n"* ]]
    [[ "$normalized" == *"payload"* ]]
}

@test "base_std_ask_yes_no validates argument count" {
    local stderr_file="$TEST_TMPDIR/ask-yes-no.err"
    local rc

    if base_std_ask_yes_no 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 2 ]
    [[ "$(cat "$stderr_file")" == *"base_std_ask_yes_no: invalid arguments"* ]]
}

@test "base_std_wait_for_enter returns after receiving a newline on a tty" {
    local normalized
    local script="$TEST_TMPDIR/wait-enter.sh"

    create_script "$script" <<EOF
#!/usr/bin/env bash
source "$STDLIB_PATH"
base_std_wait_for_enter "Continue" || exit \$?
printf 'after-wait\n'
EOF

    run_pty_command $'\n' "$script"
    normalized="${output//$'\r'/}"

    [ "$status" -eq 0 ]
    [[ "$normalized" == *"after-wait"* ]]
}

@test "base_std_wait_for_enter validates argument count" {
    local stderr_file="$TEST_TMPDIR/wait-for-enter.err"
    local rc

    if base_std_wait_for_enter "one" "two" 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 1 ]
    [[ "$(cat "$stderr_file")" == *"base_std_wait_for_enter: invalid arguments"* ]]
    [[ "$(cat "$stderr_file")" == *"Usage: base_std_wait_for_enter [prompt_message]"* ]]
}

@test "base_std_wait_for_enter fails clearly when terminal is unavailable" {
    bats_run base_std_wait_for_enter "Continue"

    [ "$status" -eq 1 ]
    [[ "$output" == *"base_std_wait_for_enter: /dev/tty is not available"* ]]
}
