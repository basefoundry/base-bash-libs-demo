# Beacon reference consumer

This repository contains Beacon, an offline support-bundle collector and a
reference consumer of the released Base Bash API. It teaches framework adoption
through a small application whose commands, input schema, redaction policy, and
messages remain application-owned.

Beacon uses a committed, verified framework bundle under `vendor/base-bash-libs`.
It requires supported Bash but not Base, Docker, cloud credentials, or network
access at runtime. The framework pin in `base-bash-libs.lock` is a reproducible
consumer baseline and need not equal the framework's newest release. Check the
lock and evidence when discussing the exact consumed version.

Beacon is first-party compatibility and learning evidence, not proof of adoption
by an independent external team. Its fixture-based collector is not a general
host diagnostic agent or a cloud upload service.

Sources: [README](../README.md), [framework lock](../base-bash-libs.lock),
[adoption guide](../docs/should-i-use-base-bash-libs.md), and
[framework boundary](../docs/why-base-bash-libs.md).
