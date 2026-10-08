#!/usr/bin/env bash

set -euo pipefail

docs_contract_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
docs_contract_readme="$docs_contract_root/README.md"
docs_contract_why="$docs_contract_root/docs/why-base-bash-libs.md"
docs_contract_decision="$docs_contract_root/docs/should-i-use-base-bash-libs.md"
docs_contract_index="$docs_contract_root/docs/README.md"
docs_contract_starter="$docs_contract_root/docs/use-in-your-project.md"
docs_contract_example="$docs_contract_root/examples/minimal-cli"
docs_contract_manifest="$docs_contract_root/vendor/base-bash-libs/base_api_manifest.yaml"
docs_contract_consumer="$docs_contract_root/lib/beacon.sh"

grep -Fq '[why Base Bash](docs/why-base-bash-libs.md)' "$docs_contract_readme"
grep -Fq '[should I use Base Bash?](docs/should-i-use-base-bash-libs.md)' "$docs_contract_readme"
grep -Fq '[five-minute Beacon tutorial](five-minute-tutorial.md)' "$docs_contract_why"
grep -Fq '[adoption decision guide](should-i-use-base-bash-libs.md)' "$docs_contract_why"
grep -Fq '[five-minute Beacon tutorial](five-minute-tutorial.md)' "$docs_contract_decision"
grep -Fq '[Beacon documentation and recommended reading path](docs/README.md)' "$docs_contract_readme"
grep -Fq '[use Base Bash in your project](docs/use-in-your-project.md)' "$docs_contract_readme"

docs_contract_expected_example="$(
    sed -n '/^<!-- BEGIN MINIMAL CONSUMER -->$/,/^<!-- END MINIMAL CONSUMER -->$/p' \
        "$docs_contract_starter" |
        sed -e '1d' -e '$d' -e '/^```bash$/d' -e '/^```$/d'
)"
docs_contract_actual_example="$(sed -n '1,$p' "$docs_contract_example")"
[[ "$docs_contract_expected_example" == "$docs_contract_actual_example" ]] || {
    printf 'Documented minimal consumer differs from examples/minimal-cli.\n' >&2
    exit 1
}

for docs_contract_path in \
    why-base-bash-libs.md \
    should-i-use-base-bash-libs.md \
    use-in-your-project.md \
    five-minute-tutorial.md \
    lifecycle-and-automation.md \
    framework-updates.md \
    release-process.md \
    ci-required-checks.md; do
    grep -Fq "($docs_contract_path)" "$docs_contract_index" || {
        printf 'Documentation index is missing %s.\n' "$docs_contract_path" >&2
        exit 1
    }
done

[[ "$(grep -c '^# ' "$docs_contract_root/docs/framework-updates.md")" -eq 1 ]] || {
    printf 'framework-updates.md must have exactly one H1.\n' >&2
    exit 1
}
grep -Fq 'Scheduled runs cover both release rows' "$docs_contract_root/docs/framework-updates.md"
grep -Fq 'leaving that input blank runs both rows' "$docs_contract_root/docs/framework-updates.md"
grep -Fq 'v2.0.0 rollback baseline and the committed v2.2.0' "$docs_contract_readme"
grep -Fq "Beacon's README has no separate release" "$docs_contract_root/docs/release-process.md"
grep -Fq '## [0.1.0] - YYYY-MM-DD' "$docs_contract_root/docs/release-process.md"
grep -Fq 'Required consumer and artifact validation' "$docs_contract_root/docs/release-process.md"
grep -Fq 'intended repository gate for the pull request' "$docs_contract_root/CONTRIBUTING.md"
grep -Fq 'tracks enabling it as an enforced required ruleset check' "$docs_contract_root/CONTRIBUTING.md"
grep -Fq 'intended release-preparation merge gate' "$docs_contract_root/docs/release-process.md"
grep -Fq 'tracks the separate ruleset update' "$docs_contract_root/docs/release-process.md"
grep -Fq 'Required consumer and artifact validation' "$docs_contract_root/CONTRIBUTING.md"
grep -Fq 'intentionally keeps an open pull request in' "$docs_contract_root/docs/project-workflow.md"
grep -Fq "does not use \`In Review\`" "$docs_contract_root/docs/project-workflow.md"
grep -Fq 'Hash-locked the SPDX artifact-test dependency' "$docs_contract_root/CHANGELOG.md"
docs_contract_release_sections="$(sed -n '/^## \[0.1.0\]/,$p' "$docs_contract_root/CHANGELOG.md")"
[[ "$(printf '%s\n' "$docs_contract_release_sections" | sed -n '/^### /p' | sed -n '1p')" == '### Added' ]]
[[ "$(printf '%s\n' "$docs_contract_release_sections" | sed -n '/^### /p' | sed -n '2p')" == '### Changed' ]]
[[ "$(printf '%s\n' "$docs_contract_release_sections" | sed -n '/^### /p' | sed -n '3p')" == '### Fixed' ]]
[[ "$(printf '%s\n' "$docs_contract_release_sections" | sed -n '/^### /p' | sed -n '4p')" == '### Security' ]]

for docs_contract_url in \
    'https://github.com/basefoundry/base-bash-libs' \
    'https://github.com/basefoundry/base-bash-libs/blob/v2.2.1/docs/README.md' \
    'https://github.com/basefoundry/base-bash-libs/blob/v2.2.1/docs/v2/quickstart.md' \
    'https://github.com/basefoundry/base-bash-libs/blob/v2.2.1/docs/api-reference.md'; do
    grep -Fq "$docs_contract_url" "$docs_contract_readme" || {
        printf 'README is missing upstream onboarding link: %s\n' "$docs_contract_url" >&2
        exit 1
    }
done
if grep -R -n -E 'base-bash-libs/blob/main/docs/(api-reference|v2/quickstart|README\.md)' \
    "$docs_contract_root/README.md" "$docs_contract_root/docs" > /dev/null; then
    printf 'Pinned consumer docs must not link API material to upstream main.\n' >&2
    exit 1
fi
grep -Fq 'v2.2.1' "$docs_contract_root/docs/use-in-your-project.md"
for docs_contract_text in \
    'BEGIN EXTERNAL CONSUMER WALKTHROUGH' \
    "base-bash-libs-v\$release_version.tar.gz" \
    "base-bash-libs-v\$release_version.SHA256SUMS" \
    "base-bash-libs-v\$release_version.provenance.json" \
    "base-bash-libs-v\$release_version.spdx.json" \
    "sha256sum -c \"\$checksum_name\"" \
    "shasum -a 256 -c \"\$checksum_name\"" \
    'base-bash-libs.lock' \
    'consumer project' \
    "rm -rf \"\$release_root\""; do
    grep -Fq "$docs_contract_text" "$docs_contract_starter" || {
        printf 'External-consumer walkthrough is missing: %s\n' "$docs_contract_text" >&2
        exit 1
    }
done
# Keep this issue reference aligned with the reviewed adoption change.
grep -Fq 'issue #38' "$docs_contract_root/docs/use-in-your-project.md"

for docs_contract_heading in \
    '## Good fit' \
    '## Poor fit' \
    '## Runtime prerequisites' \
    '## What adoption costs' \
    '## Alternatives' \
    '## Maturity and support' \
    '## Decision checklist'; do
    grep -Fqx "$docs_contract_heading" "$docs_contract_decision" || {
        printf 'Adoption decision guide is missing heading: %s\n' "$docs_contract_heading" >&2
        exit 1
    }
done

for docs_contract_url in \
    'https://github.com/ko1nksm/getoptions' \
    'https://github.com/bashly-framework/bashly' \
    'https://github.com/niieani/bash-oo-framework' \
    'https://github.com/basefoundry/base-bash-libs/issues/239'; do
    grep -Fq "$docs_contract_url" "$docs_contract_decision" || {
        printf 'Adoption decision guide is missing source: %s\n' "$docs_contract_url" >&2
        exit 1
    }
done

docs_contract_symbols=(
    base_cli_model_init
    base_cli_command
    base_cli_option
    base_cli_run
    base_app_config_define
    base_app_config_load
    base_app_config_set_cli
    base_app_config_get
    base_app_hook
    base_app_run
    base_std_make_temp_dir
    base_std_unregister_cleanup_path
    base_std_safe_mkdir
    base_std_safe_truncate
    base_std_run
    base_require_version
)

for docs_contract_symbol in "${docs_contract_symbols[@]}"; do
    grep -Fq "$docs_contract_symbol" "$docs_contract_why" || {
        printf 'Adoption document does not cite %s.\n' "$docs_contract_symbol" >&2
        exit 1
    }
    grep -Eq "public_symbols:.*[ ,]$docs_contract_symbol(,|$)" "$docs_contract_manifest" || {
        printf 'Adoption document cites non-public symbol %s.\n' "$docs_contract_symbol" >&2
        exit 1
    }
    grep -Fq "$docs_contract_symbol" "$docs_contract_consumer" || {
        printf 'Adoption document cites symbol Beacon does not exercise: %s.\n' "$docs_contract_symbol" >&2
        exit 1
    }
done

printf 'Adoption documentation contracts passed.\n'
