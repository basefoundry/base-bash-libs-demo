#!/usr/bin/env bash

smoke_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)" || exit 1
smoke_temp="$(mktemp -d "${TMPDIR:-/tmp}/beacon-bash-42.XXXXXX")" || exit 1
smoke_output="$smoke_temp/bundle"

"$smoke_root/scripts/verify-vendor" || exit $?
"$smoke_root/bin/beacon" status | grep -F 'framework_version=2.0.0' >/dev/null || exit $?
"$smoke_root/bin/beacon" plan --output "$smoke_output" | grep -F 'selected_files=3' >/dev/null || exit $?
"$smoke_root/bin/beacon" collect --dry-run --output "$smoke_output" | grep -F 'dry_run=true' >/dev/null || exit $?
[[ ! -e "$smoke_output" ]] || exit 1
"$smoke_root/bin/beacon" collect --output "$smoke_output" >/dev/null || exit $?
"$smoke_root/bin/beacon" verify --output "$smoke_output" | grep -F 'verified=true' >/dev/null || exit $?

printf 'Beacon Bash %s.%s.%s smoke passed.\n' \
    "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}" "${BASH_VERSINFO[2]}"
