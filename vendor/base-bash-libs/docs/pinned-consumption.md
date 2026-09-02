# Pinned consumption and artifact verification

Use one immutable package root for a process. Do not combine modules copied
from different tags, commits, Homebrew prefixes, or vendored trees.

## Full-commit checkout

Resolve a human-readable tag to its commit, then record and verify the full
object ID before sourcing anything:

```bash
git clone https://github.com/basefoundry/base-bash-libs.git vendor/base-bash-libs
git -C vendor/base-bash-libs fetch --tags --force origin
git -C vendor/base-bash-libs checkout --detach <full-commit>
test "$(git -C vendor/base-bash-libs rev-parse HEAD)" = <full-commit>
source vendor/base-bash-libs/lib/bash/std/lib_std.sh
base_std_import str/lib_str.sh file/lib_file.sh
```

The expected commit belongs in the consuming repository's lockfile or CI
workflow. A short SHA is not an immutable pin.

## Release archive or Homebrew artifact

Verify the release asset checksum before unpacking it. Keep the complete
`lib/bash` directory, including `base-bash-libs.release`; it embeds the version,
release commit (when published), and artifact provenance. Then source the
stdlib and use only package-relative imports:

```bash
source "$prefix/libexec/lib/bash/std/lib_std.sh"
base_std_import str/lib_str.sh
printf '%s %s %s %s\n' \
  "$BASE_BASH_LIBS_VERSION" "$BASE_BASH_LIBS_COMMIT" \
  "$BASE_BASH_LIBS_DIRTY_STATE" "$BASE_BASH_LIBS_PROVENANCE"
```

The version is not inferred from the caller's cwd. For a release artifact,
`BASE_BASH_LIBS_DIRTY_STATE` is `clean`; a checkout reports `clean` or `dirty`,
and a copy without identity reports `unknown`.

## Updating a pin

1. Select a released tag or reviewed full commit.
2. Resolve it to a full SHA and verify the release asset checksum, if using an
   archive.
3. Update the consumer lockfile/workflow and its recorded version/SHA together.
4. Run the consumer's import smoke test from a cwd containing spaces and from a
   symlinked package path.
5. Record the new resolved SHA in the change log or dependency update issue.

Do not use a moving branch, an unverified tag name, GitHub's automatic tag
archive for a release that has a canonical asset, or a mixture of v1 and v2
module files. After v2 GA, v1 inputs fail with migration guidance rather than
being fallback-loaded.
