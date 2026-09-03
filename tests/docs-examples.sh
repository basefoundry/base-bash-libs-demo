#!/usr/bin/env bash

set -euo pipefail

docs_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tutorial="$docs_root/docs/five-minute-tutorial.md"
example_script="$(mktemp "${TMPDIR:-/tmp}/beacon-docs-example.XXXXXX")"

cleanup() {
    rm -f "$example_script"
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
)

printf 'Runnable documentation examples passed.\n'
