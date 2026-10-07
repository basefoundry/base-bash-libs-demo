#!/usr/bin/env bats

load ../../tests/test_helper.sh

setup() {
    setup_test_tmpdir
    source "$BASE_BASH_DIR/std/lib_std.sh"
    # shellcheck disable=SC2034 # base_init receives the caller-owned argv array by name.
    declare -a setup_args=()
    base_init setup_args --source "$BASE_BASH_DIR/cli/tests/lib_cli.bats" --
    source "$BASE_BASH_DIR/cli/lib_cli.sh"
}

valid_target() {
    [[ "$1" =~ ^[a-z][a-z0-9-]*$ ]]
}

declare_demo_model() {
    base_cli_model_init demo name=demo version=2.0.0 description="Demo CLI"
    base_cli_command demo admin "Administration" aliases=manage
    base_cli_command demo admin/user "Show a user" aliases=u
    base_cli_option demo admin/user verbose flag --verbose -v help="Verbose output"
    base_cli_option demo admin/user color value --color default=blue enum=blue,green metavar=COLOR help="Output color"
    base_cli_option demo admin/user tag repeatable --tag -t help="A tag"
    base_cli_positional demo admin/user target required=true validator=valid_target help="Target name"
}

model_registry_dump() {
    local model="$1" key

    for key in "${!__base_bash_libs_cli_models[@]}"; do
        [[ "$key" == "$model|"* ]] || continue
        printf '%q=%q\n' "$key" "${__base_bash_libs_cli_models[$key]}"
    done | LC_ALL=C sort
}

assert_failed_declaration_preserves_demo() {
    local before="$1" status
    shift

    if base_cli_declare demo "$@"; then
        return 1
    else
        status=$?
    fi
    [ "$status" -eq 2 ]
    [ "$(model_registry_dump demo)" = "$before" ]
}

@test "quick declaration builds an order-independent model from table rows" {
    base_cli_declare quick <<'EOF'
# Rows are intentionally not in engine declaration order.
option|path=admin/user|name=verbose|type=flag|tokens=--verbose,-v|help=Verbose output
positional|path=admin/user|name=target|required=true|validator=valid_target
command|path=admin/user|description=Show a user|aliases=u
command|path=admin|description=Administration|aliases=manage
model|name=quick|version=2.0.0|description=Quick CLI
option|path=admin/user|name=color|type=value|tokens=--color|default=blue|enum=blue,green
EOF

    base_cli_parse quick -- manage u target-name --color green --verbose

    [ "$BASE_BASH_LIBS_CLI_RESULT_COMMAND" = "admin/user" ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[color]}" = "green" ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[verbose]}" = "1" ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[0]}" = "target-name" ]
}

@test "quick declaration accepts argument rows and rejects unknown row kinds" {
    base_cli_declare args \
        'model|name=args|version=2.0.0' \
        'command|path=run|description=Run'
    base_cli_parse args -- run
    [ "$BASE_BASH_LIBS_CLI_RESULT_COMMAND" = "run" ]

    bats_run base_cli_declare broken \
        'model|name=broken' \
        'unknown|path=run'
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown row kind 'unknown'"* ]]
}

@test "imperative and quick declarations share attribute allowlists" {
    base_cli_model_init imperative name=imperative version=2.0.0 description=Imperative handler=valid_target
    base_cli_command imperative run Run valid_target aliases=r
    base_cli_option imperative run other value --other help=Other
    base_cli_option imperative run target value --target help=Target metavar=TARGET default=blue \
        required=true enum=blue,green validator=valid_target conflicts=other sensitive=true hidden=true
    base_cli_positional imperative run item help=Item metavar=ITEM default=blue required=true \
        enum=blue,green validator=valid_target repeatable=true

    base_cli_declare quick_attrs \
        'model|name=quick-attrs|version=2.0.0|description=Quick|handler=valid_target' \
        'command|path=run|description=Run|handler=valid_target|aliases=r' \
        'option|path=run|name=other|type=value|tokens=--other|help=Other' \
        'option|path=run|name=target|type=value|tokens=--target|help=Target|metavar=TARGET|default=blue|required=true|enum=blue,green|validator=valid_target|conflicts=other|sensitive=true|hidden=true' \
        'positional|path=run|name=item|help=Item|metavar=ITEM|default=blue|required=true|enum=blue,green|validator=valid_target|repeatable=true'

    base_cli_parse imperative -- run --target blue blue
    [ "$BASE_BASH_LIBS_CLI_RESULT_COMMAND" = run ]
    base_cli_parse quick_attrs -- run --target blue blue
    [ "$BASE_BASH_LIBS_CLI_RESULT_COMMAND" = run ]
}

@test "quick declaration rolls back every late semantic failure" {
    base_cli_model_init demo name=original version=1.0.0 description="Original model"
    base_cli_command demo old "Original command" aliases=legacy
    base_cli_option demo old keep value --keep default=preserved
    local before
    local -a __base_bash_libs_cli_previous_positionals=(caller-owned)
    before="$(model_registry_dump demo)"

    assert_failed_declaration_preserves_demo "$before" \
        'model|name=bad/name' \
        'command|path=run|description=Run'
    assert_failed_declaration_preserves_demo "$before" \
        'model|name=replacement' \
        'command|path=missing/child|description=Missing parent'
    assert_failed_declaration_preserves_demo "$before" \
        'model|name=replacement' \
        'command|path=run|description=Run' \
        'option|path=run|name=mode|type=invalid|tokens=--mode'
    assert_failed_declaration_preserves_demo "$before" \
        'model|name=replacement' \
        'command|path=run|description=Run' \
        'positional|path=run|name=items|repeatable=true' \
        'positional|path=run|name=after'
    assert_failed_declaration_preserves_demo "$before" \
        'model|name=replacement' \
        'command|path=run|description=Run|aliases=bad/alias'
    assert_failed_declaration_preserves_demo "$before" \
        'model|name=replacement' \
        'command|path=run|description=Run' \
        'option|path=run|name=mode|type=value|tokens=--mode|enum=blue,green|default=red'
    assert_failed_declaration_preserves_demo "$before" \
        'model|name=replacement' \
        'command|path=run|description=Run' \
        'positional|path=run|name=target|required=maybe'
    assert_failed_declaration_preserves_demo "$before" \
        'model|name=replacement' \
        'command|path=run|description=Run' \
        'option|path=run|name=mode|type=value|tokens=--mode|validator=bad-name'
    [ "${__base_bash_libs_cli_previous_positionals[*]}" = caller-owned ]
}

@test "failed quick declaration leaves no partial new model" {
    if base_cli_declare unfinished \
        'model|name=unfinished' \
        'command|path=run|description=Run' \
        'option|path=run|name=mode|type=invalid|tokens=--mode'; then
        false
    else
        [ "$?" -eq 2 ]
    fi

    if __base_bash_libs_cli_model_exists__ unfinished; then
        false
    fi
    [ -z "$(model_registry_dump unfinished)" ]
}

@test "lib_cli can be sourced more than once" {
    source "$BASE_BASH_DIR/cli/lib_cli.sh"

    [ "$(type -t base_cli_model_init)" = "function" ]
}

@test "lib_cli fails clearly when sourced without stdlib" {
    bats_run bash -c 'source "$1"; rc=$?; printf "source-rc=%s\n" "$rc"; exit "$rc"' bash "$BASE_BASH_DIR/cli/lib_cli.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"lib_cli.sh requires lib_std.sh to be sourced first"* ]]
    [[ "$output" == *"source-rc=1"* ]]
}

@test "declarative model parses nested aliases and preserves result boundaries" {
    declare_demo_model

    base_cli_parse demo -- manage u target-name --color green --tag one --tag "two words" --verbose

    [ "$BASE_BASH_LIBS_CLI_RESULT_COMMAND" = "admin/user" ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[color]}" = "green" ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[verbose]}" = "1" ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_REPEATABLE_COUNTS[tag]}" -eq 2 ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_REPEATED[tag\|0]}" = "one" ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_REPEATED[tag\|1]}" = "two words" ]

    local target color count
    base_cli_result_get_positional 0 target
    base_cli_result_get color color
    base_cli_result_count tag count
    [ "$target" = "target-name" ]
    [ "$color" = "green" ]
    [ "$count" -eq 2 ]
}

@test "CLI named outputs enforce scalar and integer attributes" {
    local stderr_file="$TEST_TMPDIR/cli-typed-output.err"
    local rc
    local -u color_value=sentinel
    local -i repeatable_count=99

    declare_demo_model
    base_cli_parse demo -- manage u target-name --color green --tag one

    if base_cli_result_get color color_value 2>"$stderr_file"; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 2 ]
    [ "$color_value" = SENTINEL ]
    [[ "$(<"$stderr_file")" == *"attributes incompatible with the scalar output contract"* ]]

    base_cli_result_count tag repeatable_count
    [ "$repeatable_count" -eq 1 ]
}

@test "help is deterministic and includes aliases, defaults, and nested usage" {
    declare_demo_model

    bats_run base_cli_help demo admin/user

    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: demo admin/user [options] <target>"* ]]
    [[ "$output" == *"--color <COLOR>"* ]]
    [[ "$output" == *"(default: blue)"* ]]
    [[ "$output" == *"--tag, -t"* ]]

    bats_run base_cli_help demo
    [ "$status" -eq 0 ]
    [[ "$output" == *"admin (manage)"* ]]
}


@test "help redacts sensitive defaults and aligns long option labels" {
    base_cli_model_init secrets name=secrets version=2.0.0
    base_cli_command secrets run "Run"
    base_cli_option secrets run api_token value --api-token default='top-secret' sensitive=true help='Authentication token'
    base_cli_option secrets run extraordinarily_long_option value --extraordinarily-long-option default=visible help='Long option'

    bats_run base_cli_help secrets run

    [ "$status" -eq 0 ]
    [[ "$output" == *"--api-token <api_token>                                     Authentication token (default: <redacted>)"* ]]
    [[ "$output" != *"top-secret"* ]]
    [[ "$output" == *"--extraordinarily-long-option <extraordinarily_long_option> Long option (default: visible)"* ]]
}

@test "conflicts must reference an already declared option" {
    base_cli_model_init invalid name=invalid
    base_cli_command invalid run "Run"

    bats_run base_cli_option invalid run mode flag --mode conflicts=missing

    [ "$status" -eq 2 ]
    [[ "$output" == *"conflict option 'missing' is not declared"* ]]
}

@test "usage errors return status 2 with diagnostics" {
    declare_demo_model

    bats_run base_cli_parse demo -- admin user --color purple target-name
    [ "$status" -eq 2 ]
    [[ "$output" == *"invalid value for option 'color'"* ]]
    [[ "$output" == *"Usage: demo admin/user"* ]]

    bats_run base_cli_parse demo -- admin user target-name --unknown
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown option '--unknown'"* ]]
}

@test "flags reject empty and non-empty attached values before handlers run" {
    local handler_calls=0
    flag_handler() { handler_calls=$((handler_calls + 1)); }

    base_cli_model_init flags name=flags handler=flag_handler
    base_cli_option flags '' enabled flag --enabled

    bats_run base_cli_run flags -- --enabled=
    [ "$status" -eq 2 ]
    [ "$handler_calls" -eq 0 ]
    [[ "$output" == *"flag '--enabled' does not accept a value"* ]]

    bats_run base_cli_run flags -- --enabled=true
    [ "$status" -eq 2 ]
    [ "$handler_calls" -eq 0 ]
}

@test "flag defaults use effective booleans for ancestor and child conflicts" {
    base_cli_model_init flags name=flags
    base_cli_command flags run Run
    base_cli_option flags '' inherited flag --inherited default=false
    base_cli_option flags run selected flag --selected conflicts=inherited

    base_cli_parse flags -- run --selected
    [ "${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[inherited]}" = false ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[selected]}" = 1 ]

    base_cli_model_init booleans name=booleans
    base_cli_option booleans '' enabled flag --enabled default=yes
    base_cli_option booleans '' disabled flag --disabled default=no
    base_cli_option booleans '' one flag --one default=1
    base_cli_option booleans '' zero flag --zero default=0
    base_cli_parse booleans --
    [ "${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[enabled]}" = yes ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[disabled]}" = no ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[one]}" = 1 ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[zero]}" = 0 ]

    base_cli_model_init active name=active
    base_cli_option active '' first flag --first default=true
    base_cli_option active '' second flag --second conflicts=first
    bats_run base_cli_parse active -- --second
    [ "$status" -eq 2 ]
    [[ "$output" == *"options 'second' and 'first' conflict"* ]]
}

@test "double dash preserves empty and option-looking positionals" {
    base_cli_model_init dash name=dash
    base_cli_command dash run "Run"
    base_cli_positional dash run first required=true
    base_cli_positional dash run rest repeatable=true

    base_cli_parse dash -- run "" -- --looks-like-option

    [ "${#BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[@]}" -eq 2 ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[0]}" = "" ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[1]}" = "--looks-like-option" ]
}

@test "positional result indexes are decimal and range checked before arithmetic" {
    BASE_BASH_LIBS_CLI_RESULT_POSITIONALS=(zero one two three four five six seven eight)
    local value=unchanged

    base_cli_result_get_positional 0 value
    [ "$value" = zero ]
    base_cli_result_get_positional 08 value
    [ "$value" = eight ]

    bats_run base_cli_result_get_positional 9 value
    [ "$status" -eq 1 ]
    [ "$value" = eight ]
    bats_run base_cli_result_get_positional 18446744073709551616 value
    [ "$status" -eq 1 ]
    [ "$value" = eight ]
}

@test "double dash keeps command names and aliases as root positionals" {
    base_cli_model_init boundary name=boundary
    base_cli_command boundary run "Run" aliases=r
    base_cli_positional boundary '' target required=true repeatable=true

    base_cli_parse boundary -- -- run

    [ "$BASE_BASH_LIBS_CLI_RESULT_COMMAND" = "" ]
    [ "${#BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[@]}" -eq 1 ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[0]}" = run ]

    base_cli_parse boundary -- literal r
    [ "$BASE_BASH_LIBS_CLI_RESULT_COMMAND" = "" ]
    [ "${#BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[@]}" -eq 2 ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[0]}" = literal ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[1]}" = r ]
}

@test "positional collection closes command resolution before later command-like words" {
    base_cli_model_init positional_boundary name=positional-boundary
    base_cli_command positional_boundary run "Run"
    base_cli_positional positional_boundary '' target required=true repeatable=true

    base_cli_parse positional_boundary -- literal run

    [ "$BASE_BASH_LIBS_CLI_RESULT_COMMAND" = "" ]
    [ "${#BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[@]}" -eq 2 ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[0]}" = literal ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[1]}" = run ]
}

@test "required repeatable positionals count only their own consumed values" {
    base_cli_model_init direct_repeat name=direct-repeat
    base_cli_command direct_repeat run "Run"
    base_cli_positional direct_repeat run target required=true
    base_cli_positional direct_repeat run files required=true repeatable=true

    bats_run base_cli_parse direct_repeat -- run target-only
    [ "$status" -eq 2 ]
    [[ "$output" == *"required positional 'files' was not provided"* ]]
    base_cli_parse direct_repeat -- run target one
    base_cli_parse direct_repeat -- run target one two

    base_cli_model_init root_repeat name=root-repeat
    base_cli_positional root_repeat '' items required=true repeatable=true
    bats_run base_cli_parse root_repeat --
    [ "$status" -eq 2 ]
    base_cli_parse root_repeat -- one
    base_cli_parse root_repeat -- one two

    base_cli_model_init optional_repeat name=optional-repeat
    base_cli_command optional_repeat run "Run"
    base_cli_positional optional_repeat run target required=true
    base_cli_positional optional_repeat run files repeatable=true
    base_cli_parse optional_repeat -- run target-only
}

@test "required positionals cannot follow optional or defaulted positionals" {
    base_cli_model_init ordering name=ordering
    base_cli_command ordering run "Run"
    base_cli_positional ordering run context

    bats_run base_cli_positional ordering run target required=true
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot declare required positional 'target' after optional positional 'context'"* ]]
    [ "${__base_bash_libs_cli_models[ordering\|command\|positionals\|run]}" = context ]

    base_cli_model_init defaulted_order name=defaulted-order
    base_cli_command defaulted_order run "Run"
    base_cli_positional defaulted_order run context default=working

    bats_run base_cli_positional defaulted_order run target required=true
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot declare required positional 'target' after optional positional 'context'"* ]]

    base_cli_model_init valid_order name=valid-order
    base_cli_command valid_order run "Run"
    base_cli_positional valid_order run target required=true
    base_cli_positional valid_order run context default=working
    base_cli_parse valid_order -- run target-value
    [ "${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[0]}" = target-value ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[1]}" = working ]
}

@test "repeatable positional defaults are applied and validated only when omitted" {
    valid_archive() { [[ "$1" == archive ]]; }

    base_cli_model_init direct_repeat_default name=direct-repeat-default
    base_cli_command direct_repeat_default run "Run"
    base_cli_positional direct_repeat_default run target required=true
    base_cli_positional direct_repeat_default run files repeatable=true required=true \
        default=fallback enum=fallback,archive validator=valid_target

    base_cli_parse direct_repeat_default -- run target-value
    [ "${#BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[@]}" -eq 2 ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[0]}" = target-value ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[1]}" = fallback ]

    base_cli_parse direct_repeat_default -- run target-value archive
    [ "${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[1]}" = archive ]

    base_cli_model_init explicit_empty name=explicit-empty
    base_cli_command explicit_empty run "Run"
    base_cli_positional explicit_empty run values repeatable=true default=fallback
    base_cli_parse explicit_empty -- run ""
    [ "${#BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[@]}" -eq 1 ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[0]}" = "" ]

    base_cli_model_init invalid_enum name=invalid-enum
    base_cli_command invalid_enum run "Run"
    bats_run base_cli_positional invalid_enum run values repeatable=true default=invalid enum=valid
    [ "$status" -eq 2 ]
    [[ "$output" == *"default must be one of the declared enum values"* ]]

    base_cli_model_init invalid_validator name=invalid-validator
    base_cli_command invalid_validator run "Run"
    base_cli_positional invalid_validator run values repeatable=true default=fallback \
        enum=fallback,archive validator=valid_archive
    if base_cli_parse invalid_validator -- run >/dev/null 2>&1; then
        status=0
    else
        status=$?
    fi
    [ "$status" -eq 2 ]
    [ "${#BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[@]}" -eq 0 ]

    base_cli_model_init invalid_scalar_default name=invalid-scalar-default
    base_cli_command invalid_scalar_default run "Run"
    base_cli_positional invalid_scalar_default run value default=fallback validator=valid_archive
    if base_cli_parse invalid_scalar_default -- run >/dev/null 2>&1; then
        status=0
    else
        status=$?
    fi
    [ "$status" -eq 2 ]
    [ "${#BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[@]}" -eq 0 ]

    base_cli_declare table_repeat_default \
        'model|name=table-repeat-default' \
        'command|path=run|description=Run' \
        'positional|path=run|name=values|repeatable=true|required=true|default=fallback|enum=fallback,archive'
    base_cli_parse table_repeat_default -- run
    [ "${#BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[@]}" -eq 1 ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_POSITIONALS[0]}" = fallback ]
}

@test "quick declarations enforce required repeatable positional tails" {
    base_cli_declare table_repeat \
        'model|name=table-repeat' \
        'command|path=run|description=Run' \
        'positional|path=run|name=target|required=true' \
        'positional|path=run|name=files|required=true|repeatable=true'

    bats_run base_cli_parse table_repeat -- run target-only
    [ "$status" -eq 2 ]
    [[ "$output" == *"required positional 'files' was not provided"* ]]
    base_cli_parse table_repeat -- run target one
    base_cli_parse table_repeat -- run target one two
}

@test "run invokes handlers but help and version do not" {
    local handler_calls=0
    demo_handler() {
        handler_calls=$((handler_calls + 1))
    }
    base_cli_model_init runme name=runme version=2.0.0 handler=demo_handler

    base_cli_run runme -- --help
    [ "$handler_calls" -eq 0 ]
    base_cli_run runme -- --version
    [ "$handler_calls" -eq 0 ]
    base_cli_run runme --
    [ "$handler_calls" -eq 1 ]
}

@test "explicit model validation catches undeclared handlers" {
    base_cli_model_init validate name=validate handler=missing_root
    base_cli_command validate run "Run" handler=missing_run

    bats_run base_cli_validate_model validate

    [ "$status" -eq 2 ]
    [[ "$output" == *"<root>:missing_root"* ]]
    [[ "$output" == *"run:missing_run"* ]]

    missing_root() { :; }
    missing_run() { :; }
    base_cli_validate_model validate
}

@test "model validation accepts reachable root and nested options" {
    base_cli_model_init reachable name=reachable
    base_cli_command reachable admin "Administration" aliases=a
    base_cli_option reachable '' output value --output -o
    base_cli_option reachable '' token value --token
    base_cli_option reachable admin local flag --local
    base_cli_option reachable admin mode value --mode

    base_cli_validate_model reachable
    base_cli_parse reachable -- a --output expected --local

    [ "${BASE_BASH_LIBS_CLI_RESULT_COMMAND}" = admin ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[output]}" = expected ]
    [ "${BASE_BASH_LIBS_CLI_RESULT_OPTIONS[local]}" = 1 ]
}

@test "command names and aliases remain unique in either declaration order" {
    base_cli_model_init alias_first name=alias-first
    base_cli_command alias_first user "User" aliases=u
    bats_run base_cli_command alias_first u "Canonical collision"
    [ "$status" -eq 2 ]
    [[ "$output" == *"command name 'u' is already used"* ]]
    base_cli_parse alias_first -- u
    [ "$BASE_BASH_LIBS_CLI_RESULT_COMMAND" = user ]

    base_cli_model_init canonical_first name=canonical-first
    base_cli_command canonical_first u "Canonical"
    bats_run base_cli_command canonical_first user "User" aliases=u
    [ "$status" -eq 2 ]
    [[ "$output" == *"alias 'u' is already used"* ]]

    base_cli_model_init duplicate_alias name=duplicate-alias
    bats_run base_cli_command duplicate_alias user "User" aliases=u,u
    [ "$status" -eq 2 ]
    [[ "$output" == *"route 'u' was provided more than once"* ]]
}

@test "a lone dash is accepted as a model name command name and alias" {
    base_cli_model_init dash_model name=-
    base_cli_validate_model dash_model

    base_cli_model_init dash_command name=dash-command
    base_cli_command dash_command - "Read standard input"
    base_cli_parse dash_command -- -
    [ "$BASE_BASH_LIBS_CLI_RESULT_COMMAND" = - ]

    base_cli_model_init dash_alias name=dash-alias
    base_cli_command dash_alias stdin "Read standard input" aliases=-
    base_cli_parse dash_alias -- -
    [ "$BASE_BASH_LIBS_CLI_RESULT_COMMAND" = stdin ]
}

@test "ancestor and child option names and tokens cannot shadow each other" {
    base_cli_model_init ancestor_first name=ancestor-first
    base_cli_command ancestor_first child "Child"
    base_cli_option ancestor_first '' mode value --mode
    bats_run base_cli_option ancestor_first child mode value --child-mode
    [ "$status" -eq 2 ]
    [[ "$output" == *"option name 'mode' conflicts"* ]]
    bats_run base_cli_option ancestor_first child child_mode value --mode
    [ "$status" -eq 2 ]
    [[ "$output" == *"token '--mode' conflicts"* ]]

    base_cli_model_init child_first name=child-first
    base_cli_command child_first child "Child"
    base_cli_command child_first sibling "Sibling"
    base_cli_option child_first child child_mode value --mode
    bats_run base_cli_option child_first '' child_mode value --root-mode
    [ "$status" -eq 2 ]
    [[ "$output" == *"option name 'child_mode' conflicts"* ]]
    bats_run base_cli_option child_first '' root_mode value --mode
    [ "$status" -eq 2 ]
    [[ "$output" == *"token '--mode' conflicts"* ]]

    base_cli_option child_first child child_only value --shared
    base_cli_option child_first sibling sibling_only value --shared
}

@test "quick declarations apply the same route collision rules" {
    bats_run base_cli_declare command_collision \
        'model|name=command-collision' \
        'command|path=user|description=User|aliases=u' \
        'command|path=u|description=Canonical collision'
    [ "$status" -eq 2 ]

    bats_run base_cli_declare option_collision \
        'model|name=option-collision' \
        'command|path=child|description=Child' \
        'option|path=child|name=child_mode|type=value|tokens=--mode' \
        'option|path=|name=root_mode|type=value|tokens=--mode'
    [ "$status" -eq 2 ]
}

@test "built-in option tokens and option-shaped command routes are unreachable" {
    local before token path

    base_cli_model_init reserved name=reserved version=2.0.0
    base_cli_command reserved run "Run"
    before="$(model_registry_dump reserved)"
    for path in '' run; do
        for token in -h --help -V --version; do
            bats_run base_cli_option reserved "$path" custom value "$token"
            [ "$status" -eq 2 ]
            [[ "$output" == *"reserved for built-in CLI behavior"* ]]
            [ "$(model_registry_dump reserved)" = "$before" ]
        done
    done

    bats_run base_cli_command reserved --diagnose "Unreachable route"
    [ "$status" -eq 2 ]
    bats_run base_cli_command reserved run/-diagnose "Unreachable nested route"
    [ "$status" -eq 2 ]
    bats_run base_cli_command reserved manage "Manage" aliases=-m
    [ "$status" -eq 2 ]

    bats_run base_cli_declare reserved_table \
        'model|name=reserved-table|version=2.0.0' \
        'command|path=run|description=Run' \
        'option|path=run|name=help|type=flag|tokens=--help'
    [ "$status" -eq 2 ]
    [ "$(model_registry_dump reserved_table)" = "" ]
}

@test "model validation detects unreachable command and option routes" {
    base_cli_model_init routes name=routes
    base_cli_command routes user "User" aliases=u
    base_cli_command routes child "Child"
    base_cli_option routes '' mode value --mode

    __base_bash_libs_cli_models['routes|command|child||u']=child
    __base_bash_libs_cli_models['routes|option|child|meta|child_mode|type']=value
    __base_bash_libs_cli_models['routes|option|child|meta|child_mode|tokens']='--mode'
    __base_bash_libs_cli_models['routes|option|child|token|--mode']=child_mode

    __base_bash_libs_cli_models['routes|option|child|meta|built_in|type']=flag
    __base_bash_libs_cli_models['routes|option|child|meta|built_in|tokens']='--help'
    __base_bash_libs_cli_models['routes|option|child|token|--help']=built_in
    __base_bash_libs_cli_option_name_index['routes|built_in']=child
    __base_bash_libs_cli_option_token_index['routes|--help']=child

    bats_run base_cli_validate_model routes

    [ "$status" -eq 2 ]
    [[ "$output" == *"alias:user:u"* ]]
    [[ "$output" == *"option:child:--mode"* ]]
    [[ "$output" == *"option:child:--help"* ]]
}

@test "option validators may render help without corrupting required-option traversal" {
    show_nested_help() {
        base_cli_help nested run >/dev/null
    }

    base_cli_model_init nested name=nested
    base_cli_command nested run "Nested run"
    base_cli_option nested run mode value --mode

    base_cli_model_init outer name=outer
    base_cli_command outer run "Outer run"
    base_cli_option outer run first value --first validator=show_nested_help
    base_cli_option outer run credential value --credential required=true

    bats_run base_cli_parse outer -- run --first value

    [ "$status" -eq 2 ]
    [[ "$output" == *"required option 'credential' was not provided"* ]]
}

@test "positional validators may render help without corrupting positional traversal" {
    show_nested_help() {
        base_cli_help nested run >/dev/null
    }

    base_cli_model_init nested name=nested
    base_cli_command nested run "Nested run"
    base_cli_positional nested run target help="Target"

    base_cli_model_init outer name=outer
    base_cli_command outer run "Outer run"
    base_cli_positional outer run first required=true validator=show_nested_help
    base_cli_positional outer run credential required=true

    bats_run base_cli_parse outer -- run first-value

    [ "$status" -eq 2 ]
    [[ "$output" == *"required positional 'credential' was not provided"* ]]
}

@test "completion emits aliases and a self-contained completion adapter" {
    declare_demo_model

    bats_run base_cli_complete demo -- admin u
    [ "$status" -eq 0 ]
    [[ "$output" == *$'user\n'* || "$output" == user ]]
    [[ "$output" == *$'u'* ]]

    bats_run base_cli_completion_script demo _demo_complete
    [ "$status" -eq 0 ]
    [[ "$output" == *"_demo_complete()"* ]]
    [[ "$output" == *"complete -F _demo_complete demo"* ]]
}

@test "generated completion honors the cursor and keeps scratch variables local" {
    local completion_script="$TEST_TMPDIR/completion.bash"
    local candidate=caller-owned

    base_cli_model_init cursor name=cursor
    base_cli_command cursor admin "Administration"
    base_cli_command cursor admin/user "User"
    base_cli_option cursor '' channel value --channel enum=alpha,beta
    base_cli_option cursor '' output value --output
    base_cli_option cursor admin/user color value --color
    base_cli_completion_script cursor _cursor_complete > "$completion_script"
    source "$completion_script"

    COMP_WORDS=(cursor --ch stable --output result)
    COMP_CWORD=1
    _cursor_complete
    [ "${COMPREPLY[*]}" = --channel ]
    [ "$candidate" = caller-owned ]

    COMP_WORDS=(cursor --channel a --output result)
    COMP_CWORD=2
    _cursor_complete
    [ "${#COMPREPLY[@]}" -eq 0 ]

    COMP_WORDS=(cursor admin --out --channel alpha)
    COMP_CWORD=2
    _cursor_complete
    [ "${COMPREPLY[*]}" = --output ]

    COMP_WORDS=(cursor admin user --co)
    COMP_CWORD=3
    _cursor_complete
    [ "${COMPREPLY[*]}" = --color ]

    COMP_WORDS=(cursor -- --channel)
    COMP_CWORD=2
    _cursor_complete
    [ "${#COMPREPLY[@]}" -eq 0 ]

    COMP_WORDS=(cursor admin)
    COMP_CWORD=2
    _cursor_complete
    [ "${COMPREPLY[*]}" = user ]

    COMP_CWORD=99
    _cursor_complete
    [ "${COMPREPLY[*]}" = user ]

    COMP_WORDS=(cursor)
    COMP_CWORD=1
    _cursor_complete
    [ "${COMPREPLY[*]}" = admin ]

    unset COMP_WORDS COMP_CWORD
    set -u
    _cursor_complete
    status=$?
    set +u
    [ "$status" -eq 0 ]
    [ "${COMPREPLY[*]}" = admin ]
}

@test "completion consumes option values and honors the double-dash boundary" {
    base_cli_model_init complete name=complete
    base_cli_command complete admin "Administration" aliases=a
    base_cli_command complete admin/user "User" aliases=u
    base_cli_option complete '' verbose flag --verbose -v
    base_cli_option complete '' config value --config
    base_cli_option complete '' tag repeatable --tag

    bats_run base_cli_complete complete -- --config admin
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    bats_run base_cli_complete complete -- --config admin ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"admin"* ]]
    [[ "$output" != *"user"* ]]

    bats_run base_cli_complete complete -- --tag admin
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    bats_run base_cli_complete complete -- --config=admin ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"admin"* ]]
    bats_run base_cli_complete complete -- --config -not-an-option
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    bats_run base_cli_complete complete -- --config "" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"admin"* ]]

    bats_run base_cli_complete complete -- --verbose ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"admin"* ]]
    bats_run base_cli_complete complete -- a u
    [ "$status" -eq 0 ]
    [[ "$output" == *"user"* ]]
    [[ "$output" == *"u"* ]]

    bats_run base_cli_complete complete -- -- admin ""
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    bats_run base_cli_complete complete -- -- ""
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "completion stops command traversal after a positional while retaining root options" {
    local completion_script="$TEST_TMPDIR/boundary-completion.bash"

    base_cli_model_init boundary name=boundary
    base_cli_command boundary deploy "Deploy" aliases=d
    base_cli_command boundary deploy/plan "Plan" aliases=p
    base_cli_option boundary '' root_flag flag --root-flag
    base_cli_option boundary deploy force flag --force
    base_cli_option boundary deploy/plan deep flag --deep
    base_cli_positional boundary '' item repeatable=true

    bats_run base_cli_complete boundary -- file deploy --f
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    bats_run base_cli_complete boundary -- file deploy --r
    [ "$status" -eq 0 ]
    [ "$output" = --root-flag ]
    bats_run base_cli_complete boundary -- file d p --d
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    bats_run base_cli_complete boundary -- file -- deploy ""
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    base_cli_completion_script boundary _boundary_complete > "$completion_script"
    source "$completion_script"
    COMP_WORDS=(boundary file deploy --f)
    COMP_CWORD=3
    _boundary_complete
    [ "${#COMPREPLY[@]}" -eq 0 ]
    COMP_WORDS=(boundary file deploy --r)
    COMP_CWORD=3
    _boundary_complete
    [ "${COMPREPLY[*]}" = --root-flag ]
    COMP_WORDS=(boundary file d p --d)
    COMP_CWORD=4
    _boundary_complete
    [ "${#COMPREPLY[@]}" -eq 0 ]
    COMP_WORDS=(boundary file -- deploy "")
    COMP_CWORD=4
    _boundary_complete
    [ "${#COMPREPLY[@]}" -eq 0 ]
}

@test "completion keeps partial candidates unique and one per line" {
    base_cli_model_init unique_complete name=unique-complete
    base_cli_command unique_complete admin "Administration" aliases=adm
    base_cli_option unique_complete '' verbose flag --verbose -v

    bats_run base_cli_complete unique_complete -- ad
    [ "$status" -eq 0 ]
    [ "$output" = $'admin\nadm' ]
    [ "$(printf '%s\n' "$output" | LC_ALL=C sort | uniq -d)" = "" ]

    bats_run base_cli_complete unique_complete -- --v
    [ "$status" -eq 0 ]
    [ "$output" = --verbose ]
}

@test "public CLI paths preserve caller variables that match internal scratch names" {
    local __base_bash_libs_cli_option_name=caller-name
    local __base_bash_libs_cli_option_path=caller-path
    local __base_bash_libs_cli_option_type=caller-type
    local -a __base_bash_libs_cli_enum_values=(caller-enum)
    local -a __base_bash_libs_cli_local_option_names=(caller-options)
    local -a __base_bash_libs_cli_local_positionals=(caller-positionals)
    local -a __base_bash_libs_cli_children=(caller-children)
    local -a __base_bash_libs_cli_option_tokens=(caller-tokens)

    declare_demo_model
    base_cli_help demo > "$TEST_TMPDIR/root-help.out"
    base_cli_help demo admin/user > "$TEST_TMPDIR/child-help.out"
    base_cli_parse demo -- admin user target-name --color green
    base_cli_complete demo -- admin user -- > "$TEST_TMPDIR/completion.out"

    [ "$__base_bash_libs_cli_option_name" = caller-name ]
    [ "$__base_bash_libs_cli_option_path" = caller-path ]
    [ "$__base_bash_libs_cli_option_type" = caller-type ]
    [ "${__base_bash_libs_cli_enum_values[*]}" = caller-enum ]
    [ "${__base_bash_libs_cli_local_option_names[*]}" = caller-options ]
    [ "${__base_bash_libs_cli_local_positionals[*]}" = caller-positionals ]
    [ "${__base_bash_libs_cli_children[*]}" = caller-children ]
    [ "${__base_bash_libs_cli_option_tokens[*]}" = caller-tokens ]
}

@test "large option declarations populate indexed collision metadata" {
    local index option_name token
    base_cli_model_init indexed name=indexed
    base_cli_command indexed run Run

    for ((index = 1; index <= 200; index++)); do
        option_name="option_$index"
        token="--option-$index"
        base_cli_option indexed run "$option_name" value "$token" || return 1
    done

    [ "${__base_bash_libs_cli_option_name_index[indexed\|option_200]}" = run ]
    [ "${__base_bash_libs_cli_option_token_index[indexed\|--option-200]}" = run ]
}

@test "the declarative runtime contains no eval dependency" {
    ! grep -Ev '^[[:space:]]*#' "$BASE_BASH_DIR/cli/lib_cli.sh" | grep -Eq '(^|[[:space:];])eval([[:space:];]|$)'
}
