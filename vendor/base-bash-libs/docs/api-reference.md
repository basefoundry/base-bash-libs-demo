# Base Bash API Reference

> This file is generated from `base_api_manifest.yaml`; edit the manifest or the module READMEs instead.

## Contract

- Manifest schema: 1
- API version: 2.0.0
- Minimum Bash: 4.2

Every module remains a single sourceable file. Signatures, inputs, outputs,
statuses, and side effects are normative in the linked module README and
[API charter](v2-api-contract.md).

- Public functions: `base_`
- Globals: `BASE_BASH_LIBS_`
- Internals: `__base_bash_libs_`

## Modules

### `std`

- Kind: `sourceable-library`
- Source: [`lib/bash/std/lib_std.sh`](../lib/bash/std/lib_std.sh)
- Documentation: [`lib/bash/std/README.md`](../lib/bash/std/README.md)
- Tests: [`lib/bash/std/tests/lib_std.bats`](../lib/bash/std/tests/lib_std.bats)
- Dependencies: `none`
- Optional commands: `awk,basename,cat,command,cp,date,grep,mktemp,mv,printf,rm,sed,tput`
- Stability: `stable`; since `2.0.0`; deprecated: `false`
- Inputs: documented per symbol in the module README and API charter
- Outputs: documented per symbol; named outputs are caller-owned
- Statuses: documented per symbol; recoverable failures return status
- Side effects: documented per symbol; sourcing is passive

#### Public symbols

- `base_init` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_require_version` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_add_to_path` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_ask_yes_no` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_assert_arg_count` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_assert_associative_array` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_assert_command_exists` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_assert_dir_exists` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_assert_executable` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_assert_file_exists` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_assert_function_exists` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_assert_indexed_array` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_assert_integer` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_assert_integer_range` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_assert_not_null` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_assert_variable_name` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_check_bash_version` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_command_path` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_dedupe_path` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_dump_trace` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_exit_if_error` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_fatal_error` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_function_exists` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_get_my_source_dir` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_import` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_is_dry_run` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_is_interactive` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_log_debug` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_log_debug_enter` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_log_debug_file` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_log_debug_leave` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_log_error` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_log_fatal` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_log_info` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_log_info_enter` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_log_info_file` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_log_info_leave` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_log_is_enabled` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_log_verbose` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_log_verbose_enter` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_log_verbose_file` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_log_verbose_leave` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_log_warn` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_make_temp_dir` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_make_temp_file` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_print_bold` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_print_error` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_print_info` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_print_message` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_print_path` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_print_success` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_print_tty` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_print_warn` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_register_cleanup_hook` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_register_cleanup_path` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_run` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_run_or_exit` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_safe_cd` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_safe_mkdir` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_safe_touch` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_safe_truncate` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_safe_unalias` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_set_log_category_level` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_set_log_level` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_unregister_cleanup_hook` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_unregister_cleanup_path` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).
- `base_std_wait_for_enter` — signature: see [`lib/bash/std/README.md`](../lib/bash/std/README.md).

### `file`

- Kind: `sourceable-library`
- Source: [`lib/bash/file/lib_file.sh`](../lib/bash/file/lib_file.sh)
- Documentation: [`lib/bash/file/README.md`](../lib/bash/file/README.md)
- Tests: [`lib/bash/file/tests/lib_file.bats`](../lib/bash/file/tests/lib_file.bats)
- Dependencies: `std`
- Optional commands: `awk,cmp,cp,mv,rm,stat`
- Stability: `stable`; since `2.0.0`; deprecated: `false`
- Inputs: documented per symbol in the module README and API charter
- Outputs: documented per symbol; named outputs are caller-owned
- Statuses: documented per symbol; recoverable failures return status
- Side effects: documented per symbol; sourcing is passive

#### Public symbols

- `base_file_section_exists` — signature: see [`lib/bash/file/README.md`](../lib/bash/file/README.md).
- `base_file_section_needs_update` — signature: see [`lib/bash/file/README.md`](../lib/bash/file/README.md).
- `base_file_update_file_section` — signature: see [`lib/bash/file/README.md`](../lib/bash/file/README.md).

### `git`

- Kind: `sourceable-library`
- Source: [`lib/bash/git/lib_git.sh`](../lib/bash/git/lib_git.sh)
- Documentation: [`lib/bash/git/README.md`](../lib/bash/git/README.md)
- Tests: [`lib/bash/git/tests/lib_git.bats`](../lib/bash/git/tests/lib_git.bats)
- Dependencies: `std`
- Optional commands: `git,awk,grep,mktemp,rm,sleep`
- Stability: `stable`; since `2.0.0`; deprecated: `false`
- Inputs: documented per symbol in the module README and API charter
- Outputs: documented per symbol; named outputs are caller-owned
- Statuses: usage and contract errors return 2; recoverable failures and false predicates return 1 unless a symbol documents a specific status; freshness checks use 3 for dirty, 4 for behind, and 5 for diverged
- Side effects: documented per symbol; sourcing is passive

#### Public symbols

- `base_git_branch_merged_to_ref` — signature: see [`lib/bash/git/README.md`](../lib/bash/git/README.md).
- `base_git_branch_upstream` — signature: see [`lib/bash/git/README.md`](../lib/bash/git/README.md).
- `base_git_check_script_up_to_date` — signature: see [`lib/bash/git/README.md`](../lib/bash/git/README.md).
- `base_git_detect_default_branch` — signature: see [`lib/bash/git/README.md`](../lib/bash/git/README.md).
- `base_git_get_current_branch` — signature: see [`lib/bash/git/README.md`](../lib/bash/git/README.md).
- `base_git_list_remote_branches` — signature: see [`lib/bash/git/README.md`](../lib/bash/git/README.md).
- `base_git_list_worktree_branches` — signature: see [`lib/bash/git/README.md`](../lib/bash/git/README.md).
- `base_git_update_repo` — signature: see [`lib/bash/git/README.md`](../lib/bash/git/README.md).
- `base_git_worktree_path_for_branch` — signature: see [`lib/bash/git/README.md`](../lib/bash/git/README.md).

### `gh`

- Kind: `sourceable-library`
- Source: [`lib/bash/gh/lib_gh.sh`](../lib/bash/gh/lib_gh.sh)
- Documentation: [`lib/bash/gh/README.md`](../lib/bash/gh/README.md)
- Tests: [`lib/bash/gh/tests/lib_gh.bats`](../lib/bash/gh/tests/lib_gh.bats)
- Dependencies: `std`
- Optional commands: `gh,awk,grep,mktemp,rm,sleep,timeout,gtimeout`
- Stability: `stable`; since `2.0.0`; deprecated: `false`
- Inputs: documented per symbol in the module README and API charter
- Outputs: documented per symbol; named outputs are caller-owned
- Statuses: usage and contract errors return 2; recoverable failures return 1 unless a symbol preserves an underlying gh status
- Side effects: documented per symbol; sourcing is passive

#### Public symbols

- `base_gh_api_with_retry` — signature: see [`lib/bash/gh/README.md`](../lib/bash/gh/README.md).
- `base_gh_auth_status_diagnostics` — signature: see [`lib/bash/gh/README.md`](../lib/bash/gh/README.md).
- `base_gh_infer_repo_from_origin` — signature: see [`lib/bash/gh/README.md`](../lib/bash/gh/README.md).
- `base_gh_repo_default_branch` — signature: see [`lib/bash/gh/README.md`](../lib/bash/gh/README.md).
- `base_gh_repo_from_remote_url` — signature: see [`lib/bash/gh/README.md`](../lib/bash/gh/README.md).
- `base_gh_report_command_failure` — signature: see [`lib/bash/gh/README.md`](../lib/bash/gh/README.md).
- `base_gh_require_cli` — signature: see [`lib/bash/gh/README.md`](../lib/bash/gh/README.md).
- `base_gh_run` — signature: see [`lib/bash/gh/README.md`](../lib/bash/gh/README.md).

### `str`

- Kind: `sourceable-library`
- Source: [`lib/bash/str/lib_str.sh`](../lib/bash/str/lib_str.sh)
- Documentation: [`lib/bash/str/README.md`](../lib/bash/str/README.md)
- Tests: [`lib/bash/str/tests/lib_str.bats`](../lib/bash/str/tests/lib_str.bats)
- Dependencies: `std`
- Optional commands: `none`
- Stability: `stable`; since `2.0.0`; deprecated: `false`
- Inputs: documented per symbol in the module README and API charter
- Outputs: documented per symbol; named outputs are caller-owned
- Statuses: documented per symbol; recoverable failures return status
- Side effects: documented per symbol; sourcing is passive

#### Public symbols

- `base_str_contains` — signature: see [`lib/bash/str/README.md`](../lib/bash/str/README.md).
- `base_str_ends_with` — signature: see [`lib/bash/str/README.md`](../lib/bash/str/README.md).
- `base_str_join` — signature: see [`lib/bash/str/README.md`](../lib/bash/str/README.md).
- `base_str_lower` — signature: see [`lib/bash/str/README.md`](../lib/bash/str/README.md).
- `base_str_ltrim` — signature: see [`lib/bash/str/README.md`](../lib/bash/str/README.md).
- `base_str_rtrim` — signature: see [`lib/bash/str/README.md`](../lib/bash/str/README.md).
- `base_str_split` — signature: see [`lib/bash/str/README.md`](../lib/bash/str/README.md).
- `base_str_starts_with` — signature: see [`lib/bash/str/README.md`](../lib/bash/str/README.md).
- `base_str_trim` — signature: see [`lib/bash/str/README.md`](../lib/bash/str/README.md).
- `base_str_upper` — signature: see [`lib/bash/str/README.md`](../lib/bash/str/README.md).

### `arg`

- Kind: `sourceable-library`
- Source: [`lib/bash/arg/lib_arg.sh`](../lib/bash/arg/lib_arg.sh)
- Documentation: [`lib/bash/arg/README.md`](../lib/bash/arg/README.md)
- Tests: [`lib/bash/arg/tests/lib_arg.bats`](../lib/bash/arg/tests/lib_arg.bats)
- Dependencies: `std`
- Optional commands: `awk,grep`
- Stability: `stable`; since `2.0.0`; deprecated: `false`
- Inputs: documented per symbol in the module README and API charter
- Outputs: documented per symbol; named outputs are caller-owned
- Statuses: documented per symbol; recoverable failures return status
- Side effects: documented per symbol; sourcing is passive

#### Public symbols

- `base_arg_parse` — signature: see [`lib/bash/arg/README.md`](../lib/bash/arg/README.md).

### `list`

- Kind: `sourceable-library`
- Source: [`lib/bash/list/lib_list.sh`](../lib/bash/list/lib_list.sh)
- Documentation: [`lib/bash/list/README.md`](../lib/bash/list/README.md)
- Tests: [`lib/bash/list/tests/lib_list.bats`](../lib/bash/list/tests/lib_list.bats)
- Dependencies: `std`
- Optional commands: `none`
- Stability: `stable`; since `2.0.0`; deprecated: `false`
- Inputs: documented per symbol in the module README and API charter
- Outputs: documented per symbol; named outputs are caller-owned
- Statuses: documented per symbol; recoverable failures return status
- Side effects: documented per symbol; sourcing is passive

#### Public symbols

- `base_list_append` — signature: see [`lib/bash/list/README.md`](../lib/bash/list/README.md).
- `base_list_contains` — signature: see [`lib/bash/list/README.md`](../lib/bash/list/README.md).
- `base_list_length` — signature: see [`lib/bash/list/README.md`](../lib/bash/list/README.md).
- `base_list_prepend` — signature: see [`lib/bash/list/README.md`](../lib/bash/list/README.md).
- `base_list_remove` — signature: see [`lib/bash/list/README.md`](../lib/bash/list/README.md).
- `base_list_unique` — signature: see [`lib/bash/list/README.md`](../lib/bash/list/README.md).

### `cli`

- Kind: `sourceable-library`
- Source: [`lib/bash/cli/lib_cli.sh`](../lib/bash/cli/lib_cli.sh)
- Documentation: [`lib/bash/cli/README.md`](../lib/bash/cli/README.md)
- Tests: [`lib/bash/cli/tests/lib_cli.bats`](../lib/bash/cli/tests/lib_cli.bats)
- Dependencies: `std`
- Optional commands: `none`
- Stability: `stable`; since `2.0.0`; deprecated: `false`
- Inputs: documented per symbol in the module README and API charter
- Outputs: documented per symbol; parsed results use BASE_BASH_LIBS_CLI_RESULT_* globals and named result variables
- Statuses: documented per symbol; usage and validation errors return status 2
- Side effects: documented per symbol; sourcing is passive and completion/help are non-mutating

#### Public symbols

- `base_cli_command` — signature: see [`lib/bash/cli/README.md`](../lib/bash/cli/README.md).
- `base_cli_complete` — signature: see [`lib/bash/cli/README.md`](../lib/bash/cli/README.md).
- `base_cli_completion_script` — signature: see [`lib/bash/cli/README.md`](../lib/bash/cli/README.md).
- `base_cli_declare` — signature: see [`lib/bash/cli/README.md`](../lib/bash/cli/README.md).
- `base_cli_help` — signature: see [`lib/bash/cli/README.md`](../lib/bash/cli/README.md).
- `base_cli_model_init` — signature: see [`lib/bash/cli/README.md`](../lib/bash/cli/README.md).
- `base_cli_option` — signature: see [`lib/bash/cli/README.md`](../lib/bash/cli/README.md).
- `base_cli_parse` — signature: see [`lib/bash/cli/README.md`](../lib/bash/cli/README.md).
- `base_cli_positional` — signature: see [`lib/bash/cli/README.md`](../lib/bash/cli/README.md).
- `base_cli_result_count` — signature: see [`lib/bash/cli/README.md`](../lib/bash/cli/README.md).
- `base_cli_result_get` — signature: see [`lib/bash/cli/README.md`](../lib/bash/cli/README.md).
- `base_cli_result_get_positional` — signature: see [`lib/bash/cli/README.md`](../lib/bash/cli/README.md).
- `base_cli_run` — signature: see [`lib/bash/cli/README.md`](../lib/bash/cli/README.md).
- `base_cli_validate_model` — signature: see [`lib/bash/cli/README.md`](../lib/bash/cli/README.md).

### `app`

- Kind: `sourceable-library`
- Source: [`lib/bash/app/lib_app.sh`](../lib/bash/app/lib_app.sh)
- Documentation: [`lib/bash/app/README.md`](../lib/bash/app/README.md)
- Tests: [`lib/bash/app/tests/lib_app.bats`](../lib/bash/app/tests/lib_app.bats)
- Dependencies: `std,cli`
- Optional commands: `none`
- Stability: `stable`; since `2.0.0`; deprecated: `false`
- Inputs: documented per symbol in the module README and API charter
- Outputs: documented per symbol; reports are redacted by the secret attribute
- Statuses: recoverable failures return status; malformed configuration returns 2
- Side effects: configuration state and lifecycle hooks are explicit; sourcing is passive

#### Public symbols

- `base_app_add_standard_options` — signature: see [`lib/bash/app/README.md`](../lib/bash/app/README.md).
- `base_app_apply_standard_options` — signature: see [`lib/bash/app/README.md`](../lib/bash/app/README.md).
- `base_app_config_define` — signature: see [`lib/bash/app/README.md`](../lib/bash/app/README.md).
- `base_app_config_get` — signature: see [`lib/bash/app/README.md`](../lib/bash/app/README.md).
- `base_app_config_load` — signature: see [`lib/bash/app/README.md`](../lib/bash/app/README.md).
- `base_app_config_provenance` — signature: see [`lib/bash/app/README.md`](../lib/bash/app/README.md).
- `base_app_config_report` — signature: see [`lib/bash/app/README.md`](../lib/bash/app/README.md).
- `base_app_config_set_cli` — signature: see [`lib/bash/app/README.md`](../lib/bash/app/README.md).
- `base_app_hook` — signature: see [`lib/bash/app/README.md`](../lib/bash/app/README.md).
- `base_app_init` — signature: see [`lib/bash/app/README.md`](../lib/bash/app/README.md).
- `base_app_prompt` — signature: see [`lib/bash/app/README.md`](../lib/bash/app/README.md).
- `base_app_run` — signature: see [`lib/bash/app/README.md`](../lib/bash/app/README.md).
- `base_app_should_prompt` — signature: see [`lib/bash/app/README.md`](../lib/bash/app/README.md).
- `base_app_status` — signature: see [`lib/bash/app/README.md`](../lib/bash/app/README.md).

### `launcher`

- Kind: `executable-launcher`
- Source: [`bin/base-bash`](../bin/base-bash)
- Documentation: [`docs/v2-api-contract.md`](../docs/v2-api-contract.md)
- Tests: [`tests/launcher.bats`](../tests/launcher.bats)
- Dependencies: `std`
- Optional commands: `awk,basename,cat,cp,date,dirname,grep,mktemp,mv,readlink,rm,sed,bash,git,gh,timeout,gtimeout`
- Stability: `stable`; since `2.0.0`; deprecated: `false`
- Inputs: --help, --version, check, or [--] <script> [args...]; BASE_BASH_LIBS_DIR may select a package path
- Outputs: help/version/check records and delegated script output; application stdout remains application-owned
- Statuses: help/version 0; check 0 or 1; usage errors 2; delegated application status is preserved
- Side effects: sources the stdlib and starts the delegated script; check is non-mutating

#### Public symbols

- `base_launcher_check_project` — signature: see [`docs/v2-api-contract.md`](../docs/v2-api-contract.md).
- `base_launcher_die` — signature: see [`docs/v2-api-contract.md`](../docs/v2-api-contract.md).
- `base_launcher_ensure_supported_bash` — signature: see [`docs/v2-api-contract.md`](../docs/v2-api-contract.md).
- `base_launcher_import_base_bash_lib` — signature: see [`docs/v2-api-contract.md`](../docs/v2-api-contract.md).
- `base_launcher_init` — signature: see [`docs/v2-api-contract.md`](../docs/v2-api-contract.md).
- `base_launcher_lib_dir_is_usable` — signature: see [`docs/v2-api-contract.md`](../docs/v2-api-contract.md).
- `base_launcher_package_root` — signature: see [`docs/v2-api-contract.md`](../docs/v2-api-contract.md).
- `base_launcher_resolve_lib_dir` — signature: see [`docs/v2-api-contract.md`](../docs/v2-api-contract.md).
- `base_launcher_resolve_path` — signature: see [`docs/v2-api-contract.md`](../docs/v2-api-contract.md).
- `base_launcher_run_script` — signature: see [`docs/v2-api-contract.md`](../docs/v2-api-contract.md).
- `base_launcher_source_stdlib` — signature: see [`docs/v2-api-contract.md`](../docs/v2-api-contract.md).
- `base_launcher_usage` — signature: see [`docs/v2-api-contract.md`](../docs/v2-api-contract.md).

