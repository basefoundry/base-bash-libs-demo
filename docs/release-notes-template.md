# Beacon vX.Y.Z

Beacon is an offline reference consumer for the released Base Bash v2 API.
Replace every placeholder and review the generated evidence before publishing.

## Highlights

- Describe user-visible Beacon changes.
- State the embedded Base Bash version and full source commit.
- Confirm supported Ubuntu and macOS artifact verification.

## Standalone assets

- `beacon-vX.Y.Z.tar.gz`
- `beacon-vX.Y.Z.SHA256SUMS`
- `beacon-vX.Y.Z.spdx.json`
- `beacon-vX.Y.Z.provenance.json`

The archive contains Beacon, its deterministic fixtures, and the verified
vendored Base Bash package. It does not require Base, a framework checkout,
cloud credentials, or runtime network access.

## Verify

Download all four assets into one directory, then run the matching source
checkout's `scripts/release-artifact verify DIRECTORY`. Confirm that the
reported Beacon and Base Bash versions match this release before execution.

## Upgrade and rollback

- Review Beacon behavior and framework identity independently.
- Never replace assets attached to an existing tag.
- If a published release is defective, restore the previous immutable release
  in downstream automation and publish a new patch version after correction.
