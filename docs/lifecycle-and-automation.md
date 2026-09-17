# Lifecycle, failure, and automation scenarios

Beacon includes deterministic collection scenarios so operators can observe
the Base Bash lifecycle without real credentials, external services, or
changes to the host. The default `normal` scenario is the production-shaped
path. `failure` stops after staging but before publication, and `interrupt`
waits after staging so a test or operator can send `TERM`.

## Lifecycle evidence

Pass `--lifecycle-log PATH` to append one `phase=cleanup` record after an
invocation. Its parent directory must already exist. Beacon records only the
lifecycle phase; it never records arguments, statuses, configuration values,
workspace paths, or bundle contents.

Each invocation appends exactly one cleanup record. The process exit status is
the authoritative status evidence and remains unchanged by the hook. A
cleanup-log write failure cannot replace the primary application status because
Base Bash preserves that status across lifecycle hooks. Dry-run suppresses
lifecycle-log writes as part of its no-mutation contract.

## Failure and recovery

Use `collect --scenario failure --output PATH --lifecycle-log LOG` to exercise
the pre-publication failure path. Status `70` means the requested demonstration
failed before publication. Beacon removes its registered staging directory and
does not present `PATH` as a valid bundle. Recovery is to inspect diagnostics,
correct the input or destination, and retry with a new output path.

Use `collect --scenario interrupt` only as a controlled demonstration. Send
`TERM` after `state=waiting_for_signal` appears. Beacon exits `143`, runs its
cleanup hook once, removes staging state, and publishes no bundle. The same
recovery rule applies: confirm no output was published, then retry normally.

## Automation contract

Beacon's successful stdout is line-oriented `key=value` data. Automation
should match keys instead of timestamps or diagnostic text. Diagnostics remain
on stderr, and `--quiet` suppresses informational logging without hiding
command results. `--non-interactive` guarantees that stdin is never used for a
prompt. Combining it with `--dry-run` provides a safe policy check that writes
neither a bundle nor lifecycle evidence.

Stable statuses are:

- `0`: command completed successfully
- `1`: runtime or verification failure
- `2`: CLI usage or validation error
- `70`: deterministic pre-publication failure scenario
- `129`, `130`, `143`: `HUP`, `INT`, or `TERM`

The focused `tests/lifecycle.bats` suite exercises success, failure, `TERM`,
dry-run, non-interactive behavior, cleanup cardinality, status preservation,
staging removal, and redaction of token-like values and fake sensitive paths.
All fixtures are synthetic; malformed records are treated as data and never
evaluated as shell code.
# Filesystem trust boundary

Collection reserves an unused destination with an exclusive directory creation.
An existing directory, file, or dangling link, including one created while
collection is staging, causes failure without modifying that destination.
The owned reservation is populated and verified before success paths are printed;
failures remove the owned incomplete reservation and staging. This is not an
atomic directory swap: readers must wait for successful collection before using
the bundle. Staging may be on another filesystem. As with input checks, concurrent
mutation inside an owned reservation by another actor is outside the trust model.

Bundle schema 1 requires README metadata and at least one supported payload.
The tab-delimited SHA256 manifest lists README.txt followed by selected `files/`
paths in bytewise lexical order, without duplicates. Verification requires exact
regular-file inventory coverage, schema_version=1, application=beacon, and a
selected_files count matching the payload. Partial input workspaces are valid;
empty, incomplete, extra-file, or malformed bundles return status 1 without a
`verified=true` result. Older bundles without schema metadata must be recollected.

Workspace and bundle roots must be trusted directories, not symbolic links.
Selected workspace paths and every bundle entry must contain no symbolic links
(including dangling links and intermediate directories) or special files.
Only regular files and directories are supported. Missing optional workspace
inputs remain supported. Validation happens before selected files are read and
before a bundle is published or verified.

These portable Bash checks do not provide a sandbox against concurrent changes
to the filesystem. Keep roots, their ancestors, and their contents under trusted
ownership and do not mutate them during collection or verification.
