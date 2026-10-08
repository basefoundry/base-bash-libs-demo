#!/usr/bin/env bash

set -euo pipefail

docs_before_after_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
docs_before_after_source="$docs_before_after_root/docs/why-base-bash-libs.md"
docs_before_after_tmp="$(mktemp -d "${TMPDIR:-/tmp}/beacon-before-after.XXXXXX")"

docs_before_after_cleanup() {
    rm -rf -- "$docs_before_after_tmp"
}
trap docs_before_after_cleanup EXIT

docs_before_after_extract() {
    local marker_start="$1" marker_end="$2" destination="$3"
    awk -v marker_start="$marker_start" -v marker_end="$marker_end" '
        $0 == marker_start { in_region = 1; next }
        $0 == marker_end { exit }
        in_region && /^```bash$/ { in_code = 1; next }
        in_region && /^```$/ { in_code = 0; next }
        in_region && in_code { print }
    ' "$docs_before_after_source" > "$destination"
    [[ -s "$destination" ]]
    /usr/bin/env bash -n "$destination"
    shellcheck --shell=bash "$destination"
}

docs_before_after_extract \
    '<!-- BEGIN BEFORE AFTER CLI -->' \
    '<!-- END BEFORE AFTER CLI -->' \
    "$docs_before_after_tmp/cli.sh"
docs_before_after_extract \
    '<!-- BEGIN BEFORE AFTER CLEANUP -->' \
    '<!-- END BEFORE AFTER CLEANUP -->' \
    "$docs_before_after_tmp/cleanup.sh"

printf 'Before-and-after documentation examples passed ShellCheck.\n'
