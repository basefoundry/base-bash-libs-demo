# Beacon in five minutes

This tutorial starts from a fresh clone and exercises Beacon entirely offline.
It reads the committed fixture workspace, writes only beneath a temporary
directory, and removes that directory when it finishes. Use Bash 4.2 or newer;
on macOS, `bin/beacon` discovers a supported Homebrew Bash automatically.

Run the following block from the repository root. The repository test suite
extracts and executes this exact block, so the walkthrough cannot silently
drift away from the application.

<!-- BEGIN RUNNABLE TUTORIAL -->
```bash
set -eu

tutorial_root="$(mktemp -d "${TMPDIR:-/tmp}/beacon-tutorial.XXXXXX")"
trap 'rm -rf "$tutorial_root"' EXIT
tutorial_output="$tutorial_root/beacon-support"

./bin/beacon status | tee "$tutorial_root/status.txt"
grep -F 'workspace_ready=yes' "$tutorial_root/status.txt"
grep -F 'framework_version=2.0.0' "$tutorial_root/status.txt"

./bin/beacon plan --output "$tutorial_output" | tee "$tutorial_root/plan.txt"
grep -F 'include=config/app.env' "$tutorial_root/plan.txt"
grep -F 'redact_keys=TOKEN,SECRET,PASSWORD' "$tutorial_root/plan.txt"

./bin/beacon collect --dry-run --output "$tutorial_output"
test ! -e "$tutorial_output"

./bin/beacon collect --output "$tutorial_output"
./bin/beacon verify --output "$tutorial_output" | tee "$tutorial_root/verify.txt"
grep -F 'verified=true' "$tutorial_root/verify.txt"
grep -R -F '[REDACTED]' "$tutorial_output/files"
if grep -R -F 'demo-token-123' "$tutorial_output"; then exit 1; fi

./scripts/verify-vendor
```
<!-- END RUNNABLE TUTORIAL -->

## What just happened

1. `status` checked the consumer fixture and reported the immutable Base Bash
   release identity. The version, full commit, artifact provenance, and
   checksums come from the committed package and `base-bash-libs.lock`, not an
   ambient framework checkout.
2. `plan` resolved Beacon's application configuration and listed the selected
   inputs and redaction policy without changing the filesystem.
3. `collect --dry-run` exercised Base Bash's standard dry-run lifecycle while
   Beacon proved that it created no output.
4. `collect` staged the selected files, applied Beacon's redaction rules,
   generated a checksum manifest, and moved the completed bundle into place.
5. `verify` checked every manifest entry and confirmed that configured fixture
   secrets were absent. The final vendor check independently revalidated the
   committed framework package and release evidence.

## The framework and application boundary

Beacon imports only the released `cli`, `app`, `file`, `git`, `str`, and `list`
modules through the Base Bash launcher. Base Bash owns CLI parsing, typed
configuration, lifecycle hooks, logging, cleanup registration, safe filesystem
helpers, Git inspection, and package identity. Beacon owns the input list,
support-bundle layout, sensitive-key policy, manifest meaning, and user-facing
commands.

That separation is the main extension rule: add domain policy to
`lib/beacon.sh`, but use documented public functions for reusable runtime
behavior. Do not source files beneath another checkout or call underscore-like
implementation helpers.

The corresponding v2.0.0 references are:

- [Public API reference](https://github.com/basefoundry/base-bash-libs/blob/v2.0.0/docs/api-reference.md)
- [CLI model and parsing](https://github.com/basefoundry/base-bash-libs/blob/v2.0.0/lib/bash/cli/README.md)
- [Application configuration and lifecycle](https://github.com/basefoundry/base-bash-libs/blob/v2.0.0/lib/bash/app/README.md)
- [Immutable pinned consumption](https://github.com/basefoundry/base-bash-libs/blob/v2.0.0/docs/pinned-consumption.md)

## Safe experiments

Change only the fake files under `fixtures/workspace`, or pass a copied
workspace with `--workspace`. Use a new `--output` path for each real
collection because Beacon intentionally refuses to overwrite an existing
bundle. Run `./tests/validate.sh` after changing application policy, commands,
fixtures, or documentation.

Beacon never needs Base, cloud credentials, Docker, or access to the user's
home directory. Network access is needed only when a maintainer deliberately
updates the vendored framework pin in a separate reviewed change.
