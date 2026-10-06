#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/beacon-framework-ref-test.XXXXXX")"
    mkdir -p "$TEST_ROOT/bin"
    cat > "$TEST_ROOT/bin/git" <<'SH'
#!/usr/bin/env bash
if [[ "$1" != ls-remote ]]; then
    exit 99
fi
case "${*: -1}" in
    'refs/tags/v2.2.0^{}')
        printf '%s\trefs/tags/v2.2.0^{}\n' "$MOCK_PEELED_SHA"
        ;;
    'refs/tags/v2.1.0')
        printf '%s\trefs/tags/v2.1.0\n' "$MOCK_LIGHTWEIGHT_SHA"
        ;;
    *)
        ;;
esac
SH
    chmod +x "$TEST_ROOT/bin/git"
    PEELED_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    LIGHTWEIGHT_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
}

teardown() {
    rm -rf "$TEST_ROOT"
}

@test "resolver uses the peeled commit for an annotated release tag" {
    run env PATH="$TEST_ROOT/bin:$PATH" MOCK_PEELED_SHA="$PEELED_SHA" \
        "$REPO_ROOT/scripts/resolve-framework-ref" example/repo v2.2.0
    [ "$status" -eq 0 ]
    [ "$output" = "$PEELED_SHA" ]
}

@test "resolver accepts a lightweight release tag" {
    run env PATH="$TEST_ROOT/bin:$PATH" MOCK_LIGHTWEIGHT_SHA="$LIGHTWEIGHT_SHA" \
        "$REPO_ROOT/scripts/resolve-framework-ref" example/repo refs/tags/v2.1.0
    [ "$status" -eq 0 ]
    [ "$output" = "$LIGHTWEIGHT_SHA" ]
}

@test "resolver passes through a full commit without accepting a branch" {
    run "$REPO_ROOT/scripts/resolve-framework-ref" example/repo "$PEELED_SHA"
    [ "$status" -eq 0 ]
    [ "$output" = "$PEELED_SHA" ]

    run "$REPO_ROOT/scripts/resolve-framework-ref" example/repo v2-review-moving-branch
    [ "$status" -eq 1 ]
    [[ "$output" == *"expected a release tag or full commit"* ]]

    run "$REPO_ROOT/scripts/resolve-framework-ref" example/repo refs/heads/main
    [ "$status" -eq 1 ]
    [[ "$output" == *"moving framework reference"* ]]
}
