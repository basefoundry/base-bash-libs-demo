# shellcheck shell=bash
# Common helpers for Bash library BATS suites.

# Preserve BATS' built-in `run` helper before lib_std.sh defines its own.
if declare -f run >/dev/null 2>&1; then
    eval "$(declare -f run | sed '1 s/^run /bats_run /')"
fi

BASE_BASH_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly BASE_BASH_TESTS_DIR
BASE_BASH_DIR="$(cd "$BASE_BASH_TESTS_DIR/.." && pwd -P)"
readonly BASE_BASH_DIR
BASE_REPO_ROOT="$(cd "$BASE_BASH_DIR/../.." && pwd -P)"
# Used by BATS suites loaded after this helper.
# shellcheck disable=SC2034
readonly BASE_REPO_ROOT
# Used by BATS suites loaded after this helper.
BASE_TEST_ORIG_PATH="$PATH"
# shellcheck disable=SC2034
readonly BASE_TEST_ORIG_PATH

unset_base_runtime_env() {
    local var_name

    for var_name in \
        BASE_HOME \
        BASE_BIN_DIR \
        BASE_CLI_DIR \
        BASE_BASH_DIR \
        BASE_BASH_COMMANDS_DIR \
        BASE_LIB_DIR \
        BASE_BASH_LIB_DIR \
        BASE_SHELL_DIR \
        BASE_OS \
        BASE_HOST \
        BASE_SHELL \
        BASE_PLATFORM_TOOLS_HOME \
        BASE_PLATFORM_TOOLS_BIN_DIR \
        BASE_PROFILE_VERSION \
        BASE_ENABLE_BASH_DEFAULTS \
        BASE_ENABLE_ZSH_DEFAULTS \
        BASE_DEBUG \
        BASE_BASH_COMMAND_NAME \
        BASE_BASH_COMMAND_DIR \
        BASE_BASH_COMMAND_SCRIPT \
        BASE_BASH_LIBS_BOOTSTRAP_SOURCE \
        BASE_PROJECT \
        BASE_PROJECT_ROOT \
        BASE_PROJECT_MANIFEST \
        BASE_PROJECT_VENV_DIR \
        VIRTUAL_ENV; do
        unset "$var_name" 2>/dev/null || true
    done
}

setup_test_tmpdir() {
    unset_base_runtime_env
    TEST_TMPDIR="${BATS_TEST_TMPDIR}/workspace"
    mkdir -p "$TEST_TMPDIR"
}

capture_command() {
    local capture_file="${TEST_TMPDIR:?}/captured-command.out"

    set +e
    "$@" >"$capture_file" 2>&1
    # BATS-compatible globals consumed by individual test cases after capture_command returns.
    # shellcheck disable=SC2034
    status=$?
    set -e

    # shellcheck disable=SC2034
    output="$(cat "$capture_file")"
    # shellcheck disable=SC2034
    IFS=$'\n' read -r -d '' -a lines < "$capture_file" || true
}

init_git_repo() {
    local repo_dir="$1"
    local default_branch="${2:-main}"

    mkdir -p "$repo_dir"
    git init "$repo_dir" >/dev/null 2>&1
    git -C "$repo_dir" checkout -B "$default_branch" >/dev/null 2>&1
    git -C "$repo_dir" config user.name "Bats Test"
    git -C "$repo_dir" config user.email "bats@example.com"
}

commit_all() {
    local repo_dir="$1"
    local message="${2:-test commit}"

    git -C "$repo_dir" add -A
    git -C "$repo_dir" commit -m "$message" >/dev/null 2>&1
}

create_tracked_repo_with_upstream() {
    local repo_dir="$1"
    local remote_dir="$2"
    local rel_path="$3"
    local content="${4:-sample content}"
    local default_branch="${5:-main}"

    init_git_repo "$repo_dir" "$default_branch"
    mkdir -p "$(dirname "$repo_dir/$rel_path")"
    printf '%s\n' "$content" > "$repo_dir/$rel_path"
    commit_all "$repo_dir" "Initial commit"

    git init --bare "$remote_dir" >/dev/null 2>&1
    git -C "$repo_dir" remote add origin "$remote_dir"
    git -C "$repo_dir" push -u origin "$default_branch" >/dev/null 2>&1
    git -C "$remote_dir" symbolic-ref HEAD "refs/heads/$default_branch"
}
