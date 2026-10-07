# Framework compatibility and pin updates

Beacon has two deliberately separate dependency paths:

- Normal execution uses the committed, verified package in
  `vendor/base-bash-libs` and the identity in `base-bash-libs.lock`.
- Candidate validation uses an explicit release tag or full commit without
  changing the committed package.

The separation prevents a successful experiment from silently changing what a
fresh clone runs.

## Validate a candidate locally

Check out the candidate into a temporary directory and pass its package root:

```bash
git clone https://github.com/basefoundry/base-bash-libs.git /tmp/base-bash-candidate
git -C /tmp/base-bash-candidate checkout --detach <full-commit>
./tests/candidate-smoke.sh /tmp/base-bash-candidate
```

The script runs Beacon's status, plan, dry-run collection, real collection, and
manifest verification through the candidate launcher and public library root.
It does not modify `vendor/base-bash-libs` or `base-bash-libs.lock`.

The `Framework Compatibility` workflow performs the same check on Ubuntu and
macOS. Its matrix defaults to the immutable `v2.0.0` rollback baseline and current
supported `v2.2.0` release. Scheduled runs cover both release rows; a manual
`framework_ref` tests only the explicit release tag or 40-character commit, and
leaving that input blank runs both rows. Branch names are rejected. Release
tags are resolved via their explicit `refs/tags/` namespace (including
annotated-tag peeling), and the checkout always uses the resulting full commit.
A version-shaped branch is never accepted as a candidate.

### Canary checks

The canary checks producer status independently of output, quiet stderr,
configuration precedence, success/failure/TERM cleanup, and dry-run no-write
behavior. Its temporary directory is removed on success and failure. Synthetic
launchers returning 42 after valid output prove that the canary fails closed.

## Update the committed pin

Use a reviewed dependency-update issue and pull request:

1. Select a published release and resolve its tag to a full commit.
2. Download its canonical archive, checksum manifest, provenance, and SPDX
   SBOM into a temporary directory.
3. Verify every downloaded release asset against the checksum manifest before
   extracting anything.
4. Stage the complete extracted bundle outside `vendor/base-bash-libs` and run
   its `MANIFEST.sha256` verification.
5. Replace the vendor directory as one reviewed change. Update
   `base-bash-libs.lock`, `vendor/evidence`, and `CHANGELOG.md` together.
6. Run `./scripts/verify-vendor`, `./tests/validate.sh`, and the hosted candidate
   matrix before merging.

Never mix modules from different packages, use an automatic GitHub tag archive
in place of the canonical release asset, or update only the human-readable
version.

## Roll back

Revert the complete dependency-update pull request so the vendor tree, lock,
release evidence, and changelog move back together. Run the same local and
hosted gates against the restored pin. Do not repair a failed update by copying
individual library files from an older package.
The committed vendor pin is v2.2.0. Keep the v2.0.0 row as the rollback
baseline, and advance the current-release row deliberately when a new supported
release is adopted for compatibility testing.
