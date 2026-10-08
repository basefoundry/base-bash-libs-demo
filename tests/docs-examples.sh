#!/usr/bin/env bash

set -euo pipefail

docs_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tutorial="$docs_root/docs/five-minute-tutorial.md"
example_script="$(mktemp "${TMPDIR:-/tmp}/beacon-docs-example.XXXXXX")"
output_root="$(mktemp -d "${TMPDIR:-/tmp}/beacon-docs-output.XXXXXX")"

cleanup() {
    rm -f "$example_script"
    rm -rf "$output_root"
}
trap cleanup EXIT

[[ "$(grep -c '^<!-- BEGIN RUNNABLE TUTORIAL -->$' "$tutorial")" == "1" ]]
[[ "$(grep -c '^<!-- END RUNNABLE TUTORIAL -->$' "$tutorial")" == "1" ]]

awk '
    /^<!-- BEGIN RUNNABLE TUTORIAL -->$/ { in_region = 1; next }
    /^<!-- END RUNNABLE TUTORIAL -->$/ { exit }
    in_region && /^```bash$/ { in_code = 1; next }
    in_region && in_code && /^```$/ { in_code = 0; next }
    in_region && in_code { print }
' "$tutorial" > "$example_script"

[[ -s "$example_script" ]]
/usr/bin/env bash -n "$example_script"
shellcheck --shell=bash "$example_script"

(
    cd -- "$docs_root"
    /usr/bin/env bash "$example_script"

    ./bin/beacon --help > "$output_root/help.txt"
    grep -Fq 'Offline support-bundle collector' "$output_root/help.txt"
    grep -Fq 'Commands:' "$output_root/help.txt"
    grep -Fq '  collect                Create a redacted support bundle' "$output_root/help.txt"

    ./bin/beacon status > "$output_root/status.txt"
    grep -Fxq 'application=beacon' "$output_root/status.txt"
    grep -Fxq 'workspace_ready=yes' "$output_root/status.txt"
    grep -Fxq 'framework_provenance=release-artifact' "$output_root/status.txt"

    ./bin/beacon plan --output "$output_root/plan" > "$output_root/plan.txt"
    grep -Fxq 'operation=collect' "$output_root/plan.txt"
    grep -Fxq 'redact_keys=TOKEN,SECRET,PASSWORD' "$output_root/plan.txt"
    grep -Fxq 'include=config/app.env' "$output_root/plan.txt"

    ./bin/beacon collect --dry-run --output "$output_root/dry-run" > "$output_root/dry-run.txt"
    grep -Fxq 'dry_run=true' "$output_root/dry-run.txt"
    grep -Fxq 'operation=collect' "$output_root/dry-run.txt"
    [[ ! -e "$output_root/dry-run" ]]

    ./bin/beacon collect --output "$output_root/collect" > "$output_root/collect.txt" 2> "$output_root/collect.err"
    grep -Fxq "bundle=$output_root/collect" "$output_root/collect.txt"
    grep -Fxq "manifest=$output_root/collect/MANIFEST.sha256" "$output_root/collect.txt"

    ./bin/beacon verify --output "$output_root/collect" > "$output_root/verify.txt"
    grep -Fxq 'verified=true' "$output_root/verify.txt"
    grep -Fxq 'files=4' "$output_root/verify.txt"
)

/usr/bin/env bash "$docs_root/tests/docs-before-after.sh"

printf 'Runnable documentation examples passed.\n'
