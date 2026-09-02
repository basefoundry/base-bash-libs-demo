# `lib_git.sh`

Git helpers for Bash commands that need lightweight repository inspection or update behavior.

## Dependency

Source `lib/bash/std/lib_std.sh` before this library so logging and shared error handling are available.

## Public API

- `base_git_update_repo <repo> [allowed_dirty_path] [expected_branch]`
  Update a repository on its detected default branch, optionally allowing tracked changes in one specific path.
- `base_git_get_current_branch <directory> <result_var>`
  Return the current branch name through a caller-provided variable, or `detached head`.
- `base_git_detect_default_branch <repo> <result_var>`
  Detect a repository's default branch from its remote HEAD and standard local
  fallbacks.
- `base_git_worktree_path_for_branch <branch> [repo]`
  Print the worktree path attached to a local branch.
- `base_git_list_worktree_branches [repo]`
  Print tab-separated worktree path and branch rows.
- `base_git_branch_upstream <repo> <branch>`
  Print the configured upstream ref for a local branch.
- `base_git_branch_merged_to_ref <repo> <branch> <ref>`
  Check whether a local branch is an ancestor of a ref.
- `base_git_list_remote_branches [repo]`
  Print branch names from the `origin` remote.
- `base_git_check_script_up_to_date [--fetch] <script>`
  Check whether a tracked script appears current relative to its configured upstream.

## Internal Helpers

The `__base_bash_libs_git_*__` functions used by `base_git_update_repo` are implementation details
and are not part of the public API. In particular, the path-dirty predicate
checks whether tracked changes stay within an allowed path, while the update
helpers manage branch selection, retries, and cleanup.

## Usage

```bash
source "/absolute/path/to/lib/bash/std/lib_std.sh"
declare -a app_args=()
base_init app_args --source "${BASH_SOURCE[0]}" --
base_std_import git/lib_git.sh

branch=""
base_git_get_current_branch "$PWD" branch
base_std_log_info "Current branch: $branch"
```

## Behavior Notes

- Public functions validate the documented argument count before expanding
  required positional parameters. Usage and contract errors return `2`,
  including when the caller has enabled `nounset`; recoverable Git failures and
  false predicates return `1` unless the function documents a more specific
  status. Extra arguments are rejected unless the signature explicitly accepts
  them.
- The library does not change the caller's `errexit`, `nounset`, `pipefail`,
  `shopt`, `IFS`, `OPTIND`, cwd, umask, traps, or positional parameters.
  Parsing that requires field splitting uses a command-scoped `IFS`, so a
  caller-defined value is preserved.
- `base_git_update_repo` only attempts updates when the checked-out branch is the detected default branch, or an explicit expected branch passed by the caller.
- `base_git_update_repo` retries `git pull --ff-only` twice by default. Set
  `BASE_BASH_LIBS_GIT_PULL_MAX_ATTEMPTS` to a positive integer to change the retry count.
- `base_git_get_current_branch` uses `git -C` so it does not change the caller's
  working directory or directory stack. Missing directories and non-Git
  directories return success with an empty result variable.
- `base_git_update_repo` changes into the target repository while it runs because
  its submodule update sequence depends on repository-relative execution.
- `base_git_update_repo` only treats an allowed dirty path as safe when every tracked
  change stays within that path. Rename records must have both source and
  destination inside the allowed path.
- `base_git_check_script_up_to_date` treats a missing file, unavailable Git executable,
  non-repository path, untracked script, detached HEAD, and missing upstream as
  explicit skip states rather than hard failures. A dirty tracked script still
  returns status `3` when one of those skip states prevents comparison.
- `base_git_check_script_up_to_date <script>` compares `HEAD` with the local remote-tracking upstream ref. It does not fetch by default, so the result reflects the freshness of local refs.
- `base_git_check_script_up_to_date --fetch <script>` runs `git fetch --quiet` first,
  then compares against the refreshed upstream ref. If fetch fails, the helper
  returns status `5`; it never reports freshness from an unverified comparison.

### `base_git_check_script_up_to_date` statuses

| Status | Meaning |
| ---: | --- |
| `0` | Current or ahead of upstream, or an explicit non-error skip state. |
| `1` | Operational failure while discovering metadata, inspecting changes, fetching, or comparing revisions. |
| `2` | Invalid usage or contract. |
| `3` | The tracked script has local modifications. This takes precedence over a successful current, ahead, behind, or diverged comparison, and over documented skip states. |
| `4` | Behind upstream; the script may be stale. |
| `5` | The repository has diverged from upstream. |

Operational failures take precedence over the dirty status because the result
cannot be trusted. Every status is accompanied by an explicit diagnostic, and
failed Git commands never fall through to an “up to date” result.

## Tests

BATS coverage lives in `lib/bash/git/tests/lib_git.bats`.
