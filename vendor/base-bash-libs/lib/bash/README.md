# Bash Libraries

Reusable Bash libraries for command wrappers and other Bash tooling.

## Layout

- `std/`
  Foundation library with logging, error handling, PATH helpers, and other
  shared Bash primitives.
- `git/`
  Git-related helpers built on top of the stdlib.
- `gh/`
  GitHub CLI helpers built on top of the stdlib.
- `file/`
  File-editing helpers built on top of the stdlib.
- `str/`
  String helpers built on top of the stdlib.
- `arg/`
  Argument parsing helpers built on top of the stdlib.
- `list/`
  Indexed-array helpers built on top of the stdlib.
- `cli/`
  Declarative command contracts with parsing, validation, help, and completion.
- `app/`
  Optional application policy for typed configuration, standard options,
  prompts, and exactly-once lifecycle hooks.
- `tests/`
  Common BATS helpers for Bash library test suites.
- `base-bash-libs.release`
  Embedded release identity copied with installed, archived, vendored, and
  standalone `lib/bash` artifacts.

The Base runtime shell files and Base version helpers remain in
`basefoundry/base`. This repository carries only sourceable reusable library
modules.

## Caller Runtime Contract

All public modules support Bash 4.2 or newer with every combination of caller-
selected `errexit`, `nounset`, and `pipefail`. Sourcing a module is passive: it
does not change those settings, any other `set` or `shopt` option, `IFS`,
`OPTIND`, the working directory, the umask, traps, exports, or ordinary
positional arguments. After sourcing `lib_std.sh`, callers explicitly invoke
`base_init` to initialize runtime state and receive wrapper-filtered
arguments in a caller-owned array.

Public API calls preserve the same process state unless their documented
purpose is to change it. Examples of intentional mutation include PATH helpers,
`base_std_safe_cd`, caller-owned output variables, file-editing helpers, and cleanup
registrations while a hook or path remains active. Transient internal cleanup
registrations restore the caller's preexisting `EXIT` trap when the operation
finishes.

Required arity is checked before a public helper expands a required positional
parameter, so a usage error remains diagnosable with caller `nounset` enabled.
Predicates and recoverable failures intentionally return nonzero; callers using
`errexit` should invoke expected nonzero results in `if`, `while`, `&&`, or
another Bash conditional context.

The standalone `tests/bash-option-contract.sh` matrix sources every module and
exercises success, usage, predicate, and recoverable-failure paths in all eight
option combinations. CI runs that matrix on the current macOS and Ubuntu Bash
runtimes and in the digest-pinned, networkless Bash 4.2.53 compatibility image.

## Naming Contract

The v2 `base_` namespace is part of the sourceable-library contract:

- Public functions use `base_<module>_<name>`. The stdlib lifecycle
  functions are `base_init` and `base_require_version`,
  while the remaining stdlib functions use the `base_std_` segment.
- Framework-owned globals, configuration variables, metadata, and load guards
  use `BASE_BASH_LIBS_...`.
- Implementation-only functions use `__base_bash_libs_<module>_...__` and are
  not a supported call surface.

Libraries do not define generic aliases for the old v1 names. This keeps
default loading safe for applications that already have functions such as
`import`, `log_info`, or `str_trim`. See
[`docs/v2-api-contract.md`](../../docs/v2-api-contract.md) for the complete
status/effects charter, and [`docs/v2-symbol-map.md`](../../docs/v2-symbol-map.md) for the complete mapping
and [`scripts/migrate-v2-symbols`](../../scripts/migrate-v2-symbols) for a
mechanical migration aid. The single-file boundary remains unchanged: each
public library is still one physical `.sh` file.

Public helpers that accept caller-supplied variable or array names reserve the
`__` prefix for library-internal state. Passing a caller-owned source or result
name that begins with `__` fails before the helper changes caller state. Use a
regular Bash variable name for public input and output values and arrays.
`base_std_assert_variable_name` is the syntax-only exception: it validates whether any
identifier is legal Bash syntax, including names in the reserved namespace,
without reading or writing the named variable.

When one API accepts multiple caller-owned inputs or outputs, names that would
alias an input with an output are rejected before mutation. The module README
for that API documents the required distinct-name relationships.

## Import contract

Source the stdlib once, then load every companion module with the same
package-relative API:

```bash
source "/path/to/base-bash-libs/lib/bash/std/lib_std.sh"
base_std_import str/lib_str.sh file/lib_file.sh
```

`base_std_import` resolves paths from the loaded package's `lib/bash` root, so
the caller's cwd, script directory, Homebrew `libexec` layout, vendored tree,
and symlinked installation path do not change the import. Absolute paths,
`..` traversal, and symlinks that escape the package are rejected. Repeated
loads are no-ops; dependency cycles and mixed-major package graphs fail with
diagnostics. The launcher's `base_launcher_import_base_bash_lib` name is only
a thin process-boundary adapter to this same loader.

The loader promotes top-level `declare` statements in a module to global
declarations while it is sourced. Module authors can therefore write normal
module-level declarations without knowing that the loader itself is a
function; declarations executed later inside public functions retain normal
Bash scope rules. Every module remains a single physical `.sh` file.

## Standalone launcher contract

`bin/base-bash` provides the application boundary for scripts that use the
stdlib. `base-bash --help` and `--version` are successful stdout commands;
malformed invocations use stderr and status `2`. `base-bash check` is a
non-mutating diagnostic for Bash support, installation health, package identity,
imports, and external tools. See the normative [v2 launcher contract](../../docs/v2-api-contract.md#6-launcher-contract-v2-rc)
for the complete stream, status, lifecycle, signal, cleanup, and wrapper-flag
mapping rules.

The launcher initializes once, sources the application once, calls `main` once,
and preserves application argv boundaries and the primary application status.
It does not enable strict mode. Use `--` before a script path that begins with
a dash; the launcher separator itself is not forwarded. The standard cleanup
registry composes application hooks with existing traps and preserves `130` for
INT and `143` for TERM.
