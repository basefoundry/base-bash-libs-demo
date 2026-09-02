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
candidate_output="$candidate_temp/bundle"
candidate_status="$(
    BASE_BASH_LIBS_DIR="$candidate_lib_dir" \
        "$candidate_launcher" "$candidate_demo_root/lib/beacon.sh" status
)" || candidate_fail "candidate status failed"

grep -Fqx "framework_version=$candidate_expected_version" <<< "$candidate_status" || \
    candidate_fail "candidate version does not match"
grep -Fqx "framework_commit=$candidate_expected_commit" <<< "$candidate_status" || \
    candidate_fail "candidate commit does not match"

BASE_BASH_LIBS_DIR="$candidate_lib_dir" \
    "$candidate_launcher" "$candidate_demo_root/lib/beacon.sh" \
    plan --output "$candidate_output" | grep -F 'selected_files=3' >/dev/null || \
    candidate_fail "candidate plan failed"
BASE_BASH_LIBS_DIR="$candidate_lib_dir" \
    "$candidate_launcher" "$candidate_demo_root/lib/beacon.sh" \
    collect --dry-run --output "$candidate_output" | grep -F 'dry_run=true' >/dev/null || \
    candidate_fail "candidate dry-run failed"
[[ ! -e "$candidate_output" ]] || candidate_fail "candidate dry-run mutated output"
BASE_BASH_LIBS_DIR="$candidate_lib_dir" \
    "$candidate_launcher" "$candidate_demo_root/lib/beacon.sh" \
    collect --quiet --output "$candidate_output" >/dev/null || \
    candidate_fail "candidate collection failed"
BASE_BASH_LIBS_DIR="$candidate_lib_dir" \
    "$candidate_launcher" "$candidate_demo_root/lib/beacon.sh" \
    verify --output "$candidate_output" | grep -F 'verified=true' >/dev/null || \
    candidate_fail "candidate verification failed"

printf 'Candidate base-bash-libs %s at %s passed.\n' \
    "$candidate_expected_version" "$candidate_expected_commit"
