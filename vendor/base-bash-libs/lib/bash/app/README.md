# Application policy (`app`)

`lib_app.sh` is an optional policy layer for applications that use the `std`
and `cli` modules. It keeps configuration and lifecycle policy out of the
foundation module while giving applications one small, composable contract.

The module is one sourceable file, is safe to source repeatedly, and never
executes configuration data. Configuration files contain only trimmed
`key=value` records; comments and blank lines are ignored. A malformed,
unknown, or explicitly requested missing file is an error.

## Configuration

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
`\\`, `\\t`, `\\r`, and `\\n` so each record remains one safe line.
`base_app_config_set_cli` is a programmatic equivalent of `--cli key=value`.

Supported types are `string`, `path`, `bool`, `integer`, and `enum`. Optional
`validator=FUNCTION` callbacks receive the candidate value and must return
zero. No configuration value is evaluated as shell code.

## Standard options and prompts

`base_app_add_standard_options CLI_MODEL COMMAND_PATH` adds opt-in
`--verbose`, `--quiet`, `--color`, `--dry-run`, `--non-interactive`,
`--config`, and `--user-config` options to a declarative CLI model.
`base_app_apply_standard_options` publishes the parsed policy in
`BASE_BASH_LIBS_APP_*` globals. Applications should call
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

The policy module owns no global trap or shell-code strings itself. It uses
the stdlib's shared cleanup dispatcher and can therefore coexist with other
cleanup paths and hooks.

The focused BATS coverage is in
`lib/bash/app/tests/lib_app.bats`; the repository validation matrix also loads
the module under every supported Bash option combination.
