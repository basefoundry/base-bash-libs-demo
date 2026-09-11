#!/usr/bin/env bash

set -euo pipefail

docs_contract_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
docs_contract_readme="$docs_contract_root/README.md"
docs_contract_why="$docs_contract_root/docs/why-base-bash-libs.md"
docs_contract_manifest="$docs_contract_root/vendor/base-bash-libs/base_api_manifest.yaml"
docs_contract_consumer="$docs_contract_root/lib/beacon.sh"

grep -Fq '[why Base Bash](docs/why-base-bash-libs.md)' "$docs_contract_readme"
grep -Fq '[five-minute Beacon tutorial](five-minute-tutorial.md)' "$docs_contract_why"

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
