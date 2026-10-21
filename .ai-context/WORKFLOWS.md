# Workflows

From a fresh checkout with supported Bash:

```bash
./bin/beacon --help
./bin/beacon status
./bin/beacon plan
./bin/beacon collect --dry-run
./scripts/verify-vendor
```

For a real collection, choose an unused output directory and pass the same path
to `verify`. Do not silently delete an existing bundle to make collection pass.
Use [the tutorial](../docs/five-minute-tutorial.md) for expected output.

Development validation is `./tests/validate.sh`. The artifact checks require the
pinned SPDX dependency in `tests/requirements-artifacts.txt`. In a Base workspace,
run `basectl setup base-bash-libs-demo` before testing; direct validation must
use the prepared interpreter or set `SPDX_VALIDATOR_PYTHON` accordingly.

Use an issue and a dedicated canonical worktree. This repository keeps its
Project item In Progress while a PR is open; it does not use In Review in the
workflow. Only a merged PR becomes Done. Framework upgrades and releases follow
their own pin, evidence, compatibility, and required-check contracts.

Sources: [contribution guide](../CONTRIBUTING.md), [agent guidance](../AGENTS.md),
[validation driver](../tests/validate.sh), and
[required checks](../docs/ci-required-checks.md).
