# base-bash-libs v2 API contract

This document is the normative, human-readable contract for the v2 sourceable
Bash libraries. It is intentionally separate from the machine-readable API
manifest planned for #225. The single-file rule in `STANDARDS.md` remains in
force: every library listed here is implemented by one physical `.sh` file.

## 1. Process and status model

Library functions are callable components, not miniature applications. They
return to their caller and never terminate the caller's shell unless the name
explicitly says that it is fatal or exits:

- `base_std_exit_if_error` and `base_std_fatal_error` are the intentional
  fail-fast escape hatches. They log, dump a trace where appropriate, and
  terminate the process.
- `base_launcher_*` is an executable entrypoint implementation. Its `die`,
  re-exec, and script-run paths may terminate because the launcher owns the
  process boundary.
- `base_std_assert_*` functions are explicit precondition assertions. They are
  fail-fast by design; callers that need recoverable validation should use a
  predicate or validate inputs before calling an assertion.

All other public library functions return a status. The common status classes
are:

| Status | Meaning |
| --- | --- |
| `0` | Success, or a true predicate. |
| `1` | False predicate or recoverable operational failure. |
| `2` | Usage or contract error (arity, malformed option, invalid output name, or invalid value). |
| `3`–`5` | Module-specific Git freshness outcomes documented by `lib_git.sh`. |
| `6` | Optimistic-concurrency conflict: a file changed after it was read and before an atomic commit. |
| `124` | Command attempt exceeded its requested timeout. |
| `125` | Framework/supervisor failure while enforcing a command timeout. |
| `128+n` | A child or supervisor was interrupted by signal `n`. |

Functions preserve the status of a useful underlying operation where doing so
is meaningful, but callers should rely on the documented class rather than a
platform-specific utility's exact status.

## 2. Output, diagnostics, and named outputs

- Standard output is data: paths, predicates represented as values, Git
  listings, and explicit `print_*` output. A successful mutator is silent
  unless its module documentation says it reports progress.
- Diagnostics, warnings, logs, usage text, traces, and failure explanations
  go to standard error. They never contaminate command-substitution data.
- APIs that return a value use one pass-by-name result as their first argument,
  followed by inputs. Result arrays are caller-declared indexed arrays and
  scalar results are caller-owned variables.
- Before any side effect, an output name is checked for valid Bash identifier
  syntax, the reserved `__` prefix, readonly status, correct array kind, and
  aliases with an input or another output. On failure, outputs remain
  unchanged unless an API explicitly documents partial mutation.
- Named-output APIs are preferred over command substitution for values that
  may contain newlines, whitespace, or leading dashes.

## 3. Effects and repeatability

Each public function documents the following dimensions in its module README:

- **Mutation:** whether caller variables, `PATH`, the working directory,
  traps/cleanup registries, environment variables, or files are changed.
- **Idempotency:** whether repeating the call is a no-op, repeats an operation,
  or is rejected.
- **Dry run:** mutating command wrappers honor `BASE_BASH_LIBS_DRY_RUN`; a
  dry-run plan is emitted as a diagnostic on stderr and does not mutate.
- **Environment and shell state:** libraries do not enable strict mode, change
  `IFS`, consume positional parameters while sourced, or silently alter
  caller traps/options. APIs whose purpose is to change `PATH`, `PWD`, or a
  cleanup registry say so explicitly.
- **Filesystem:** paths are handled literally, temporary files are cleaned
  through the shared cleanup registry, and atomic file replacement is used
  where the operation mutates an existing file.

## 4. Import and package identity

`base_std_import <module>...` is the only module-loading contract. Each module
argument is relative to the loaded package's `lib/bash` root (for example,
`str/lib_str.sh`); absolute paths and paths containing traversal components are
invalid. The loader resolves symlinks before checking that the target remains
inside that root, records `loading`/`loaded` state for idempotence and cycle
detection, and requires the std dependency before companion modules. Imports do
not depend on cwd, application script directory, Homebrew's `libexec` layout,
or the location of a vendored copy.

The loader promotes top-level module `declare` statements to global
declarations while the source file is evaluated, eliminating the function-
scoped sourcing footgun without changing declarations executed later inside
public functions. Every module remains one physical sourceable `.sh` file.

`lib/bash/base-bash-libs.release` carries the embedded release identity used
when a copied, vendored, source-archive, Homebrew, or standalone artifact has
no repository `VERSION` file. `BASE_BASH_LIBS_COMMIT` and
`BASE_BASH_LIBS_DIRTY_STATE` report checkout provenance distinctly from the
artifact's version; unknown values are explicit rather than inferred from cwd.
Loading a second stdlib from another major version is rejected with migration
guidance. v1 inputs are never fallback-loaded into a v2 module graph.

## 5. Interactive behavior

`base_std_ask_yes_no MESSAGE [yes|no]` defaults to `no` and displays `[y/N]`;
passing `yes` displays `[Y/n]`. `y`/`n` are accepted case-insensitively, and
Enter accepts the displayed default. Invalid input is reprompted. Missing
`/dev/tty`, EOF, and non-interactive use return `1` without terminating.
`base_std_wait_for_enter` has the same non-TTY/EOF rule. Neither API reads from
or mutates the caller's ordinary stdin stream.

## 6. Launcher contract (v2 RC)

`bin/base-bash` is a conventional application launcher. This contract is
frozen for the v2 release candidate; later v2 changes require an explicit
contract amendment rather than silently changing process, argv, or output
semantics.

### Commands and streams

- `base-bash --help` (or `-h`/`help`) writes usage to stdout and returns `0`.
- `base-bash --version` (or `-V`) writes the launcher/package version,
  commit, dirty state, and provenance to stdout and returns `0`.
- `base-bash check` performs a non-mutating diagnostic of Bash support,
  launcher installation, package identity, companion imports, and required or
  optional external tools. It writes `OK`, `WARN`, `SKIP`, and `ERROR` records
  to stdout and returns `0` when required checks pass, otherwise `1`.
- Missing scripts, unknown launcher options, extra command arguments, and
  malformed launcher invocations write an explanation and usage to stderr and
  return `2`. Application failures are not converted into usage errors.

The launcher itself requires Bash 4.2 or newer. On macOS Bash 3.2, a launcher
invocation that runs an application searches the supported candidate paths and
re-execs itself with the first usable candidate. `--help`, `--version`, and
`check` remain diagnostic commands and do not run the application.

### Application lifecycle and argv

For `base-bash [--] <script> [args...]`, the launcher resolves the script and
package without changing the caller's working directory, sources the stdlib
once, calls `base_init` once with the script path, sources the application once,
and calls its `main` function exactly once. The script's arguments retain their
original boundaries and the return status from `main` (or a fatal application
failure) is the launcher's status. The launcher does not enable Bash strict
mode or rewrite application traps/options. A script whose path begins with a
dash is selected with the launcher's `--` separator; that separator is not
forwarded to the application.

The shared stdlib cleanup registry composes application cleanup hooks with
existing `EXIT`, `INT`, and `TERM` traps. Hooks run exactly once, in LIFO order,
before the launcher exits, while signal-derived statuses remain `130` for INT
and `143` for TERM.

### One-time wrapper-flag mapping

The current wrapper controls are consumed by `base_init` only before the first
argument separator. Everything after that separator is literal application
argv. This mapping is the v2 migration reference:

| Existing control | v2 behavior |
| --- | --- |
| `--debug-wrapper` | Enables DEBUG logging and is removed from application argv. |
| `--verbose-wrapper` | Preserves the deprecated VERBOSE compatibility level and is removed from application argv. |
| `--utc-wrapper` | Exports UTC logging for the initialized runtime and is removed from application argv. |
| `--color` | Requests terminal colors and is removed from application argv. |
| `base_init --` | Stops wrapper parsing; the separator and all following values remain literal application argv. (The launcher's own script-selection `--` is not forwarded.) |

No other launcher option is implicitly forwarded. Applications that need an
option beginning with `--` should place it after the first application `--`.

## 7. File mutation guarantees

`base_file_update_file_section` is idempotent and uses a temporary file followed
by an atomic replacement. It resolves symlinks to edit the referent while
leaving the symlink in place, preserves the target mode, and cleans temporary
paths on every failure. Before committing, it compares device, inode, size,
modification time, and change time with a fingerprint captured before the
read. A concurrent change returns status `6` and leaves the newer target
untouched. A failed read, copy, permission preservation, or commit returns a
recoverable nonzero status and never reports success.

## 8. Complete public-surface audit

The following is the complete v2 surface. The module README is the detailed
signature/effects reference; this table makes coverage auditable.

| Module | Public functions | Default result/effect contract |
| --- | --- | --- |
| lifecycle | `base_init`, `base_require_version` | Return recoverable setup/version statuses; initialize caller-owned state only once. |
| std predicates and setup | `base_std_is_interactive`, `base_std_check_bash_version`, `base_std_import`, `base_std_add_to_path`, `base_std_dedupe_path`, `base_std_print_path`, `base_std_set_log_level`, `base_std_set_log_category_level`, `base_std_log_is_enabled` | Predicates return `0/1`; package-relative import and configuration return `0/1/2`; imports are idempotent, dependency-aware, cycle-safe, cwd-independent, and reject traversal/package-root escape; PATH and log settings intentionally mutate their documented state. |
| std logging and display | `base_std_log_fatal`, `base_std_log_error`, `base_std_log_warn`, `base_std_log_info`, `base_std_log_debug`, `base_std_log_verbose`, `base_std_log_info_file`, `base_std_log_debug_file`, `base_std_log_verbose_file`, `base_std_log_info_enter`, `base_std_log_debug_enter`, `base_std_log_verbose_enter`, `base_std_log_info_leave`, `base_std_log_debug_leave`, `base_std_log_verbose_leave`, `base_std_print_error`, `base_std_print_warn`, `base_std_print_info`, `base_std_print_success`, `base_std_print_bold`, `base_std_print_message`, `base_std_print_tty`, `base_std_dump_trace` | Diagnostics use stderr; explicit print/data helpers use stdout as documented; logging itself does not terminate. |
| std process/error | `base_std_exit_if_error`, `base_std_fatal_error`, `base_std_is_dry_run`, `base_std_run`, `base_std_run_or_exit` | Explicitly named fatal helpers and `base_std_run_or_exit` terminate; dry-run is a predicate; `base_std_run` returns command/timeout/supervisor status and never hides diagnostics. |
| std filesystem/cleanup | `base_std_safe_mkdir`, `base_std_safe_touch`, `base_std_safe_truncate`, `base_std_register_cleanup_hook`, `base_std_unregister_cleanup_hook`, `base_std_register_cleanup_path`, `base_std_unregister_cleanup_path`, `base_std_make_temp_file`, `base_std_make_temp_dir` | Mutators return recoverable failures; cleanup/temp APIs mutate only their documented registry and owned paths. |
| std validation/reflection | `base_std_assert_variable_name`, `base_std_assert_indexed_array`, `base_std_assert_associative_array`, `base_std_command_path`, `base_std_function_exists`, `base_std_assert_function_exists`, `base_std_assert_not_null`, `base_std_assert_integer`, `base_std_assert_integer_range`, `base_std_assert_arg_count`, `base_std_assert_command_exists`, `base_std_assert_file_exists`, `base_std_assert_executable`, `base_std_assert_dir_exists` | Predicates return status; explicit `assert_*` APIs are intentional fail-fast precondition checks; named outputs are validated before writes. |
| std miscellaneous | `base_std_safe_cd`, `base_std_safe_unalias`, `base_std_get_my_source_dir`, `base_std_ask_yes_no`, `base_std_wait_for_enter` | `safe_cd` changes `PWD`; source-dir writes one validated output; interactive functions return recoverable EOF/non-TTY statuses. |
| file | `base_file_section_exists`, `base_file_section_needs_update`, `base_file_update_file_section` | Read-only predicates do not mutate; update is idempotent, symlink-preserving, atomic, metadata-preserving, and conflict-aware. |
| git | `base_git_detect_default_branch`, `base_git_worktree_path_for_branch`, `base_git_list_worktree_branches`, `base_git_branch_upstream`, `base_git_branch_merged_to_ref`, `base_git_list_remote_branches`, `base_git_update_repo`, `base_git_get_current_branch`, `base_git_check_script_up_to_date` | Usage and contract errors return `2`; recoverable Git failures and false predicates return `1` unless a function documents a specific status. Read-only inspections use named outputs/stdout as documented; freshness outcomes are `3` dirty, `4` behind, and `5` diverged. |
| gh | `base_gh_require_cli`, `base_gh_auth_status_diagnostics`, `base_gh_report_command_failure`, `base_gh_run`, `base_gh_repo_from_remote_url`, `base_gh_infer_repo_from_origin`, `base_gh_repo_default_branch`, `base_gh_api_with_retry` | Usage and contract errors return `2`; recoverable GitHub failures return `1` unless the helper preserves the underlying `gh` status. Diagnostics go stderr; repository/API values use named outputs; retries are bounded and mutation-aware. |
| str | `base_str_lower`, `base_str_upper`, `base_str_ltrim`, `base_str_rtrim`, `base_str_trim`, `base_str_contains`, `base_str_starts_with`, `base_str_ends_with`, `base_str_split`, `base_str_join` | String transforms/predicates preserve caller values until validation succeeds; split/join use validated named outputs. |
| arg | `base_arg_parse` | Parses into caller-owned validated arrays/maps and leaves them unchanged on failure. |
| list | `base_list_append`, `base_list_prepend`, `base_list_remove`, `base_list_contains`, `base_list_unique`, `base_list_length` | Indexed-array mutators/predicates use caller-owned arrays; usage and operational errors return rather than exit. |
| cli | `base_cli_declare`, `base_cli_model_init`, `base_cli_validate_model`, `base_cli_command`, `base_cli_option`, `base_cli_positional`, `base_cli_help`, `base_cli_parse`, `base_cli_run`, `base_cli_complete`, `base_cli_completion_script`, `base_cli_result_get`, `base_cli_result_get_positional`, `base_cli_result_count` | A single declarative model drives nested parsing, aliases, defaults, required/enum/validator/conflict checks, deterministic help, and completion. `base_cli_declare` is a data-only pipe-delimited table layer that orders parent commands before children and expands into the same low-level model calls; `base_cli_validate_model` provides an explicit post-declaration handler-wiring check for tests and CI. Successful parses publish fixed `BASE_BASH_LIBS_CLI_RESULT_*` globals; usage and validation errors return status `2`. |
| app | `base_app_init`, `base_app_config_define`, `base_app_config_set_cli`, `base_app_config_load`, `base_app_config_get`, `base_app_config_provenance`, `base_app_config_report`, `base_app_add_standard_options`, `base_app_apply_standard_options`, `base_app_should_prompt`, `base_app_prompt`, `base_app_hook`, `base_app_run`, `base_app_status` | Optional typed configuration and lifecycle policy. Configuration is data-only with CLI > environment > project > user > default precedence; reports redact secrets. Hooks are named functions, LIFO, exactly-once, and preserve the application status. |
| launcher | `base_launcher_check_project`, `base_launcher_die`, `base_launcher_resolve_path`, `base_launcher_package_root`, `base_launcher_ensure_supported_bash`, `base_launcher_lib_dir_is_usable`, `base_launcher_resolve_lib_dir`, `base_launcher_source_stdlib`, `base_launcher_import_base_bash_lib`, `base_launcher_init`, `base_launcher_run_script`, `base_launcher_usage` | Entrypoint helpers may terminate only at the executable process boundary; path and usability helpers return status. `base_launcher_init` creates a deterministic minimal or standard scaffold and refuses divergent overwrites. `base_launcher_check_project` is non-mutating and emits human or JSON conformance records. `main` remains application-defined. |

### Declarative CLI contract

`lib_cli.sh` is the high-level application-facing command contract. The model
is declared once and is consumed by parsing, validation, help, and completion;
there is no separate handwritten usage path to drift. Command paths are
canonical slash-separated names, with aliases accepted at every segment.
Options support flags, scalar values, repeatable values, defaults, required
values, enums, Bash-function validators, conflicts, hidden entries, and
metavars. Positionals preserve boundaries and may be required, defaulted,
validated, or repeatable (only as the final positional).

`base_arg_parse` remains the low-level array parser for callers that need its
direct caller-owned output contract. It is not silently replaced. Bashly,
Argc, Argbash, and similar generators may adapt their build output into the
native model, but they are optional build-time adapters and never runtime
dependencies. The runtime stays Bash 4.2-compatible, avoids `eval`, and has no
mandatory Python, Ruby, Node, or `jq` dependency.

### Application policy contract

`lib_app.sh` is intentionally optional: applications that need only parsing can
use `lib_cli.sh` without adopting a configuration or lifecycle policy. When
used, `base_app_config_define` declares typed values and `base_app_config_load`
reads only key/value data; it never evaluates a file as shell code. Explicit
missing files and malformed or unknown records fail before the effective state
is reported. Secret values are available to application code through the
named-output API but are redacted from effective reports and provenance.

`base_app_run` composes named application hooks with the stdlib cleanup
dispatcher. A successful handler dispatches `normal`; a non-signal failure
dispatches `fatal`; INT, TERM, and HUP dispatch `int`, `term`, and `hup` with
statuses 130, 143, and 129. The selected phase and then `cleanup` run in LIFO
order at most once, and hook failures never replace the handler status.

## 9. v1.4.0 → v2 migration inventory

This release line is a deliberate clean break. There are no generic aliases and
no inconsistent legacy behavior retained for compatibility.

| Change | Migration consequence |
| --- | --- |
| Public namespace | The pre-release `base_bash_libs_*` names are replaced by the coherent `base_*` module namespace; globals remain `BASE_BASH_LIBS_*`. |
| Lifecycle | Sourcing is passive; callers invoke `base_init` explicitly. |
| Error handling | Ordinary imports, version checks, list mutators, safe filesystem helpers, directory changes, and source-dir resolution return statuses instead of terminating. Explicit `fatal`, `exit`, and `assert` names retain their intentional process semantics. |
| Interactive defaults | `base_std_ask_yes_no` supports `[y/N]` and `[Y/n]`, and Enter accepts the displayed default. |
| File safety | Section updates preserve symlinks/mode and return conflict status `6` when a concurrent writer wins the race. |
| Named outputs | Output-first, caller-declared, prevalidated pass-by-name signatures are mandatory; aliases and readonly/wrong-kind outputs fail before side effects. |

The symbol-level mapping remains in [`v2-symbol-map.md`](v2-symbol-map.md), and
the mechanical checker is [`scripts/migrate-v2-symbols`](../scripts/migrate-v2-symbols).
The machine-readable manifest is the checked-in companion to this audit; any
manifest disagreement is a release blocker.
