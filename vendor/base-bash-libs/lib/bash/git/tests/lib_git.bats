#!/usr/bin/env bats

load ../../tests/test_helper.sh

setup() {
    setup_test_tmpdir
    source "$BASE_BASH_DIR/std/lib_std.sh"
    declare -a setup_args=()
    base_init setup_args --source "$BASE_BASH_DIR/git/tests/lib_git.bats" --
    source "$BASE_BASH_DIR/git/lib_git.sh"
}

@test "lib_git can be sourced more than once" {
    source "$BASE_BASH_DIR/git/lib_git.sh"

    [ "$(type -t base_git_update_repo)" = "function" ]
}

@test "lib_git fails clearly when sourced without stdlib" {
    bats_run bash -c 'source "$1"; rc=$?; printf "source-rc=%s\n" "$rc"; exit "$rc"' bash "$BASE_BASH_DIR/git/lib_git.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"lib_git.sh requires lib_std.sh to be sourced first"* ]]
    [[ "$output" == *"source-rc=1"* ]]
    [[ "$output" != *"command not found"* ]]
}

@test "lib_git requires the stdlib loaded marker" {
    bats_run bash -c 'base_std_log_error() { :; }; base_std_log_debug() { :; }; source "$1"; rc=$?; printf "source-rc=%s\n" "$rc"; exit "$rc"' bash "$BASE_BASH_DIR/git/lib_git.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"lib_git.sh requires lib_std.sh to be sourced first"* ]]
    [[ "$output" == *"source-rc=1"* ]]
}

@test "git required-argument APIs return usage errors under every caller option combination" {
    local function_name mode

    for mode in off e u p eu ep up eup; do
        for function_name in \
            base_git_detect_default_branch \
            base_git_worktree_path_for_branch \
            base_git_branch_upstream \
            base_git_branch_merged_to_ref \
            base_git_update_repo \
            base_git_get_current_branch \
            base_git_check_script_up_to_date; do
            bats_run "$BASH" -c '
                mode="$1"
                case "$mode" in *e*) set -e ;; esac
                case "$mode" in *u*) set -u ;; esac
                case "$mode" in *p*) set -o pipefail ;; esac
                source "$2"
                declare -a app_args=()
                base_init app_args --source "$0" --
                source "$3"
                "$4"
                rc=$?
                exit "$rc"
            ' bash "$mode" "$BASE_BASH_DIR/std/lib_std.sh" "$BASE_BASH_DIR/git/lib_git.sh" "$function_name"

            [ "$status" -eq 2 ]
            [[ "$output" == *"Usage:"* ]]
            [[ "$output" != *"unbound variable"* ]]
        done
    done
}

@test "git optional forms reject excess arguments and unsupported option placement" {
    capture_command base_git_list_worktree_branches one two
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage: base_git_list_worktree_branches [repo_dir]"* ]]

    capture_command base_git_list_remote_branches one two
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage: base_git_list_remote_branches [repo_dir]"* ]]

    capture_command base_git_worktree_path_for_branch branch repo extra
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage: base_git_worktree_path_for_branch <branch> [repo_dir]"* ]]

    capture_command base_git_check_script_up_to_date --refresh script.sh
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage: base_git_check_script_up_to_date [--fetch] <script_path>"* ]]

    capture_command base_git_check_script_up_to_date --fetch
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage: base_git_check_script_up_to_date [--fetch] <script_path>"* ]]
}

@test "git remote parsing is independent of and preserves caller IFS" {
    local output_file="$TEST_TMPDIR/remote-branches.out"
    local rc

    git() {
        if [[ "${1:-}" == "-C" && "${3:-}" == "ls-remote" ]]; then
            printf 'abc123\trefs/heads/main\n'
            printf 'def456\trefs/heads/feature/topic\n'
            return 0
        fi
        command git "$@"
    }

    IFS=:
    if base_git_list_remote_branches "$TEST_TMPDIR" >"$output_file"; then
        rc=0
    else
        rc=$?
    fi
    unset -f git

    [ "$rc" -eq 0 ]
    [ "$IFS" = ":" ]
    [ "$(cat "$output_file")" = $'main\nfeature/topic' ]
}

@test "git predicate status survives every caller option combination" {
    local mode
    local repo="$TEST_TMPDIR/repo"

    init_git_repo "$repo"
    printf 'base\n' > "$repo/data.txt"
    commit_all "$repo" "Initial commit"
    git -C "$repo" checkout -b feature >/dev/null 2>&1
    printf 'feature\n' > "$repo/feature.txt"
    commit_all "$repo" "Feature commit"
    git -C "$repo" checkout main >/dev/null 2>&1

    for mode in off e u p eu ep up eup; do
        bats_run "$BASH" -c '
            mode="$1"
            case "$mode" in *e*) set -e ;; esac
            case "$mode" in *u*) set -u ;; esac
            case "$mode" in *p*) set -o pipefail ;; esac
            source "$2"
            declare -a app_args=()
            base_init app_args --
            source "$3"
            base_git_branch_merged_to_ref "$4" feature main
            rc=$?
            exit "$rc"
        ' bash "$mode" "$BASE_BASH_DIR/std/lib_std.sh" "$BASE_BASH_DIR/git/lib_git.sh" "$repo"

        [ "$status" -eq 1 ]
        [[ "$output" != *"unbound variable"* ]]
    done
}

@test "base_git_detect_default_branch resolves origin HEAD and fallback branches" {
    local repo="$TEST_TMPDIR/repo"
    local branch=""

    init_git_repo "$repo"
    printf 'base\n' > "$repo/data.txt"
    commit_all "$repo" "Initial commit"
    git -C "$repo" update-ref refs/remotes/origin/trunk HEAD
    git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk

    base_git_detect_default_branch "$repo" branch
    [ "$branch" = "trunk" ]

    git -C "$repo" symbolic-ref -d refs/remotes/origin/HEAD
    base_git_detect_default_branch "$repo" branch
    [ "$branch" = "main" ]
}

@test "default branch fallback order is shared by public and update helpers" {
    local repo="$TEST_TMPDIR/repo"
    local branch=""

    init_git_repo "$repo"
    printf 'base\n' >"$repo/data.txt"
    commit_all "$repo" "Initial commit"
    git -C "$repo" update-ref refs/remotes/origin/master HEAD
    git -C "$repo" update-ref refs/heads/main HEAD

    base_git_detect_default_branch "$repo" branch
    [ "$branch" = "master" ]
    pushd "$repo" >/dev/null
    branch="$(__base_bash_libs_git_expected_update_branch__)"
    popd >/dev/null
    [ "$branch" = "master" ]
}

@test "git worktree helpers surface producer failures" {
    git() {
        printf 'worktree command failed\n' >&2
        return 7
    }

    capture_command base_git_worktree_path_for_branch feature
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unable to list Git worktrees."* ]]

    capture_command base_git_list_worktree_branches
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unable to list Git worktrees."* ]]
    unset -f git
}

@test "git worktree helpers parse canonical porcelain output" {
    git() {
        if [[ "${1:-}" == "worktree" || "${3:-}" == "worktree" ]]; then
            cat <<'EOF'
worktree /tmp/main
HEAD abc123
branch refs/heads/main

worktree /tmp/feature
HEAD def456
branch refs/heads/feature/test
EOF
            return 0
        fi
        command git "$@"
    }

    capture_command base_git_worktree_path_for_branch feature/test
    [ "$status" -eq 0 ]
    [ "$output" = "/tmp/feature" ]

    capture_command base_git_list_worktree_branches
    [ "$status" -eq 0 ]
    [[ "$output" == *$'/tmp/main\tmain'* ]]
    [[ "$output" == *$'/tmp/feature\tfeature/test'* ]]
    unset -f git
}

@test "git worktree command arrays are Bash 4.2 nounset-safe" {
    bats_run "$BASH" -c '
        set -u
        source "$1"
        declare -a app_args=()
        base_init app_args --
        source "$2"
        git() {
            printf "%s\n" \
                "worktree /tmp/main" \
                "HEAD abc123" \
                "branch refs/heads/main" \
                "" \
                "worktree /tmp/feature" \
                "HEAD def456" \
                "branch refs/heads/feature/test"
        }
        base_git_worktree_path_for_branch feature/test
        base_git_list_worktree_branches /tmp/repo
    ' bash "$BASE_BASH_DIR/std/lib_std.sh" "$BASE_BASH_DIR/git/lib_git.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"/tmp/feature"* ]]
    [[ "$output" == *$'/tmp/main\tmain'* ]]
    [[ "$output" == *$'/tmp/feature\tfeature/test'* ]]
    [[ "$output" != *"unbound variable"* ]]
}

@test "git branch and remote helpers use generic names" {
    local repo="$TEST_TMPDIR/repo"
    local branch_output remote_output

    init_git_repo "$repo"
    printf 'base\n' > "$repo/data.txt"
    commit_all "$repo" "Initial commit"
    git -C "$repo" branch feature

    branch_output="$(base_git_branch_upstream "$repo" main)"
    [ -z "$branch_output" ]
    base_git_branch_merged_to_ref "$repo" feature main

    git() {
        if [[ "${1:-}" == "-C" && "${3:-}" == "ls-remote" ]]; then
            printf 'abc123\trefs/heads/main\n'
            printf 'def456\trefs/tags/v1\n'
            return 0
        fi
        command git "$@"
    }
    remote_output="$(base_git_list_remote_branches "$repo")"
    unset -f git
    [ "$remote_output" = "main" ]
}

@test "base_git_get_current_branch returns the current branch name" {
    local repo="$TEST_TMPDIR/repo"
    local branch=""

    init_git_repo "$repo"
    base_git_get_current_branch "$repo" branch

    [ "$branch" = "main" ]
}

@test "base_git_get_current_branch rejects readonly result variables" {
    local repo="$TEST_TMPDIR/repo"
    local branch="sentinel"
    local stderr_file="$TEST_TMPDIR/git-readonly-output.err"
    local rc

    init_git_repo "$repo"
    readonly branch
    if base_git_get_current_branch "$repo" branch 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 2 ]
    [ "$branch" = "sentinel" ]
    [[ "$(cat "$stderr_file")" == *"result variable 'branch' is readonly"* ]]
}

@test "Git result helpers reject exact internal holder names before locals or mutation" {
    local -r __base_bash_libs_git_detect_result_name=detected
    local -r __base_bash_libs_git_branch_result_name=current
    local detected="keep-detected"
    local current="keep-current"
    local stderr_file="$TEST_TMPDIR/git-internal-holder.err"
    local rc

    if base_git_detect_default_branch . __base_bash_libs_git_detect_result_name 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 2 ]
    [ "$detected" = "keep-detected" ]

    if base_git_get_current_branch . __base_bash_libs_git_branch_result_name 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 2 ]
    [ "$current" = "keep-current" ]
    [[ "$(cat "$stderr_file")" == *"uses the reserved '__' internal namespace"* ]]
    [[ "$(cat "$stderr_file")" != *"readonly variable"* ]]
}

@test "base_git_get_current_branch supports shadowing-prone output variable names" {
    local repo="$TEST_TMPDIR/repo"
    local result_var_name=""
    local branch_name=""

    init_git_repo "$repo"

    base_git_get_current_branch "$repo" result_var_name
    base_git_get_current_branch "$repo" branch_name

    [ "$result_var_name" = "main" ]
    [ "$branch_name" = "main" ]
}

@test "base_git_get_current_branch reports detached head" {
    local repo="$TEST_TMPDIR/repo"
    local branch=""

    init_git_repo "$repo"
    printf 'hello\n' > "$repo/README.md"
    commit_all "$repo" "Initial commit"
    git -C "$repo" checkout --detach >/dev/null 2>&1

    base_git_get_current_branch "$repo" branch

    [ "$branch" = "detached head" ]
}

@test "base_git_get_current_branch leaves missing directories as empty success" {
    local branch="sentinel"
    local rc

    if base_git_get_current_branch "$TEST_TMPDIR/missing" branch; then
        rc=0
    else
        rc=$?
    fi

    [ "$rc" -eq 0 ]
    [ "$branch" = "" ]
}

@test "base_git_get_current_branch does not use pushd or popd" {
    local repo="$TEST_TMPDIR/repo"
    local branch="" rc

    init_git_repo "$repo"
    pushd() {
        printf 'unexpected pushd\n' >&2
        return 99
    }
    popd() {
        printf 'unexpected popd\n' >&2
        return 99
    }

    if base_git_get_current_branch "$repo" branch; then
        rc=0
    else
        rc=$?
    fi
    unset -f pushd popd

    [ "$rc" -eq 0 ]
    [ "$branch" = "main" ]
}

@test "base_git_get_current_branch usage names the current function" {
    bats_run base_git_get_current_branch

    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage: base_git_get_current_branch <directory> <result_variable_name>"* ]]
    [[ "$output" != *"Usage: get_git_branch"* ]]
}

@test "base_git_get_current_branch rejects invalid result variable names" {
    local repo="$TEST_TMPDIR/repo"

    init_git_repo "$repo"

    bats_run base_git_get_current_branch "$repo" "bad-name"

    [ "$status" -eq 2 ]
    [[ "$output" == *"base_git_get_current_branch: result variable name must be a valid Bash variable name"* ]]
    [[ "$output" != *"invalid variable name"* ]]
}

@test "base_git_update_repo usage names the current function" {
    capture_command base_git_update_repo

    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage: base_git_update_repo /path/to/repo [allowed_dirty_path] [expected_branch]"* ]]
    [[ "$output" != *"Usage: update_repo"* ]]
}

@test "base_git_update_repo skips dirty repositories when no dirty path is allowed" {
    local repo="$TEST_TMPDIR/repo"

    init_git_repo "$repo"
    printf 'base\n' > "$repo/data.txt"
    commit_all "$repo" "Initial commit"
    printf 'local change\n' > "$repo/data.txt"
    base_std_set_log_level DEBUG
    base_std_set_log_category_level -l base_bash_libs.git DEBUG

    capture_command base_git_update_repo "$repo"

    [ "$status" -eq 0 ]
    [[ "$output" == *"has local changes; skipping auto-update"* ]]
}

@test "caller DEBUG does not enable reusable Git DEBUG by default" {
    local repo="$TEST_TMPDIR/repo"

    init_git_repo "$repo"
    printf 'base\n' > "$repo/data.txt"
    commit_all "$repo" "Initial commit"
    base_std_set_log_level DEBUG

    capture_command base_git_update_repo "$repo" "" release

    [ "$status" -eq 0 ]
    [[ "$output" != *"not 'release'. Skipping update"* ]]
}

@test "Git child category DEBUG opt-in enables reusable Git diagnostics" {
    local repo="$TEST_TMPDIR/repo"

    init_git_repo "$repo"
    printf 'base\n' > "$repo/data.txt"
    commit_all "$repo" "Initial commit"
    base_std_set_log_level DEBUG
    base_std_set_log_category_level -l base_bash_libs.git DEBUG

    capture_command base_git_update_repo "$repo" "" release

    [ "$status" -eq 0 ]
    [[ "$output" == *"not 'release'. Skipping update"* ]]
}

@test "base_bash_libs parent DEBUG opt-in enables reusable Git diagnostics" {
    local repo="$TEST_TMPDIR/repo"

    init_git_repo "$repo"
    printf 'base\n' > "$repo/data.txt"
    commit_all "$repo" "Initial commit"
    base_std_set_log_level DEBUG
    base_std_set_log_category_level -l base_bash_libs DEBUG

    capture_command base_git_update_repo "$repo" "" release

    [ "$status" -eq 0 ]
    [[ "$output" == *"not 'release'. Skipping update"* ]]
}

@test "base_git_update_repo fails clearly when origin remote is missing" {
    local before_head
    local repo="$TEST_TMPDIR/repo"

    init_git_repo "$repo"
    printf 'base\n' > "$repo/data.txt"
    commit_all "$repo" "Initial commit"
    before_head="$(git -C "$repo" rev-parse HEAD)"

    capture_command base_git_update_repo "$repo" "" main

    [ "$status" -eq 1 ]
    [[ "$output" == *"git pull failed on repo '$repo'"* ]]
    [ "$(git -C "$repo" rev-parse HEAD)" = "$before_head" ]
    [ "$(cat "$repo/data.txt")" = "base" ]
    [ -z "$(git -C "$repo" status --porcelain)" ]
}

@test "base_git_update_repo fails clearly when origin remote is unreachable" {
    local before_head
    local remote="$TEST_TMPDIR/remote.git"
    local repo="$TEST_TMPDIR/repo"

    create_tracked_repo_with_upstream "$repo" "$remote" "data.txt" "base"
    before_head="$(git -C "$repo" rev-parse HEAD)"
    git -C "$repo" remote set-url origin "$TEST_TMPDIR/missing-remote.git"

    capture_command base_git_update_repo "$repo" "" main

    [ "$status" -eq 1 ]
    [[ "$output" == *"git pull failed on repo '$repo'"* ]]
    [ "$(git -C "$repo" rev-parse HEAD)" = "$before_head" ]
    [ "$(cat "$repo/data.txt")" = "base" ]
    [ -z "$(git -C "$repo" status --porcelain)" ]
}

@test "base_git_update_repo fails on non-fast-forward updates without changing HEAD" {
    local before_head
    local other="$TEST_TMPDIR/other"
    local remote="$TEST_TMPDIR/remote.git"
    local repo="$TEST_TMPDIR/repo"

    create_tracked_repo_with_upstream "$repo" "$remote" "data.txt" "base"
    before_head="$(git -C "$repo" rev-parse HEAD)"

    git clone "$remote" "$other" >/dev/null 2>&1
    git -C "$other" config user.name "Bats Test"
    git -C "$other" config user.email "bats@example.com"
    printf 'rewritten remote\n' > "$other/data.txt"
    git -C "$other" add data.txt
    git -C "$other" commit --amend -m "Rewrite remote history" >/dev/null 2>&1
    git -C "$other" push --force origin main >/dev/null 2>&1

    capture_command base_git_update_repo "$repo" "" main

    [ "$status" -eq 1 ]
    [[ "$output" == *"git pull failed on repo '$repo'"* ]]
    [ "$(git -C "$repo" rev-parse HEAD)" = "$before_head" ]
    [ "$(cat "$repo/data.txt")" = "base" ]
    [ -z "$(git -C "$repo" status --porcelain)" ]
}

@test "base_git_update_repo lets git protect untracked files from incoming tracked paths" {
    local before_head
    local other="$TEST_TMPDIR/other"
    local remote="$TEST_TMPDIR/remote.git"
    local repo="$TEST_TMPDIR/repo"

    create_tracked_repo_with_upstream "$repo" "$remote" "data.txt" "base"
    before_head="$(git -C "$repo" rev-parse HEAD)"
    git clone "$remote" "$other" >/dev/null 2>&1
    git -C "$other" config user.name "Bats Test"
    git -C "$other" config user.email "bats@example.com"
    printf 'incoming tracked\n' > "$other/local-notes.md"
    git -C "$other" add local-notes.md
    git -C "$other" commit -m "Add tracked notes" >/dev/null 2>&1
    git -C "$other" push origin main >/dev/null 2>&1
    printf 'local untracked\n' > "$repo/local-notes.md"

    capture_command base_git_update_repo "$repo" "" main

    [ "$status" -eq 1 ]
    [[ "$output" == *"git pull failed on repo '$repo'"* ]]
    [ "$(git -C "$repo" rev-parse HEAD)" = "$before_head" ]
    [ "$(cat "$repo/local-notes.md")" = "local untracked" ]
    ! git -C "$repo" ls-files --error-unmatch local-notes.md >/dev/null 2>&1
}

@test "base_git_update_repo accepts main as the detected update branch" {
    local repo="$TEST_TMPDIR/repo"

    init_git_repo "$repo"
    git -C "$repo" checkout -B main >/dev/null 2>&1
    printf 'base\n' > "$repo/data.txt"
    commit_all "$repo" "Initial commit"
    printf 'local change\n' > "$repo/data.txt"
    base_std_set_log_level DEBUG
    base_std_set_log_category_level -l base_bash_libs.git DEBUG

    capture_command base_git_update_repo "$repo"

    [ "$status" -eq 0 ]
    [[ "$output" == *"has local changes; skipping auto-update"* ]]
    [[ "$output" != *"not 'main'"* ]]
}

@test "__base_bash_libs_git_expected_update_branch__ returns main when origin has main" {
    local repo="$TEST_TMPDIR/repo"
    local branch

    init_git_repo "$repo"
    printf 'base\n' > "$repo/data.txt"
    commit_all "$repo" "Initial commit"
    git -C "$repo" update-ref refs/remotes/origin/main HEAD
    git -C "$repo" checkout --detach >/dev/null 2>&1
    git -C "$repo" branch -D main >/dev/null 2>&1

    pushd "$repo" >/dev/null
    branch="$(__base_bash_libs_git_expected_update_branch__)"
    popd >/dev/null

    [ "$branch" = "main" ]
}

@test "__base_bash_libs_git_expected_update_branch__ returns master when origin only has master" {
    local repo="$TEST_TMPDIR/repo"
    local branch

    init_git_repo "$repo"
    printf 'base\n' > "$repo/data.txt"
    commit_all "$repo" "Initial commit"
    git -C "$repo" update-ref refs/remotes/origin/master HEAD
    git -C "$repo" checkout --detach >/dev/null 2>&1
    git -C "$repo" branch -D main >/dev/null 2>&1

    pushd "$repo" >/dev/null
    branch="$(__base_bash_libs_git_expected_update_branch__)"
    popd >/dev/null

    [ "$branch" = "master" ]
}

@test "__base_bash_libs_git_expected_update_branch__ falls back to main without main or master refs" {
    local repo="$TEST_TMPDIR/repo"
    local branch

    init_git_repo "$repo"

    pushd "$repo" >/dev/null
    branch="$(__base_bash_libs_git_expected_update_branch__)"
    popd >/dev/null

    [ "$branch" = "main" ]
}

@test "__base_bash_libs_git_only_path_dirty__ accepts multiple dirty files under an allowed directory" {
    local repo="$TEST_TMPDIR/repo"
    local rc

    init_git_repo "$repo"
    mkdir -p "$repo/shared"
    printf 'one\n' > "$repo/shared/one.txt"
    printf 'two\n' > "$repo/shared/two.txt"
    commit_all "$repo" "Initial commit"
    printf 'local one\n' > "$repo/shared/one.txt"
    printf 'local two\n' > "$repo/shared/two.txt"

    __base_bash_libs_git_only_path_dirty__ "$repo" "shared"
    rc=$?

    [ "$rc" -eq 0 ]
}

@test "__base_bash_libs_git_only_path_dirty__ accepts tracked paths containing spaces" {
    local repo="$TEST_TMPDIR/repo"
    local rc

    init_git_repo "$repo"
    mkdir -p "$repo/shared"
    printf 'one\n' > "$repo/shared/hello world.txt"
    commit_all "$repo" "Initial commit"
    printf 'local change\n' >> "$repo/shared/hello world.txt"

    pushd "$repo" >/dev/null
    __base_bash_libs_git_only_path_dirty__ "$repo" "shared"
    rc=$?
    popd >/dev/null

    [ "$rc" -eq 0 ]
}

@test "__base_bash_libs_git_only_path_dirty__ does not treat sibling path prefixes as allowed" {
    local repo="$TEST_TMPDIR/repo"
    local rc

    init_git_repo "$repo"
    mkdir -p "$repo/shared"
    printf 'one\n' > "$repo/shared/one.txt"
    printf 'other\n' > "$repo/shared-other.txt"
    commit_all "$repo" "Initial commit"
    printf 'local one\n' > "$repo/shared/one.txt"
    printf 'local other\n' > "$repo/shared-other.txt"

    pushd "$repo" >/dev/null
    set +e
    __base_bash_libs_git_only_path_dirty__ "$repo" "shared"
    rc=$?
    set -e
    popd >/dev/null

    [ "$rc" -eq 1 ]
}

@test "__base_bash_libs_git_only_path_dirty__ rejects renames from outside the allowed path" {
    local repo="$TEST_TMPDIR/repo"
    local rc

    init_git_repo "$repo"
    mkdir -p "$repo/shared" "$repo/src"
    printf 'one\n' > "$repo/src/one.txt"
    commit_all "$repo" "Initial commit"
    git -C "$repo" mv src/one.txt shared/one.txt

    pushd "$repo" >/dev/null
    set +e
    __base_bash_libs_git_only_path_dirty__ "$repo" "shared"
    rc=$?
    set -e
    popd >/dev/null

    [ "$rc" -eq 1 ]
}

@test "__base_bash_libs_git_only_path_dirty__ accepts renames inside the allowed path" {
    local repo="$TEST_TMPDIR/repo"
    local rc

    init_git_repo "$repo"
    mkdir -p "$repo/shared"
    printf 'one\n' > "$repo/shared/one.txt"
    commit_all "$repo" "Initial commit"
    git -C "$repo" mv shared/one.txt shared/two.txt

    pushd "$repo" >/dev/null
    __base_bash_libs_git_only_path_dirty__ "$repo" "shared"
    rc=$?
    popd >/dev/null

    [ "$rc" -eq 0 ]
}

@test "base_git_update_repo cleans up temp log without changing RETURN trap" {
    local repo="$TEST_TMPDIR/repo"
    local temp_dir="$TEST_TMPDIR/git-temp"
    local return_trap

    mkdir -p "$temp_dir"
    init_git_repo "$repo"
    printf 'base\n' > "$repo/data.txt"
    commit_all "$repo" "Initial commit"
    printf 'local change\n' > "$repo/data.txt"

    trap 'printf "outer return trap\n"' RETURN
    TMPDIR="$temp_dir" capture_command base_git_update_repo "$repo"
    return_trap="$(trap -p RETURN)"
    trap - RETURN

    [ "$status" -eq 0 ]
    [[ "$return_trap" == *"outer return trap"* ]]
    ! compgen -G "$temp_dir/git_log.*" >/dev/null
}

@test "base_git_update_repo registers temp log for cleanup" {
    local repo="$TEST_TMPDIR/repo"
    local registration_file="$TEST_TMPDIR/registered-cleanup-paths.txt"

    init_git_repo "$repo"
    printf 'base\n' > "$repo/data.txt"
    commit_all "$repo" "Initial commit"
    printf 'local change\n' > "$repo/data.txt"

    eval "$(declare -f base_std_register_cleanup_path | sed '1s/base_std_register_cleanup_path/__orig_std_register_cleanup_path/')"
    base_std_register_cleanup_path() {
        printf '%s\n' "$@" >> "$registration_file"
        __orig_std_register_cleanup_path "$@"
    }

    capture_command base_git_update_repo "$repo"
    unset -f base_std_register_cleanup_path __orig_std_register_cleanup_path

    [ "$status" -eq 0 ]
    [[ "$(cat "$registration_file")" == *"git_log."* ]]
}

@test "__base_bash_libs_git_update_repo_finish__ removes temp log after success" {
    local git_log="$TEST_TMPDIR/git.log"

    printf 'pull output\n' > "$git_log"

    bats_run __base_bash_libs_git_update_repo_finish__ "$git_log" false 0

    [ "$status" -eq 0 ]
    [ ! -e "$git_log" ]
}

@test "__base_bash_libs_git_update_repo_finish__ preserves an existing RETURN trap" {
    local git_log="$TEST_TMPDIR/git.log"
    local return_trap

    printf 'pull output\n' > "$git_log"
    trap 'printf "outer return trap\n"' RETURN

    bats_run __base_bash_libs_git_update_repo_finish__ "$git_log" false 0
    return_trap="$(trap -p RETURN)"
    trap - RETURN

    [ "$status" -eq 0 ]
    [[ "$return_trap" == *"outer return trap"* ]]
    [ ! -e "$git_log" ]
}

@test "__base_bash_libs_git_update_repo_finish__ unregisters removed temp logs" {
    local git_log="$TEST_TMPDIR/git.log"
    local unregister_file="$TEST_TMPDIR/unregistered-paths.txt"

    printf 'pull output\n' > "$git_log"
    eval "$(declare -f base_std_unregister_cleanup_path | sed '1s/base_std_unregister_cleanup_path/__orig_std_unregister_cleanup_path/')"
    base_std_unregister_cleanup_path() {
        printf '%s\n' "$@" >> "$unregister_file"
        __orig_std_unregister_cleanup_path "$@"
    }

    __base_bash_libs_git_update_repo_finish__ "$git_log" false 0
    unset -f base_std_unregister_cleanup_path __orig_std_unregister_cleanup_path

    [ "$(cat "$unregister_file")" = "$git_log" ]
    [ ! -e "$git_log" ]
}

@test "base_git_update_repo reports captured submodule diagnostics" {
    local repo="$TEST_TMPDIR/repo"
    local remote="$TEST_TMPDIR/remote.git"

    create_tracked_repo_with_upstream "$repo" "$remote" "data.txt" "base"
    git() {
        if [[ "${1:-}" == "submodule" ]]; then
            printf 'submodule exploded\n' >&2
            return 1
        fi
        command git "$@"
    }

    capture_command base_git_update_repo "$repo"
    unset -f git

    [ "$status" -eq 1 ]
    [[ "$output" == *"git submodule update failed on repo '$repo'"* ]]
    [[ "$output" == *"submodule exploded"* ]]
    ! compgen -G "$TEST_TMPDIR/git-submodule-log.*" >/dev/null
}

@test "__base_bash_libs_git_pull_with_retry__ retries once after a transient pull failure" {
    local git_log="$TEST_TMPDIR/git.log"
    local pull_count="$TEST_TMPDIR/pull-count"

    printf '0\n' > "$pull_count"
    git() {
        local count

        if [[ "${1:-}" == "pull" ]]; then
            count="$(cat "$pull_count")"
            count=$((count + 1))
            printf '%s\n' "$count" > "$pull_count"
            printf 'pull attempt %s\n' "$count" >&2
            [[ "$count" -ge 2 ]]
            return $?
        fi
        command git "$@"
    }

    bats_run __base_bash_libs_git_pull_with_retry__ "$git_log"
    unset -f git

    [ "$status" -eq 0 ]
    [ "$(cat "$pull_count")" = "2" ]
    [[ "$output" == *"git pull failed on attempt 1; retrying once."* ]]
    [ "$(cat "$git_log")" = "pull attempt 2" ]
}

@test "__base_bash_libs_git_pull_with_retry__ honors configured max attempts" {
    local git_log="$TEST_TMPDIR/git.log"
    local pull_count="$TEST_TMPDIR/pull-count"

    printf '0\n' > "$pull_count"
    git() {
        local count

        if [[ "${1:-}" == "pull" ]]; then
            count="$(cat "$pull_count")"
            count=$((count + 1))
            printf '%s\n' "$count" > "$pull_count"
            printf 'pull attempt %s\n' "$count" >&2
            [[ "$count" -ge 3 ]]
            return $?
        fi
        command git "$@"
    }

    BASE_BASH_LIBS_GIT_PULL_MAX_ATTEMPTS=3 bats_run __base_bash_libs_git_pull_with_retry__ "$git_log"
    unset -f git

    [ "$status" -eq 0 ]
    [ "$(cat "$pull_count")" = "3" ]
    [[ "$output" == *"git pull failed on attempt 2; retrying (attempt 3 of 3)."* ]]
    [ "$(cat "$git_log")" = "pull attempt 3" ]
}

@test "__base_bash_libs_git_pull_with_retry__ falls back for invalid configured max attempts" {
    local git_log="$TEST_TMPDIR/git.log"
    local max_attempts
    local pull_count="$TEST_TMPDIR/pull-count"

    git() {
        local count

        if [[ "${1:-}" == "pull" ]]; then
            count="$(cat "$pull_count")"
            count=$((count + 1))
            printf '%s\n' "$count" > "$pull_count"
            printf 'pull attempt %s\n' "$count" >&2
            [[ "$count" -ge 2 ]]
            return $?
        fi
        command git "$@"
    }

    for max_attempts in abc 0 -1; do
        printf '0\n' > "$pull_count"
        : > "$git_log"

        BASE_BASH_LIBS_GIT_PULL_MAX_ATTEMPTS="$max_attempts" bats_run __base_bash_libs_git_pull_with_retry__ "$git_log"

        [ "$status" -eq 0 ]
        [ "$(cat "$pull_count")" = "2" ]
        [[ "$output" == *"BASE_BASH_LIBS_GIT_PULL_MAX_ATTEMPTS must be a positive integer; using 2."* ]]
        [[ "$output" == *"git pull failed on attempt 1; retrying once."* ]]
        [ "$(cat "$git_log")" = "pull attempt 2" ]
    done
    unset -f git
}

@test "__base_bash_libs_git_pull_with_retry__ fails after two pull attempts" {
    local git_log="$TEST_TMPDIR/git.log"
    local pull_count="$TEST_TMPDIR/pull-count"

    printf '0\n' > "$pull_count"
    git() {
        local count

        if [[ "${1:-}" == "pull" ]]; then
            count="$(cat "$pull_count")"
            count=$((count + 1))
            printf '%s\n' "$count" > "$pull_count"
            printf 'pull attempt %s\n' "$count" >&2
            return 1
        fi
        command git "$@"
    }

    bats_run __base_bash_libs_git_pull_with_retry__ "$git_log"
    unset -f git

    [ "$status" -eq 1 ]
    [ "$(cat "$pull_count")" = "2" ]
    [[ "$output" == *"git pull failed on attempt 1; retrying once."* ]]
    [ "$(cat "$git_log")" = "pull attempt 2" ]
}

@test "base_git_check_script_up_to_date reports success for an up-to-date tracked script" {
    local repo="$TEST_TMPDIR/repo"
    local remote="$TEST_TMPDIR/remote.git"
    local script_path="$repo/scripts/tool.sh"

    create_tracked_repo_with_upstream "$repo" "$remote" "scripts/tool.sh" "#!/usr/bin/env bash"

    bats_run base_git_check_script_up_to_date "$script_path"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Repository is up to date with origin/main."* ]]
}

@test "base_git_check_script_up_to_date uses local remote-tracking refs by default" {
    local other="$TEST_TMPDIR/other"
    local repo="$TEST_TMPDIR/repo"
    local remote="$TEST_TMPDIR/remote.git"
    local script_path="$repo/scripts/tool.sh"

    create_tracked_repo_with_upstream "$repo" "$remote" "scripts/tool.sh" "#!/usr/bin/env bash"
    git clone "$remote" "$other" >/dev/null 2>&1
    git -C "$other" config user.name "Bats Test"
    git -C "$other" config user.email "bats@example.com"
    printf 'echo remote\n' >> "$other/scripts/tool.sh"
    git -C "$other" add scripts/tool.sh
    git -C "$other" commit -m "Update remote script" >/dev/null 2>&1
    git -C "$other" push origin main >/dev/null 2>&1

    bats_run base_git_check_script_up_to_date "$script_path"

    [ "$status" -eq 0 ]
    [[ "$output" != *"Using local remote-tracking refs"* ]]
    [[ "$output" == *"Repository is up to date with origin/main."* ]]
}

@test "base_git_check_script_up_to_date reports local remote-tracking refs at debug level" {
    local repo="$TEST_TMPDIR/repo"
    local remote="$TEST_TMPDIR/remote.git"
    local script_path="$repo/scripts/tool.sh"

    create_tracked_repo_with_upstream "$repo" "$remote" "scripts/tool.sh" "#!/usr/bin/env bash"
    base_std_set_log_level DEBUG
    base_std_set_log_category_level -l base_bash_libs.git DEBUG

    bats_run base_git_check_script_up_to_date "$script_path"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Using local remote-tracking refs; pass --fetch for a live remote check."* ]]
    [[ "$output" == *"Repository is up to date with origin/main."* ]]
}

@test "base_git_check_script_up_to_date fetches before comparing when requested" {
    local other="$TEST_TMPDIR/other"
    local repo="$TEST_TMPDIR/repo"
    local remote="$TEST_TMPDIR/remote.git"
    local script_path="$repo/scripts/tool.sh"

    create_tracked_repo_with_upstream "$repo" "$remote" "scripts/tool.sh" "#!/usr/bin/env bash"
    git clone "$remote" "$other" >/dev/null 2>&1
    git -C "$other" config user.name "Bats Test"
    git -C "$other" config user.email "bats@example.com"
    printf 'echo remote\n' >> "$other/scripts/tool.sh"
    git -C "$other" add scripts/tool.sh
    git -C "$other" commit -m "Update remote script" >/dev/null 2>&1
    git -C "$other" push origin main >/dev/null 2>&1

    bats_run base_git_check_script_up_to_date --fetch "$script_path"

    [ "$status" -eq 4 ]
    [[ "$output" == *"Fetched upstream state before latest-version check."* ]]
    [[ "$output" == *"Repository is 1 commit(s) behind origin/main"* ]]
}

@test "base_git_check_script_up_to_date returns 3 for a dirty tracked script" {
    local repo="$TEST_TMPDIR/repo"
    local remote="$TEST_TMPDIR/remote.git"
    local script_path="$repo/scripts/tool.sh"

    create_tracked_repo_with_upstream "$repo" "$remote" "scripts/tool.sh" "#!/usr/bin/env bash"
    printf 'echo dirty\n' >> "$script_path"

    bats_run base_git_check_script_up_to_date "$script_path"

    [ "$status" -eq 3 ]
    [[ "$output" == *"has local modifications"* ]]
}

@test "base_git_check_script_up_to_date returns 3 when a script is both behind and dirty" {
    local other="$TEST_TMPDIR/other"
    local repo="$TEST_TMPDIR/repo"
    local remote="$TEST_TMPDIR/remote.git"
    local script_path="$repo/scripts/tool.sh"

    create_tracked_repo_with_upstream "$repo" "$remote" "scripts/tool.sh" "#!/usr/bin/env bash"
    git clone "$remote" "$other" >/dev/null 2>&1
    git -C "$other" config user.name "Bats Test"
    git -C "$other" config user.email "bats@example.com"
    printf 'echo remote\n' >> "$other/scripts/tool.sh"
    git -C "$other" add scripts/tool.sh
    git -C "$other" commit -m "Update remote script" >/dev/null 2>&1
    git -C "$other" push origin main >/dev/null 2>&1
    printf 'echo dirty\n' >> "$script_path"

    bats_run base_git_check_script_up_to_date --fetch "$script_path"

    [ "$status" -eq 3 ]
    [[ "$output" == *"has local modifications"* ]]
    [[ "$output" == *"Repository is 1 commit(s) behind origin/main"* ]]
}

@test "base_git_check_script_up_to_date preserves dirty status when no upstream exists" {
    local repo="$TEST_TMPDIR/repo"
    local script_path="$repo/scripts/tool.sh"

    init_git_repo "$repo"
    mkdir -p "$repo/scripts"
    printf '#!/usr/bin/env bash\n' > "$script_path"
    commit_all "$repo" "Initial script"
    printf 'echo dirty\n' >> "$script_path"

    bats_run base_git_check_script_up_to_date "$script_path"

    [ "$status" -eq 3 ]
    [[ "$output" == *"has local modifications"* ]]
    [[ "$output" == *"No upstream branch configured"* ]]
    [[ "$output" != *"up to date"* ]]
}

@test "base_git_check_script_up_to_date reports a clean missing-upstream skip explicitly" {
    local repo="$TEST_TMPDIR/repo"
    local script_path="$repo/scripts/tool.sh"

    init_git_repo "$repo"
    mkdir -p "$repo/scripts"
    printf '#!/usr/bin/env bash\n' > "$script_path"
    commit_all "$repo" "Initial script"

    bats_run base_git_check_script_up_to_date "$script_path"

    [ "$status" -eq 0 ]
    [[ "$output" == *"No upstream branch configured"* ]]
    [[ "$output" != *"up to date"* ]]
}

@test "base_git_check_script_up_to_date reports detached HEAD without claiming freshness" {
    local repo="$TEST_TMPDIR/repo"
    local remote="$TEST_TMPDIR/remote.git"
    local script_path="$repo/scripts/tool.sh"

    create_tracked_repo_with_upstream "$repo" "$remote" "scripts/tool.sh" "#!/usr/bin/env bash"
    git -C "$repo" checkout --detach HEAD >/dev/null 2>&1

    bats_run base_git_check_script_up_to_date "$script_path"

    [ "$status" -eq 0 ]
    [[ "$output" == *"detached HEAD state"* ]]
    [[ "$output" != *"up to date"* ]]
}

@test "base_git_check_script_up_to_date preserves dirty status in detached HEAD" {
    local repo="$TEST_TMPDIR/repo"
    local remote="$TEST_TMPDIR/remote.git"
    local script_path="$repo/scripts/tool.sh"

    create_tracked_repo_with_upstream "$repo" "$remote" "scripts/tool.sh" "#!/usr/bin/env bash"
    git -C "$repo" checkout --detach HEAD >/dev/null 2>&1
    printf 'echo dirty\n' >> "$script_path"

    bats_run base_git_check_script_up_to_date "$script_path"

    [ "$status" -eq 3 ]
    [[ "$output" == *"has local modifications"* ]]
    [[ "$output" == *"detached HEAD state"* ]]
}

@test "base_git_check_script_up_to_date reports untracked scripts as an explicit skip" {
    local repo="$TEST_TMPDIR/repo"
    local script_path="$repo/scripts/tool.sh"

    init_git_repo "$repo"
    mkdir -p "$repo/scripts"
    printf 'tracked\n' > "$repo/README"
    commit_all "$repo" "Initial file"
    printf '#!/usr/bin/env bash\n' > "$script_path"

    bats_run base_git_check_script_up_to_date "$script_path"

    [ "$status" -eq 0 ]
    [[ "$output" == *"is not tracked in git"* ]]
    [[ "$output" != *"up to date"* ]]
}

@test "base_git_check_script_up_to_date reports non-repository paths as an explicit skip" {
    local repo="$TEST_TMPDIR/not-a-repo"
    local script_path="$repo/scripts/tool.sh"

    mkdir -p "$(dirname "$script_path")"
    printf '#!/usr/bin/env bash\n' > "$script_path"

    bats_run base_git_check_script_up_to_date "$script_path"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Not in a Git repo"* ]]
    [[ "$output" != *"up to date"* ]]
}

@test "base_git_check_script_up_to_date distinguishes a repository ahead of upstream" {
    local repo="$TEST_TMPDIR/repo"
    local remote="$TEST_TMPDIR/remote.git"
    local script_path="$repo/scripts/tool.sh"

    create_tracked_repo_with_upstream "$repo" "$remote" "scripts/tool.sh" "#!/usr/bin/env bash"
    printf 'echo local\n' >> "$script_path"
    git -C "$repo" add scripts/tool.sh
    git -C "$repo" commit -m "Local update" >/dev/null 2>&1

    bats_run base_git_check_script_up_to_date "$script_path"

    [ "$status" -eq 0 ]
    [[ "$output" == *"ahead of origin/main"* ]]
    [[ "$output" != *"up to date"* ]]
}

@test "base_git_check_script_up_to_date returns a distinct status for divergence" {
    local other="$TEST_TMPDIR/other"
    local repo="$TEST_TMPDIR/repo"
    local remote="$TEST_TMPDIR/remote.git"
    local script_path="$repo/scripts/tool.sh"

    create_tracked_repo_with_upstream "$repo" "$remote" "scripts/tool.sh" "#!/usr/bin/env bash"
    git clone "$remote" "$other" >/dev/null 2>&1
    git -C "$other" config user.name "Bats Test"
    git -C "$other" config user.email "bats@example.com"
    printf 'echo remote\n' >> "$other/scripts/tool.sh"
    git -C "$other" add scripts/tool.sh
    git -C "$other" commit -m "Remote update" >/dev/null 2>&1
    git -C "$other" push origin main >/dev/null 2>&1
    git -C "$repo" fetch origin >/dev/null 2>&1
    printf 'echo local\n' >> "$script_path"
    git -C "$repo" add scripts/tool.sh
    git -C "$repo" commit -m "Local update" >/dev/null 2>&1

    bats_run base_git_check_script_up_to_date "$script_path"

    [ "$status" -eq 5 ]
    [[ "$output" == *"has diverged from origin/main"* ]]
    [[ "$output" != *"up to date"* ]]
}

@test "base_git_check_script_up_to_date fails closed when fetch fails" {
    local repo="$TEST_TMPDIR/repo"
    local remote="$TEST_TMPDIR/remote.git"
    local script_path="$repo/scripts/tool.sh"

    create_tracked_repo_with_upstream "$repo" "$remote" "scripts/tool.sh" "#!/usr/bin/env bash"
    git() {
        if [[ "${1:-}" == "-C" && "${3:-}" == "fetch" ]]; then
            printf 'network unavailable\n' >&2
            return 1
        fi
        command git "$@"
    }

    bats_run base_git_check_script_up_to_date --fetch "$script_path"
    unset -f git

    [ "$status" -eq 1 ]
    [[ "$output" == *"freshness is unknown"* ]]
    [[ "$output" != *"up to date"* ]]
}

@test "base_git_check_script_up_to_date fails closed when rev-list fails" {
    local repo="$TEST_TMPDIR/repo"
    local remote="$TEST_TMPDIR/remote.git"
    local script_path="$repo/scripts/tool.sh"

    create_tracked_repo_with_upstream "$repo" "$remote" "scripts/tool.sh" "#!/usr/bin/env bash"
    git() {
        if [[ "${1:-}" == "-C" && "${3:-}" == "rev-list" ]]; then
            printf 'comparison unavailable\n' >&2
            return 2
        fi
        command git "$@"
    }

    bats_run base_git_check_script_up_to_date "$script_path"
    unset -f git

    [ "$status" -eq 1 ]
    [[ "$output" == *"freshness is unknown"* ]]
    [[ "$output" != *"up to date"* ]]
}

@test "base_git_check_script_up_to_date reports repository discovery failures" {
    local repo="$TEST_TMPDIR/repo"
    local remote="$TEST_TMPDIR/remote.git"
    local script_path="$repo/scripts/tool.sh"

    create_tracked_repo_with_upstream "$repo" "$remote" "scripts/tool.sh" "#!/usr/bin/env bash"
    git() {
        if [[ "${1:-}" == "-C" && "${3:-}" == "rev-parse" &&
            "${4:-}" == "--is-inside-work-tree" ]]; then
            printf 'fatal: repository metadata unavailable\n' >&2
            return 2
        fi
        command git "$@"
    }

    bats_run base_git_check_script_up_to_date "$script_path"
    unset -f git

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unable to discover the Git repository"* ]]
    [[ "$output" != *"up to date"* ]]
}

@test "base_git_check_script_up_to_date reports diff inspection failures" {
    local repo="$TEST_TMPDIR/repo"
    local remote="$TEST_TMPDIR/remote.git"
    local script_path="$repo/scripts/tool.sh"

    create_tracked_repo_with_upstream "$repo" "$remote" "scripts/tool.sh" "#!/usr/bin/env bash"
    git() {
        if [[ "${1:-}" == "-C" && "${3:-}" == "diff" && "${4:-}" == "--quiet" ]]; then
            printf 'permission denied\n' >&2
            return 2
        fi
        command git "$@"
    }

    bats_run base_git_check_script_up_to_date "$script_path"
    unset -f git

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unable to inspect working-tree changes"* ]]
    [[ "$output" != *"up to date"* ]]
}

@test "base_git_check_script_up_to_date preserves statuses under caller shell options" {
    local mode
    local repo="$TEST_TMPDIR/repo"
    local script_path="$repo/scripts/tool.sh"

    init_git_repo "$repo"
    mkdir -p "$repo/scripts"
    printf '#!/usr/bin/env bash\n' > "$script_path"
    commit_all "$repo" "Initial script"
    printf 'echo dirty\n' >> "$script_path"

    for mode in off e u p eu ep up eup; do
        bats_run "$BASH" -c '
            mode="$1"
            case "$mode" in *e*) set -e ;; esac
            case "$mode" in *u*) set -u ;; esac
            case "$mode" in *p*) set -o pipefail ;; esac
            source "$2"
            declare -a app_args=()
            base_init app_args --
            source "$3"
            base_git_check_script_up_to_date "$4"
        ' bash "$mode" "$BASE_BASH_DIR/std/lib_std.sh" "$BASE_BASH_DIR/git/lib_git.sh" "$script_path"

        [ "$status" -eq 3 ]
        [[ "$output" != *"unbound variable"* ]]
    done
}
