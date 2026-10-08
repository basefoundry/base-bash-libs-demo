# Changelog

All notable changes to base-bash-libs-demo will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions are tracked in the repo-root `VERSION` file.

## [Unreleased]

### Documentation

- Added a verified external-consumer walkthrough for the current Base Bash
  release, including checksum/evidence verification, lockfile identity, and
  offline post-preparation execution.

## [0.1.0] - 2026-10-07

### Added

- Initialized the repository with the Base-managed repo baseline.
- Added the Beacon offline support-bundle reference consumer.
- Vendored and independently verified the canonical Base Bash v2.2.0 release.
- Added Ubuntu, minimum Bash 4.2.53, and macOS Homebrew Bash validation.
- Added explicit release/full-commit compatibility checks and a documented,
  atomic framework pin-update and rollback workflow.
- Added an executable five-minute Beacon learning path covering immutable
  package identity, public imports, lifecycle behavior, application policy,
  dry-run safety, verification, and extension boundaries.
- Added deterministic pre-publication failure and interruption scenarios,
  machine-readable cleanup evidence, documented exit statuses, and focused
  lifecycle, automation, and hostile-fixture redaction coverage.
- Added deterministic standalone Beacon archives with checksums, SPDX SBOMs,
  source/framework provenance, cross-platform verification, release notes, and
  rollback guidance without granting publication authority.
- Added a code-linked explanation of the Bash infrastructure Base Bash
  replaces while preserving Beacon's application-owned policy boundaries.
- Added a candid Base Bash adoption guide covering fit, runtime constraints,
  maintenance cost, alternatives, maturity, and independent-evidence limits.
- Added a tested minimal consumer, upstream getting-started links, an ordered
  documentation map, and repository-specific agent workflow guidance.

### Changed

- Documented the repository-specific Project rule that open pull requests stay
  `In Progress`, including the `Ready` and `Done` transitions.
- Added the required consumer-and-artifact aggregate as the explicit release
  preparation merge gate.
- Adopted the published Base Bash v2.2.0 release at commit
  `d8894bf4453e6b6beaa6de7ce2e082497cb236f2`; the lock, vendored package,
  release evidence, compatibility rows, and onboarding docs now agree on that
  immutable framework pin.

### Fixed

- Require the committed Base Bash vendor manifest to exactly match a regular,
  link-free payload inventory before verifying checksums.

- Declare and preflight the pinned SPDX artifact-test dependency so the normal
  Base setup and test path fails early with actionable guidance when it is
  unavailable.

- Resolve compatibility release tags through the explicit tag namespace and
  test the resulting immutable commit instead of trusting version-shaped refs.

- Bind release evidence to exact archive contents and identities; validate archive
  entries before extraction and require explicit trust before executing smoke tests.

- Emit independently validated SPDX 2.3 file and package evidence with SHA1 and SHA256.
- Enforce candidate exit statuses, cleanup and critical contracts; test baseline
  and current supported releases without changing the vendor pin.

- Reserve bundle destinations exclusively to prevent concurrent publication nesting.
- Honor user configuration and scenario precedence without implicit CLI overrides.
- Normalize release timestamps in UTC and test cross-timezone reproducibility.

- Require complete, unique bundle manifests and coherent schema/count metadata.

- Reject links and special files in selected inputs and verified bundles.

### Security

- Hash-locked the SPDX artifact-test dependency and document the trust
  re-approval required when its manifest identity changes.
