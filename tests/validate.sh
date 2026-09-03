#!/usr/bin/env bash

required_files=(
    README.md
    VERSION
    CHANGELOG.md
    CONTRIBUTING.md
    .github/pull_request_template.md
    .github/base-project.yml
    LICENSE
    base_manifest.yaml
    .github/workflows/issue-branch-policy.yml
    .github/workflows/project-intake.yml
    .github/workflows/tests.yml
    base-bash-libs.lock
    bin/beacon
    lib/beacon.sh
    scripts/release-artifact
    scripts/verify-vendor
    tests/beacon.bats
    tests/lifecycle.bats
    tests/bash-42-smoke.sh
    tests/candidate-smoke.sh
    tests/docs-examples.sh
    tests/release-artifact.sh
    docs/five-minute-tutorial.md
    docs/lifecycle-and-automation.md
    docs/framework-updates.md
    docs/release-notes-template.md
    .github/workflows/framework-compatibility.yml
    vendor/base-bash-libs/MANIFEST.sha256
    vendor/base-bash-libs/lib/bash/base-bash-libs.release
)

for file in "${required_files[@]}"; do
    [[ -f "$file" ]] || {
        printf 'Missing required file: %s\n' "$file" >&2
        exit 1
    }
done

for executable in bin/beacon scripts/release-artifact scripts/verify-vendor tests/validate.sh tests/bash-42-smoke.sh tests/candidate-smoke.sh tests/docs-examples.sh tests/release-artifact.sh; do
    [[ -x "$executable" ]] || {
        printf 'Expected executable file: %s\n' "$executable" >&2
        exit 1
    }
done

./scripts/verify-vendor || exit $?

command -v shellcheck > /dev/null 2>&1 || {
    printf 'shellcheck is required.\n' >&2
    exit 1
}
shellcheck bin/beacon lib/beacon.sh scripts/release-artifact scripts/verify-vendor tests/validate.sh tests/bash-42-smoke.sh tests/candidate-smoke.sh tests/docs-examples.sh tests/release-artifact.sh || exit $?

./tests/docs-examples.sh || exit $?

command -v bats > /dev/null 2>&1 || {
    printf 'bats is required.\n' >&2
    exit 1
}
bats tests/beacon.bats tests/lifecycle.bats || exit $?

./tests/bash-42-smoke.sh || exit $?
./tests/candidate-smoke.sh "$PWD/vendor/base-bash-libs" || exit $?
./tests/release-artifact.sh || exit $?

printf 'Repository and Beacon validation passed.\n'
