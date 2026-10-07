# Offline vendor and standalone workflow

Build and verify a framework bundle from the canonical source tree:

```bash
scripts/library-bundle bundle /tmp/base-bash-libs-v2
scripts/library-bundle verify /tmp/base-bash-libs-v2
```

Install it into a consumer without network access:

```bash
scripts/vendor create /tmp/base-bash-libs-v2 vendor/base-bash-libs
scripts/vendor verify vendor/base-bash-libs
```

`base-bash-libs.lock` records the framework version, source commit, manifest
hash, and verification mode. `scripts/vendor update` stages a complete new
tree, writes its lock, and swaps it atomically; the previous tree remains at
`vendor/base-bash-libs.previous` until a deliberate
`scripts/vendor rollback`. A successful rollback restores that previous tree
and permanently discards the displaced current tree; the command reports this
cleanup and does not retain a roll-forward copy. A failed move restores the
original destination when possible and leaves the rollback directory in place
for inspection, so disk usage and recovery remain explicit.

For an application that must run without a framework checkout, assemble a
standalone directory:

```bash
scripts/vendor standalone . /tmp/base-bash-libs-v2 /tmp/my-app-dist
PATH="/tmp/my-app-dist/bin:$PATH" /tmp/my-app-dist/bin/app --help
```

The required application payload is defined once in
`scripts/standalone-app-payloads.txt`; both the project generator and standalone
packager use that list. Development-only repository metadata, local
configuration overrides, tests, build output, caches, and previous
output/staging trees are not recursively copied. Put additional runtime assets
under `assets/` or `config/` and name each one explicitly:

```bash
scripts/vendor standalone . /tmp/base-bash-libs-v2 /tmp/my-app-dist \
  --include assets/templates/default.conf \
  --include config/production.conf
```

Included paths must be regular files with no symlink in any path component.
The packager validates each path before copying, checks the source again around
the copy, and verifies the staged bytes against the pre-copy digest; if a path
changes during staging, packaging fails and the incomplete staging tree is
discarded. These checks apply equally to required files and explicitly selected
runtime assets. The destination parent must already exist, and the destination
must be outside the application source tree; containment is checked using
filesystem identity so alternate path casing on case-insensitive filesystems
cannot bypass it. Use a sibling or temporary output directory. This prevents
an output/staging tree from becoming part of its own package input.

The standalone payload contains two deterministic copies of the same verified
framework bundle. The root copy is the authoritative runtime layout and is
bound by `BASE_BASH_STANDALONE.release`; the launcher resolves its colocated
`lib/bash` tree without ambient `BASE_BASH_LIBS_DIR`. The application's root
`VERSION` remains its own user-visible version; the launcher reads the framework
version from `lib/bash/base-bash-libs.release`. The
`vendor/base-bash-libs` copy is the authoritative audit/vendor layout and has
its own `base-bash-libs.lock`, so consumers can verify it independently:

```bash
scripts/vendor verify dist/app/vendor/base-bash-libs
```

Both framework copies carry the same framework version, source commit, and
canonical manifest before the application payload is restored. The root copy's
manifest then records the application's user-visible `VERSION`, while
`BASE_BASH_STANDALONE.release` binds `framework_lock` to the canonical manifest
in `vendor/base-bash-libs`. Standalone creation stages the complete payload and
its lock before one atomic move. No command downloads, executes, or evaluates
remote content.
