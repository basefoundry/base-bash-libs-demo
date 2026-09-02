# Single-file distribution contract

Every public sourceable library in `lib/bash/<module>/` has exactly one
canonical implementation file named `lib_<module>.sh`. The file is the source
of truth for consumers, vendored copies, and release artifacts. Contributors
may improve section ordering, private helper naming, README coverage, and
focused BATS tests, but must not split implementation concerns into fragments
that are concatenated or loaded at source time.

## Validate

```bash
scripts/library-bundle check
```

This runs the API manifest contract, verifies that each public library
directory contains one canonical file, rejects source-time implementation
imports, and checks every manifest artifact. Duplicate public symbols and
missing module entries are rejected by the manifest validator.

## Produce and verify a bundle

```bash
scripts/library-bundle bundle /tmp/base-bash-libs-bundle
scripts/library-bundle verify /tmp/base-bash-libs-bundle
```

The bundle is a deterministic directory assembled in sorted manifest order.
It copies complete files without rewriting or concatenating them, records
source version/commit/provenance in `BUNDLE.release`, and records SHA-256
content hashes in `MANIFEST.sha256`. Existing destinations are never silently
overwritten. Consumers can vendor this directory or package it with their
release system; behavior is equivalent because the canonical source files are
unchanged.

The release train packages the verified bundle as the canonical v2 archive
with `scripts/release-artifact`. The same command emits a checksum manifest,
an SPDX 2.3 SBOM, and a reproducibility/provenance statement; downstream
channels must consume that exact archive instead of rebuilding it or using a
mutable source-tree URL.

CI runs the check and bundle tests in addition to the source, vendored, and
consumer contract suites. A stale generated API reference, missing provenance,
hash mismatch, duplicate symbol, or boundary violation fails validation.
