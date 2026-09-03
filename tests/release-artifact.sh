#!/usr/bin/env bash

set -euo pipefail

release_test_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
release_test_temp="$(mktemp -d "${TMPDIR:-/tmp}/beacon-release-test.XXXXXX")"
release_test_first="$release_test_temp/first"
release_test_second="$release_test_temp/second"
release_test_tampered="$release_test_temp/tampered"
release_test_version="$(sed -n '1p' "$release_test_root/VERSION")"

release_test_cleanup() {
    rm -rf -- "$release_test_temp"
}
trap release_test_cleanup EXIT

"$release_test_root/scripts/release-artifact" build \
    --version "$release_test_version" --output "$release_test_first"
"$release_test_root/scripts/release-artifact" build \
    --version "$release_test_version" --output "$release_test_second"

diff -r "$release_test_first" "$release_test_second"
"$release_test_root/scripts/release-artifact" verify "$release_test_first"

if "$release_test_root/scripts/release-artifact" build \
    --version "$release_test_version" --output "$release_test_first" > /dev/null 2>&1; then
    printf 'Release artifact build unexpectedly overwrote an existing output.\n' >&2
    exit 1
fi

cp -pR "$release_test_first" "$release_test_tampered"
printf '\n' >> "$release_test_tampered/beacon-v$release_test_version.spdx.json"
if "$release_test_root/scripts/release-artifact" verify "$release_test_tampered" > /dev/null 2>&1; then
    printf 'Release artifact verification unexpectedly accepted tampering.\n' >&2
    exit 1
fi

printf 'Beacon release artifact reproducibility and verification passed.\n'
