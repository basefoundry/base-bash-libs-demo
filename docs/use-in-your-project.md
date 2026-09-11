# Use Base Bash in your project

Start with one command and one handler. The application below relies only on
the released v2 public API and delegates parsing, validation, help, and
dispatch to Base Bash.

<!-- BEGIN MINIMAL CONSUMER -->
```bash
#!/usr/bin/env base-bash

# shellcheck shell=bash

base_std_import cli/lib_cli.sh
base_require_version 2.0.0 || base_std_fatal_error "This example requires Base Bash 2.0.0 or newer."

base_cli_model_init starter \
    name=starter version=0.1.0 \
    description="Minimal Base Bash consumer"
base_cli_command starter greet "Greet one person" handler=starter_greet
base_cli_positional starter greet name required=true metavar=NAME

starter_greet() {
    printf 'Hello, %s!\n' "$1"
}

main() {
    base_cli_run starter -- "$@"
}
```
<!-- END MINIMAL CONSUMER -->

Save it as an executable such as `bin/starter`. The shebang deliberately asks
for `base-bash`; the dependency mode determines which launcher is found on
`PATH`, while the application remains unchanged.

## Try the vendored release

This repository already carries a verified v2.0.0 release, so the example is
offline and immediately runnable:

```bash
PATH="$PWD/vendor/base-bash-libs/bin:$PATH" ./examples/minimal-cli --help
PATH="$PWD/vendor/base-bash-libs/bin:$PATH" ./examples/minimal-cli greet Ada
```

The second command prints `Hello, Ada!`. For your own repository, copy a
verified release under a stable path, record its version and full commit, and
place its `bin` directory on `PATH`. Beacon's `base-bash-libs.lock`,
`vendor/evidence`, and `scripts/verify-vendor` show the full auditable model.

## Use a Homebrew installation

When a managed installation is preferable to vendoring:

```bash
brew trust basefoundry/base
brew install basefoundry/base/base-bash-libs
./examples/minimal-cli greet Ada
```

Homebrew places `base-bash` on `PATH`; it also supplies the supported Bash
runtime required on macOS. Pin and test the package version according to your
deployment policy rather than assuming every machine upgrades together.

## Grow deliberately

The minimal consumer imports only the CLI module. Add modules only when the
application needs their contracts:

- `app/lib_app.sh` for typed configuration, standard options, and lifecycle;
- `file/lib_file.sh` for idempotent file-section operations;
- `git/lib_git.sh` for Git inspection and update helpers;
- `str/lib_str.sh` and `list/lib_list.sh` for named string and array results.

The [public API reference](https://github.com/basefoundry/base-bash-libs/blob/main/docs/api-reference.md)
defines the available symbols. The upstream
[five-minute quickstart](https://github.com/basefoundry/base-bash-libs/blob/main/docs/v2/quickstart.md)
shows the current immutable release path. Use Beacon's
[five-minute tutorial](five-minute-tutorial.md) when you are ready for a
production-shaped consumer with configuration, lifecycle, redaction, and
verified artifacts.
