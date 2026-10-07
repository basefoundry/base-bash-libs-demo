# Project Workflow

The repository Project follows the issue-backed pull-request workflow.

## Status transitions

- An open issue starts with the normal issue-intake status, `Backlog`.
- Opening, reopening, or preparing a pull request moves its tracked issue to
  `In Progress`.
- This repository intentionally keeps an open pull request in `In Progress`;
  its Project Intake workflow does not use `In Review`. The sibling
  `base-bash-libs` contributor guidance uses `In Review` for open PRs, so do not
  copy that status rule into this Project without changing this repository's
  workflow and its contract tests together.
- Closing a pull request without merging returns the issue to `Ready`.
- Merging a pull request moves the issue to `Done`.

The tracked issue is resolved from the canonical branch name, such as
`ci/47-20261006-sync-project-pr-workflow`. This supports stacked pull requests
whose base is another PR branch rather than `main`.

## Pull-request linkage

The Project Intake workflow explicitly registers the pull request as a closing
reference for the issue. This keeps the Project linked-pull-request field
accurate for stacked PRs; a closing keyword in a PR body alone is not sufficient
when the PR targets an intermediate branch.

The workflow runs in the trusted repository context and only reads the PR
metadata and updates the repository Project. It does not check out or execute
the pull-request branch.

For recovery, maintainers can dispatch Project Intake with either an issue
number or a pull-request number. A pull-request dispatch re-applies the status
and linkage rules to the current PR state.
