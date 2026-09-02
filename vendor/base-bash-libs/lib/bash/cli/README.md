# `lib_cli.sh`

Declarative command contracts for professional Bash applications. The module
keeps the command model, parser, validation rules, help output, and completion
metadata in one source of truth. It is one sourceable file and requires
`lib/bash/std/lib_std.sh` first.

## Public API

- `base_cli_model_init MODEL [name=PROGRAM] [version=VERSION] [description=TEXT] [handler=FUNCTION]`
- `base_cli_declare MODEL [ROW...]` builds the same model from compact,
  pipe-delimited data rows. With no `ROW` arguments it reads rows from stdin,
  making a quoted heredoc a convenient declaration table. Row kinds are
  `model`, `command`, `option`, and `positional`; values may contain spaces,
  but `|` is reserved as the field delimiter. The helper applies parent
  commands before children, so rows may be ordered for readability, and never
  evaluates row contents as shell code.
- `base_cli_validate_model MODEL` checks all declared handlers after the model
  and application functions have been loaded; use it in tests or CI.
  starts or replaces a model. `MODEL` is an in-process identifier and `name`
  is the executable name shown in usage and completion output.
- `base_cli_command MODEL PATH DESCRIPTION [HANDLER] [aliases=A,B]` declares a
  nested command. `PATH` uses slash-separated command segments, and aliases are
  accepted at every segment while parsing and completing.
- `base_cli_option MODEL PATH NAME TYPE TOKEN... [help=TEXT] [metavar=NAME]
  [default=VALUE] [required=true|false] [enum=A,B] [validator=FUNCTION]
  [conflicts=A,B] [sensitive=true|false] [hidden=true|false]` declares a
  `flag`, single `value`, or `repeatable` option. Tokens are exact `-x` or
  `--long` spellings; long options also accept `--long=value` for value kinds.
  Conflict names must refer to options already declared on the same or an
  ancestor command. Sensitive defaults are redacted in generated help.
- `base_cli_positional MODEL PATH NAME [required=true|false]
  [repeatable=true|false] [default=VALUE] [enum=A,B] [validator=FUNCTION]
  [help=TEXT] [metavar=NAME]` declares a positional argument. A repeatable
  positional must be the final positional in its command.
- `base_cli_help MODEL [PATH]` renders deterministic help to stdout.
- `base_cli_parse MODEL -- [ARGV...]` parses and validates an invocation. It
  returns `0` on success, `2` for usage/validation errors, and publishes the
  result in the `BASE_BASH_LIBS_CLI_RESULT_*` globals described below.
- `base_cli_run MODEL -- [ARGV...]` parses, then invokes the declared handler
  for the selected command. A handler receives positional values as ordinary
  Bash arguments and reads options through the result helpers.
- `base_cli_complete MODEL -- [WORDS...]` prints one completion candidate per
  line for the current prefix (the final word). `base_cli_completion_script
  MODEL FUNCTION` emits a portable Bash completion function.
- `base_cli_result_get KEY RESULT_VARIABLE`,
  `base_cli_result_get_positional INDEX RESULT_VARIABLE`, and
  `base_cli_result_count KEY RESULT_VARIABLE` copy parsed values into
  caller-owned variables without command substitution.

## Result contract

After a successful run parse:

- `BASE_BASH_LIBS_CLI_RESULT_OPTIONS` is an associative array of scalar
  option values. Flags have value `1` when present.
- `BASE_BASH_LIBS_CLI_RESULT_REPEATED` is keyed by `NAME|INDEX`, and
  `BASE_BASH_LIBS_CLI_RESULT_REPEATABLE_COUNTS[NAME]` records the count.
- `BASE_BASH_LIBS_CLI_RESULT_POSITIONALS` preserves positional boundaries,
  including empty values and values beginning with `-` after `--`.
- `BASE_BASH_LIBS_CLI_RESULT_MODEL`, `..._COMMAND`, and `..._ACTION` identify
  the model, canonical command path, and `run`, `help`, or `version` action.

Results are valid after a successful parse. A failed parse returns status `2`
and may have partially inspected input, but does not claim a valid result.

## Example

The quick declaration layer is useful for a small or generated command table:

```bash
base_cli_declare deploy <<'EOF'
model|name=deploy|version=2.0.0|description=Release tooling
command|path=release|description=Create a release|handler=deploy_release|aliases=r
option|path=release|name=dry_run|type=flag|tokens=--dry-run,-n|help=Do not mutate
option|path=release|name=channel|type=value|tokens=--channel|default=stable|enum=stable,canary
positional|path=release|name=target|required=true|metavar=TARGET
EOF
```

The lower-level calls below remain available when declarations are built
programmatically or a caller needs full control over the order of individual
mutations.

```bash
source "/path/to/base-bash-libs/lib/bash/std/lib_std.sh"
base_std_import cli/lib_cli.sh

base_cli_model_init deploy name=deploy version=2.0.0 description="Release tooling"
base_cli_command deploy release "Create a release" handler=deploy_release aliases=r
base_cli_option deploy release dry_run flag --dry-run -n help="Do not mutate"
base_cli_option deploy release channel value --channel default=stable enum=stable,canary
base_cli_option deploy release artifact repeatable --artifact help="Input artifact"
base_cli_positional deploy release target required=true metavar=TARGET

deploy_release() {
    local channel
    base_cli_result_get channel channel
    printf 'releasing %s via %s\n' "${1-}" "$channel"
}

base_cli_run deploy -- release target --channel canary --artifact app.tgz
```

## Adapter boundary

The native model above is the canonical runtime contract. Projects may generate
the same model from Bashly, Argc, Argbash, or another generator, but generated
artifacts belong at an adapter/build boundary. The runtime does not detect,
install, or require Python, Ruby, Node, `jq`, or any external generator.

## Tests

BATS coverage lives in `lib/bash/cli/tests/lib_cli.bats`.
