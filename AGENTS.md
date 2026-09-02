# Agent Instructions for base-bash-libs-demo

Use this file for repository-local agent guidance. User instructions still take
precedence over this baseline.

## Workflow

1. Create or choose a GitHub issue before implementation work.
2. Use exactly one standard issue category label: `bug`, `enhancement`,
   `documentation`, `ci`, or `security`.
3. Branch from the issue with:

   ```text
   <category>/<issue>-<YYYYMMDD>-<slug>
   ```

   The category prefix must match the issue's single standard category label.
   This branch shape is tool-independent; `feat/`, `agent/`, `codex/`, and
   bare issue-number prefixes are invalid.

4. Use a dedicated worktree for each pull request:

   ```bash
   git fetch origin
   git worktree add -b <branch> ../base-bash-libs-demo-worktrees/<slug> origin/main
   ```

5. Keep the pull request scoped to the issue and link it with
   `Fixes #<issue>` or `Closes #<issue>` when merge should close the issue.
6. Preserve existing user changes. Do not overwrite project-owned files unless
   the user explicitly asks for that edit.

## Validation

Run the project validation command before publishing changes:

   ```bash
   ./tests/validate.sh
   ```

Also run narrower tests for the files changed when available.

## Documentation

Update docs when behavior, commands, setup, or workflow expectations change.
Update `CHANGELOG.md` only for notable user-visible or release-worthy changes.

## Finish

After merge, sync main, remove the worktree, and delete merged local
and remote branches when safe.
