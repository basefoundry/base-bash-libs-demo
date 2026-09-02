# Release Process

This repository uses the Base release contract. The machine-readable release
metadata lives in `base_manifest.yaml`; the guarded `basectl release`
commands use that contract for readiness checks, notes, tags, and GitHub
Releases.

## Standard Sequence

1. Create or choose a release issue and keep its Project metadata current.
2. Create a release-preparation branch and dedicated worktree from
   `origin/main`.
3. Update `VERSION`, the README release reference, and `CHANGELOG.md`.
   Keep ordinary pull requests under `[Unreleased]`; only release-preparation
   work changes the published version.
4. Run the repository validation command, `git diff --check`, and any package
   or integration checks required by this repository.
5. Open and merge the release-preparation pull request.
6. Sync local `main`, then inspect the release:

   ```bash
   basectl release check --version X.Y.Z
   basectl release plan --version X.Y.Z
   basectl release notes --version X.Y.Z
   basectl release publish --version X.Y.Z --dry-run
   ```

7. Publish only after the checks pass. Use `--yes` only from a trusted
   non-interactive release shell:

   ```bash
   basectl release publish --version X.Y.Z --yes
   ```

8. Verify the annotated tag and GitHub Release for `basefoundry/base-bash-libs-demo`.
9. Complete every declared downstream handoff. For Homebrew, update the tap
   formula to the published archive and checksum, run the formula tests and
   audit, publish required bottles, and verify install and upgrade paths. If a
   downstream repository pins this project by commit, update and validate that
   pin after the release.
10. Record the release and downstream URLs on the release issue, then remove
    the release worktree and merged branches when safe.

## Repository Contract

- Project: `base-bash-libs-demo`
- GitHub repository: `basefoundry/base-bash-libs-demo`
- Version file: `VERSION`
- Changelog: `CHANGELOG.md`
- Tag prefix: `v`

Do not publish a release when the repository is dirty, the version metadata is
inconsistent, the changelog section is missing, or a required downstream handoff
has not been identified.
