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

This repository already carries a verified v2.2.0 release, so the example is
offline and immediately runnable:

```bash
PATH="$PWD/vendor/base-bash-libs/bin:$PATH" ./examples/minimal-cli --help
PATH="$PWD/vendor/base-bash-libs/bin:$PATH" ./examples/minimal-cli greet Ada
```

The second command prints `Hello, Ada!`.

## Use a verified release in a new project

Choose the archive path when the application should be reproducible without
Homebrew or a sibling source checkout. The commands below download the
canonical v2.2.1 asset and all of its evidence, verify every checksum before
extracting anything, retain the full source identity in a project lockfile,
and then run a minimal consumer from a directory containing spaces. The
`BASE_BASH_LIBS_RELEASE_*` overrides are for the documentation test fixture;
normal users should leave them unset.

<!-- BEGIN EXTERNAL CONSUMER WALKTHROUGH -->
```bash
set -euo pipefail

release_version="${BASE_BASH_LIBS_RELEASE_VERSION:-2.2.1}"
release_tag="${BASE_BASH_LIBS_RELEASE_TAG:-v$release_version}"
release_base_url="${BASE_BASH_LIBS_RELEASE_URL:-https://github.com/basefoundry/base-bash-libs/releases/download/$release_tag}"
work_root="${BASE_BASH_LIBS_CONSUMER_ROOT:-$(mktemp -d "${TMPDIR:-/tmp}/base-bash-consumer.XXXXXX")}"
project_root="$work_root/consumer project"
release_root="$work_root/release"
mkdir -p "$project_root/vendor" "$release_root"

archive_name="base-bash-libs-v$release_version.tar.gz"
checksum_name="base-bash-libs-v$release_version.SHA256SUMS"
provenance_name="base-bash-libs-v$release_version.provenance.json"
sbom_name="base-bash-libs-v$release_version.spdx.json"
for release_asset in "$archive_name" "$checksum_name" "$provenance_name" "$sbom_name"; do
    curl -fsSL "$release_base_url/$release_asset" -o "$release_root/$release_asset"
done

# Verify the archive, checksum manifest, provenance, and SBOM before extraction.
(
    cd "$release_root"
    if command -v sha256sum > /dev/null 2>&1; then
        sha256sum -c "$checksum_name"
    else
        shasum -a 256 -c "$checksum_name"
    fi
)

framework_commit="$(sed -n 's/.*\"sourceCommit\": \"\([0-9a-f]\{40\}\)\".*/\1/p' "$release_root/$provenance_name" | sed -n '1p')"
[[ "$framework_commit" =~ ^[0-9a-f]{40}$ ]]
tar -xzf "$release_root/$archive_name" -C "$project_root/vendor"
mv "$project_root/vendor/base-bash-libs-v$release_version" \
    "$project_root/vendor/base-bash-libs"
framework_root="$project_root/vendor/base-bash-libs"
framework_version="$(< "$framework_root/VERSION")"
asset_sha256="$(sed -n "s/^\([0-9a-f]\{64\}\)[[:space:]]\+$archive_name$/\1/p" \
    "$release_root/$checksum_name")"
manifest_sha256="$(if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "$framework_root/MANIFEST.sha256"
else
    shasum -a 256 "$framework_root/MANIFEST.sha256"
fi)"
manifest_sha256="${manifest_sha256%% *}"
cat > "$project_root/base-bash-libs.lock" <<EOF
schema_version=1
version=$framework_version
commit=$framework_commit
asset=$archive_name
asset_sha256=$asset_sha256
manifest_sha256=$manifest_sha256
provenance=release-artifact
EOF

mkdir -p "$project_root/bin"
cat > "$project_root/bin/starter" <<'BASH'
#!/usr/bin/env base-bash

base_std_import cli/lib_cli.sh
base_require_version 2.0.0 || base_std_fatal_error "Base Bash 2.0.0 or newer is required."
base_cli_model_init starter name=starter version=0.1.0 description="Minimal Base Bash consumer"
base_cli_command starter greet "Greet one person" handler=starter_greet
base_cli_positional starter greet name required=true metavar=NAME
starter_greet() { printf 'Hello, %s!\n' "$1"; }
main() { base_cli_run starter -- "$@"; }
BASH
chmod +x "$project_root/bin/starter"

# Preparation above may use the network; this consumer run does not.
export BASE_BASH_LIBS_DIR="$framework_root/lib/bash"
export PATH="$framework_root/bin:$PATH"
"$framework_root/bin/base-bash" --version
"$project_root/bin/starter" --help
[[ "$("$project_root/bin/starter" greet Ada)" == 'Hello, Ada!' ]]
rm -rf "$release_root"
```
<!-- END EXTERNAL CONSUMER WALKTHROUGH -->

After the preparation step, the project has its own vendor tree and lockfile;
runtime execution does not need Base, Beacon, a sibling checkout, or network
access. Beacon's `base-bash-libs.lock`, `vendor/evidence`, and
`scripts/verify-vendor` show the corresponding auditable model for a committed
reference consumer. The committed vendor reflects the reviewed adoption work in
issue #38.

## Use a Homebrew installation

When a managed installation is preferable to vendoring:

```bash
brew trust basefoundry/base
brew install basefoundry/base/base-bash-libs
./examples/minimal-cli greet Ada
```

Homebrew places `base-bash` on `PATH`; it also supplies the supported Bash
runtime required on macOS. This command follows the current published Base Bash
release (v2.2.1). The demo's committed vendor remains v2.2.0 so the released
Beacon baseline stays reproducible; an external project should pin and test
the package version according to its deployment policy rather than assuming
every machine upgrades together.

## Grow deliberately

The minimal consumer imports only the CLI module. Add modules only when the
application needs their contracts:

- `app/lib_app.sh` for typed configuration, standard options, and lifecycle;
- `file/lib_file.sh` for idempotent file-section operations;
- `git/lib_git.sh` for Git inspection and update helpers;
- `str/lib_str.sh` and `list/lib_list.sh` for named string and array results.

The [v2.2.1 public API reference](https://github.com/basefoundry/base-bash-libs/blob/v2.2.1/docs/api-reference.md)
defines the available symbols in the vendored package. The upstream
[v2.2.1 five-minute quickstart](https://github.com/basefoundry/base-bash-libs/blob/v2.2.1/docs/v2/quickstart.md)
shows the immutable release path for a new consumer. Use Beacon's
[five-minute tutorial](five-minute-tutorial.md) when you are ready for a
production-shaped consumer with configuration, lifecycle, redaction, and
verified artifacts.
