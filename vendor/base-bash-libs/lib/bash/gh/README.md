# GitHub CLI Helpers

`lib_gh.sh` provides thin wrappers around the GitHub CLI for scripts that want
consistent command checks and authentication diagnostics without adopting Base's
GitHub workflow policy.

Source the stdlib before this library:

```bash
source "/path/to/base-bash-libs/lib/bash/std/lib_std.sh"
declare -a app_args=()
base_init app_args --source "${BASH_SOURCE[0]}" --
base_std_import gh/lib_gh.sh
```

## Public Functions

- `base_gh_require_cli [install_hint]`
  Verifies that `gh` is available on `PATH`. When it is missing, the helper logs
  a generic error and an optional caller-provided install hint.
- `base_gh_auth_status_diagnostics [login_hint]`
  Runs `gh auth status -h github.com`. On failure, it logs non-empty diagnostic
  lines from the GitHub CLI and then logs a caller-provided login hint, or the
  default `gh auth login -h github.com` hint.
- `base_gh_report_command_failure <status> [gh args...]`
  Logs a failed `gh` command and appends auth diagnostics. Protected reporting
  uses the control-first sensitive form documented below. The original status
  is returned.
- `base_gh_run [gh args...]`
  Runs `gh "$@"` after command availability checks. On command failure, it
  reports the failed command and auth diagnostics while preserving the original
  exit status. Protected calls use the sensitive form documented below.
- `base_gh_repo_from_remote_url <remote_url> <result_var>`
  Parses supported GitHub SSH and HTTPS remote URLs into `owner/repo`. Returns
  non-zero for non-GitHub or malformed remotes and leaves the result variable
  unchanged on failure.
- `base_gh_infer_repo_from_origin <repo_dir> <result_var> [--optional]`
  Reads the `origin` remote from a local Git repository and stores `owner/repo`
  when it points to GitHub. With `--optional`, missing or non-GitHub remotes
  store an empty string and return success.
- `base_gh_repo_default_branch <owner/repo> <result_var>`
  Uses `gh repo view` to read the GitHub repository default branch.
- `base_gh_api_with_retry [retry controls --] <endpoint> [gh api args...]`
  Runs `gh api "$@"` with idempotency-aware, elapsed-time-bounded retries.
  Reads may retry by default; mutations, GraphQL, file-backed payloads, and
  requests the parser cannot classify do not retry unless the caller explicitly
  attests that replay is safe. Stdin-backed payloads never retry. See
  [Idempotency-aware API retries](#idempotency-aware-api-retries).

All GitHub helper failures return a nonzero status and preserve the underlying
`gh` status where applicable. The remote parser and origin inference helpers
leave caller-owned result variables unchanged on failure; use `--optional` with
`base_gh_infer_repo_from_origin` when a missing or non-GitHub origin is expected.

Public functions validate the documented argument count before expanding
required positional parameters. Usage and contract errors return `2`, including
when the caller has enabled `nounset`; recoverable GitHub failures return `1`
unless the function preserves the underlying `gh` status. Optional flags such
as `--optional` are rejected when misspelled. `base_gh_run` passes every GitHub
argument after its optional protected-diagnostic control prefix through
unchanged. `base_gh_api_with_retry` preserves those caller arguments except for
the documented internal response-metadata instrumentation on compatible
retry-authorized calls.

The library does not change the caller's `errexit`, `nounset`, `pipefail`,
`noclobber`, `shopt`, `IFS`, `OPTIND`, cwd, umask, traps, or positional
parameters. Its diagnostic parsing uses a command-scoped empty `IFS`, and
failed `gh` commands retain their original status from `1` through `255`.
During a retry call, an explicitly ignored HUP, INT, QUIT, or TERM remains
ignored. Other dispositions are temporarily supervised so captures and child
processes can be cleaned; the exact caller disposition is then restored and
the signal is re-delivered, preserving default termination and custom trap
handlers.

## Idempotency-aware API retries

The legacy form remains valid and uses the conservative defaults:

```bash
base_gh_api_with_retry repos/basefoundry/base-bash-libs --jq .name
```

When any framework retry or sensitive-diagnostic control is present, put every
control in one leading prefix and terminate it with `--`:

```bash
base_gh_api_with_retry \
    --retry-policy replay-safe \
    --max-attempts 4 \
    --max-elapsed-seconds 180 \
    --attempt-timeout-seconds 45 \
    --base-delay-seconds 2 \
    --max-delay-seconds 90 \
    -- \
    repos/owner/repo/branches/main/protection --method PUT --input "$stable_payload"
```

This example is suitable only when `stable_payload` is immutable for the call
and describes the complete desired branch-protection state. Repeating that PUT
converges on the same known final state; an event-creating POST such as a
repository dispatch would not have that property.

The controls and defaults are:

| Control | Default | Allowed values |
| --- | ---: | --- |
| `--retry-policy` | `read-only` | `read-only`, `never`, `replay-safe` |
| `--max-attempts` | `3` | `1` through `10` |
| `--max-elapsed-seconds` | `300` | `1` through `3600` |
| `--attempt-timeout-seconds` | `60` | `1` through `600` |
| `--base-delay-seconds` | `2` | `0` through `60` |
| `--max-delay-seconds` | `120` | `1` through `300` |

Duplicate, missing, out-of-range, or conflicting controls fail before `gh`
runs. `--base-delay-seconds` cannot exceed `--max-delay-seconds`. Control
values are not repeated in validation diagnostics. The retired
`BASE_GH_API_MAX_ATTEMPTS` and `BASE_GH_API_RETRY_DELAY_SECONDS` environment
variables have no effect; migrate each call to the explicit controls above.

### Replay policy

`read-only` retries only confidently classified `GET`, `HEAD`, and `OPTIONS`
requests. An explicit method may use any GitHub CLI form, including
`--method GET`, `--method=GET`, `-X GET`, `-XGET`, or `-X=GET`. Without an
explicit method, any `--field`/`-F`, `--raw-field`/`-f`, or `--input` implies
`POST`; otherwise the method is `GET`. The parser understands interspersed
options, pflag short-option clusters, attached values, option-looking flag
values, and the `--` terminator. Duplicate method flags and unfamiliar syntax
are deliberately classified as unknown.

GraphQL is never classified as a read, even when the query text happens to be
read-only. File-backed `--input` and `--field key=@file` requests also require
`replay-safe`, because their data could change between attempts.

`replay-safe` is an explicit caller attestation that repeating the operation is
semantically safe and that every file or other data source will remain stable
for the whole call. It is not a generic GitHub idempotency-key mechanism. Use it
for a mutation only when duplicate execution and an unknown first-attempt
outcome are acceptable. `never` performs exactly one attempt.

`--input -` and typed `--field key=@-`/`-Fkey=@-` consume stdin and therefore
never retry, including under `replay-safe`. The same prohibition applies to
`/dev/stdin`, `/dev/fd/*`, `/proc/*/fd/*`, and named-pipe paths supplied through
`--input` or typed fields. A raw field such as `--raw-field key=@-` sends the
literal string `@-`; it is not stdin-backed. Typed fields split at their first
`=`, so `--field payload=literal=@-` is also a stable literal value rather than
a stdin reference.

### Retry evidence and scheduling

For a retry-authorized ordinary request, the helper internally adds
`--include`, examines the bounded leading response-header block, and removes
that exact byte prefix before returning stdout. This lets default reads retry
structured HTTP `408`, `425`, `429`, `500`, `502`, `503`, and `504` responses
without changing their public output. HTTP `403` retries only when the same
header block establishes rate limiting. A caller's own `--include`/`-i` is
preserved and its headers remain in stdout.

Internal header injection is disabled for pagination, slurp, verbose output,
an explicit include setting, ambiguous syntax, and forced-TTY/color rendering.
Those modes retain their original output. A caller-supplied include can still
provide structured HTTP evidence; otherwise retries are limited to the
narrowly authenticated transport and wrapper-timeout paths allowed for that
output mode. Header prefixes containing terminal control or NUL bytes,
incomplete or oversized blocks, conflicting retry metadata, and metadata
rendered under forced terminal/color settings fail closed. NUL bytes in the
response body are not metadata and remain byte-preserved.

Genuine GitHub CLI transport failures use either its exact two-line DNS
diagnostic or a single raw Go URL-error line. The helper matches the complete
stderr file against a narrow transient allowlist and requires stdout to be
empty; NUL bytes, oversized content, extra/debug lines, certificates,
cancellation, and response-rendering modes fail closed. GitHub error bodies
instead flow through `gh:`-prefixed stderr and can contain text shaped like
`(HTTP NNN)`, so stderr HTTP or rate text is never authoritative.
Authentication and authorization failures, other
client errors, jq/template/configuration failures, GitHub CLI statuses `2` and
`4`, arbitrary response bodies, and unknown text do not retry.

Generic transient failures use capped exponential equal jitter: for an
exponential cap `C`, the selected whole-second delay is in
`[ceil(C / 2), C]`. Server `Retry-After` and rate-limit-reset delays are minimum
waits and are never jittered or clamped downward. A structured rate-limit
response without delay headers starts at 60 seconds and backs off
exponentially. If a required server or rate-limit wait exceeds either the
configured delay bound or the remaining elapsed-time budget, the helper stops
and returns the last `gh` status instead of sleeping for less time.

The elapsed-time budget covers both attempts and waits. Each attempt timeout is
the smaller of `--attempt-timeout-seconds` and the remaining total budget. The
clock and controls use whole seconds. GitHub retries use the stdlib's shared
TERM-then-KILL supervisor: a verified GNU `timeout` or `gtimeout` is only a
deadline clock, while the framework owns the process group and sends `TERM`,
waits one second, then sends `KILL`. If neither external clock is available,
the Bash clock fallback provides the same public contract. A wrapper-enforced
attempt timeout has status `124`; supervisor setup failures use `125`, and a
natural command status (including `124`) is preserved. The one-second grace
can make observed wall time slightly exceed the nominal budget. No sleep is
performed after the final attempt, and clock, jitter, or sleep failures after
an attempt preserve that attempt's status.

### Captured output

Each invocation creates a mode-`0700` workspace and writes attempt stdout and
stderr to separate mode-`0600` files. A small guardian is running before those
files are created and removes the workspace if the owning shell disappears.
This design leaves the caller's EXIT trap and shared cleanup registry alone.
Intermediate attempt output is suppressed. On every success, including a
sensitive call, the final stdout and stderr are replayed byte-for-byte to their
original channels after any internally added header prefix is removed.
Ordinary final failures receive the same channel-preserving replay unless an
internally injected header prefix cannot be separated safely; in that case
failure stdout is withheld, while a nominal success is converted to a replay
failure. This preserves empty output, missing or repeated trailing newlines,
and binary NUL bytes without using command substitution.

Sensitive final failures replay neither captured channel. Their terminal and
persistent-log diagnostics contain only the caller-vetted safe label (if any),
method/status/attempt/budget context, and a notice that captured output was
hidden. Managed completion waits until guardian shutdown and workspace cleanup
finish. The guardian also performs best-effort cleanup after owner `SIGKILL`;
a simultaneous guardian failure, host failure, or unavailable temporary
filesystem can still leave mode-`0600` files for operating-system cleanup.

## Secret-safe command diagnostics

Ordinary `base_gh_run` and `base_gh_report_command_failure` failures render every GitHub
argument with Bash `%q`. This preserves argument boundaries and produces a
copyable diagnostic, but it is not secret-safe. Headers, fields, URL userinfo,
positional values, and `--option=value` forms are all rendered as supplied.

Use `--sensitive` whenever any GitHub argument may contain a credential or
other value that must not enter terminal or persistent logs:

```bash
base_gh_run --sensitive --safe-display "create release" -- \
    release create "$tag" --notes "$private_notes"

base_gh_api_with_retry --sensitive --safe-display "update project item" -- \
    graphql --header "Authorization: Bearer $token" \
    --raw-field "query=$query"

base_gh_report_command_failure --sensitive --safe-display "publish release" -- \
    "$status" release create "$tag" --notes "$private_notes"
```

A protected call requires the explicit `--` separator. `--safe-display` is
valid only with `--sensitive`; its value must be a non-empty printable ASCII
label that does not begin with `-` and that the caller has already determined
is safe to log. The label appears as, for example, `create release [sensitive
GitHub operation; arguments hidden]`. Without a label the helpers use only the
generic bracketed description.

Protected diagnostics never render the GitHub argv. This applies to final
failure records, retry notices, persistent logs, and the nested authentication
check performed by `base_gh_run` and `base_gh_report_command_failure`. A protected
`base_gh_api_with_retry` may inspect captured failure text internally to decide
whether and when to retry, but it does not replay that text on failure.
Successful API output remains functional stdout and is byte-preserved after
any internal response-metadata prefix is removed.

Sensitivity is explicit rather than heuristic. The helpers do not try to infer
which `--header`, `--field`, `--raw-field`, `--option=value`, URL, extension,
alias, or positional argument contains a secret. They also do not sanitize
output emitted by the executed command, whether that command is a shell
function, builtin, or external subprocess. Caller-enabled shell tracing such
as `set -x`, operating-system process listings, and an unsafe label supplied
through `--safe-display` are also outside this guarantee. Callers remain
responsible for those channels and should prefer non-argv credential
mechanisms whenever the invoked tool supports them.

## Boundary

This library is intentionally generic. It does not know about Base branch
names, issue categories, GitHub Project fields, repository baselines, generated
pull request bodies, or any other Base workflow policy.

## Tests

BATS coverage lives in `lib/bash/gh/tests/lib_gh.bats`.
