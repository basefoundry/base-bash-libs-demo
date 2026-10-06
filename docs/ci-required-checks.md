# Required CI Checks

The pull-request gate is the stable aggregate check named
`Required consumer and artifact validation`. It is designed to be configured as
the required status check for the default branch after the repository ruleset
has been updated through the separately authorized policy change.

The aggregate depends on these validation lanes:

- `Ubuntu validation`
- `Minimum runtime (Bash 4.2.53)`
- `macOS Homebrew Bash validation`
- both matrix legs of `Standalone artifact (ubuntu-24.04)` and
  `Standalone artifact (macos-14)`

The aggregate runs even when a dependency fails, is cancelled, or is skipped.
It fails closed unless every dependency reports `success`, so a partial or
incomplete validation result cannot satisfy the merge gate. The aggregate does
not replace the detailed lane results; those remain the evidence to inspect when
diagnosing a failure.

The required-check setting is repository policy, not workflow source. Updating
this workflow does not change the live GitHub ruleset or grant a bypass. After
the policy change is separately authorized, verify that the ruleset requires the
exact aggregate check name above and that the requirement applies to pull
requests targeting `main`.

For local validation, run `./tests/validate.sh` with
`SPDX_VALIDATOR_PYTHON` pointing to the validator environment. This runs the
consumer, minimum-runtime, and standalone-artifact checks represented by the
hosted lanes.
