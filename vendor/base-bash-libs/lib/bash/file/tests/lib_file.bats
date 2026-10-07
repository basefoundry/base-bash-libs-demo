#!/usr/bin/env bats

load ../../tests/test_helper.sh

setup() {
    setup_test_tmpdir
    source "$BASE_BASH_DIR/std/lib_std.sh"
    declare -a setup_args=()
    base_init setup_args --source "$BASE_BASH_DIR/file/tests/lib_file.bats" --
    source "$BASE_BASH_DIR/file/lib_file.sh"
}

file_inode() {
    if stat -c '%i' "$1" >/dev/null 2>&1; then
        stat -c '%i' "$1"
    else
        stat -f '%i' "$1"
    fi
}

file_mode() {
    if stat -c '%a' "$1" >/dev/null 2>&1; then
        stat -c '%a' "$1"
    else
        stat -f '%Lp' "$1"
    fi
}

@test "base_file_update_file_section appends a new marked block when markers are absent" {
    local target="$TEST_TMPDIR/config.txt"
    printf 'line-one' > "$target"

    base_file_update_file_section "$target" "# BEGIN" "# END" "first" "second"

    [ "$(cat "$target")" = $'line-one\n# BEGIN\nfirst\nsecond\n# END' ]
}

@test "base_file_update_file_section logs adding when markers are absent" {
    local script="$TEST_TMPDIR/add-log.sh"
    local target="$TEST_TMPDIR/config.txt"
    cat > "$script" <<EOF
#!/usr/bin/env bash
source "$BASE_BASH_DIR/std/lib_std.sh"
declare -a app_args=()
base_init app_args --source "\${BASH_SOURCE[0]}" -- "\$@"
source "$BASE_BASH_DIR/file/lib_file.sh"
printf 'line-one' > "\$1"
base_file_update_file_section "\$1" "# BEGIN" "# END" "first"
EOF
    chmod +x "$script"

    bats_run bash "$script" "$target"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Adding section to '$target'"* ]]
    [[ "$output" != *"Updating '$target'"* ]]
    [ "$(cat "$target")" = $'line-one\n# BEGIN\nfirst\n# END' ]
}

@test "base_file_update_file_section appends to an empty file without a leading blank line" {
    local target="$TEST_TMPDIR/config.txt"
    touch "$target"

    base_file_update_file_section "$target" "# BEGIN" "# END" "first"

    [ "$(cat "$target")" = $'# BEGIN\nfirst\n# END' ]
}

@test "base_file_update_file_section preserves normal file mode when appending" {
    local target="$TEST_TMPDIR/config.txt"
    printf 'line-one' > "$target"
    chmod 0644 "$target"

    base_file_update_file_section "$target" "# BEGIN" "# END" "first"

    [ "$(file_mode "$target")" = "644" ]
    [ "$(cat "$target")" = $'line-one\n# BEGIN\nfirst\n# END' ]
}

@test "lib_file can be sourced more than once" {
    source "$BASE_BASH_DIR/file/lib_file.sh"

    [ "$(type -t base_file_update_file_section)" = "function" ]
}

@test "lib_file fails clearly when sourced without stdlib" {
    bats_run bash -c 'source "$1"; rc=$?; printf "source-rc=%s\n" "$rc"; exit "$rc"' bash "$BASE_BASH_DIR/file/lib_file.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"lib_file.sh requires lib_std.sh to be sourced first"* ]]
    [[ "$output" == *"source-rc=1"* ]]
    [[ "$output" != *"command not found"* ]]
}

@test "lib_file requires the stdlib loaded marker" {
    bats_run bash -c 'base_std_log_error() { :; }; base_std_log_debug() { :; }; source "$1"; rc=$?; printf "source-rc=%s\n" "$rc"; exit "$rc"' bash "$BASE_BASH_DIR/file/lib_file.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"lib_file.sh requires lib_std.sh to be sourced first"* ]]
    [[ "$output" == *"source-rc=1"* ]]
}

@test "base_file_update_file_section reports zero-argument usage under strict options" {
    local script="$TEST_TMPDIR/update-file-section-usage-strict.sh"

    cat > "$script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$BASE_BASH_DIR/std/lib_std.sh"
declare -a app_args=()
base_init app_args --source "\${BASH_SOURCE[0]}" -- "\$@"
source "$BASE_BASH_DIR/file/lib_file.sh"
if base_file_update_file_section; then status=0; else status=\$?; fi
printf 'after\n'
exit "\$status"
EOF
    chmod +x "$script"

    bats_run bash "$script"

    [ "$status" -eq 2 ]
    [[ "$output" == *"Insufficient arguments."* ]]
    [[ "$output" == *"Usage: base_file_update_file_section"* ]]
    [[ "$output" != *"unbound variable"* ]]
    [[ "$output" == *"after"* ]]
}

@test "base_file_update_file_section accepts empty content under strict options" {
    local script="$TEST_TMPDIR/update-file-section-empty-strict.sh"
    local target="$TEST_TMPDIR/strict-config.txt"

    printf 'before\n' > "$target"
    cat > "$script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$BASE_BASH_DIR/std/lib_std.sh"
declare -a app_args=()
base_init app_args --source "\${BASH_SOURCE[0]}" -- "\$@"
source "$BASE_BASH_DIR/file/lib_file.sh"
base_file_update_file_section "\$1" "# BEGIN" "# END"
printf 'strict=preserved\n'
EOF
    chmod +x "$script"

    bats_run bash "$script" "$target"

    [ "$status" -eq 0 ]
    [[ "$output" == *"strict=preserved"* ]]
    [[ "$output" != *"unbound variable"* ]]
    [ "$(cat "$target")" = $'before\n# BEGIN\n# END' ]
}

@test "base_file_update_file_section writes option-like markers literally" {
    local target="$TEST_TMPDIR/config.txt"
    printf 'line-one' > "$target"

    base_file_update_file_section "$target" "-n" "-e" "value"

    [ "$(cat "$target")" = $'line-one\n-n\nvalue\n-e' ]
}

@test "base_file_update_file_section preserves literal backslashes in markers and content" {
    local target="$TEST_TMPDIR/config.txt"
    local beginning='\t'
    local ending='\e'
    local replacement='replacement\t'
    printf '%s\nold\n%s\nafter\n' "$beginning" "$ending" > "$target"

    base_file_update_file_section "$target" "$beginning" "$ending" "$replacement"

    printf -v expected '%s\n%s\n%s\nafter' "$beginning" "$replacement" "$ending"
    [ "$(cat "$target")" = "$expected" ]
}

@test "base_file_update_file_section preserves symlinks while updating their targets" {
    local target="$TEST_TMPDIR/config.txt"
    local link="$TEST_TMPDIR/config-link"
    printf 'before\n# BEGIN\nold\n# END\nafter\n' > "$target"
    ln -s "$(basename "$target")" "$link"

    base_file_update_file_section "$link" "# BEGIN" "# END" "new"

    [ -L "$link" ]
    [ "$(readlink "$link")" = "$(basename "$target")" ]
    [ "$(cat "$link")" = $'before\n# BEGIN\nnew\n# END\nafter' ]
}

@test "base_file_update_file_section treats option-like target paths literally" {
    local target="-config.txt"
    pushd "$TEST_TMPDIR" >/dev/null
    printf 'before' > "$target"

    base_file_update_file_section "$target" "# BEGIN" "# END" "new"

    [ "$(cat "./$target")" = $'before\n# BEGIN\nnew\n# END' ]
    popd >/dev/null
}

@test "base_file_update_file_section replaces the first matching section" {
    local target="$TEST_TMPDIR/config.txt"
    cat <<'EOF' > "$target"
before
# BEGIN
old
# END
after
EOF

    base_file_update_file_section "$target" "# BEGIN" "# END" "new"

    [ "$(cat "$target")" = $'before\n# BEGIN\nnew\n# END\nafter' ]
}

@test "base_file_update_file_section ignores marker substrings embedded in longer lines" {
    local target="$TEST_TMPDIR/config.txt"
    cat <<'EOF' > "$target"
before
echo # BEGIN
old
echo # END
after
EOF

    base_file_update_file_section "$target" "# BEGIN" "# END" "new"

    [ "$(cat "$target")" = $'before\necho # BEGIN\nold\necho # END\nafter\n# BEGIN\nnew\n# END' ]
}

@test "base_file_update_file_section rejects a concurrent writer before commit" {
    local target="$TEST_TMPDIR/config.txt"
    local stderr_file="$TEST_TMPDIR/concurrent.err"

    printf 'before\n# BEGIN\nold\n# END\nafter\n' > "$target"
    eval "$(declare -f __base_bash_libs_file_commit_temp__ | sed '1s/__base_bash_libs_file_commit_temp__/__orig_base_bash_libs_file_commit_temp__/')"
    __base_bash_libs_file_commit_temp__() {
        # Keep the replacement the same size so coarse timestamp/size
        # fingerprints cannot distinguish this concurrent rewrite.
        printf 'before\n# BEGIN\nnew\n# END\nafter\n' > "$target"
        __orig_base_bash_libs_file_commit_temp__ "$@"
    }

    if base_file_update_file_section "$target" "# BEGIN" "# END" "new" 2>"$stderr_file"; then
        return 1
    else
        status=$?
    fi

    unset -f __base_bash_libs_file_commit_temp__ __orig_base_bash_libs_file_commit_temp__
    [ "$status" -eq 6 ]
    [ "$(cat "$target")" = $'before\n# BEGIN\nnew\n# END\nafter' ]
    [[ "$(cat "$stderr_file")" == *"Concurrent modification detected"* ]]
}

@test "base_file_update_file_section preserves executable file mode when replacing" {
    local target="$TEST_TMPDIR/script.sh"
    cat <<'EOF' > "$target"
#!/usr/bin/env bash
# BEGIN
echo old
# END
EOF
    chmod 0755 "$target"

    base_file_update_file_section "$target" "# BEGIN" "# END" "echo new"

    [ -x "$target" ]
    [ "$(file_mode "$target")" = "755" ]
    [ "$(cat "$target")" = $'#!/usr/bin/env bash\n# BEGIN\necho new\n# END' ]
}

@test "base_file_update_file_section replaces an existing section with multi-line content" {
    local target="$TEST_TMPDIR/config.txt"
    cat <<'EOF' > "$target"
before
# BEGIN
old
# END
after
EOF

    base_file_update_file_section "$target" "# BEGIN" "# END" "first" "second" "third"

    [ "$(cat "$target")" = $'before\n# BEGIN\nfirst\nsecond\nthird\n# END\nafter' ]
}

@test "base_file_update_file_section registers internal temp files for cleanup" {
    local registration_file="$TEST_TMPDIR/registered-cleanup-paths.txt"
    local target="$TEST_TMPDIR/config.txt"
    cat <<'EOF' > "$target"
before
# BEGIN
old
# END
after
EOF

    eval "$(declare -f base_std_register_cleanup_path | sed '1s/base_std_register_cleanup_path/__orig_std_register_cleanup_path/')"
    base_std_register_cleanup_path() {
        printf '%s\n' "$@" >> "$registration_file"
        __orig_std_register_cleanup_path "$@"
    }

    base_file_update_file_section "$target" "# BEGIN" "# END" "new"
    unset -f base_std_register_cleanup_path __orig_std_register_cleanup_path

    [ "$(cat "$target")" = $'before\n# BEGIN\nnew\n# END\nafter' ]
    [[ "$(cat "$registration_file")" == *"base-file-section-new."* ]]
    [[ "$(cat "$registration_file")" == *"base-file-section-current."* ]]
    [[ "$(cat "$registration_file")" == *"config.txt."* ]]
}

@test "base_file_update_file_section unregisters temp files after eager cleanup" {
    local cleanup_path
    local target="$TEST_TMPDIR/config.txt"
    cat <<'EOF' > "$target"
before
# BEGIN
old
# END
after
EOF

    base_file_update_file_section "$target" "# BEGIN" "# END" "new"

    for cleanup_path in "${__base_bash_libs_std_cleanup_paths[@]+"${__base_bash_libs_std_cleanup_paths[@]}"}"; do
        if [[ "$cleanup_path" == *"base-file-section-new."* ||
            "$cleanup_path" == *"base-file-section-current."* ||
            "$cleanup_path" == *"config.txt."* ]]; then
            printf 'stale cleanup path: %s\n' "$cleanup_path" >&2
            return 1
        fi
    done
}

@test "base_file_update_file_section restores a preexisting EXIT trap after transient cleanup" {
    local script="$TEST_TMPDIR/update-file-section-exit-trap.sh"
    local target="$TEST_TMPDIR/update-file-section-exit-trap.txt"
    local log_file="$TEST_TMPDIR/update-file-section-exit-trap.log"

    printf 'before\n' > "$target"
    cat > "$script" <<EOF
#!/usr/bin/env bash
source "$BASE_BASH_DIR/std/lib_std.sh"
declare -a app_args=()
base_init app_args --source "\${BASH_SOURCE[0]}" -- "\$@"
source "$BASE_BASH_DIR/file/lib_file.sh"
trap 'printf "caller\n" >> "$log_file"' EXIT
before_trap="\$(trap -p EXIT)"
base_file_update_file_section "$target" '# BEGIN' '# END' 'managed'
after_trap="\$(trap -p EXIT)"
[[ "\$after_trap" == "\$before_trap" ]]
EOF
    chmod +x "$script"

    bats_run bash "$script"

    [ "$status" -eq 0 ]
    [ "$(cat "$log_file")" = "caller" ]
    [ "$(cat "$target")" = $'before\n# BEGIN\nmanaged\n# END' ]
}

@test "base_file_update_file_section skips unchanged existing section" {
    local before_inode
    local target="$TEST_TMPDIR/config.txt"
    cat <<'EOF' > "$target"
before
# BEGIN
same
content
# END
after
EOF
    before_inode="$(file_inode "$target")"

    capture_command base_file_update_file_section "$target" "# BEGIN" "# END" "same" "content"

    [ "$status" -eq 0 ]
    [[ "$output" != *"Updating '$target'"* ]]
    [ "$(file_inode "$target")" = "$before_inode" ]
    [ "$(cat "$target")" = $'before\n# BEGIN\nsame\ncontent\n# END\nafter' ]

    base_std_set_log_level DEBUG
    base_std_set_log_category_level -l base_bash_libs.file DEBUG
    capture_command base_file_update_file_section "$target" "# BEGIN" "# END" "same" "content"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Section already up to date in '$target'."* ]]
}

@test "base_file_section_exists detects a present marked section" {
    local target="$TEST_TMPDIR/config.txt"
    cat <<'EOF' > "$target"
before
# BEGIN
managed
# END
after
EOF

    capture_command base_file_section_exists "$target" "# BEGIN" "# END"

    [ "$status" -eq 0 ]
}

@test "base_file_section_exists returns no-change for absent and missing target files" {
    local target="$TEST_TMPDIR/config.txt"
    printf 'plain\ncontent\n' > "$target"

    capture_command base_file_section_exists "$target" "# BEGIN" "# END"
    [ "$status" -eq 1 ]

    capture_command base_file_section_exists "$TEST_TMPDIR/missing.txt" "# BEGIN" "# END"
    [ "$status" -eq 1 ]
}

@test "file-section helpers reject invalid marker contracts" {
    local target="$TEST_TMPDIR/config.txt"
    printf 'plain\ncontent\n' > "$target"

    capture_command base_file_section_exists "$target" "" "# END"
    [ "$status" -eq 2 ]

    capture_command base_file_section_needs_update "$target" "# BEGIN" "# BEGIN"
    [ "$status" -eq 2 ]

    capture_command base_file_update_file_section "$target" "# BEGIN" $'# END\nextra' "new"
    [ "$status" -eq 2 ]
    [ "$(cat "$target")" = $'plain\ncontent' ]
}

@test "base_file_section_exists rejects asymmetric markers" {
    local target="$TEST_TMPDIR/config.txt"
    cat <<'EOF' > "$target"
before
# BEGIN
orphaned
EOF

    bats_run base_file_section_exists "$target" "# BEGIN" "# END"

    [ "$status" -eq 2 ]
    [[ "$output" == *"Asymmetric markers in '$target': 1 start, 0 end. Manual repair needed."* ]]
}

@test "base_file_section_exists rejects misordered markers" {
    local target="$TEST_TMPDIR/config.txt"
    cat <<'EOF' > "$target"
before
# END
middle
# BEGIN
after
EOF

    bats_run base_file_section_exists "$target" "# BEGIN" "# END"

    [ "$status" -eq 2 ]
    [[ "$output" == *"Misordered markers in '$target'. Manual repair needed."* ]]
}

@test "base_file_section_needs_update detects changed marked section content" {
    local target="$TEST_TMPDIR/config.txt"
    cat <<'EOF' > "$target"
before
# BEGIN
old
# END
after
EOF

    capture_command base_file_section_needs_update "$target" "# BEGIN" "# END" "new"

    [ "$status" -eq 0 ]
}

@test "base_file_section_needs_update returns no-change for matching section content" {
    local target="$TEST_TMPDIR/config.txt"
    cat <<'EOF' > "$target"
before
# BEGIN
same
content
# END
after
EOF

    capture_command base_file_section_needs_update "$target" "# BEGIN" "# END" "same" "content"

    [ "$status" -eq 1 ]
}

@test "base_file_section_needs_update returns change-needed for absent and missing target files" {
    local target="$TEST_TMPDIR/config.txt"
    printf 'plain\ncontent\n' > "$target"

    capture_command base_file_section_needs_update "$target" "# BEGIN" "# END" "new"
    [ "$status" -eq 0 ]

    capture_command base_file_section_needs_update "$TEST_TMPDIR/missing.txt" "# BEGIN" "# END" "new"
    [ "$status" -eq 0 ]
}

@test "base_file_update_file_section does not export replacement content to awk" {
    local awk_log="$TEST_TMPDIR/awk-env.log"
    local target="$TEST_TMPDIR/config.txt"
    cat <<'EOF' > "$target"
before
# BEGIN
old
# END
after
EOF

    awk() {
        if [[ -n "${AWK_NEW_TEXT+x}" ]]; then
            printf 'leaked=%s\n' "$AWK_NEW_TEXT" > "$awk_log"
        else
            printf 'not-leaked\n' > "$awk_log"
        fi
        command awk "$@"
    }

    base_file_update_file_section "$target" "# BEGIN" "# END" "secret" "value"
    unset -f awk

    [ "$(cat "$awk_log")" = "not-leaked" ]
    [ "$(cat "$target")" = $'before\n# BEGIN\nsecret\nvalue\n# END\nafter' ]
}

@test "base_file_update_file_section removes a marked block with remove option" {
    local target="$TEST_TMPDIR/config.txt"
    cat <<'EOF' > "$target"
before
# BEGIN
remove-me
# END
after
EOF

    base_file_update_file_section -r "$target" "# BEGIN" "# END"

    [ "$(cat "$target")" = $'before\nafter' ]
}

@test "base_file_update_file_section removes only the first matching marked block with remove option" {
    local target="$TEST_TMPDIR/config.txt"
    cat <<'EOF' > "$target"
before
# BEGIN
remove-me
# END
middle
# BEGIN
keep-me
# END
after
EOF

    base_file_update_file_section -r "$target" "# BEGIN" "# END"

    [ "$(cat "$target")" = $'before\nmiddle\n# BEGIN\nkeep-me\n# END\nafter' ]
}

@test "base_file_update_file_section rejects a section with only a start marker" {
    local target="$TEST_TMPDIR/config.txt"
    cat <<'EOF' > "$target"
before
# BEGIN
orphaned
EOF

    bats_run base_file_update_file_section "$target" "# BEGIN" "# END" "new"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Asymmetric markers in '$target': 1 start, 0 end. Manual repair needed."* ]]
    [ "$(cat "$target")" = $'before\n# BEGIN\norphaned' ]
}

@test "base_file_update_file_section rejects a section with only an end marker" {
    local target="$TEST_TMPDIR/config.txt"
    cat <<'EOF' > "$target"
before
orphaned
# END
EOF

    bats_run base_file_update_file_section "$target" "# BEGIN" "# END" "new"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Asymmetric markers in '$target': 0 start, 1 end. Manual repair needed."* ]]
    [ "$(cat "$target")" = $'before\norphaned\n# END' ]
}

@test "base_file_update_file_section rejects end markers before start markers" {
    local before
    local target="$TEST_TMPDIR/config.txt"
    cat <<'EOF' > "$target"
before
# END
middle
# BEGIN
after
EOF
    before="$(cat "$target")"

    bats_run base_file_update_file_section "$target" "# BEGIN" "# END" "new"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Misordered markers in '$target'. Manual repair needed."* ]]
    [ "$(cat "$target")" = "$before" ]
}

@test "base_file_update_file_section is a no-op for a missing target file" {
    local target="$TEST_TMPDIR/missing.txt"

    capture_command base_file_update_file_section "$target" "# BEGIN" "# END" "value"

    [ "$status" -eq 0 ]
    [ ! -e "$target" ]
}

@test "base_file_update_file_section rejects content arguments when removing a section" {
    local target="$TEST_TMPDIR/config.txt"
    touch "$target"

    bats_run base_file_update_file_section -r "$target" "# BEGIN" "# END" "unexpected"

    [ "$status" -eq 2 ]
    [[ "$output" == *"When -r flag is used"* ]]
}

@test "base_file_update_file_section cleans up temp file when initial copy fails" {
    local target="$TEST_TMPDIR/config.txt"
    printf 'line-one' > "$target"

    cp() {
        : > "$2"
        return 1
    }

    capture_command base_file_update_file_section "$target" "# BEGIN" "# END" "value"
    unset -f cp

    [ "$status" -eq 1 ]
    [[ "$output" == *"Failed to copy"* ]]
    [ "$(cat "$target")" = "line-one" ]
    ! compgen -G "$target".'*' >/dev/null
}
