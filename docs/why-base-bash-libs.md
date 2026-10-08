# Why Base Bash?

Base Bash is for Bash applications that have outgrown a one-off script but
still need Bash as their runtime. It replaces recurring infrastructure with a
released, testable contract; it does not replace application policy.

Beacon is useful evidence because it consumes only the public API committed in
`vendor/base-bash-libs/base_api_manifest.yaml`. The examples below are calls in
`lib/beacon.sh`, not hypothetical framework features.

## From shell plumbing to application policy

| Recurring Bash work | Beacon's Base Bash contract | What Beacon keeps |
| --- | --- | --- |
| Parse commands and options, reject invalid input, and render consistent help | `base_cli_model_init`, `base_cli_command`, `base_cli_option`, and `base_cli_run` declare and execute the command model | The meaning of `status`, `plan`, `collect`, and `verify` |
| Merge defaults, environment, project configuration, user configuration, and CLI values | `base_app_config_define`, `base_app_config_load`, `base_app_config_set_cli`, and `base_app_config_get` provide typed precedence | Workspace, output, lifecycle-log, and scenario policy |
| Compose normal exit, failure, `INT`, and `TERM` without losing the primary status | `base_app_hook` and `base_app_run` provide exactly-once lifecycle cleanup | The cleanup evidence Beacon records and its documented statuses |
| Create staging directories and remove them on failure without replacing an existing trap | `base_std_make_temp_dir` registers cleanup; `base_std_unregister_cleanup_path` transfers ownership after publication | Which files enter the stage and when a complete bundle may be published |
| Repeat checked directory, file, and command handling | `base_std_safe_mkdir`, `base_std_safe_truncate`, and `base_std_run` provide consistent failure behavior | Bundle layout, manifest format, and domain-specific diagnostics |
| Display the dependency that actually ran | `base_require_version` and the immutable `BASE_BASH_LIBS_VERSION`, `BASE_BASH_LIBS_COMMIT`, `BASE_BASH_LIBS_DIRTY_STATE`, and `BASE_BASH_LIBS_PROVENANCE` values expose package identity | Beacon's independent application version and release lifecycle |

## Code-level before and after

The following examples are illustrative, not Beacon's history. They show the
kind of plumbing a small Bash application would otherwise have to maintain.
The `before` version is intentionally short but runnable; the `after` version
uses the same public contracts that Beacon exercises.

<!-- BEGIN BEFORE AFTER CLI -->
### Command parsing and dispatch

Before, an application has to keep option parsing, usage text, validation, and
dispatch consistent by hand:

```bash
set -eu

usage() {
    printf 'usage: %s [-o PATH] {status|collect}\n' "${0##*/}"
}

output=''
while getopts ':o:h' option; do
    case "$option" in
        o) output="$OPTARG" ;;
        h) usage; exit 0 ;;
        :) printf 'missing value for -%s\n' "$OPTARG" >&2; usage >&2; exit 2 ;;
        \?) printf 'unknown option: -%s\n' "$OPTARG" >&2; usage >&2; exit 2 ;;
    esac
done
shift "$((OPTIND - 1))"

case "${1-}" in
    status) printf 'status=ready\n' ;;
    collect) printf 'collecting=%s\n' "${output:-default}" ;;
    *) usage >&2; exit 2 ;;
esac
```

After, the CLI contract generates help, option validation, and dispatch from
one declaration boundary:

```bash
base_cli_model_init beacon name=beacon version=0.1.0 \
    description="Offline support-bundle collector" handler=beacon_dispatch
base_cli_command beacon status "Show fixture and framework readiness" handler=beacon_dispatch
base_cli_command beacon collect "Create a redacted support bundle" handler=beacon_dispatch
base_cli_option beacon "" output value --output help="Support bundle directory" metavar=PATH
```
<!-- END BEFORE AFTER CLI -->

<!-- BEGIN BEFORE AFTER CLEANUP -->
### Temporary-directory cleanup

Before, an application owns a trap and must preserve it when another cleanup
path or signal handler is added later:

```bash
stage="$(mktemp -d)"
cleanup_stage() {
    rm -rf -- "$stage"
}
trap cleanup_stage EXIT
printf 'staging=%s\n' "$stage"
```

After, Base Bash composes cleanup ownership and lets the application transfer a
published path explicitly:

```bash
base_std_make_temp_dir stage beacon-demo
printf 'staging=%s\n' "$stage"
base_std_unregister_cleanup_path "$stage"
```

The lifecycle contract is executable evidence, not just prose:
`bats --filter 'cleanup evidence failure' tests/lifecycle.bats` demonstrates
that a cleanup-log failure does not replace the application's successful exit
status.
<!-- END BEFORE AFTER CLEANUP -->

For example, `beacon_collect` asks `base_std_make_temp_dir` for a staging
directory. The framework registers that path with its composed cleanup
lifecycle. Beacon can return from any later failure without adding a second
`trap 'rm -rf ...' EXIT` or deciding how that trap interacts with signals. Only
after the finished bundle is moved into place does Beacon call
`base_std_unregister_cleanup_path` to transfer ownership to the user.

Likewise, the CLI declarations at the top of `lib/beacon.sh` are the source of
help, option validation, and dispatch. Beacon does not maintain a separate
`case "$1"`, `getopts` loop, usage string, and parser state that can drift apart.

## What the framework does not own

Reusable mechanics do not make domain decisions. Beacon deliberately owns:

- which fixture files are safe and useful to collect;
- recognition and replacement of sensitive values inside collected payloads;
- the support-bundle manifest and verification rules;
- the user-facing meaning of each command and exit status; and
- the choice between `sha256sum` and `shasum` after Base Bash locates an
  available command.

Base Bash can redact configuration values declared as secret and sensitive CLI
display values, but it cannot infer how arbitrary application files should be
sanitized. Beacon's `beacon_load_secret_values` and
`beacon_write_redacted_file` remain application code for that reason.

Base Bash enforces Bash 4.2 or newer; the tested minimum is Bash 4.2.53. It does
not turn Bash into a cross-language runtime or make macOS `/bin/bash` 3.2
sufficient. Those are
adoption constraints, not hidden implementation details.

The [adoption decision guide](should-i-use-base-bash-libs.md) examines those
constraints, maintenance costs, and alternatives directly.

## The resulting trade

The application carries a pinned, verified dependency and follows its public
API and upgrade process. In return, it can review and test one shared
implementation of CLI, configuration, lifecycle, safe execution, and identity
contracts instead of maintaining a new private version in every Bash tool.

Run the proof locally:

```bash
./bin/beacon --help
./bin/beacon status
./bin/beacon collect --dry-run --non-interactive
./tests/lifecycle.bats
```

The [five-minute Beacon tutorial](five-minute-tutorial.md) follows the same
boundary from a user's perspective.
