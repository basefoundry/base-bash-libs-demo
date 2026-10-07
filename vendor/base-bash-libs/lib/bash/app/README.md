# Application policy (`app`)

`lib_app.sh` is an optional policy layer for applications that use the `std`,
`cli`, and `str` modules. It keeps configuration and lifecycle policy out of the
foundation module while giving applications one small, composable contract.
The library imports `lib/bash/str/lib_str.sh` automatically for the shared TSV
field-escaping contract used by configuration reports.

The module is one sourceable file, is safe to source repeatedly, and never
executes configuration data. Configuration files contain only trimmed
`key=value` records; comments and blank lines are ignored. A malformed,
unknown, or explicitly requested missing file is an error.

## Configuration

`base_app_init MODEL` accepts only `name=APP_KEY` and `description=TEXT`.
`base_app_config_define MODEL KEY TYPE` accepts `env=NAME`, `default=VALUE`,
`required=BOOL`, `secret=BOOL`, `enum=A,B`, `validator=FUNCTION`, and
`help=TEXT`. Attributes from one declaration context are rejected in the
other with usage status `2`.

```bash
base_app_init deploy name=deploy description="Example application"
base_app_config_define deploy channel enum \
  enum=stable,canary default=stable env=DEPLOY_CHANNEL
base_app_config_define deploy token string required=true secret=true env=DEPLOY_TOKEN

base_app_config_load deploy --user "$HOME/.config/deploy/config" \
  --project ./deploy.conf --cli channel=canary
base_app_config_get deploy channel channel
base_app_config_provenance deploy channel source
```

The deterministic precedence is `CLI > environment > project > user >
default`. `base_app_config_report` prints `key`, source, and effective value
as tab-separated records and redacts values declared with `secret=true`.
Backslashes, tabs, carriage returns, and newlines in fields are escaped as
`\`, `\t`, `\r`, and `\n` so each record remains one safe line. See the
[shared TSV field escaping contract](../str/README.md#shared-tsv-field-escaping).
`base_app_config_set_cli` is a programmatic equivalent of `--cli key=value`.

`base_app_config_load` validates the complete candidate configuration before
publishing it. If loading fails, the previously successful values and
provenance remain unchanged; a successful load atomically replaces the
model's complete effective snapshot.

Supported types are `string`, `path`, `bool`, `integer`, and `enum`. Optional
`validator=FUNCTION` callbacks receive the candidate value and must return
zero. `base_app_config_get` writes integer-typed values to either an ordinary
scalar or a caller-declared integer (`-i`) scalar; other configuration types
require an ordinary scalar. Integer values use signed 64-bit decimal semantics;
leading zeroes are normalized before publishing to an integer (`-i`) output,
and values outside that domain are rejected without replacing the previous
successful configuration snapshot. No configuration value is evaluated as
shell code.

## Standard options and prompts

`base_app_add_standard_options CLI_MODEL COMMAND_PATH` adds opt-in
`--verbose`, `--quiet`, `--color`, `--dry-run`, `--non-interactive`,
`--config`, and `--user-config` options to a declarative CLI model.
`--color` accepts `auto`, `always`, or `never`; the bare legacy launcher
`--color` flag remains supported, and wrappers can use `--color-mode MODE`
when they need an explicit policy independent of the app's own CLI model.
An explicit wrapper mode takes precedence over the app's `--color` selection.
`auto` colors only when stderr is a terminal and `NO_COLOR` is unset;
`always` forces ANSI colors even for captured stderr or a set `NO_COLOR`, and
`never` disables them. `--quiet` sets the default logger threshold to `WARN`,
while `--verbose` sets it to `DEBUG`; the options are mutually exclusive.
`base_app_apply_standard_options` publishes the parsed policy in
`BASE_BASH_LIBS_APP_*` globals and applies the logging/color policy.
Applications should call
`base_app_should_prompt` before `base_app_prompt`; prompts are denied when
stdin is not interactive or `--non-interactive` was selected.

## Lifecycle

```bash
base_app_init deploy
base_app_hook deploy fatal report_failure report_failure_hook
base_app_hook deploy cleanup release_resources cleanup_hook
base_app_run deploy deploy_main "$@"
```

Hooks are named functions, receive `(phase, status)`, and run in LIFO order.
The normal/fatal/signal phase is followed by `cleanup`; each phase is
dispatched at most once per `base_app_run`, and the application status is
preserved even if a hook fails. `INT`, `TERM`, and `HUP` map to statuses
130, 143, and 129 respectively.

Runs may nest, including recursive runs of the same model. Each logical run
owns a separate lifecycle frame. A normally returning inner run dispatches
before the outer handler resumes; process exit or a signal unwinds every
active frame from inner to outer with the terminating status.

`base_app_status MODEL RESULT_VARIABLE` returns that model's most recent run or
signal-derived status. A newly initialized model that has not run reports `0`.
`BASE_BASH_LIBS_APP_LAST_STATUS` remains the compatibility view of the most
recently completed logical run, but model-aware callers should use
`base_app_status`. While handlers run, `BASE_BASH_LIBS_APP_ACTIVE_MODEL` names
the innermost model and is restored to the outer model when a nested run
returns. For same-model recursion, the inner status is visible until the outer
run completes and replaces that model's last status.

The policy module owns no global trap or shell-code strings itself. It uses
the stdlib's shared cleanup dispatcher and can therefore coexist with other
cleanup paths and hooks.

The focused BATS coverage is in
`lib/bash/app/tests/lib_app.bats`; the repository validation matrix also loads
the module under every supported Bash option combination.
