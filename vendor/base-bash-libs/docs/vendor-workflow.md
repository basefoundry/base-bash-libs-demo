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
`scripts/vendor rollback`.

For an application that must run without a framework checkout, assemble a
standalone directory:

```bash
scripts/vendor standalone . /tmp/base-bash-libs-v2 dist/app
PATH="$PWD/dist/app/bin:$PATH" dist/app/bin/app --help
```

The standalone payload contains the verified launcher and framework under its
own root plus an auditable vendor copy and `BASE_BASH_STANDALONE.release`. The
launcher resolves its colocated `lib/bash` tree, so runtime network access and
ambient `BASE_BASH_LIBS_DIR` are unnecessary. No command downloads, executes,
or evaluates remote content.
