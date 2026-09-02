# base-bash-libs-demo

Reference consumer and learning application for
[`base-bash-libs`](https://github.com/basefoundry/base-bash-libs).

This repository contains Beacon, a small offline support-bundle collector. It
shows how a real Bash application can consume the released Base Bash v2 API
while keeping its own commands, fixture schema, collection policy, redaction
rules, and user-facing messages.

Beacon does not require Base, Docker, cloud credentials, or network access at
runtime. The verified `base-bash-libs` v2.0.0 release bundle is committed under
`vendor/base-bash-libs`, so a fresh clone has everything it needs.

## Quick start

Use Bash 4.2 or newer. On macOS, install a supported Bash with Homebrew; the
vendored launcher discovers it automatically.

```bash
./bin/beacon --help
./bin/beacon status
./bin/beacon plan
./bin/beacon collect --dry-run
./bin/beacon collect
./bin/beacon verify
```

The default input is the deterministic fixture in `fixtures/workspace`. Real
collection writes only to `.beacon-output/beacon-support`. Remove that
directory before repeating the real collection, or select an unused destination:

```bash
./bin/beacon collect --output /tmp/my-beacon-bundle
./bin/beacon verify --output /tmp/my-beacon-bundle
```

`collect --dry-run` creates neither the output directory nor temporary
application state beneath it.

## What Beacon demonstrates

- `beacon status` reports fixture readiness, the consumer Git branch, and the
  immutable framework version, commit, dirty state, and provenance.
- `beacon plan` lists the relative inputs, output location, and redaction
  policy without changing the filesystem.
- `beacon collect` copies selected fixture files into a support directory,
  replaces values whose keys contain `TOKEN`, `SECRET`, or `PASSWORD`, and
  writes a checksum manifest without absolute developer-machine paths.
- `beacon verify` checks every manifest entry and confirms that configured
  fixture secrets are absent from the collected payload.
- `--workspace`, `--output`, `--config`, `--user-config`, `--quiet`,
  `--verbose`, `--dry-run`, and `--non-interactive` compose application policy
  with the Base Bash lifecycle.

## Framework boundary

Base Bash owns argument parsing, standard application options, typed
configuration, lifecycle hooks, logging, cleanup, safe filesystem helpers,
Git inspection, and immutable package identity. Beacon owns which files form a
support bundle, which fixture keys are sensitive, the manifest format, and the
meaning of `status`, `plan`, `collect`, and `verify`.

The application imports only modules listed in the released public v2 API. It
does not source a sibling checkout or inspect unpublished framework functions.

## Immutable dependency

[`base-bash-libs.lock`](base-bash-libs.lock) records the human-readable
version, full release commit, canonical asset digest, and bundle-manifest
digest. `vendor/evidence` preserves the release checksum manifest, provenance,
and SPDX SBOM. Verify the committed package independently:

```bash
./scripts/verify-vendor
```

The default application path is completely offline. Downloading or changing a
framework release belongs to a reviewed dependency-update change, not runtime.

## Development

Install BATS and ShellCheck, then run the full gate:

```bash
./tests/validate.sh
```

CI runs the full suite on Ubuntu and macOS with Homebrew Bash, plus a
network-disabled smoke test on the exact minimum Bash 4.2.53 runtime.

## Repository shape

- `bin/beacon` selects the committed Base Bash launcher.
- `lib/beacon.sh` contains the consumer-owned CLI and application policy.
- `fixtures/workspace` provides deterministic, intentionally fake inputs.
- `vendor/base-bash-libs` is the verified v2.0.0 release bundle.
- `tests/beacon.bats` exercises the installed application boundary.
- `tests/validate.sh` verifies the vendor, shell quality, tests, and smoke path.

## Base

This repository is managed by [Base](https://github.com/basefoundry/base).

Common commands:

```bash
basectl setup base-bash-libs-demo
basectl check base-bash-libs-demo
basectl doctor base-bash-libs-demo
basectl test base-bash-libs-demo
```

Base manages this repository's development workflow. It is not a Beacon or
Base Bash runtime dependency.
