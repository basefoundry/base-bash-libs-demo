#!/usr/bin/env bats

load ../lib/bash/tests/test_helper.sh

setup() {
    setup_test_tmpdir
    PATH="$BASE_REPO_ROOT/bin:$BASE_TEST_ORIG_PATH"
    unset BASE_BASH_LIBS_DRY_RUN BASE_BASH_LIBS_DRY_RUN BASE_BASH_LIBS_LOG_DEBUG BASE_BASH_LIBS_LOG_UTC NO_COLOR BASE_BASH_LIBS_BOOTSTRAP_SOURCE
}

create_script() {
    local script_path="$1"
    shift

    cat > "$script_path"
    chmod +x "$script_path"
}

launcher_file_mode() {
    if stat -c '%a' "$1" >/dev/null 2>&1; then
        stat -c '%a' "$1"
    else
        stat -f '%Lp' "$1"
    fi
}

copy_launcher_package() {
    local package_root="$1"

    mkdir -p "$package_root/bin" "$package_root/lib/bash" "$package_root/scripts"
    cp "$BASE_REPO_ROOT/bin/base-bash" "$package_root/bin/base-bash"
    cp "$BASE_REPO_ROOT/VERSION" "$package_root/VERSION"
    cp "$BASE_REPO_ROOT/lib/bash/base-bash-libs.release" "$package_root/lib/bash/base-bash-libs.release"
    cp "$BASE_REPO_ROOT/scripts/standalone-app-payloads.txt" "$package_root/scripts/standalone-app-payloads.txt"
    chmod +x "$package_root/bin/base-bash"
}

commit_launcher_package() {
    local package_root="$1"

    git -C "$package_root" init -q
    git -C "$package_root" add .
    env GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
        GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
        git -C "$package_root" commit -qm fixture
}

@test "base-bash shebang preloads stdlib and calls main with filtered args" {
    local script_dir="$TEST_TMPDIR/scripts"
    local script="$script_dir/tool"

    mkdir -p "$script_dir"
    script_dir="$(cd "$script_dir" && pwd -P)"
    create_script "$script" <<'SCRIPT'
#!/usr/bin/env base-bash
# shellcheck shell=bash

base_launcher_import_base_bash_lib str/lib_str.sh

main() {
    local value="$1"
    base_str_trim value

    printf 'argc=%s\n' "$#"
    printf 'first=<%s>\n' "$1"
    printf 'second=<%s>\n' "${2-}"
    printf 'trimmed=<%s>\n' "$value"
    printf 'script-dir=%s\n' "$BASE_BASH_LIBS_SCRIPT_DIR"
    printf 'loaded=%s\n' "${BASE_BASH_LIBS_STDLIB_LOADED:-}"
    printf 'base-home=%s\n' "${BASE_HOME-unset}"
    printf 'str-trim=%s\n' "$(type -t base_str_trim)"
}
SCRIPT

    bats_run "$script" --verbose-wrapper --color "  alpha  " beta

    [ "$status" -eq 0 ]
    [[ "$output" == *"argc=2"* ]]
    [[ "$output" == *"first=<  alpha  >"* ]]
    [[ "$output" == *"second=<beta>"* ]]
    [[ "$output" == *"trimmed=<alpha>"* ]]
    [[ "$output" == *"script-dir=$script_dir"* ]]
    [[ "$output" == *"loaded=1"* ]]
    [[ "$output" == *"base-home=unset"* ]]
    [[ "$output" == *"str-trim=function"* ]]
}

@test "base-bash preserves wrapper-like arguments after --" {
    local script="$TEST_TMPDIR/escape-tool"

    create_script "$script" <<'SCRIPT'
#!/usr/bin/env base-bash
# shellcheck shell=bash

main() {
    printf 'args=%s\n' "$*"
}
SCRIPT

    bats_run "$script" --color alpha -- --color omega

    [ "$status" -eq 0 ]
    [[ "$output" == *"args=alpha -- --color omega"* ]]
}

@test "base-bash reports a missing main function" {
    local script="$TEST_TMPDIR/no-main"

    create_script "$script" <<'SCRIPT'
#!/usr/bin/env base-bash
# shellcheck shell=bash

printf 'body sourced\n'
SCRIPT

    bats_run "$script"

    [ "$status" -ne 0 ]
    [[ "$output" == *"body sourced"* ]]
    [[ "$output" == *"did not define main()"* ]]
}

@test "base-bash init generates and safely repeats a standard project scaffold" {
    local project_dir="$TEST_TMPDIR/generated"

    mkdir -p "$project_dir"
    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" init --profile standard --dir "$project_dir"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Initialized standard profile"* ]]
    [ -x "$project_dir/bin/app" ]
    [ -f "$project_dir/lib/app.sh" ]
    [ -f "$project_dir/tests/run.sh" ]
    [ -f "$project_dir/.github/workflows/validate.yml" ]
    grep -Eq 'actions/checkout@[0-9a-f]{40}[[:space:]]+# v4\.2\.2$' \
        "$project_dir/.github/workflows/validate.yml"
    grep -Eq 'bats-core/bats-action@[0-9a-f]{40}[[:space:]]+# v4\.0\.0$' \
        "$project_dir/.github/workflows/validate.yml"
    run grep -Eq 'uses: .+@(v[0-9]|main|master)([[:space:]]|$)' \
        "$project_dir/.github/workflows/validate.yml"
    [ "$status" -eq 1 ]

    bats_run env PATH="$BASE_REPO_ROOT/bin:$PATH" BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$project_dir/bin/app" run
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello=world"* ]]

    bats_run env PATH="$BASE_REPO_ROOT/bin:$PATH" BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$project_dir/bin/app" --version
    [ "$status" -eq 0 ]
    [ "$output" = "demo 0.1.0" ]

    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" init --profile standard --dir "$project_dir"
    [ "$status" -eq 0 ]

    printf 'user edit\n' >> "$project_dir/README.md"
    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" init --profile standard --dir "$project_dir"
    [ "$status" -eq 2 ]
    [[ "$output" == *"refusing to overwrite existing file"* ]]
}

@test "v2 quickstart uses one explicit launcher from an unrelated cwd" {
    local project_root="$TEST_TMPDIR/quickstart/demo"
    local framework_root="$BASE_REPO_ROOT"
    local framework_launcher="$framework_root/bin/base-bash"
    local bundle="$TEST_TMPDIR/quickstart/bundle"

    mkdir -p "$project_root"
    env -i HOME="$TEST_TMPDIR/home" PATH="$framework_root/bin:$BASE_TEST_ORIG_PATH" \
        BASE_BASH_LIBS_DIR="$framework_root/lib/bash" \
        "$framework_launcher" init --profile standard --dir "$project_root"

    run env PATH="$framework_root/bin:$BASE_TEST_ORIG_PATH" \
        BASE_BASH_LIBS_DIR="$framework_root/lib/bash" \
        "$framework_launcher" "$project_root/bin/app" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]

    run env PATH="$framework_root/bin:$BASE_TEST_ORIG_PATH" \
        BASE_BASH_LIBS_DIR="$framework_root/lib/bash" \
        "$framework_launcher" check --project "$project_root"
    [ "$status" -eq 0 ]

    run env PATH="$framework_root/bin:$BASE_TEST_ORIG_PATH" \
        BASE_BASH_LIBS_DIR="$framework_root/lib/bash" \
        bash -c 'cd "$1" && ./tests/run.sh' _ "$project_root"
    [ "$status" -eq 0 ]

    run env PATH="$framework_root/bin:$BASE_TEST_ORIG_PATH" \
        BASE_BASH_LIBS_DIR="$framework_root/lib/bash" \
        "$framework_root/scripts/library-bundle" bundle "$bundle"
    [ "$status" -eq 0 ]
    run env PATH="$framework_root/bin:$BASE_TEST_ORIG_PATH" \
        BASE_BASH_LIBS_DIR="$framework_root/lib/bash" \
        "$framework_root/scripts/library-bundle" verify "$bundle"
    [ "$status" -eq 0 ]
}

@test "base-bash init reconciles minimal scaffold modes under restrictive umask" {
    local project_dir="$TEST_TMPDIR/generated"
    local previous_umask

    mkdir -p "$project_dir"
    previous_umask="$(umask)"
    umask 077
    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" init --profile minimal --dir "$project_dir"
    umask "$previous_umask"
    [ "$status" -eq 0 ]
    [ "$(launcher_file_mode "$project_dir/bin/app")" = 755 ]
    [ "$(launcher_file_mode "$project_dir/tests/app.bats")" = 755 ]
    [ "$(launcher_file_mode "$project_dir/README.md")" = 644 ]

    chmod 0644 "$project_dir/bin/app" "$project_dir/tests/app.bats"
    chmod 0755 "$project_dir/README.md"
    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" init --profile minimal --dir "$project_dir"

    [ "$status" -eq 0 ]
    [ "$(launcher_file_mode "$project_dir/bin/app")" = 755 ]
    [ "$(launcher_file_mode "$project_dir/tests/app.bats")" = 755 ]
    [ "$(launcher_file_mode "$project_dir/README.md")" = 644 ]

    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" check --project "$project_dir"
    [ "$status" -eq 0 ]
}

@test "base-bash init reconciles standard profile executable modes" {
    local project_dir="$TEST_TMPDIR/generated" path
    local -a executable_paths=(bin/app tests/app.bats tests/run.sh tools/shfmt-check.sh)

    mkdir -p "$project_dir"
    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" init --profile standard --dir "$project_dir"
    [ "$status" -eq 0 ]
    chmod 0644 "${executable_paths[@]/#/$project_dir/}"
    chmod 0755 "$project_dir/Makefile"

    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" init --profile standard --dir "$project_dir"

    [ "$status" -eq 0 ]
    for path in "${executable_paths[@]}"; do
        [ "$(launcher_file_mode "$project_dir/$path")" = 755 ]
    done
    [ "$(launcher_file_mode "$project_dir/Makefile")" = 644 ]
}

@test "base-bash init keeps failed new-file chmod atomic and recoverable" {
    local project_dir="$TEST_TMPDIR/generated"
    local stub_dir="$TEST_TMPDIR/stub-bin"
    local real_chmod

    mkdir -p "$project_dir" "$stub_dir"
    real_chmod="$(command -v chmod)"
    cat >"$stub_dir/chmod" <<'EOF'
#!/usr/bin/env bash
if [[ "${2-}" == */bin/app.base-bash-init.* ]]; then
    exit 9
fi
exec "${REAL_CHMOD:?}" "$@"
EOF
    chmod +x "$stub_dir/chmod"

    bats_run env REAL_CHMOD="$real_chmod" PATH="$stub_dir:$PATH" BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" \
        "$BASE_REPO_ROOT/bin/base-bash" init --profile minimal --dir "$project_dir"

    [ "$status" -eq 1 ]
    [ ! -e "$project_dir/bin/app" ]
    [ -z "$(find "$project_dir/bin" -name 'app.base-bash-init.*' -print -quit)" ]

    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" init --profile minimal --dir "$project_dir"
    [ "$status" -eq 0 ]
    [ "$(launcher_file_mode "$project_dir/bin/app")" = 755 ]
}

@test "base-bash init still refuses matching symlink targets" {
    local project_dir="$TEST_TMPDIR/generated"
    local target="$TEST_TMPDIR/README.target"

    mkdir -p "$project_dir"
    "$BASE_REPO_ROOT/bin/base-bash" init --profile minimal --dir "$project_dir"
    mv "$project_dir/README.md" "$target"
    ln -s "$target" "$project_dir/README.md"

    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" init --profile minimal --dir "$project_dir"

    [ "$status" -eq 2 ]
    [ -L "$project_dir/README.md" ]
    [[ "$output" == *"refusing to overwrite existing file"* ]]
}

@test "base-bash check validates a consumer project without mutation" {
    local project_dir="$TEST_TMPDIR/generated"
    local before after expected_version

    expected_version="$(<"$BASE_REPO_ROOT/VERSION")"

    mkdir -p "$project_dir"
    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" init --profile minimal --dir "$project_dir"
    [ "$status" -eq 0 ]
    before="$(find "$project_dir" -type f -exec shasum {} + | sort)"

    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" check --project "$project_dir"
    [ "$status" -eq 0 ]
    [[ "$output" == *"project/framework-pin: $expected_version@"* ]]
    [[ "$output" == *"OK project/application-version: CLI is bound to VERSION 0.1.0"* ]]
    [[ "$output" == *"OK project/namespace:"* ]]

    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" check --project "$project_dir" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"check":"framework-pin"'* ]]
    [[ "$output" == *'"status":"OK"'* ]]

    after="$(find "$project_dir" -type f -exec shasum {} + | sort)"
    [ "$before" = "$after" ]
}

@test "base-bash check emits parseable JSON for control characters in paths" {
    local project_dir="$TEST_TMPDIR/generated"
    local control_file="$project_dir/lib/line"$'\n'"break.sh"
    local missing_project="$TEST_TMPDIR/missing"$'\n'"project"

    mkdir -p "$project_dir"
    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" init --profile minimal --dir "$project_dir"
    [ "$status" -eq 0 ]
    printf '%s\n' ':' >"$control_file"

    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" check --project "$project_dir" --format json
    [ "$status" -eq 0 ]
    jq -e . >/dev/null <<<"$output"
    [[ "$output" == *$'syntax:lib/line\\nbreak.sh'* ]]

    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" check --project "$missing_project" --format json
    [ "$status" -eq 1 ]
    jq -e . >/dev/null <<<"$output"
    [[ "$output" == *$'missing\\nproject'* ]]
}

@test "base-bash init pins clean and detached source checkouts to exact HEAD" {
    local package_root="$TEST_TMPDIR/package"
    local project_root="$TEST_TMPDIR/project"
    local detached_project_root="$TEST_TMPDIR/detached-project"
    local expected_commit

    copy_launcher_package "$package_root"
    commit_launcher_package "$package_root"
    expected_commit="$(git -C "$package_root" rev-parse HEAD)"
    mkdir -p "$project_root" "$detached_project_root"

    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$package_root/bin/base-bash" init --dir "$project_root"
    [ "$status" -eq 0 ]
    grep -Fx "source_commit=$expected_commit" "$project_root/BASE_BASH_LIBS_PIN"
    grep -Fx 'dirty_state=clean' "$project_root/BASE_BASH_LIBS_PIN"
    grep -Fx 'verification=pin-and-verify-before-update' "$project_root/BASE_BASH_LIBS_PIN"

    git -C "$package_root" checkout --detach -q
    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$package_root/bin/base-bash" init --dir "$detached_project_root"
    [ "$status" -eq 0 ]
    grep -Fx "source_commit=$expected_commit" "$detached_project_root/BASE_BASH_LIBS_PIN"
    grep -Fx 'dirty_state=clean' "$detached_project_root/BASE_BASH_LIBS_PIN"
    grep -Fx 'verification=pin-and-verify-before-update' "$detached_project_root/BASE_BASH_LIBS_PIN"
}

@test "base-bash init marks dirty source checkout provenance as development-unverified" {
    local package_root="$TEST_TMPDIR/package"
    local project_root="$TEST_TMPDIR/project"
    local expected_commit

    copy_launcher_package "$package_root"
    commit_launcher_package "$package_root"
    expected_commit="$(git -C "$package_root" rev-parse HEAD)"
    printf 'dirty\n' > "$package_root/untracked"
    mkdir -p "$project_root"

    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$package_root/bin/base-bash" init --dir "$project_root"

    [ "$status" -eq 0 ]
    grep -Fx "source_commit=$expected_commit" "$project_root/BASE_BASH_LIBS_PIN"
    grep -Fx 'dirty_state=dirty' "$project_root/BASE_BASH_LIBS_PIN"
    grep -Fx 'verification=development-unverified' "$project_root/BASE_BASH_LIBS_PIN"
    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$package_root/bin/base-bash" check --project "$project_root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN project/framework-pin:"*"development-unverified"* ]]
}

@test "base-bash init retains verified release artifact provenance" {
    local package_root="$TEST_TMPDIR/package"
    local project_root="$TEST_TMPDIR/project"
    local expected_commit=1111111111111111111111111111111111111111

    copy_launcher_package "$package_root"
    printf 'schema_version=1\nversion=2.0.0\ncommit=%s\ndirty_state=clean\nprovenance=release-artifact\n' \
        "$expected_commit" > "$package_root/lib/bash/base-bash-libs.release"
    mkdir -p "$project_root"

    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$package_root/bin/base-bash" init --dir "$project_root"

    [ "$status" -eq 0 ]
    grep -Fx "source_commit=$expected_commit" "$project_root/BASE_BASH_LIBS_PIN"
    grep -Fx 'dirty_state=clean' "$project_root/BASE_BASH_LIBS_PIN"
    grep -Fx 'verification=pin-and-verify-before-update' "$project_root/BASE_BASH_LIBS_PIN"
}

@test "base-bash init makes missing identity explicit and project check rejects a false immutable claim" {
    local package_root="$TEST_TMPDIR/package"
    local project_root="$TEST_TMPDIR/project"

    copy_launcher_package "$package_root"
    mkdir -p "$project_root"

    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$package_root/bin/base-bash" init --dir "$project_root"

    [ "$status" -eq 0 ]
    grep -Fx 'source_commit=unknown' "$project_root/BASE_BASH_LIBS_PIN"
    grep -Fx 'dirty_state=unknown' "$project_root/BASE_BASH_LIBS_PIN"
    grep -Fx 'verification=development-unverified' "$project_root/BASE_BASH_LIBS_PIN"

    sed 's/verification=development-unverified/verification=pin-and-verify-before-update/' \
        "$project_root/BASE_BASH_LIBS_PIN" > "$project_root/BASE_BASH_LIBS_PIN.new"
    mv "$project_root/BASE_BASH_LIBS_PIN.new" "$project_root/BASE_BASH_LIBS_PIN"
    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$package_root/bin/base-bash" check --project "$project_root"

    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR project/framework-pin: inconsistent verification, commit, or dirty-state metadata"* ]]
}

@test "consumer check accepts canonical application and v2 pin prereleases" {
    local project_dir="$TEST_TMPDIR/generated"

    mkdir -p "$project_dir"
    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" init --profile minimal --dir "$project_dir"
    [ "$status" -eq 0 ]
    printf '10.20.30-rc.7\n' >"$project_dir/VERSION"
    sed 's/^version=.*/version=2.1.0-beta.3/' "$project_dir/BASE_BASH_LIBS_PIN" >"$project_dir/BASE_BASH_LIBS_PIN.new"
    mv "$project_dir/BASE_BASH_LIBS_PIN.new" "$project_dir/BASE_BASH_LIBS_PIN"

    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" check --project "$project_dir"

    [ "$status" -eq 0 ]
    [[ "$output" == *"OK project/version: 10.20.30-rc.7"* ]]
    [[ "$output" == *"project/framework-pin: 2.1.0-beta.3@"* ]]
}

@test "consumer check rejects noncanonical application versions and framework pins" {
    local project_dir="$TEST_TMPDIR/generated"

    mkdir -p "$project_dir"
    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" init --profile minimal --dir "$project_dir"
    [ "$status" -eq 0 ]
    printf '01.0.0\n' >"$project_dir/VERSION"
    sed 's/^version=.*/version=2.not-a-version/' "$project_dir/BASE_BASH_LIBS_PIN" >"$project_dir/BASE_BASH_LIBS_PIN.new"
    mv "$project_dir/BASE_BASH_LIBS_PIN.new" "$project_dir/BASE_BASH_LIBS_PIN"

    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" check --project "$project_dir"

    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR project/version: invalid VERSION '01.0.0'"* ]]
    [[ "$output" == *"ERROR project/framework-pin: requires a canonical v2 version, found '2.not-a-version'"* ]]
}

@test "generated application version follows VERSION and project check detects static divergence" {
    local project_dir="$TEST_TMPDIR/generated-version"

    mkdir -p "$project_dir"
    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" init --profile minimal --dir "$project_dir"
    [ "$status" -eq 0 ]
    printf '1.2.3-rc.1\n' > "$project_dir/VERSION"

    bats_run env PATH="$BASE_REPO_ROOT/bin:$PATH" BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$project_dir/bin/app" --version
    [ "$status" -eq 0 ]
    [ "$output" = "demo 1.2.3-rc.1" ]

    sed 's/version="\$__base_bash_generated_app_version"/version=2.0.0/' \
        "$project_dir/lib/app.sh" > "$project_dir/lib/app.sh.new"
    mv "$project_dir/lib/app.sh.new" "$project_dir/lib/app.sh"
    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" check --project "$project_dir" --format json

    [ "$status" -eq 1 ]
    [[ "$output" == *'"status":"ERROR","check":"application-version"'* ]]
    [[ "$output" == *"lib/app.sh is not bound to project VERSION"* ]]
}

@test "consumer check rejects legacy v1 symbols without executing them" {
    local project_dir="$TEST_TMPDIR/legacy"

    mkdir -p "$project_dir/bin" "$project_dir/lib" "$project_dir/tests"
    printf '%s\n' '# legacy fixture' >"$project_dir/README.md"
    printf '0.1.0\n' >"$project_dir/VERSION"
    printf 'version=2.0.0\n' >"$project_dir/BASE_BASH_LIBS_PIN"
    printf '%s\n' '#!/usr/bin/env bash' 'std_run dangerous-command' >"$project_dir/bin/app"
    printf '%s\n' '#!/usr/bin/env bash' 'main() { :; }' >"$project_dir/lib/app.sh"
    printf '%s\n' '@test "placeholder" { :; }' >"$project_dir/tests/app.bats"
    chmod +x "$project_dir/bin/app"

    bats_run env BASE_BASH_LIBS_DIR="$BASE_BASH_DIR" "$BASE_REPO_ROOT/bin/base-bash" check --project "$project_dir" --format json
    [ "$status" -eq 1 ]
    [[ "$output" == *'"check":"namespace"'* ]]
    [[ "$output" == *"v1 API symbol detected"* ]]
}

@test "base-bash bounds symlink resolution" {
    local first_link="$TEST_TMPDIR/cycle-a"
    local second_link="$TEST_TMPDIR/cycle-b"

    ln -s "$(basename "$second_link")" "$first_link"
    ln -s "$(basename "$first_link")" "$second_link"

    bats_run base-bash "$first_link"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Symlink resolution exceeded 40 links"* ]]
}

@test "base-bash resolves Homebrew-style libexec layout" {
    local prefix="$TEST_TMPDIR/homebrew-prefix"
    local script="$TEST_TMPDIR/brew-tool"

    mkdir -p "$prefix/bin" "$prefix/libexec"
    prefix="$(cd "$prefix" && pwd -P)"
    cp "$BASE_REPO_ROOT/bin/base-bash" "$prefix/bin/base-bash"
    chmod +x "$prefix/bin/base-bash"
    cp "$BASE_REPO_ROOT/VERSION" "$prefix/libexec/VERSION"
    cp -R "$BASE_REPO_ROOT/lib" "$prefix/libexec/lib"

    PATH="$prefix/bin:$BASE_TEST_ORIG_PATH"

    create_script "$script" <<'SCRIPT'
#!/usr/bin/env base-bash
# shellcheck shell=bash

main() {
    printf 'version=%s\n' "$BASE_BASH_LIBS_VERSION"
    printf 'lib-dir=%s\n' "$BASE_BASH_LIBS_DIR"
}
SCRIPT

    bats_run "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"version=$(<"$BASE_REPO_ROOT/VERSION")"* ]]
    [[ "$output" == *"lib-dir=$prefix/libexec/lib/bash"* ]]
}

@test "base-bash help is successful stdout data" {
    local stdout_file="$TEST_TMPDIR/help.stdout"
    local stderr_file="$TEST_TMPDIR/help.stderr"

    set +e
    "$BASE_REPO_ROOT/bin/base-bash" --help >"$stdout_file" 2>"$stderr_file"
    status=$?
    set -e

    [ "$status" -eq 0 ]
    [[ "$(<"$stdout_file")" == *"Usage:"* ]]
    [[ "$(<"$stdout_file")" == *"base-bash check"* ]]
    [ ! -s "$stderr_file" ]
}

@test "base-bash version reports package provenance on stdout" {
    local stdout_file="$TEST_TMPDIR/version.stdout"
    local stderr_file="$TEST_TMPDIR/version.stderr"

    set +e
    "$BASE_REPO_ROOT/bin/base-bash" --version >"$stdout_file" 2>"$stderr_file"
    status=$?
    set -e

    [ "$status" -eq 0 ]
    [[ "$(<"$stdout_file")" == *"base-bash $(<"$BASE_REPO_ROOT/VERSION")"* ]]
    [[ "$(<"$stdout_file")" == *$'commit: '* ]]
    [[ "$(<"$stdout_file")" == *$'dirty-state: '* ]]
    [[ "$(<"$stdout_file")" == *$'provenance: '* ]]
    [ ! -s "$stderr_file" ]
}

@test "base-bash usage errors use stderr and status 2" {
    local missing_script="$TEST_TMPDIR/does-not-exist"

    bats_run "$BASE_REPO_ROOT/bin/base-bash" --unknown-launcher-option
    [ "$status" -eq 2 ]
    [[ "$output" == *"ERROR: Unknown launcher option"* ]]
    [[ "$output" == *"Usage:"* ]]

    bats_run "$BASE_REPO_ROOT/bin/base-bash" -x
    [ "$status" -eq 2 ]
    [[ "$output" == *"ERROR: Unknown launcher option '-x'"* ]]

    bats_run "$BASE_REPO_ROOT/bin/base-bash" "$missing_script"
    [ "$status" -eq 2 ]
    [[ "$output" == *"ERROR: Script "*" was not found."* ]]
}

@test "base-bash check diagnoses a healthy checkout without mutation" {
    bats_run "$BASE_REPO_ROOT/bin/base-bash" check

    [ "$status" -eq 0 ]
    [[ "$output" == *"OK bash:"* ]]
    [[ "$output" == *"OK installation:"* ]]
    [[ "$output" == *"OK package: base-bash-libs"* ]]
    [[ "$output" == *"OK imports: std plus"* ]]
}

@test "base-bash check reports an unusable explicit package directory" {
    local invalid_dir="$TEST_TMPDIR/not-a-package"

    mkdir -p "$invalid_dir"
    bats_run env BASE_BASH_LIBS_DIR="$invalid_dir" "$BASE_REPO_ROOT/bin/base-bash" check

    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR package: BASE_BASH_LIBS_DIR $invalid_dir does not contain std/lib_std.sh."* ]]
}

@test "base-bash forwards a literal double-dash script path and exact arguments" {
    local script="$TEST_TMPDIR/-literal-script"

    create_script "$script" <<'SCRIPT'
#!/usr/bin/env base-bash
# shellcheck shell=bash

main() {
    printf 'argc=%s\n' "$#"
    printf 'arg1=<%s>\n' "$1"
    printf 'arg2=<%s>\n' "$2"
}
SCRIPT

    bats_run "$BASE_REPO_ROOT/bin/base-bash" -- "$script" --first "value with spaces"

    [ "$status" -eq 0 ]
    [[ "$output" == *"argc=2"* ]]
    [[ "$output" == *"arg1=<--first>"* ]]
    [[ "$output" == *"arg2=<value with spaces>"* ]]
}

@test "base-bash supports scripts in paths containing spaces" {
    local script_dir="$TEST_TMPDIR/path with spaces"
    local script="$script_dir/script with spaces"

    mkdir -p "$script_dir"
    create_script "$script" <<'SCRIPT'
#!/usr/bin/env base-bash
# shellcheck shell=bash

main() {
    printf 'script-dir=%s\n' "$BASE_BASH_LIBS_SCRIPT_DIR"
}
SCRIPT

    bats_run "$BASE_REPO_ROOT/bin/base-bash" "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"script-dir=$(cd "$script_dir" && pwd -P)"* ]]
}

@test "base-bash follows a symlinked launcher to the real package" {
    local launcher="$TEST_TMPDIR/linked-base-bash"
    local script="$TEST_TMPDIR/symlink-script"

    ln -s "$BASE_REPO_ROOT/bin/base-bash" "$launcher"
    create_script "$script" <<'SCRIPT'
#!/usr/bin/env bash
# shellcheck shell=bash

main() {
    printf 'symlink-version=%s\n' "$BASE_BASH_LIBS_VERSION"
}
SCRIPT

    bats_run "$launcher" "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"symlink-version=$(<"$BASE_REPO_ROOT/VERSION")"* ]]
}

@test "base-bash runs from a copied vendored layout" {
    local vendor="$TEST_TMPDIR/vendor/base-bash-libs"
    local script="$TEST_TMPDIR/vendor-script"

    mkdir -p "$vendor/bin"
    vendor="$(cd "$vendor" && pwd -P)"
    cp "$BASE_REPO_ROOT/bin/base-bash" "$vendor/bin/base-bash"
    chmod +x "$vendor/bin/base-bash"
    cp "$BASE_REPO_ROOT/VERSION" "$vendor/VERSION"
    cp -R "$BASE_REPO_ROOT/lib" "$vendor/lib"
    create_script "$script" <<'SCRIPT'
#!/usr/bin/env bash
# shellcheck shell=bash

main() {
    printf 'vendor-version=%s\n' "$BASE_BASH_LIBS_VERSION"
    printf 'vendor-lib=%s\n' "$BASE_BASH_LIBS_DIR"
}
SCRIPT

    bats_run "$vendor/bin/base-bash" "$script"

    [ "$status" -eq 0 ]
    [[ "$output" == *"vendor-version=$(<"$BASE_REPO_ROOT/VERSION")"* ]]
    [[ "$output" == *"vendor-lib=$vendor/lib/bash"* ]]
}

@test "base-bash invokes main once and preserves its normal status" {
    local script="$TEST_TMPDIR/status-script"

    create_script "$script" <<'SCRIPT'
#!/usr/bin/env base-bash
# shellcheck shell=bash

printf 'sourced\n'

main() {
    if [[ "$-" == *e* || "$-" == *u* ]] ||
        ! set -o | grep -q '^pipefail[[:space:]]*off'; then
        printf 'strict-mode-was-enabled\n'
        return 1
    fi
    printf 'main\n'
    return 37
}
SCRIPT

    bats_run "$BASE_REPO_ROOT/bin/base-bash" "$script"

    [ "$status" -eq 37 ]
    [ "$(grep -c '^main$' <<<"$output")" -eq 1 ]
    [[ "$output" == *"sourced"* ]]
}

@test "base-bash preserves fatal failure status" {
    local script="$TEST_TMPDIR/fatal-script"

    create_script "$script" <<'SCRIPT'
#!/usr/bin/env base-bash
# shellcheck shell=bash

main() {
    false
    base_std_fatal_error "intentional launcher contract failure"
}
SCRIPT

    bats_run "$BASE_REPO_ROOT/bin/base-bash" "$script"

    [ "$status" -eq 1 ]
    [[ "$output" == *"intentional launcher contract failure"* ]]
}

@test "base-bash cleanup hooks run on normal application exit" {
    local script="$TEST_TMPDIR/cleanup-script"
    local marker="$TEST_TMPDIR/cleanup.marker"

    create_script "$script" <<'SCRIPT'
#!/usr/bin/env base-bash
# shellcheck shell=bash

cleanup_marker=""
cleanup_hook() {
    printf 'cleaned\n' >"$cleanup_marker"
}

main() {
    cleanup_marker="$1"
    base_std_register_cleanup_hook cleanup_hook
    return 23
}
SCRIPT

    bats_run "$BASE_REPO_ROOT/bin/base-bash" "$script" "$marker"

    [ "$status" -eq 23 ]
    [ "$(<"$marker")" = "cleaned" ]
}

@test "base-bash runs cleanup and returns 143 on TERM" {
    local script="$TEST_TMPDIR/term-script"
    local marker="$TEST_TMPDIR/term.marker"
    local pid rc deadline

    create_script "$script" <<'SCRIPT'
#!/usr/bin/env base-bash
# shellcheck shell=bash

cleanup_marker=""
cleanup_hook() {
    printf 'cleaned\n' >"$cleanup_marker"
}

main() {
    cleanup_marker="$1"
    base_std_register_cleanup_hook cleanup_hook
    while :; do
        sleep 0.1
    done
}
SCRIPT

    "$BASE_REPO_ROOT/bin/base-bash" "$script" "$marker" >"$TEST_TMPDIR/term.out" 2>&1 &
    pid=$!
    sleep 0.2
    kill -TERM "$pid"
    deadline=$((SECONDS + 5))
    while kill -0 "$pid" 2>/dev/null && ((SECONDS < deadline)); do
        sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null || true
    fi
    set +e
    wait "$pid"
    rc=$?
    set -e

    [ "$rc" -eq 143 ]
    [ "$(<"$marker")" = "cleaned" ]
}

@test "base-bash runs cleanup and returns 130 on INT" {
    local script="$TEST_TMPDIR/int-script"
    local marker="$TEST_TMPDIR/int.marker"
    local pid rc deadline

    create_script "$script" <<'SCRIPT'
#!/usr/bin/env base-bash
# shellcheck shell=bash

cleanup_marker=""
cleanup_hook() {
    printf 'cleaned\n' >"$cleanup_marker"
}

main() {
    cleanup_marker="$1"
    base_std_register_cleanup_hook cleanup_hook
    while :; do
        sleep 0.1
    done
}
SCRIPT

    perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV' -- \
        "$BASE_REPO_ROOT/bin/base-bash" "$script" "$marker" >"$TEST_TMPDIR/int.out" 2>&1 &
    pid=$!
    sleep 0.2
    kill -INT "$pid"
    deadline=$((SECONDS + 5))
    while kill -0 "$pid" 2>/dev/null && ((SECONDS < deadline)); do
        sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null || true
    fi
    set +e
    wait "$pid"
    rc=$?
    set -e

    [ "$rc" -eq 130 ]
    [ "$(<"$marker")" = "cleaned" ]
}

@test "base-bash re-execs a supported Bash when started under Bash 3.2" {
    local script="$TEST_TMPDIR/reexec-script"
    local candidate="$TEST_TMPDIR/supported-bash"
    local marker="$TEST_TMPDIR/reexec.marker"

    create_script "$candidate" <<'SCRIPT'
#!/usr/bin/env bash
printf 'reexec\n' >"$BASE_BASH_LIBS_TEST_REEXEC_MARKER"
unset BASE_BASH_LIBS_TEST_BASH_VERSION BASE_BASH_LIBS_TEST_BASH_CANDIDATES
exec /bin/bash "$@"
SCRIPT

    create_script "$script" <<'SCRIPT'
#!/usr/bin/env base-bash
# shellcheck shell=bash

main() {
    printf 'reexec-app=%s\n' "$1"
}
SCRIPT

    bats_run env \
        BASE_BASH_LIBS_TEST_BASH_VERSION=32 \
        BASE_BASH_LIBS_TEST_BASH_CANDIDATES="$candidate" \
        BASE_BASH_LIBS_TEST_REEXEC_MARKER="$marker" \
        "$BASE_REPO_ROOT/bin/base-bash" "$script" forwarded

    [ "$status" -eq 0 ]
    [ "$(<"$marker")" = "reexec" ]
    [[ "$output" == *"reexec-app=forwarded"* ]]
}
