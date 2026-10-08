# Bundle format and trust boundary

Beacon's collection and verification rules define a portable trust boundary;
they do not turn Bash into a concurrent-filesystem sandbox. Keep workspace and
bundle roots, their ancestors, and their contents under trusted ownership, and
do not mutate them during collection or verification.

## Filesystem ownership

Collection reserves an unused destination with an exclusive directory creation.
An existing directory, file, or dangling link, including one created while
collection is staging, causes failure without modifying that destination. The
owned reservation is populated and verified before success is reported;
failures remove the owned incomplete reservation and staging. This is not an
atomic directory swap: readers must wait for successful collection before using
the bundle. Staging may be on another filesystem. Concurrent mutation inside an
owned reservation is outside the trust model.

Workspace and bundle roots must be trusted directories, not symbolic links.
Selected workspace paths and every bundle entry must contain no symbolic links,
including dangling links and intermediate directories, or special files. Only
regular files and directories are supported. Missing optional workspace inputs
remain supported. Validation happens before selected files are read and before
a bundle is published or verified.

## Configuration precedence

Configuration precedence is policy defaults, `--user-config`, `--config`,
environment, then explicitly supplied CLI options. An explicitly requested user
file must exist and be readable. The scenario default lives in application
policy; omitting `--scenario` does not override a configured or environment
scenario.

## Bundle schema 1

Bundle schema 1 requires README metadata and at least one supported payload. The
tab-delimited SHA256 manifest lists `README.txt` followed by selected `files/`
paths in bytewise lexical order, without duplicates. Verification requires exact
regular-file inventory coverage, `schema_version=1`, `application=beacon`, and
a `selected_files` count matching the payload. Partial input workspaces are
valid; empty, incomplete, extra-file, or malformed bundles return status 1
without a `verified=true` result. Older bundles without schema metadata must be
recollected.
