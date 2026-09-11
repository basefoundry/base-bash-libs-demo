# Project Skills for base-bash-libs-demo

Use this file as the repo-local index for project-specific agent workflows.
Read `AGENTS.md` first; it owns the branch, worktree, validation, PR, and
cleanup contract.

## Development workflow

- Begin with an existing issue and exactly one standard category label.
- Run `basectl gh issue start ISSUE`, then create the returned branch and
  dedicated worktree from `origin/main`.
- Keep one issue per PR and link it with `Fixes #ISSUE` when merge should close
  it.
- After an authorized merge, synchronize `main`, verify the post-merge checks,
  and remove the worktree and merged branches.

## Testing workflow

- Run `./tests/docs-contracts.sh` for adoption and onboarding documentation.
- Run `./tests/docs-examples.sh` when changing the five-minute tutorial.
- Run `./tests/minimal-consumer.sh` when changing the starter or launcher path.
- Run `./tests/candidate-smoke.sh PATH` for an explicit framework candidate.
- Run `./tests/validate.sh` before every PR; it is the complete local gate.

## Release workflow

- Read `docs/release-process.md` and `docs/release-notes-template.md`.
- Build and verify artifacts with `scripts/release-artifact`; never attach an
  asset that fails its checksum, identity, vendor, or standalone smoke gates.
- Treat Beacon's `VERSION` and the framework identity in
  `base-bash-libs.lock` independently.
- Artifact preparation does not authorize a tag or GitHub Release. Publication
  requires a separate explicit maintainer action.

## Beacon domain workflow

- Consume only symbols listed in the vendored public API manifest.
- Keep framework mechanics and Beacon policy separate: Beacon owns selected
  inputs, payload redaction, bundle structure, and command meaning.
- Preserve dry-run and non-interactive no-write behavior.
- Preserve primary statuses through exactly-once cleanup: normal `0`, simulated
  failure `70`, and `TERM` interruption `143`.
- Change the framework pin only through `docs/framework-updates.md`, including
  immutable evidence, compatibility testing, and rollback.

## Boundaries

Do not vendor third-party methodology files here. Link to external guidance or
copy only repo-owned instructions that the project intends to maintain.
The branch convention is tool-independent; `feat/`, `agent/`, `codex/`, and
bare issue-number prefixes are invalid.
