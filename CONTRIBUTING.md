# Contributing to base-bash-libs-demo

Thank you for improving this project.

## Workflow

1. Create or choose a GitHub issue before starting implementation work.
2. Use exactly one standard issue category label: `bug`, `enhancement`,
   `documentation`, `ci`, or `security`.
3. Create an issue-backed branch:

   ```text
   <category>/<issue>-<YYYYMMDD>-<slug>
   ```

   The category prefix must match the issue's single standard category label.
   This branch shape is tool-independent; `feat/`, `agent/`, `codex/`, and
   bare issue-number prefixes are invalid.

4. Use a dedicated Git worktree for each pull request so the main checkout can
   stay on the default branch:

   ```bash
   git fetch origin
   git worktree add -b <branch> ../base-bash-libs-demo-worktrees/<slug> origin/<default-branch>
   ```

5. Keep the pull request scoped to the issue and link it with
   `Fixes #<issue>` or `Closes #<issue>` when merge should close the issue.
6. Run the project checks before opening or updating a pull request.
7. Update `CHANGELOG.md` only for notable user-visible or release-worthy
   changes.
8. After merge, sync the default branch, remove the worktree, and delete merged
   local and remote branches when safe:

   ```bash
   git pull --ff-only origin <default-branch>
   git worktree remove ../base-bash-libs-demo-worktrees/<slug>
   git branch -d <branch>
   git push origin --delete <branch>
   ```

Useful commands:

```bash
basectl check base-bash-libs-demo
basectl doctor base-bash-libs-demo
basectl setup base-bash-libs-demo
basectl test base-bash-libs-demo
```

The repository manifest declares the pinned artifact-test dependency in
`test.requirements`. Run setup before testing so the SPDX validator is installed
in the project environment; direct test-script invocations must either use that
interpreter or set `SPDX_VALIDATOR_PYTHON` explicitly.

Because `test.requirements` contributes to the manifest trust identity, adding or
changing that file makes existing `basectl trust allow` approvals stale. Review
the new dependency and re-run the suggested trust approval command before
running `basectl test`.

Before merging release-preparation work, confirm the exact
`Required consumer and artifact validation` aggregate described in
[`docs/ci-required-checks.md`](docs/ci-required-checks.md) is green. It is the
intended repository gate for the pull request; [issue #37](https://github.com/basefoundry/base-bash-libs-demo/issues/37)
tracks enabling it as an enforced required ruleset check after the exact
context is configured and read back.
