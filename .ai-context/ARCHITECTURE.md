# Architecture

`bin/beacon` starts the vendored framework launcher; `lib/beacon.sh` owns the
application's command model and collection policy. Framework modules provide
CLI parsing, typed configuration, execution, and cleanup. Beacon decides which
fixture files are selected, how secret-valued fields are redacted, and what a
valid bundle contains.

`fixtures/workspace/` is the default deterministic input. `status` reports
readiness, `plan` describes selected files, `collect` creates a bundle, and
`verify` checks the collected manifest. The default destination is
`.beacon-output/beacon-support`; collection refuses an existing destination.
The dry-run path does not create the destination or temporary application state
beneath it. Inputs and bundles reject unsupported links and special files;
these checks do not constitute a concurrent-filesystem sandbox.

Framework distribution and provenance remain under `vendor/` and are checked by
`scripts/verify-vendor`. Consumer packaging and artifact validation are owned by
this repository. Do not edit vendor files to fix application behavior.

Sources: [application](../lib/beacon.sh), [launcher](../bin/beacon),
[lifecycle guide](../docs/lifecycle-and-automation.md), and
[framework updates](../docs/framework-updates.md).
