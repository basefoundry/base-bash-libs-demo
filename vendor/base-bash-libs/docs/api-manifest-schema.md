# API and module manifest

`base_api_manifest.yaml` is the authoritative v2 API/module inventory. It is
deliberately separate from `base_manifest.yaml`, which is the Base release and
developer-tooling manifest. The API manifest is a small, line-oriented YAML
subset so that consumers can inspect it with Bash, `awk`, or another YAML
reader; no Python, Ruby, `yq`, or `jq` runtime is required to consume the
library.

## Schema

The current schema is `1` and the manifest identifies itself with
`manifest_kind: base-bash-libs-api`. The required top-level fields are:

| Field | Meaning |
| --- | --- |
| `schema_version` | Manifest schema compatibility number. |
| `manifest_version` | API release line represented by the manifest (`2.0.0` during v2 development). |
| `minimum_bash` | Minimum supported Bash runtime (`4.2`). |
| `generated_reference` | Checked-in API reference generated from this manifest. |
| `migration_inventory` | Normative v1-to-v2 behavior and symbol migration record. |
| `namespace` | Public function, global, internal, and lifecycle naming contract. |
| `environment` | Caller inputs and framework-owned globals, with kind and purpose. |
| `optional_commands` | External commands that are optional runtime capabilities. |
| `artifacts` | Manifest-owned source, documentation, generated, and test-support files. |
| `modules` | Ordered module records described below. |

Each module declares its single source boundary, documentation, BATS suite,
dependencies, optional commands, package artifacts, public symbols, and API
metadata:

- `kind` is `sourceable-library` for a sourceable `.sh` library or
  `executable-launcher` for `bin/base-bash`.
- `dependencies` names other manifest modules. `scripts/api-manifest check`
  rejects missing modules and dependency cycles.
- `public_symbols` is the complete exported function set. The checker compares
  it with declarations in the source file and rejects both undocumented and
  duplicate symbols.
- `signature_source` points to the README or charter containing call-specific
  signatures and examples. `inputs`, `outputs`, `statuses`, and `side_effects`
  provide the module-level contract inherited by each listed symbol.
- `stability`, `since`, and `deprecated` are required release metadata. A
  future deprecation must add a migration-inventory entry before changing the
  symbol.

The artifact list makes packaging membership reviewable. Every module must
package its source, documentation, and tests. Generated files are checked for
drift rather than silently rewritten by validation.

## Commands

The Bash-native consumer tool is [`scripts/api-manifest`](../scripts/api-manifest):

```bash
scripts/api-manifest check
scripts/api-manifest generate
scripts/api-manifest symbols
scripts/api-manifest module-paths
scripts/api-manifest source-paths
scripts/api-manifest test-paths
scripts/api-manifest artifact-paths
```

`check` validates schema and metadata, module/file existence, duplicate symbols,
source/manifest drift, dependency cycles, unsafe paths, packaging membership,
and the generated API reference. The repository validation suite obtains its
module source, test, and artifact paths from these commands instead of keeping
another hardcoded module list.

## Single-file boundary

The manifest describes library boundaries; it does not create a loader graph.
Each public sourceable library remains one physical file as required by
[`STANDARDS.md`](../STANDARDS.md). Adding a concern means adding or extending a
documented module boundary, not splitting an existing library into fragments.
