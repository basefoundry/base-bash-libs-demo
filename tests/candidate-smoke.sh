#!/usr/bin/env bash

candidate_demo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)" || exit 1
candidate_root="${1:-}"
candidate_expected_version="${2:-}"
candidate_expected_commit="${3:-}"

candidate_fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ -n "$candidate_root" ]] || candidate_fail "usage: candidate-smoke.sh CANDIDATE_ROOT [VERSION] [COMMIT]"
candidate_root="$(cd -- "$candidate_root" && pwd -P)" || candidate_fail "candidate root does not exist"
candidate_launcher="$candidate_root/bin/base-bash"
candidate_lib_dir="$candidate_root/lib/bash"

[[ -x "$candidate_launcher" ]] || candidate_fail "candidate launcher is missing"
[[ -f "$candidate_lib_dir/std/lib_std.sh" ]] || candidate_fail "candidate stdlib is missing"

if [[ -z "$candidate_expected_version" && -f "$candidate_root/VERSION" ]]; then
    candidate_expected_version="$(< "$candidate_root/VERSION")"
fi
if [[ -z "$candidate_expected_commit" && -f "$candidate_root/BUNDLE.release" ]]; then
    candidate_expected_commit="$(sed -n 's/^source_commit=//p' "$candidate_root/BUNDLE.release")"
fi
if [[ -z "$candidate_expected_commit" ]] && git -C "$candidate_root" rev-parse --git-dir >/dev/null 2>&1; then
    candidate_expected_commit="$(git -C "$candidate_root" rev-parse --verify 'HEAD^{commit}')"
fi
[[ -n "$candidate_expected_version" ]] || candidate_fail "unable to determine candidate version"
[[ "$candidate_expected_commit" =~ ^[0-9a-f]{40}$ ]] || candidate_fail "candidate commit must be a full object ID"

candidate_temp="$(mktemp -d "${TMPDIR:-/tmp}/beacon-candidate.XXXXXX")" || exit 1
candidate_pid=""
candidate_cleanup() {
    if [[ -n "$candidate_pid" ]]; then
        kill -TERM "$candidate_pid" 2>/dev/null || true
        wait "$candidate_pid" 2>/dev/null || true
    fi
    rm -rf -- "$candidate_temp"
}
trap candidate_cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$candidate_temp/staging" || exit 1
candidate_output="$candidate_temp/bundle"

candidate_run() {
    local expected="$1" result=0
    shift
    candidate_stdout="$(
        TMPDIR="$candidate_temp/staging" BASE_BASH_LIBS_DIR="$candidate_lib_dir" \
            "$candidate_launcher" "$candidate_demo_root/lib/beacon.sh" "$@" \
            2> "$candidate_temp/stderr"
    )" || result=$?
    [[ "$result" -eq "$expected" ]] || candidate_fail "candidate $1 returned $result, expected $expected"
    [[ -z "$(find "$candidate_temp/staging" -mindepth 1 -print -quit)" ]] || candidate_fail "candidate leaked staging"
}
candidate_has() {
    grep -Fqx -- "$1" <<< "$candidate_stdout" || candidate_fail "missing candidate result: $1"
}
candidate_cleanup_once() {
    [[ "$(cat "$1")" == phase=cleanup && "$(wc -l < "$1" | tr -d ' ')" == 1 ]] || candidate_fail "cleanup was not exactly once"
}

candidate_run 0 status
candidate_has "framework_version=$candidate_expected_version"
candidate_has "framework_commit=$candidate_expected_commit"
candidate_run 0 plan --output "$candidate_output"
candidate_has selected_files=3
candidate_run 0 collect --dry-run --non-interactive --output "$candidate_output" --lifecycle-log "$candidate_temp/dry.log"
candidate_has dry_run=true
[[ ! -e "$candidate_output" && ! -e "$candidate_temp/dry.log" ]] || candidate_fail "dry-run mutated output"
candidate_run 0 collect --quiet --output "$candidate_output" --lifecycle-log "$candidate_temp/success.log"
[[ ! -s "$candidate_temp/stderr" ]] || candidate_fail "quiet collection wrote stderr"
candidate_has "manifest=$candidate_output/MANIFEST.sha256"
candidate_cleanup_once "$candidate_temp/success.log"
candidate_run 0 verify --quiet --output "$candidate_output"
candidate_has verified=true
[[ ! -s "$candidate_temp/stderr" ]] || candidate_fail "quiet verification wrote stderr"

printf 'scenario=failure\n' > "$candidate_temp/user.conf"
printf 'scenario=normal\n' > "$candidate_temp/project.conf"
candidate_run 70 collect --user-config "$candidate_temp/user.conf" --output "$candidate_temp/user" --lifecycle-log "$candidate_temp/failure.log"
[[ ! -e "$candidate_temp/user" ]] || candidate_fail "failure published output"
candidate_cleanup_once "$candidate_temp/failure.log"
candidate_run 0 collect --user-config "$candidate_temp/user.conf" --config "$candidate_temp/project.conf" --output "$candidate_temp/project"
BEACON_SCENARIO=failure candidate_run 70 collect --config "$candidate_temp/project.conf" --output "$candidate_temp/environment"
[[ ! -e "$candidate_temp/environment" ]] || candidate_fail "environment failure published output"
BEACON_SCENARIO=failure candidate_run 0 collect --scenario normal --output "$candidate_temp/cli"
candidate_run 1 plan --user-config "$candidate_temp/missing.conf"

TMPDIR="$candidate_temp/staging" BASE_BASH_LIBS_DIR="$candidate_lib_dir" \
    "$candidate_launcher" "$candidate_demo_root/lib/beacon.sh" collect \
    --scenario interrupt --output "$candidate_temp/interrupted" --lifecycle-log "$candidate_temp/signal.log" \
    > "$candidate_temp/signal.out" 2> "$candidate_temp/signal.err" &
candidate_pid=$!
candidate_ready=no
for _ in {1..100}; do
    if grep -Fqx state=waiting_for_signal "$candidate_temp/signal.out"; then candidate_ready=yes; break; fi
    kill -0 "$candidate_pid" 2>/dev/null || break
    sleep 0.05
done
[[ "$candidate_ready" == yes ]] || candidate_fail "candidate signal scenario did not start"
kill -TERM "$candidate_pid" || candidate_fail "candidate signal failed"
candidate_signal_status=0
wait "$candidate_pid" || candidate_signal_status=$?
candidate_pid=""
[[ "$candidate_signal_status" -eq 143 ]] || candidate_fail "candidate signal status was not 143"
candidate_cleanup_once "$candidate_temp/signal.log"
[[ ! -e "$candidate_temp/interrupted" ]] || candidate_fail "signal published output"
[[ -z "$(find "$candidate_temp/staging" -mindepth 1 -print -quit)" ]] || candidate_fail "signal leaked staging"

printf 'Candidate base-bash-libs %s at %s passed.\n' \
    "$candidate_expected_version" "$candidate_expected_commit"
