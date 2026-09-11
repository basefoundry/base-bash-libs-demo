# Should I use Base Bash?

Use Base Bash when Bash is a real application constraint and you need shared,
reviewable behavior for more than argument parsing. Do not adopt it merely to
make a short script look like a framework application.

## Good fit

Base Bash is a strong candidate when several of these are true:

- the deliverable must remain Bash because it runs during provisioning,
  bootstrap, recovery, CI, or before another language runtime is available;
- the tool has commands, options, generated help, and automation consumers;
- configuration needs typed validation and explicit precedence;
- failures, signals, temporary paths, and cleanup must compose predictably;
- Linux and macOS behavior must share a tested contract;
- dependency identity and upgrades must be reviewable and reproducible; or
- several Bash applications should share the same operational conventions.

Beacon demonstrates that shape. It combines a declarative CLI, configuration,
failure and signal scenarios, exactly-once cleanup, safe filesystem operations,
and immutable dependency identity while keeping collection policy in the
application.

## Poor fit

Prefer a smaller solution when:

- the script is short, single-purpose, and unlikely to grow;
- POSIX `sh` rather than Bash is the required runtime;
- option parsing is the only repeated problem;
- installing Bash 4.2 or newer on every target is unacceptable;
- a generated standalone program is preferred to a sourceable runtime
  dependency; or
- Python, Go, Rust, or another richer runtime is available and better suited to
  the application's data model and maintenance team.

Plain Bash with a focused test may be the most maintainable answer for a
30-line hook. A framework dependency should remove more complexity than it
introduces.

## Runtime prerequisites

Base Bash requires Bash 4.2 or newer. Linux environments commonly satisfy that
requirement. macOS `/bin/bash` is 3.2, so supported macOS use requires a newer
Bash such as Homebrew Bash. Beacon's launcher discovers that supported Bash,
but it cannot remove the installation requirement.

The application must also provide any external commands used by its own
policy. For example, Beacon accepts either `sha256sum` or `shasum`; Base Bash
helps resolve the command, while Beacon decides that either implementation is
valid for its manifest.

## What adoption costs

This repository uses the most auditable consumption model rather than the
least work:

1. `base-bash-libs.lock` pins a release version, full commit, and asset hashes.
2. `vendor/base-bash-libs` contains the verified package for offline runtime.
3. `vendor/evidence` retains checksum, provenance, and SPDX evidence.
4. `scripts/verify-vendor` rejects identity or content drift.
5. `docs/framework-updates.md` requires candidate testing, an atomic pin
   update, review, and a documented rollback.

That model makes startup independent of a network and makes upgrades
reproducible. It also means maintainers must review security and compatibility
changes, refresh evidence, and carry the vendored package in the repository.
Projects can instead use a Homebrew installation or another documented
distribution mode, but they still need an explicit version and upgrade policy.

Base Bash also adds an API to learn. Application authors still own their
business rules, data validation, sensitive payload handling, user messages,
and end-to-end tests.

## Alternatives

These tools solve different-sized problems. The links below point to their
own documentation; verify current requirements before choosing.

| Choice | Best when | Main trade-off relative to Base Bash |
| --- | --- | --- |
| Plain Bash | The script is small and the team wants no framework dependency | Maximum control and minimum dependency surface, but the application owns every parser, lifecycle, portability, and upgrade convention |
| [`getoptions`](https://github.com/ko1nksm/getoptions) | POSIX-shell portability and option parsing/help are the primary needs | A focused parser and generator rather than an application lifecycle, typed-configuration, filesystem, Git, and package-identity library |
| [`Bashly`](https://github.com/bashly-framework/bashly) | A YAML-driven generator producing a standalone Bash CLI fits the delivery model | Generation uses Ruby or Docker and centers on generated CLI structure; Base Bash is a sourceable Bash runtime with broader operational contracts |
| [`Bash Infinity`](https://github.com/niieani/bash-oo-framework) | Its object-oriented and exception-style Bash programming model is specifically desired | A substantially different application model; consult its current project guidance before selecting it for new work |
| Base Bash | Bash 4.2+ is acceptable and CLI, configuration, lifecycle, safe execution, and immutable delivery should share one public contract | Broader dependency and upgrade responsibility than a parser-only or plain-Bash solution |

This is a boundary comparison, not a ranking. Prototype the smallest realistic
command and failure path before standardizing a team on any option.

## Maturity and support

Base Bash is on the stable v2 API line and publishes immutable release assets,
checksums, an SPDX SBOM, and provenance. Beacon deliberately remains pinned to
v2.0.0 even when newer compatible v2 releases exist; an upstream release does
not silently change this application.

Evidence is still narrower than broad ecosystem adoption. Beacon and the other
listed Base Foundry integrations are first-party compatibility evidence, not
proof of independent production use. The upstream project tracks that work
openly in its
[`Who uses Base Bash?`](https://github.com/basefoundry/base-bash-libs/blob/main/docs/who-uses-base-bash.md)
page and
[independent-consumer issue](https://github.com/basefoundry/base-bash-libs/issues/239).
Review the upstream
[support policy](https://github.com/basefoundry/base-bash-libs/blob/main/docs/support-policy.md),
[community guide](https://github.com/basefoundry/base-bash-libs/blob/main/docs/community.md),
and [releases](https://github.com/basefoundry/base-bash-libs/releases) when
calibrating operational risk.

## Decision checklist

Before adopting, answer yes to the questions that matter for your project:

- Can every target run Bash 4.2 or newer?
- Does the application need enough shared behavior to justify a framework?
- Which immutable installation or vendoring mode will you support?
- Who reviews framework upgrades and retained release evidence?
- Which behaviors remain application-owned, and how will you test them?
- Is the current support and independent-adoption evidence sufficient for the
  application's risk level?

If the answers are clear, continue with the
[five-minute Beacon tutorial](five-minute-tutorial.md) to see the public
boundary running offline.
