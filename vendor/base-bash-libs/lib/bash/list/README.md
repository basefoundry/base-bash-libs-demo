# `lib_list.sh`

Indexed-array helpers for Base-style Bash scripts.

The normative v2 status, output, and mutation rules are in
[`docs/v2-api-contract.md`](../../../docs/v2-api-contract.md).

## Dependency

Source `lib/bash/std/lib_std.sh` before this library so validation and error
helpers are available.

## Public API

- `base_list_append <array> <value> [value...]`
  Append one or more values to a named indexed array.
- `base_list_prepend <array> <value> [value...]`
  Prepend one or more values to a named indexed array.
- `base_list_remove <array> <value>`
  Remove all exact matches from a named indexed array.
- `base_list_contains <value> <array>`
  Predicate that checks whether a named indexed array contains a value.
- `base_list_unique <result_array> <source_array>`
  Store first-seen unique values in a named result array.
- `base_list_length <result_var> <source_array>`
  Store an array length in a named result variable.

## Usage

```bash
source "/absolute/path/to/lib/bash/std/lib_std.sh"
declare -a app_args=()
base_init app_args --source "${BASH_SOURCE[0]}" --
base_std_import list/lib_list.sh

declare -a packages=("jq")

base_list_append packages "shellcheck" "bats-core"
base_list_prepend packages "bash"

if base_list_contains "shellcheck" packages; then
    base_std_log_info "ShellCheck validation is available."
fi
```

Mutating helpers update the caller-owned array in place. Array arguments and
array result variables must already be declared as indexed arrays, for example
with `declare -a values=()`. `base_list_length` accepts an untyped or integer
(`-i`) scalar result; other string-valued scalar outputs must be untyped or
exported only. Integer and case-converting attributes are rejected when they
could coerce array or string data. Readonly variables and nameref outputs are
rejected before mutation.

For `base_list_unique` and `base_list_length`, the result and source variable names must
be distinct. An alias is rejected before the source is changed.

Usage and caller-contract errors return status `2`. Predicate misses and
operational failures return `1`; validation never terminates the caller.

## Tests

BATS coverage lives in `lib/bash/list/tests/lib_list.bats`.
