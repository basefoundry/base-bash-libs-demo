# Required CI Checks

The pull-request gate is the stable aggregate check named
`Required consumer and artifact validation`. The trusted
`.github/workflows/required-checks.yml` workflow runs from the base branch and
reads the exact pull-request test run by head SHA; the test lanes themselves
remain ordinary `pull_request` jobs that execute the proposed change.

The aggregate depends on these validation lanes:

- `Ubuntu validation`
- `Minimum runtime (Bash 4.2.53)`
- `macOS Homebrew Bash validation`
- both matrix legs of `Standalone artifact (ubuntu-24.04)` and
  `Standalone artifact (macos-14)`

The aggregate waits for every named lane and fails closed unless every
dependency reports `success`, so a missing, partial, cancelled, or incomplete
validation result cannot satisfy the merge gate. It does not replace the
detailed lane results; those remain the evidence to inspect when diagnosing a
failure. The separate trusted workflow is intentional: the aggregate itself
must not be editable by the pull request it protects.

If a validation lane is rerun after a transient failure, rerun the original
trusted aggregate run from the pull request's Checks tab after the lane is
green. That preserves the pull-request event context used by the ruleset. The
workflow's `workflow_dispatch` action can be used for diagnostic verification
with the pull request number and current head SHA, but its check is not the
ruleset-safe replacement for the original pull-request run.

The required-check setting is repository policy, not workflow source. Updating
these workflows does not change the live GitHub ruleset or grant a bypass. The
authorized ruleset update remains tracked by
[issue #37](https://github.com/basefoundry/base-bash-libs-demo/issues/37); after
that change, verify that the ruleset requires the exact aggregate check name
above for pull requests targeting `main`.

For local validation, run `./tests/validate.sh` with
`SPDX_VALIDATOR_PYTHON` pointing to the validator environment. This exercises
the consumer and artifact contracts on the current host and Bash runtime. It
does not reproduce the hosted Bash 4.2.53 image or both Ubuntu and macOS
artifact matrix legs; those remain hosted-only coverage.
