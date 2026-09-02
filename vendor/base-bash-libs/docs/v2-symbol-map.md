# Base Bash v2 symbol map

Base Bash v2 has one coherent public function namespace: `base_`. Public metadata,
configuration, and runtime state remain under `BASE_BASH_LIBS_`. Implementation-
only functions use `__base_bash_libs_...__` and
are intentionally outside the compatibility contract.

The v2 release is a clean break. Generic v1 names are not defined and no
compatibility alias is installed. For source trees or scripts that still use
the v1 surface, run `scripts/migrate-v2-symbols` on a copy or a clean branch,
then review the result and run the consumer's tests.

## Public function map

The tables below are complete by module. Where a rule is shown, every legacy
name in that row is covered by the rule; the explicit lists make the inventory
auditable without requiring a parser.

### Standard library

`base_init` and `base_require_version` already use the v2
package namespace and keep their names. Every other listed stdlib function
maps to `base_std_` followed by the legacy name with a leading
`std_` removed when present.

| Legacy names | v2 names |
| --- | --- |
| `is_interactive`, `check_bash_version`, `import`, `add_to_path`, `dedupe_path`, `print_path` | `base_std_is_interactive`, `base_std_check_bash_version`, `base_std_import`, `base_std_add_to_path`, `base_std_dedupe_path`, `base_std_print_path` |
| `set_log_level`, `set_log_category_level`, `log_is_enabled` | `base_std_set_log_level`, `base_std_set_log_category_level`, `base_std_log_is_enabled` |
| `log_fatal`, `log_error`, `log_warn`, `log_info`, `log_debug`, `log_verbose` | `base_std_log_fatal`, `base_std_log_error`, `base_std_log_warn`, `base_std_log_info`, `base_std_log_debug`, `base_std_log_verbose` |
| `log_info_file`, `log_debug_file`, `log_verbose_file` | `base_std_log_info_file`, `base_std_log_debug_file`, `base_std_log_verbose_file` |
| `log_info_enter`, `log_debug_enter`, `log_verbose_enter`, `log_info_leave`, `log_debug_leave`, `log_verbose_leave` | `base_std_log_info_enter`, `base_std_log_debug_enter`, `base_std_log_verbose_enter`, `base_std_log_info_leave`, `base_std_log_debug_leave`, `base_std_log_verbose_leave` |
| `print_error`, `print_warn`, `print_info`, `print_success`, `print_bold`, `print_message`, `print_tty`, `dump_trace` | `base_std_print_error`, `base_std_print_warn`, `base_std_print_info`, `base_std_print_success`, `base_std_print_bold`, `base_std_print_message`, `base_std_print_tty`, `base_std_dump_trace` |
| `exit_if_error`, `fatal_error`, `is_dry_run`, `std_run` | `base_std_exit_if_error`, `base_std_fatal_error`, `base_std_is_dry_run`, `base_std_run` |

| `safe_mkdir`, `safe_touch`, `safe_truncate`, `safe_cd`, `safe_unalias` | `base_std_safe_mkdir`, `base_std_safe_touch`, `base_std_safe_truncate`, `base_std_safe_cd`, `base_std_safe_unalias` |
| `std_register_cleanup_hook`, `std_unregister_cleanup_hook`, `std_register_cleanup_path`, `std_unregister_cleanup_path` | `base_std_register_cleanup_hook`, `base_std_unregister_cleanup_hook`, `base_std_register_cleanup_path`, `base_std_unregister_cleanup_path` |
| `std_make_temp_file`, `std_make_temp_dir`, `std_command_path`, `std_function_exists` | `base_std_make_temp_file`, `base_std_make_temp_dir`, `base_std_command_path`, `base_std_function_exists` |
| `assert_variable_name`, `assert_indexed_array`, `assert_associative_array`, `assert_function_exists`, `assert_not_null` | `base_std_assert_variable_name`, `base_std_assert_indexed_array`, `base_std_assert_associative_array`, `base_std_assert_function_exists`, `base_std_assert_not_null` |
| `assert_integer`, `assert_integer_range`, `assert_arg_count`, `assert_command_exists`, `assert_file_exists`, `assert_executable`, `assert_dir_exists` | `base_std_assert_integer`, `base_std_assert_integer_range`, `base_std_assert_arg_count`, `base_std_assert_command_exists`, `base_std_assert_file_exists`, `base_std_assert_executable`, `base_std_assert_dir_exists` |
| `get_my_source_dir`, `ask_yes_no`, `wait_for_enter` | `base_std_get_my_source_dir`, `base_std_ask_yes_no`, `base_std_wait_for_enter` |

`base_std_run` is the non-exiting v2 default. The explicit fail-fast sibling
`base_std_run_or_exit` has no v1 alias and should be used only when termination
is part of the caller's intended policy.

### Companion libraries

| Module | Legacy names | v2 names |
| --- | --- | --- |
| file | `file_section_exists`, `file_section_needs_update`, `update_file_section` | `base_file_section_exists`, `base_file_section_needs_update`, `base_file_update_file_section` |
| git | `git_detect_default_branch`, `git_worktree_path_for_branch`, `git_list_worktree_branches`, `git_branch_upstream`, `git_branch_merged_to_ref`, `git_list_remote_branches`, `git_update_repo`, `git_get_current_branch`, `check_script_up_to_date` | `base_git_detect_default_branch`, `base_git_worktree_path_for_branch`, `base_git_list_worktree_branches`, `base_git_branch_upstream`, `base_git_branch_merged_to_ref`, `base_git_list_remote_branches`, `base_git_update_repo`, `base_git_get_current_branch`, `base_git_check_script_up_to_date` |
| gh | `gh_require_cli`, `gh_auth_status_diagnostics`, `gh_report_command_failure`, `gh_run`, `gh_repo_from_remote_url`, `gh_infer_repo_from_origin`, `gh_repo_default_branch`, `gh_api_with_retry` | `base_gh_require_cli`, `base_gh_auth_status_diagnostics`, `base_gh_report_command_failure`, `base_gh_run`, `base_gh_repo_from_remote_url`, `base_gh_infer_repo_from_origin`, `base_gh_repo_default_branch`, `base_gh_api_with_retry` |
| str | `str_lower`, `str_upper`, `str_ltrim`, `str_rtrim`, `str_trim`, `str_contains`, `str_starts_with`, `str_ends_with`, `str_split`, `str_join` | `base_str_lower`, `base_str_upper`, `base_str_ltrim`, `base_str_rtrim`, `base_str_trim`, `base_str_contains`, `base_str_starts_with`, `base_str_ends_with`, `base_str_split`, `base_str_join` |
| arg | `arg_parse` | `base_arg_parse` |
| list | `list_append`, `list_prepend`, `list_remove`, `list_contains`, `list_unique`, `list_length` | `base_list_append`, `base_list_prepend`, `base_list_remove`, `base_list_contains`, `base_list_unique`, `base_list_length` |

The standalone launcher keeps `main` as the application entrypoint. Its helper
functions use `base_launcher_`:

| Legacy name | v2 name |
| --- | --- |
| `base_bash_die`, `base_bash_resolve_path`, `base_bash_package_root`, `base_bash_ensure_supported_bash` | `base_launcher_die`, `base_launcher_resolve_path`, `base_launcher_package_root`, `base_launcher_ensure_supported_bash` |
| `base_bash_lib_dir_is_usable`, `base_bash_resolve_lib_dir`, `base_bash_source_stdlib` | `base_launcher_lib_dir_is_usable`, `base_launcher_resolve_lib_dir`, `base_launcher_source_stdlib` |
| `import_base_bash_lib`, `base_bash_run_script`, `base_bash_usage` | `base_launcher_import_base_bash_lib`, `base_launcher_run_script`, `base_launcher_usage` |

The application-defined `main` function is intentionally not namespaced.

## Global and environment map

| Legacy name | v2 name |
| --- | --- |
| `__SCRIPT_ARGS__` | `BASE_BASH_LIBS_SCRIPT_ARGS` |
| `__SCRIPT_DIR__` | `BASE_BASH_LIBS_SCRIPT_DIR` |
| `__color__` | `BASE_BASH_LIBS_STD_COLOR_ENABLED` |
| `COLOR_BOLD`, `COLOR_RED`, `COLOR_GREEN`, `COLOR_YELLOW`, `COLOR_BLUE`, `COLOR_OFF` | `BASE_BASH_LIBS_STD_COLOR_BOLD`, `BASE_BASH_LIBS_STD_COLOR_RED`, `BASE_BASH_LIBS_STD_COLOR_GREEN`, `BASE_BASH_LIBS_STD_COLOR_YELLOW`, `BASE_BASH_LIBS_STD_COLOR_BLUE`, `BASE_BASH_LIBS_STD_COLOR_OFF` |
| `LOG_DEBUG`, `LOG_UTC` | `BASE_BASH_LIBS_LOG_DEBUG`, `BASE_BASH_LIBS_LOG_UTC` |
| `BASE_BASH_BOOTSTRAP_SOURCE` | `BASE_BASH_LIBS_BOOTSTRAP_SOURCE` |
| `BASE_CLI_PRIMARY_LOG` | `BASE_BASH_LIBS_PRIMARY_LOG` |
| `BASE_GIT_PULL_MAX_ATTEMPTS` | `BASE_BASH_LIBS_GIT_PULL_MAX_ATTEMPTS` |
| `BASE_BASH_FILE_START_MARKER`, `BASE_BASH_FILE_END_MARKER`, `BASE_BASH_FILE_NEW_CONTENT_FILE` | `BASE_BASH_LIBS_FILE_START_MARKER`, `BASE_BASH_LIBS_FILE_END_MARKER`, `BASE_BASH_LIBS_FILE_NEW_CONTENT_FILE` |
| `DRY_RUN`, `dry_run` | `BASE_BASH_LIBS_DRY_RUN` |
| `__lib_std_sourced__`, `__lib_file_sourced__`, `__lib_git_sourced__`, `__lib_gh_sourced__`, `__lib_str_sourced__`, `__lib_arg_sourced__`, `__lib_list_sourced__` | `BASE_BASH_LIBS_STDLIB_LOADED`, `BASE_BASH_LIBS_FILE_LOADED`, `BASE_BASH_LIBS_GIT_LOADED`, `BASE_BASH_LIBS_GH_LOADED`, `BASE_BASH_LIBS_STR_LOADED`, `BASE_BASH_LIBS_ARG_LOADED`, `BASE_BASH_LIBS_LIST_LOADED` |
| `_log_levels`, `_loggers_level_map`, `_log_category_level_map`, `_log_primary_sink_failed_paths` | `BASE_BASH_LIBS_STD_LOG_LEVELS`, `BASE_BASH_LIBS_STD_LOGGER_LEVELS`, `BASE_BASH_LIBS_STD_LOG_CATEGORY_LEVELS`, `BASE_BASH_LIBS_STD_LOG_FAILED_SINKS` |

`NO_COLOR`, `PATH`, `TMPDIR`, `BASH_*`, `GH_*`, `TZ`, and other documented
shell or ecosystem variables remain caller-owned inputs. The framework does
not define or export them, so they are not part of its symbol namespace.

## Internal prefix map

All implementation-only functions and local holders use the same module
segment under the reserved internal namespace:

| Legacy prefix | v2 prefix |
| --- | --- |
| `__lib_std_require_supported_bash__`, `__std_`, `__log_`, `__print_`, `__init_colors__`, `__join_message__`, `__resolve_log_category_level__`, `__is_valid_variable_name__` | `__base_bash_libs_std_...__` |
| `__file_`, `__preserve_file_mode__` | `__base_bash_libs_file_...__` |
| `__git_` | `__base_bash_libs_git_...__` |
| `__gh_` | `__base_bash_libs_gh_...__` |
| `__arg_` | `__base_bash_libs_arg_...__` |
| `__list_` | `__base_bash_libs_list_...__` |
| `__str_` | `__base_bash_libs_str_...__` |

No v2 compatibility guarantee is made for internal names. New code must not
call them; collision fixtures and static checks ensure generic internal names
are not exported by the libraries.
