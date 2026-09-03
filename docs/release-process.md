# Release Process

This repository uses the Base release contract. The machine-readable release
metadata lives in `base_manifest.yaml`; the guarded `basectl release`
commands use that contract for readiness checks, notes, tags, and GitHub
Releases.

Beacon's version in `VERSION` is independent of the Base Bash version in
`base-bash-libs.lock`. A Beacon release may embed an unchanged framework
release, and a framework pin update does not publish Beacon by itself.

## Standalone Artifact Gate

From the clean release commit, build the four assets without publishing them:

```bash
./scripts/release-artifact build --version X.Y.Z --output /tmp/beacon-release-a
./scripts/release-artifact build --version X.Y.Z --output /tmp/beacon-release-b
diff -r /tmp/beacon-release-a /tmp/beacon-release-b
./scripts/release-artifact verify /tmp/beacon-release-a
```

The directory contains:

- `beacon-vX.Y.Z.tar.gz`, the standalone Beacon application, fixtures, and
  verified vendored Base Bash package;
- `beacon-vX.Y.Z.SHA256SUMS`, covering the archive and both JSON documents;
- `beacon-vX.Y.Z.spdx.json`, recording Beacon and framework package identity;
- `beacon-vX.Y.Z.provenance.json`, binding the archive to the clean Beacon
  source commit and immutable Base Bash commit.

The verifier rejects missing, extra, renamed, or modified evidence assets;
unsafe archive paths or symlinks; malformed identity; vendor drift; and failed
Beacon status, dry-run, collection, or verification smoke checks. CI builds the
set twice and verifies it on Ubuntu and macOS. The build and verifier are local
preparation tools: they never create a tag, GitHub Release, or network request.

## Standard Sequence

1. Create or choose a release issue and keep its Project metadata current.
2. Create a release-preparation branch and dedicated worktree from
   `origin/main`.
3. Update `VERSION`, the README release reference, and `CHANGELOG.md`.
   Keep ordinary pull requests under `[Unreleased]`; only release-preparation
   work changes the published version.
4. Run the repository validation command, `git diff --check`, and the
   standalone artifact gate above. Review the generated SBOM, provenance, and
   the release notes prepared from `docs/release-notes-template.md`.
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

If verification fails before publication, discard the generated directory,
fix the release-preparation branch, and rebuild from a clean commit. Never
replace an asset on an existing tag. After publication, roll downstream users
back to the preceding immutable release and publish a corrected patch release;
do not rewrite the tag or its assets.

## Repository Contract

- Project: `base-bash-libs-demo`
- GitHub repository: `basefoundry/base-bash-libs-demo`
- Version file: `VERSION`
- Changelog: `CHANGELOG.md`
- Tag prefix: `v`

Do not publish a release when the repository is dirty, the version metadata is
inconsistent, the changelog section is missing, or a required downstream handoff
has not been identified.

Building or verifying artifacts is not authorization to publish them. Keep
`basectl release publish` behind the explicit approval in step 7.
