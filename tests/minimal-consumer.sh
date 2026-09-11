#!/usr/bin/env bash

set -euo pipefail

minimal_test_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
minimal_test_consumer="$minimal_test_root/examples/minimal-cli"
minimal_test_path="$minimal_test_root/vendor/base-bash-libs/bin:$PATH"

minimal_test_help="$(PATH="$minimal_test_path" "$minimal_test_consumer" --help)"
grep -Fq 'Usage: starter [options] <command>' <<< "$minimal_test_help"
grep -Fq 'greet' <<< "$minimal_test_help"

minimal_test_output="$(PATH="$minimal_test_path" "$minimal_test_consumer" greet Ada)"
[[ "$minimal_test_output" == 'Hello, Ada!' ]]

set +e
minimal_test_error="$(PATH="$minimal_test_path" "$minimal_test_consumer" greet 2>&1)"
minimal_test_status=$?
set -e
[[ "$minimal_test_status" -eq 2 ]]
grep -Fq "required positional 'name' was not provided." <<< "$minimal_test_error"

printf 'Minimal Base Bash consumer passed.\n'
