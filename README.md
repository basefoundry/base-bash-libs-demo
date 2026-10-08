# base-bash-libs-demo

Reference consumer and learning application for
[`base-bash-libs`](https://github.com/basefoundry/base-bash-libs).

This repository contains Beacon, a small offline support-bundle collector. It
shows how a real Bash application can consume the released Base Bash v2 API
while keeping its own commands, fixture schema, collection policy, redaction
rules, and user-facing messages.

Beacon does not require Base, Docker, cloud credentials, or network access at
runtime. The verified `base-bash-libs` v2.2.0 release bundle is committed under
`vendor/base-bash-libs`, so a fresh clone has everything it needs. New external
projects should follow the onboarding path for the current v2.2.1 release;
Beacon's committed vendor is intentionally a separate reproducible baseline.

## Start here

- [Base Bash overview](https://github.com/basefoundry/base-bash-libs)
- [Versioned documentation map](https://github.com/basefoundry/base-bash-libs/blob/v2.2.1/docs/README.md)
- [Five-minute v2 quickstart](https://github.com/basefoundry/base-bash-libs/blob/v2.2.1/docs/v2/quickstart.md)
- [Generated public API reference](https://github.com/basefoundry/base-bash-libs/blob/v2.2.1/docs/api-reference.md)
- [Beacon documentation and recommended reading path](docs/README.md)

To move directly from evaluation to a small application, follow
[use Base Bash in your project](docs/use-in-your-project.md). It contains a
copy-pasteable one-command consumer and both vendored and Homebrew launch
paths.

## Why base-bash-libs?

Non-trivial Bash tools repeatedly rebuild the same infrastructure: consistent
commands and help, configuration precedence, temporary-directory cleanup,
signal-safe lifecycle handling, checked filesystem operations, and portable
package identity. Base Bash supplies those reusable contracts so an
application can concentrate on its own policy.

Beacon makes that division concrete. Base Bash declares and runs the CLI,
loads typed configuration, owns cleanup registration, and exposes immutable
framework identity. Beacon decides which support files matter, how their data
must be redacted, and what collection and verification mean. See
[why Base Bash](docs/why-base-bash-libs.md) for the code-level before/after and
the boundaries that remain application-owned. If you are evaluating it for
your own project, read [should I use Base Bash?](docs/should-i-use-base-bash-libs.md)
for prerequisites, adoption costs, alternatives, and maturity signals.

## Quick start

Use Bash 4.2.53 or newer. On macOS, install a supported Bash with Homebrew; the
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

### Expected output

The paths, branch name, framework commit, and timestamps vary by checkout. The
stable lines below are the useful contract to compare with a terminal session:

`./bin/beacon --help` includes:

```text
Offline support-bundle collector
Commands:
  status                 Show fixture and framework readiness
  plan                   Describe bundle inputs and redactions
  collect                Create a redacted support bundle
  verify                 Verify a collected support bundle
```

`./bin/beacon status` reports the consumer and the immutable framework identity:

```text
application=beacon
workspace_ready=yes
selected_files=3
framework_version=<release version>
framework_provenance=release-artifact
```

`./bin/beacon plan` reports the selected inputs and redaction policy without
creating a bundle:

```text
operation=collect
selected_files=3
inputs=config/app.env,logs/app.log,system/info.txt
redact_keys=TOKEN,SECRET,PASSWORD
include=config/app.env
include=logs/app.log
include=system/info.txt
```

`./bin/beacon collect --dry-run` reports the planned operation and does not
write the destination:

```text
dry_run=true
operation=collect
selected_files=3
```

Successful `./bin/beacon collect` reports the bundle and checksum manifest:

```text
bundle=<output path>
manifest=<output path>/MANIFEST.sha256
```

Successful `./bin/beacon verify --output <output path>` reports:

```text
verified=true
files=4
bundle=<output path>
```

On a normal, non-quiet collection, the vendored `file` module may also emit an
`INFO` line while it updates the bundle README section. That line includes a
temporary path and a framework source location, so both are intentionally
environment-specific; it is informational, not a failure. Use `--quiet` when
only the stable machine-readable result is wanted.

## Troubleshooting

### The launcher cannot find a supported Bash

Beacon requires Bash 4.2.53 or newer. On macOS, install the Homebrew Bash
formula and ask Base to diagnose the project setup:

```bash
brew install bash
base-bash check --project .
```

Run the check from this repository. It confirms the launcher and framework
setup without changing Beacon's committed vendor.

### Collection refuses to overwrite an output directory

Collection never overwrites an existing destination. Choose a new path, or
remove only a bundle that you own before retrying:

```bash
./bin/beacon collect --output /tmp/my-beacon-bundle-2
```

### Verification reports a checksum mismatch

The bundle is immutable after collection. If a file under `files/` was edited,
`verify` exits non-zero with `ERROR: Manifest checksum mismatch.` Collect again
to a new destination rather than editing the existing bundle:

```bash
./bin/beacon collect --output /tmp/my-beacon-bundle-fixed
./bin/beacon verify --output /tmp/my-beacon-bundle-fixed
```

For a scenario-driven walkthrough whose commands are exercised by CI, follow
[Beacon in five minutes](docs/five-minute-tutorial.md).

For deterministic success, failure, interruption, cleanup, redaction, and
non-interactive examples, see
[lifecycle and automation scenarios](docs/lifecycle-and-automation.md).

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
- `collect --scenario failure|interrupt` and `--lifecycle-log` provide safe,
  machine-readable evidence for failure and cleanup demonstrations.
- The [bundle format and trust boundary](docs/bundle-format-and-trust-boundary.md)
  explains schema 1, configuration precedence, destination ownership, and the
  filesystem rules that collection and verification enforce.

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

Install BATS and ShellCheck, then let Base install the declared artifact-test
requirement and run the full gate:

```bash
basectl setup base-bash-libs-demo
basectl test base-bash-libs-demo
```

The setup command reads `test.requirements` from `base_manifest.yaml` and
installs the pinned `spdx-tools` validator used by standalone artifact tests.
If you invoke a test script directly, activate that environment or set
`SPDX_VALIDATOR_PYTHON` to its Python interpreter.

CI runs the full suite on Ubuntu and macOS with Homebrew Bash, plus a
network-disabled smoke test on the exact minimum Bash 4.2.53 runtime.

## Standalone release artifacts

Beacon has its own version and release lifecycle, independent of the embedded
Base Bash version. From a clean checkout whose `VERSION` matches the requested
version, build and verify the deterministic four-file artifact set locally:

```bash
release_version=X.Y.Z
release_output=/tmp/beacon-release-$release_version
./scripts/release-artifact build --version "$release_version" --output "$release_output"
./scripts/release-artifact verify "$release_output"
./scripts/release-artifact verify "$release_output" --trusted-smoke
```

The output contains the standalone archive, SHA-256 manifest, SPDX SBOM, and
SLSA-style provenance. Default verification does not execute payload code; the
`--trusted-smoke` option explicitly runs checks from a trusted artifact. Internal
consistency is not proof of publisher authenticity. The archive carries both Beacon source identity and the
distinct vendored framework identity. These commands do not tag, publish, or
use the network; release publication always requires a separate authorized
maintainer action. See the [release process](docs/release-process.md).

## Framework compatibility

The scheduled `Framework Compatibility` workflow tests both the immutable
v2.0.0 rollback baseline and the committed v2.2.0 release on Ubuntu and macOS.
Manual dispatch can test one explicit Base Bash release tag or full commit
without changing Beacon's committed default package. The same black-box
contract is available locally:

```bash
./tests/candidate-smoke.sh /path/to/base-bash-libs-candidate
```

See [framework compatibility and pin updates](docs/framework-updates.md) for
the immutable-input rules, reviewed pin-update procedure, and rollback path.

## Repository shape

- `bin/beacon` selects the committed Base Bash launcher.
- `lib/beacon.sh` contains the consumer-owned CLI and application policy.
- `fixtures/workspace` provides deterministic, intentionally fake inputs.
- `examples/minimal-cli` is the tested smallest runnable CLI consumer.
- `vendor/base-bash-libs` is the verified v2.2.0 release bundle used by the
  committed Beacon baseline.
- `tests/beacon.bats` exercises the installed application boundary.
- `tests/lifecycle.bats` exercises failure, signals, cleanup, automation, and
  hostile synthetic fixture data.
- `tests/docs-examples.sh` executes the exact five-minute tutorial commands.
- `tests/docs-contracts.sh` checks adoption-document links and API evidence.
- `tests/minimal-consumer.sh` runs the starter through the vendored launcher.
- `scripts/release-artifact` builds and verifies standalone release evidence.
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
