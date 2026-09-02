# `lib_std.sh`

`lib_std.sh` is the foundation library for Bash scripts in the Base family.

The normative v2 status, output, mutation, interactive, and process-boundary
rules are in [`docs/v2-api-contract.md`](../../../docs/v2-api-contract.md).

Bash is excellent glue, but raw Bash makes it too easy for every script to
invent its own logging, path handling, argument conventions, dry-run behavior,
error reporting, and import rules. `lib_std.sh` gives Bash code one shared
toolbox so scripts can stay small, readable, and consistent.

## Why This Makes Bash Scripting Better

The library improves Bash-based scripting in a few practical ways:

- **Consistent logs**: every script can emit timestamped logs with level and
  source location.
- **Logs stay on stderr**: stdout remains available for real program output that
  another command may pipe or capture.
- **Readable failures**: fatal errors include a message and Bash stack trace
  instead of a mysterious non-zero exit.
- **Safe command execution**: `base_std_run` preserves argument boundaries, supports
  dry-run mode, timeout, retry, and returns a status by default; use the explicit
  `base_std_run_or_exit` wrapper when fail-fast behavior is intended.
- **Shared dry-run behavior**: scripts do not need to reimplement "print what
  would happen" logic.
- **Composable cleanup**: scripts can register exit cleanup without replacing
  an already-installed `EXIT` trap.
- **Portable temp state**: scripts can create temp files or directories under
  `TMPDIR` and register them for cleanup in one call.
- **Non-fatal introspection**: scripts can resolve command paths and check
  function availability without turning every probe into a hard exit.
- **Simple library imports**: scripts can import helpers relative to their own
  source directory.
- **Predictable PATH edits**: PATH additions avoid duplicates and can prepend or
  append intentionally.
- **Batch validation**: required variables, files, directories, commands, and
  integer ranges can be checked with one helper call.
- **Safer filesystem helpers**: common operations report all failures in one
  clear error.
- **Base wrapper integration**: wrapper flags are recognized once and removed
  before command-specific argument parsing begins.

Log timestamps use the host's local timezone and include its numeric offset by
default, for example `2026-07-18 13:14:32 -0700`. Setting `BASE_BASH_LIBS_LOG_UTC=1` switches
the timestamp to the explicit `UTC` form. Base's `--utc-wrapper` option sets
this variable for the complete Bash/Python runtime chain.

The goal is not to hide Bash. The goal is to make scripts fail in ways a user
or developer can understand.

## Public API Reference

The functions below are the supported `lib_std.sh` API. Functions beginning
with `__` are internal implementation details and are intentionally omitted.
Functions that return a value through a variable name mutate that caller-owned
variable only after validating it. Unless noted otherwise, predicates return
zero for success and nonzero for a false or invalid condition.

Required arguments are shown with angle brackets, optional arguments with square
brackets, and variadic arguments with `...`. Callers should pass only the
documented arguments. Public helpers that write through caller-supplied
variable or array names reserve the `__` prefix for library-internal state;
such output names are rejected before caller state is changed.

### Runtime and Imports

- `base_init <result_array> [--source <script>] -- [argv...]`:
  explicitly initializes runtime state and returns wrapper-filtered application
  arguments without mutating the caller's positional parameters.
- `base_require_version <version>`: returns `1` when the loaded package version
  is older and `2` for malformed usage/version values.
- `base_std_check_bash_version`: returns zero for Bash 4.2 or newer and reports the
  required version otherwise.
- `base_std_is_interactive`: returns zero when stdin is attached to an interactive TTY.
- `base_std_import <path>...`: sources package-relative modules from the loaded
  `lib/bash` root; returns a recoverable failure for missing, unsafe, cyclic,
  or failed imports.
- `base_std_get_my_source_dir <result_var>`: stores the caller script directory in a
  validated variable without printing it.

### Logging and Messages

- `base_std_set_log_level [-l <logger>] <level>`: changes terminal verbosity and returns
  nonzero for an unknown level or logger option error.
- `base_std_set_log_category_level -l <category> <level>`: changes the independent gate
  for a category and its dotted descendants.
- `base_std_log_is_enabled [-l <category>] <level>`: returns zero when the category gate
  and at least one configured sink accept the level.
- `base_std_log_fatal`, `base_std_log_error`, `base_std_log_warn`, `base_std_log_info`, `base_std_log_debug`,
  `base_std_log_verbose <message...>`: write a structured message to stderr at the
  named level. `base_std_log_verbose` is deprecated; use `base_std_log_debug`.
- `base_std_log_info_file`, `base_std_log_debug_file`, `base_std_log_verbose_file [-l <logger>] <file>`:
  log a file's contents at the requested level when that level is enabled.
  `base_std_log_verbose_file` is deprecated; use `base_std_log_debug_file`.
- `base_std_log_info_enter`, `base_std_log_debug_enter`, `base_std_log_verbose_enter` and
  `base_std_log_info_leave`, `base_std_log_debug_leave`, `base_std_log_verbose_leave`: log the current
  function boundary without arguments. The `log_verbose_*` forms are
  deprecated; use the DEBUG forms.
- `base_std_print_error`, `base_std_print_warn`, `base_std_print_info`, `base_std_print_success <message...>`:
  write an unstructured user-facing message to stderr.
- `base_std_print_bold`, `base_std_print_message <message...>`: write an unstructured message to
  stdout; `base_std_print_bold` applies terminal formatting when enabled.
- `base_std_print_tty <message...>`: writes only when stdout is attached to a TTY.
- `base_std_dump_trace`: writes the current Bash call stack to stderr.

### Command and Error Control

- `base_std_run [policy options] <command> [args...]`: runs an argument-preserving
  command and returns its status. See [Running Commands Safely](#running-commands-safely).
- `base_std_run_or_exit [policy options] <command> [args...]`: runs an
  argument-preserving command and exits the caller when it fails. Use this
  explicit wrapper when fail-fast behavior is intentional.
- `base_std_exit_if_error <status> [message...]`: returns for zero and exits with the
  supplied status after logging a message for nonzero status.
- `base_std_fatal_error <message...>`: logs a fatal error, prints a trace, and exits.
- `base_std_is_dry_run`: returns zero when `BASE_BASH_LIBS_DRY_RUN` is truthy.

### PATH and Filesystem Helpers

- `base_std_add_to_path [-p] [-n] <directory...>`: prepends or appends existing PATH
  entries, optionally allowing missing directories; returns nonzero on invalid
  options or update failure.
- `base_std_dedupe_path`: removes duplicate and empty PATH entries in place.
- `base_std_print_path`: prints one PATH entry per line.
- `base_std_safe_mkdir [-p] <directory...>`, `base_std_safe_touch <file...>`,
  `base_std_safe_truncate <file...>`, and `base_std_safe_cd <directory>`: perform the named
  filesystem operation with explicit diagnostics and failure statuses.
- `base_std_safe_unalias <name...>`: removes aliases when present and ignores names that
  are not aliases.

### Cleanup and Temporary State

- `base_std_register_cleanup_hook <function>`,
  `base_std_unregister_cleanup_hook <function>`: add or remove a named cleanup
  function from the shared exit dispatcher.
- `base_std_register_cleanup_path [--unsafe] <absolute_path...>`,
  `base_std_unregister_cleanup_path <absolute_path...>`: add or remove paths from
  exit cleanup; invalid, broad, protected, and relative paths are rejected.
  Normal registration snapshots every path component and refuses deletion if a
  symlink, parent directory, rename, or other identity substitution changes
  the registered resource. `--unsafe` explicitly opts out of that ownership
  proof for a specific path, but protected roots and system/shared directories
  remain rejected.
- `base_std_make_temp_file [--keep] <result_var> [prefix]` and
  `base_std_make_temp_dir [--keep] <result_var> [prefix]`: create a temporary path,
  store it in the caller variable, and register it for cleanup unless
  `--keep` is used.

### Introspection and Assertions

- `base_std_command_path <result_var> <command>`: stores the resolved executable
  path or returns nonzero when the command is unavailable.
- `base_std_function_exists <name>`: returns zero when a Bash function exists.
- `base_std_assert_function_exists <name...>`: exits through `base_std_fatal_error` when one or
  more required functions are missing or invalid. Use `base_std_function_exists` for
  a non-fatal predicate.
- `base_std_assert_variable_name <name...>`: validates Bash variable names.
- `base_std_assert_indexed_array <name...>` and `base_std_assert_associative_array <name...>`:
  validate caller-owned array declarations.
- `base_std_assert_not_null <variable...>`: validates that named variables are set and
  non-empty without treating values as variable names accidentally.
- `base_std_assert_integer <variable...>` and
  `base_std_assert_integer_range <variable> <min> <max>`: validate the values of named
  variables as decimal integers and enforce inclusive bounds.
- `base_std_assert_arg_count <actual> <expected> [max]`: validates exact or ranged
  positional argument counts.
- `base_std_assert_command_exists <command...>`, `base_std_assert_file_exists <path...>`,
  `base_std_assert_executable <path...>`, and `base_std_assert_dir_exists <path...>`: validate
  required commands or filesystem objects.

### Interactive Helpers

- `base_std_ask_yes_no <prompt> [yes|no]`: prompts on a TTY, accepts Enter as
  the displayed `[y/N]` or `[Y/n]` default, and returns the user's decision.
- `base_std_wait_for_enter [prompt]`: waits for Enter on a TTY and returns nonzero when
  no usable terminal is available.

## Loading The Library

Standalone scripts can source the library directly:

```bash
source "/absolute/path/to/lib/bash/std/lib_std.sh"
```

Standalone scripts can also use the `base-bash` launcher when it is installed on
`PATH`:

```bash
#!/usr/bin/env base-bash

base_launcher_import_base_bash_lib str/lib_str.sh

main() {
    local name="  Example  "
    base_str_trim name
    base_std_run echo "$name"
}
```

Base entrypoints preload this library through Base's own runtime bootstrap. The
`base-bash` launcher provides the same stdlib preload pattern without Base
runtime state. Callers should run on Bash 4.2 or newer; the library has passive
Bash version helpers, but sourcing it does not prompt, install packages, or
re-exec the caller.

## Initialization Contract

Sourcing `lib_std.sh` is passive. It publishes function definitions, immutable
package metadata, and a collision-safe load guard, but it does not consume or
rewrite positional parameters, install traps, export runtime controls, change
shell options, initialize logging, or create caller-owned generic state.

Call `base_init` exactly once for the application lifecycle:

```bash
declare -a app_args=()
base_init app_args --source "${BASH_SOURCE[0]}" -- "$@"

# The caller owns this explicit handoff; the library never changes "$@".
main "${app_args[@]}"
```

The first argument is a caller-declared indexed array. Optional `--source`
identifies the application script for diagnostics and runtime context. The
arguments after the configuration separator `--` are copied into the result
array after these wrapper controls are consumed:

- `--debug-wrapper` enables DEBUG logging for the terminal and the stdlib
  category.
- `--verbose-wrapper` retains the deprecated VERBOSE compatibility level.
- `--utc-wrapper` exports `BASE_BASH_LIBS_LOG_UTC=1` for the initialized runtime.
- `--color` enables terminal colors when stderr is a TTY and `NO_COLOR` is not
  set.

Initialization is idempotent for the same script context and argv. A repeated
call with different context or argv fails with a diagnostic instead of silently
changing a running application's configuration. Companion libraries should be
imported after initialization.

Caller-visible metadata:

- `BASE_BASH_LIBS_VERSION`: readonly package version read from the root
  `VERSION` file when present, otherwise from the embedded
  `lib/bash/base-bash-libs.release` metadata
- `BASE_BASH_LIBS_COMMIT`: readonly full checkout commit or embedded release
  commit; `unknown` when no identity is available
- `BASE_BASH_LIBS_DIRTY_STATE`: readonly `clean`, `dirty`, or `unknown`
- `BASE_BASH_LIBS_PROVENANCE`: readonly `checkout`, `release-artifact`,
  `source-archive`, `copy`, or `unknown`
- `BASE_BASH_LIBS_STDLIB_LOADED`: readonly marker set to `1` after
  `lib_std.sh` has loaded successfully; it does not imply runtime init
- `BASE_BASH_LIBS_SCRIPT_ARGS`: original arguments before wrapper flags were stripped
- `BASE_BASH_LIBS_SCRIPT_DIR`: absolute source directory for the script being bootstrapped

`BASE_BASH_LIBS_SCRIPT_ARGS` and `BASE_BASH_LIBS_SCRIPT_DIR` are published only by the explicit
initializer. A launcher may pass `--source` directly; `BASE_BASH_LIBS_BOOTSTRAP_SOURCE`
is only a fallback for callers that cannot provide that option.

The library preserves caller-selected `errexit`, `nounset`, and `pipefail`
settings and supports every combination on Bash 4.2 or newer. It does not
enable or disable those options for the caller. A top-level interactive or
`bash -c` source has no outer `BASH_SOURCE` frame; without a bootstrap override,
`BASE_BASH_LIBS_SCRIPT_DIR` and `base_std_get_my_source_dir` use the current working directory in
that case. Predicate helpers can intentionally return nonzero, so callers using
`errexit` should invoke them in `if`, `while`, `&&`, or another normal Bash
conditional context.

## Version Requirements

Use `base_require_version` when a downstream script depends on APIs
added after the first public release:

```bash
base_require_version 1.1.0
```

The helper compares supported SemVer versions, including the v2
`alpha.N`, `beta.N`, and `rc.N` prerelease identifiers. It returns silently
when the loaded library is new enough and exits with a clear fatal error when
the loaded `BASE_BASH_LIBS_VERSION` is too old.

## Logging

Use structured logging for operational messages:

```bash
base_std_log_info "Installing package '$name'."
base_std_log_warn "Cache directory does not exist: $cache_dir"
base_std_log_error "Unable to read manifest '$manifest_path'."
base_std_log_debug "resolved_home=$resolved_home"
```

Available levels:

- `FATAL`
- `ERROR`
- `WARN`
- `INFO`
- `DEBUG`
- `VERBOSE` (deprecated compatibility level)

`DEBUG` is the most detailed supported level for new code. `VERBOSE`,
`base_std_log_verbose`, `base_std_log_verbose_file`,
`base_std_log_verbose_enter`, `base_std_log_verbose_leave`,
and `--verbose-wrapper` remain available as explicitly deprecated v2 controls.
They do not define generic v1 aliases and do not emit runtime deprecation
warnings.

Change terminal verbosity with:

```bash
base_std_set_log_level DEBUG
```

The `-l` identifier on a log call selects both its category gate and any
explicitly configured named terminal logger. For example:

```bash
base_std_set_log_level -l artifact DEBUG
base_std_log_debug -l artifact "registry key: $key"
```

Terminal verbosity and category gates answer different questions:

- `base_std_set_log_level` controls what appears on the terminal. An unconfigured named
  logger inherits the default terminal level.
- `base_std_set_log_category_level` controls whether a component may emit a record at
  all. Categories inherit from the nearest explicitly configured dotted parent,
  then from `default`.
- `BASE_BASH_LIBS_PRIMARY_LOG`, when it names an eligible path, receives accepted
  records through DEBUG even when the terminal remains at INFO.

The primary sink is best-effort and never changes application status. An
existing target must be an owned, writable, regular non-symlink file; a missing
target needs an existing writable and searchable parent directory. The library
does not create parent directories. `base_std_log_is_enabled` checks this eligibility
without creating or changing the target. Before appending, the library creates
or normalizes the primary log to mode `0600`; setup and write failures are
suppressed and disable that path for the remainder of the process.

The global default category gate is permissive for compatibility. Applications
can keep their own DEBUG output while limiting a reusable component:

```bash
base_std_set_log_level DEBUG
base_std_set_log_category_level -l reusable_library INFO
base_std_set_log_category_level -l reusable_library.network DEBUG

base_std_log_debug "application diagnostic"
base_std_log_debug -l reusable_library "suppressed library diagnostic"
base_std_log_debug -l reusable_library.network "enabled network diagnostic"
```

The library's own records use these categories:

- `base_bash_libs.std`
- `base_bash_libs.arg`
- `base_bash_libs.file`
- `base_bash_libs.git`
- `base_bash_libs.gh`

The parent `base_bash_libs` gate defaults to INFO. Consequently, an application
can enable its own DEBUG terminal output without also enabling reusable-library
DEBUG records:

```bash
base_std_set_log_level DEBUG

# Opt in to every base-bash-libs DEBUG category:
base_std_set_log_category_level -l base_bash_libs DEBUG

# Or keep the parent at INFO and enable one component:
base_std_set_log_category_level -l base_bash_libs INFO
base_std_set_log_category_level -l base_bash_libs.git DEBUG
```

`--debug-wrapper` enables both DEBUG terminal output and the
`base_bash_libs` DEBUG gate. The deprecated `--verbose-wrapper` continues to
enable both at VERBOSE during the compatibility window.

Merely sourcing `lib_std.sh` does not log the caller process argument vector.
Explicit command execution is different: ordinary `base_std_run` dry-run and
failure diagnostics intentionally render the command arguments with Bash
`%q`. Arguments may contain credentials or other sensitive data, so use
`base_std_run --sensitive` for a protected command and apply schema-aware redaction
before writing any caller-owned invocation diagnostic.

Use `base_std_log_is_enabled` to avoid constructing an expensive diagnostic unless a
terminal or persistent sink will consume it:

```bash
if base_std_log_is_enabled -l reusable_library.network DEBUG; then
    base_std_log_debug -l reusable_library.network "response=$(render_large_response)"
fi
```

For user-facing messages that should not include timestamps or source
locations, use:

```bash
base_std_print_error "Invalid project name."
base_std_print_warn "Using default workspace."
base_std_print_info "Setup complete."
base_std_print_success "Done."
base_std_print_message "plain stdout message"
```

`log_*`, `base_std_print_error`, `base_std_print_warn`, `base_std_print_info`, and `base_std_print_success` write to
stderr. `base_std_print_bold` and `base_std_print_message` write to stdout.

Colors are only enabled for terminal stderr when `--color` is passed. Set
`NO_COLOR` to disable colored output even when `--color` is present.

## Error Handling

Use `base_std_fatal_error` when the script cannot continue:

```bash
[[ -f "$manifest_path" ]] || base_std_fatal_error "Manifest '$manifest_path' was not found."
```

Use `base_std_exit_if_error` when checking a command's explicit status:

```bash
some_command
base_std_exit_if_error $? "some_command failed."
```

Fatal failures log the message, dump a Bash stack trace, and exit with the
original failing status when possible.

Not every user mistake should be fatal. Command-line usage errors should usually
print usage and return `2` rather than calling `base_std_fatal_error`, because the command
itself is fine and the user simply gave invalid arguments.

## Running Commands Safely

`base_std_run` is the preferred helper for external command execution. It
returns the command status by default, so the caller remains in control of
whether a failure is recoverable:

```bash
base_std_run git status --short
base_std_run touch "file with spaces.txt"
```

It improves on ad hoc command strings because it:

- executes commands as argument arrays, not through `eval`
- preserves spaces and special characters
- logs a copy-pastable command in ordinary dry-run and failure diagnostics
- can replace sensitive command text with a protected marker and safe label
- can bound each attempt with `--timeout`
- can retry transient failures with `--max-attempts` and `--retry-delay`
- returns the command, timeout, or supervisor status when a command fails

For scripts that intentionally stop on the first failed command, use the
explicitly named fail-fast wrapper:

```bash
base_std_run_or_exit git status --short
```

Dry-run mode:

```bash
BASE_BASH_LIBS_DRY_RUN=true
base_std_run brew install jq
```

`BASE_BASH_LIBS_DRY_RUN` and `BASE_BASH_LIBS_DRY_RUN` both accept `true`, `1`, `yes`, and `on`. Use
`base_std_is_dry_run` when a script needs to branch on the same normalized dry-run state
without executing a command through `base_std_run`.

Protect framework-generated diagnostics for a command whose arguments contain
credentials or other sensitive values with `--sensitive`. Protected calls must
use `--` to separate runner options from the command:

```bash
base_std_run \
    --sensitive \
    --safe-display "upload release asset" \
    -- \
    curl \
        --header "Authorization: Bearer $token" \
        --form "asset=@$archive" \
        "$upload_url"
```

The rendered operation is:

```text
upload release asset [sensitive command; arguments hidden]
```

Without `--safe-display`, diagnostics contain only
`[sensitive command; arguments hidden]`. A safe display must be non-empty,
contain only printable ASCII bytes, and not begin with `-`. The byte-oriented
rule rejects line separators, bidirectional text controls, and other
locale-dependent non-printing characters. Rejecting a leading hyphen prevents
a missing label from consuming an option-like command argument. The label is
copied into terminal and persistent diagnostics exactly as the caller supplies
it, so the caller is responsible for ensuring that the label itself contains
no secret.

`--sensitive` changes diagnostics only. It does not alter argument boundaries,
execution, status propagation, timeout, retry, dry-run, or `--quiet` behavior,
and it does not attempt heuristic redaction. In particular, it cannot protect:

- output emitted by the executed command, including shell functions, builtins,
  and subprocesses
- shell tracing such as `set -x`
- command arguments visible through the operating system process list
- secrets placed in the caller-supplied safe display or other explicit logs

Configure or redirect an executed command that may echo secrets, and disable
tracing around sensitive invocations. Ordinary commands continue to use `%q`
so their diagnostics retain exact, copy-pastable argument boundaries.

Handle a failing command yourself directly with `base_std_run` (the
`--no-exit` spelling remains accepted when sharing an option list with
`base_std_run_or_exit`):

```bash
if ! base_std_run grep "needle" "$file"; then
    base_std_log_info "needle was not present; continuing"
fi
```

For expected probe failures where the caller handles the status, add `--quiet`
to suppress the warning:

```bash
if ! base_std_run --quiet test -f "$optional_file"; then
    base_std_log_debug "Optional file is absent."
fi
```

Add a per-attempt timeout when a command must finish within a bounded number of
seconds:

```bash
base_std_run --timeout 30 curl -fsSL "$health_url"
```

Timeouts return status `124` to the caller:

```bash
if ! base_std_run --quiet --timeout 5 nc -z localhost 5432; then
    base_std_log_warn "database port did not open within 5 seconds"
fi
```

Retry transient failures by setting the total attempt count. `--retry-delay`
adds a fixed sleep between failed attempts:

```bash
base_std_run --max-attempts 3 --retry-delay 2 curl -fsSL "$artifact_url"
```

Timeout and retry compose directly. The timeout is per attempt, not a total
budget for all attempts:

```bash
base_std_run --timeout 30 --max-attempts 3 --retry-delay 2 curl -fsSL "$artifact_url"
```

`--retry-attempts` is accepted as an alias for `--max-attempts`, but new code
should prefer `--max-attempts` because it makes clear that the value is the total
number of attempts, not retries after the first attempt.

For a timed command, the framework sends `TERM` at the per-attempt deadline,
waits one second, and then sends `KILL` to the supervised process group. The
one-second escalation grace is part of the hard upper-bound contract, so a
single attempt normally takes at most `timeout + 1` seconds plus scheduler and
startup overhead. With `A` total attempts and retry delay `D`, the policy's
nominal upper bound is `A * (timeout + 1) + (A - 1) * D`, plus that small
overhead. `--timeout` is never silently converted into a best-effort warning.

The runner capability-detects a GNU `timeout`, GNU `gtimeout`, or the Bash
fallback. A verified external binary is used only as a deadline clock; it
never receives the caller's command or arguments. The framework owns the
process group and always applies the same status contract: `124` means the
framework deadline fired, `125` means supervision could not be established
safely, and a command's natural exit status (including `124`) is preserved.
Caller signals are restored and re-delivered after cleanup with their normal
signal-derived status. Managed same-user descendants in the process group are
covered. A process that deliberately detaches/reparents itself, or is stuck in
an uninterruptible kernel wait, is outside any user-space Bash guarantee.

Timed commands require non-terminal stdin. This fail-closed rule prevents a
foreground TTY job-control path from claiming a hard descendant guarantee.
Use an explicit pipe or `</dev/null` when the command does not need terminal
input; a foreground TTY invocation returns `125` without executing the
command. This restriction is intentional for v2 and is independent of which
timeout backend was detected.

Use `base_std_run` for commands plus arguments. Keep shell features such as
pipelines, redirection, process substitution, and complex conditionals explicit
in the calling script so the code remains clear.

Unknown `base_std_run` options beginning with `--` are rejected before command
execution. If the command itself begins with `--`, terminate `base_std_run` options
first:

```bash
base_std_run -- --command-name arg
```

The separator is optional for ordinary commands whose name does not begin with
`--`, but mandatory whenever `--sensitive` is selected. `--safe-display` is
valid only with `--sensitive`. Invalid protected controls return `1` without
executing the command, and their diagnostics do not repeat an offending token
after sensitive mode has been selected.

In dry-run mode, the plan is emitted as a timestamped `DRY-RUN` record directly
to stderr, even when INFO logging, category gates, or `--quiet` would suppress
ordinary diagnostics. Stdout remains reserved for command data, and the exact
argv is rendered without executing anything. Sensitive plans retain the same
redaction rules as other framework diagnostics.

## Importing Other Bash Libraries

Use `base_std_import` to source package-relative helper libraries:

```bash
base_std_import file/lib_file.sh
base_std_import git/lib_git.sh str/lib_str.sh
```

Imports resolve from the loaded package's `lib/bash` directory, independent of
the caller's cwd or `BASE_BASH_LIBS_SCRIPT_DIR`. Absolute paths, traversal, and
package-root-escaping symlinks are rejected. Imports are idempotent and cycle-
safe, and every non-stdlib module requires the already-loaded std dependency.
The loader makes top-level `declare` statements global while sourcing a module,
so module authors do not need `declare -g` solely because the loader is a
function. Declarations executed later inside functions retain normal Bash
scope rules.

## PATH Helpers

Use `base_std_add_to_path` instead of hand-editing PATH:

```bash
base_std_add_to_path "/opt/tool/bin"
base_std_add_to_path -p "$HOME/.local/bin"
base_std_add_to_path -n "$maybe_created_later/bin"
```

Options:

- `-p`: prepend instead of append
- `-n`: do not require the directory to already exist

`base_std_add_to_path` de-duplicates PATH after adding entries. You can also call:

```bash
base_std_dedupe_path
base_std_print_path
```

## Filesystem Helpers

The safe filesystem helpers collect failures and report them clearly:

```bash
base_std_safe_mkdir -p "$state_dir" "$cache_dir"
base_std_safe_touch "$log_file"
base_std_safe_truncate "$log_file"
base_std_safe_cd "$project_root"
```

These helpers are useful in setup scripts where a partially completed operation
should fail loudly and explain which path could not be created, touched, or
entered.

`base_std_safe_mkdir` accepts only `-p` as an option. Calling it without directory
arguments logs a warning and returns success without creating anything.

## Cleanup Helpers

Use cleanup registration when a script creates transient state that should be
removed on exit:

```bash
workspace="$(mktemp -d)"
base_std_register_cleanup_path "$workspace"
```

Cleanup paths are removed with `rm -rf --` from a shared `EXIT` trap. Paths must
be absolute so cleanup cannot drift when a script changes directory after
registration. Empty paths, root paths, current/parent directory traversal
components, broad roots, home, system directories, and shared temporary roots
are rejected before registration. Normal paths are identity-checked at exit;
if a parent is renamed or replaced, cleanup refuses to remove the new object.
When one call mixes valid and invalid paths, valid paths are registered, invalid
paths are rejected, and the helper returns nonzero.

When a script removes or moves a registered path before exit, unregister it so
the shared cleanup registry only contains paths that may still need fallback
cleanup:

```bash
rm -rf -- "$workspace"
base_std_unregister_cleanup_path "$workspace"
```

For custom cleanup, register a function name:

```bash
cleanup_workspace() {
    rm -rf -- "$workspace"
}

base_std_register_cleanup_hook cleanup_workspace
base_std_unregister_cleanup_hook cleanup_workspace
```

Hooks and paths unwind in strict last-in, first-out order, and duplicate
registrations are ignored. If an `EXIT` trap already exists when the first
cleanup hook or path is registered, that existing trap is preserved and runs
before the registered resources. Caller `EXIT`, `INT`, `TERM`, and `DEBUG`
traps installed later are composed with the dispatcher instead of silently
replacing it. Cleanup runs at most once, preserves the primary exit status,
and reports secondary hook/path failures without skipping later resources.
Signals received during cleanup are latched and reflected in the final status.
The shared dispatcher remains installed only while at least one hook or path is
registered. Removing the final registration restores the caller traps that the
dispatcher still owns.

## Temporary Path Helpers

Use temp helpers when a script needs a scratch file or directory and wants the
path stored in a variable:

```bash
base_std_make_temp_file temp_file base
base_std_make_temp_dir temp_dir workspace
```

Both helpers create paths under `${TMPDIR:-/tmp}` using `mktemp` templates that
work on macOS/BSD and GNU systems. The created path is registered for exit
cleanup by default:

```bash
base_std_make_temp_dir workspace_dir
printf 'payload\n' > "$workspace_dir/input.txt"
```

Pass `--keep` when the caller intentionally owns cleanup:

```bash
base_std_make_temp_file --keep report_path report
```

The optional prefix is a filename prefix, not a directory path. It must be
non-empty and must not contain `/`. Set `TMPDIR` before calling the helper when
the temp root should be somewhere other than `/tmp`.

## Introspection Helpers

Use `base_std_command_path` when a script needs the path to an external command but
wants to decide what to do if it is absent:

```bash
if base_std_command_path git_path git; then
    base_std_run "$git_path" status --short
else
    base_std_log_warn "git is not available; skipping repository status."
fi
```

The helper stores an executable path in the named result variable and returns
nonzero with an empty result when the command is not found.

Use `base_std_function_exists` for predicate-style checks:

```bash
if base_std_function_exists cleanup_workspace; then
    base_std_register_cleanup_hook cleanup_workspace
fi
```

Use `base_std_assert_function_exists` when missing functions should be fatal:

```bash
base_std_assert_function_exists main cleanup_workspace
```

## Validation Helpers

Use assertions near the top of functions to make assumptions explicit:

```bash
base_std_assert_arg_count "$#" 2
base_std_assert_variable_name result_var array_var
base_std_assert_indexed_array values
base_std_assert_associative_array options
base_std_assert_not_null BASE_HOME project_name
base_std_assert_integer retry_count
base_std_assert_integer_range retry_count 0 5
base_std_assert_command_exists git brew
base_std_assert_function_exists main cleanup_workspace
base_std_assert_file_exists "$manifest_path"
base_std_assert_executable "$project_root/bin/build"
base_std_assert_dir_exists "$project_root"
```

`base_std_assert_not_null` takes variable names, not expanded values. Use
`base_std_assert_not_null TOKEN`, not `base_std_assert_not_null "$TOKEN"`. When an argument is not
a valid Bash variable name, `base_std_assert_not_null` reports likely misuse without
echoing the invalid value.

Use `base_std_assert_variable_name` when a helper accepts variable names but does not
require those variables to exist or contain values.

Use `base_std_assert_indexed_array` when a helper accepts a caller-owned array by name.
Callers should declare those variables with `declare -a` or an indexed-array
assignment before passing them to array-mutating helpers.

Use `base_std_assert_associative_array` when a helper accepts a caller-owned associative
array by name. Callers should declare those variables with `declare -A` before
passing them to map-mutating helpers.

The assertions favor clear failure messages over scattered one-off tests. Some
helpers check all provided values and report all missing items together.
Use `base_std_assert_executable` for explicit paths to project-local tools or scripts;
use `base_std_assert_command_exists` for commands that should be discoverable through
`PATH`.

## Interactive Helpers

For interactive scripts:

```bash
if base_std_ask_yes_no "Continue?"; then
    base_std_log_info "Continuing."
fi

base_std_wait_for_enter "Press Enter after reviewing the output."
```

Use `base_std_is_interactive` before prompting from code paths that might run in CI,
cron, or another non-interactive environment:

```bash
if base_std_is_interactive; then
    base_std_ask_yes_no "Install optional tools?" || return 0
fi
```

## Suggested Script Pattern

A small Base-style Bash command should look like this:

```bash
#!/usr/bin/env bash

main() {
    local project="${1:-}"

    if [[ -z "$project" ]]; then
        base_std_print_error "Project name is required."
        return 2
    fi

    base_std_assert_command_exists git
    base_std_log_info "Checking project '$project'."
    base_std_run git status --short
}

main "$@"
```

When the script runs through `basectl`, the Base runtime provides the stdlib and
calls `main` with wrapper flags already filtered out.

For standalone scripts that source the library directly:

```bash
#!/usr/bin/env bash
source "/path/to/base-bash-libs/lib/bash/std/lib_std.sh"

declare -a app_args=()
base_init app_args --source "${BASH_SOURCE[0]}" -- "$@"

main() {
    base_std_set_log_level DEBUG
    base_std_run echo "hello"
}

main "${app_args[@]}"
```

## What Belongs Here

`lib_std.sh` should contain small, broadly useful primitives for Bash code:

- logging
- error handling
- path manipulation
- command execution
- imports
- validation
- simple filesystem safety wrappers
- exit cleanup registration
- temporary file and directory creation
- command and function introspection

Domain-specific behavior should live in other libraries or command modules. For
example, Git helpers belong in a Git library, file editing helpers belong in a
file library, and artifact setup behavior belongs in setup code.

## Tests

BATS coverage lives in:

```text
lib/bash/std/tests/lib_std.bats
```

When changing this library, run:

```bash
bats lib/bash/std/tests/lib_std.bats
```

For command-level changes that depend on stdlib behavior, also run the relevant
command BATS tests.
