# Beacon documentation

Choose the shortest path that answers your current question.

## Evaluate

1. [Why Base Bash?](why-base-bash-libs.md) maps recurring Bash infrastructure
   to released public API calls exercised by Beacon.
2. [Should I use Base Bash?](should-i-use-base-bash-libs.md) covers fit,
   prerequisites, costs, alternatives, and maturity.

## Start using it

3. [Use Base Bash in your project](use-in-your-project.md) provides the tested
   minimal consumer and vendored and Homebrew launch paths.
4. [Beacon in five minutes](five-minute-tutorial.md) walks through the complete
   offline reference consumer.

## Operate and maintain

5. [Lifecycle and automation](lifecycle-and-automation.md) demonstrates normal,
   failure, interruption, cleanup, non-interactive, and redaction contracts.
6. [Bundle format and trust boundary](bundle-format-and-trust-boundary.md)
   documents schema 1, configuration precedence, and filesystem safety rules.
7. [Framework updates](framework-updates.md) defines candidate testing, atomic
   pin changes, evidence, and rollback.
8. [Release process](release-process.md) defines reproducible Beacon artifacts
   and the separately authorized publication sequence.
9. [Project workflow](project-workflow.md) explains issue status and pull-request
   linkage for ordinary and stacked PRs.
10. [Required CI checks](ci-required-checks.md) defines the aggregate validation
   contract used before merging changes to `main`.

Maintainers preparing a release should also use the
[release-notes template](release-notes-template.md). Beacon's committed package
is v2.2.0, so its repository-specific framework reference remains pinned to
that baseline. New projects should use the current upstream
[v2.2.1 documentation map](https://github.com/basefoundry/base-bash-libs/blob/v2.2.1/docs/README.md)
through [Use Base Bash in your project](use-in-your-project.md).
