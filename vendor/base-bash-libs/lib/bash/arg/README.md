# `lib_arg.sh`

Argument and option parsing helpers for Base-style Bash scripts.

## Dependency

Source `lib/bash/std/lib_std.sh` before this library so validation and logging
helpers are available.

## Public API

- `base_arg_parse <options_array> <positionals_array> <specs_array> -- [args...]`
  Parse exact flag, value, and repeatable options into caller-owned arrays.
  Returns `0` on success, `1` for invalid caller-owned variable contracts, and
  `2` for malformed specs, unknown options, or missing values; caller-owned
  outputs are published only after a successful parse.

The options, positionals, and specs arrays must have distinct names. Every
repeatable option's output array must also be distinct from those three arrays.
Aliasing is rejected before any caller-owned output is changed.

## Usage

```bash
source "/absolute/path/to/lib/bash/std/lib_std.sh"
declare -a app_args=()
base_init app_args --source "${BASH_SOURCE[0]}" --
base_std_import arg/lib_arg.sh

declare -A options=()
declare -a positionals=()
declare -a include=()
specs=(
  "verbose|flag|--verbose|-v"
  "output|value|--output|-o"
  "include|repeatable|--include|-I"
)

base_arg_parse options positionals specs -- "$@" || exit $?

if [[ "${options[verbose]-}" == "1" ]]; then
    base_std_set_log_level DEBUG
fi
```

Spec entries use `name|kind|token[|token...]`:

- `name` is the associative-array key populated in the options result.
- `kind` is `flag`, `value`, or `repeatable`.
- each `token` is an exact option token, such as `--verbose` or `-v`.

Repeatable specs require a caller-declared indexed array with the same name as
the spec. Each occurrence is appended in input order, and the options result
contains that name with value `1` when at least one value was provided. A
successful parse with no occurrences clears the repeatable array.

The parser supports `--option value`, `--option=value`, repeated scalar options
where the last value wins, repeatable values in input order, and `--` to stop
option parsing. When a value option is waiting for a value, a standalone `--`
is treated as that value; use another `--` if you also need to stop option
parsing after it. A value option followed by another registered option token is
treated as missing its value; use `--option=value` when a value is intentionally
option-like. Unknown options, duplicate or unreachable spec tokens, malformed
specs, and missing values return status `2`. Caller-owned outputs are published
only after a successful parse.

## Tests

BATS coverage lives in `lib/bash/arg/tests/lib_arg.bats`.
