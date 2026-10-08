#!/usr/bin/env bash

set -euo pipefail

walkthrough_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
walkthrough_tmp="$(mktemp -d "${TMPDIR:-/tmp}/base-bash-external-consumer.XXXXXX")"
walkthrough_cleanup() {
    rm -rf -- "$walkthrough_tmp"
}
trap walkthrough_cleanup EXIT

walkthrough_fixture="$walkthrough_tmp/release"
walkthrough_stage="$walkthrough_tmp/stage/base-bash-libs-v2.2.0"
mkdir -p "$walkthrough_fixture" "$walkthrough_stage"
cp -R "$walkthrough_root/vendor/base-bash-libs/." "$walkthrough_stage/"
(
    cd "$walkthrough_tmp/stage"
    tar -czf "$walkthrough_fixture/base-bash-libs-v2.2.0.tar.gz" \
        base-bash-libs-v2.2.0
)
cp "$walkthrough_root/vendor/evidence/base-bash-libs-v2.2.0.provenance.json" \
    "$walkthrough_fixture/"
cp "$walkthrough_root/vendor/evidence/base-bash-libs-v2.2.0.spdx.json" \
    "$walkthrough_fixture/"
(
    cd "$walkthrough_fixture"
    if command -v sha256sum > /dev/null 2>&1; then
        sha256sum base-bash-libs-v2.2.0.tar.gz \
            base-bash-libs-v2.2.0.provenance.json \
            base-bash-libs-v2.2.0.spdx.json > base-bash-libs-v2.2.0.SHA256SUMS
    else
        shasum -a 256 base-bash-libs-v2.2.0.tar.gz \
            base-bash-libs-v2.2.0.provenance.json \
            base-bash-libs-v2.2.0.spdx.json > base-bash-libs-v2.2.0.SHA256SUMS
    fi
)

walkthrough_script="$walkthrough_tmp/walkthrough.sh"
awk '
    /^<!-- BEGIN EXTERNAL CONSUMER WALKTHROUGH -->$/ { in_region = 1; next }
    /^<!-- END EXTERNAL CONSUMER WALKTHROUGH -->$/ { exit }
    in_region && index($0, sprintf("%c%c%c", 96, 96, 96) "bash") == 1 { in_code = 1; next }
    in_region && in_code && index($0, sprintf("%c%c%c", 96, 96, 96)) == 1 { in_code = 0; next }
    in_region && in_code { print }
' "$walkthrough_root/docs/use-in-your-project.md" > "$walkthrough_script"

[[ -s "$walkthrough_script" ]]
/usr/bin/env bash -n "$walkthrough_script"
shellcheck --shell=bash "$walkthrough_script"
BASE_BASH_LIBS_RELEASE_VERSION=2.2.0 \
BASE_BASH_LIBS_RELEASE_TAG=v2.2.0 \
BASE_BASH_LIBS_RELEASE_URL="file://$walkthrough_fixture" \
BASE_BASH_LIBS_CONSUMER_ROOT="$walkthrough_tmp/consumer root with spaces" \
bash "$walkthrough_script"

walkthrough_lock="$walkthrough_tmp/consumer root with spaces/consumer project/base-bash-libs.lock"
grep -Fqx 'version=2.2.0' "$walkthrough_lock"
grep -Eq '^commit=[0-9a-f]{40}$' "$walkthrough_lock"

printf 'External consumer walkthrough passed offline after preparation.\n'
