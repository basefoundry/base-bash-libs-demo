# `lib_file.sh`

File-oriented Bash helpers shared by CLI commands.

The normative v2 status and mutation rules are in
[`docs/v2-api-contract.md`](../../../docs/v2-api-contract.md).

## Dependency

Source `lib/bash/std/lib_std.sh` before this library so logging and error helpers are available.
Both libraries preserve caller-selected `errexit`, `nounset`, and `pipefail`
settings; they do not impose a strict-mode policy on the calling script.

## Public API

- `base_file_section_exists <target> <start_marker> <end_marker>`
  Inspect whether a valid marker-delimited block is present without changing
  the file; returns `0` for present, `1` for absent, and `2` for invalid
  marker order or counts.
- `base_file_section_needs_update <target> <start_marker> <end_marker> [content...]`
  Inspect whether adding or replacing a marker-delimited block would change the
  file; returns `0` when an update is needed, `1` when unchanged, and `2` for
  invalid marker order or counts.
- `base_file_update_file_section [-r] <target> <start_marker> <end_marker> [content...]`
  Idempotently add, replace, or remove a marker-delimited block inside a file.
  It mutates the target or symlink referent and returns nonzero on validation or
  filesystem failure. A concurrent writer detected after the read returns
  status `6`; the newer target is never overwritten.

## Usage

```bash
source "/absolute/path/to/lib/bash/std/lib_std.sh"
declare -a app_args=()
base_init app_args --source "${BASH_SOURCE[0]}" --
base_std_import file/lib_file.sh

base_file_update_file_section ~/.bash_profile "# BEGIN APP" "# END APP" \
    "export APP_HOME=/opt/app" \
    "alias appctl='app status'"
```

Use the inspection helpers before dry-run output, backup creation, or other
caller-owned side effects:

```bash
if base_file_section_needs_update ~/.bash_profile "# BEGIN APP" "# END APP" \
    "export APP_HOME=/opt/app"; then
    cp -p ~/.bash_profile ~/.bash_profile.backup
    base_file_update_file_section ~/.bash_profile "# BEGIN APP" "# END APP" \
        "export APP_HOME=/opt/app"
fi
```

## Behavior Notes

- Returns success when the target file does not exist and there is nothing to remove.
- Replaces or removes only the first matching marked section when markers already exist.
- Treats markers as exact full lines; marker text embedded in longer lines is ignored.
- Requires non-empty, distinct, single-line marker values.
- Preserves a target symlink while atomically updating its referent.
- Preserves the target mode and detects device/inode/size/time changes before
  committing; concurrent modification returns `6` and cleans temporary files.
- Treats option-like target paths literally.
- Appends the marked block when markers are not present.
- `base_file_section_exists` returns `0` when a valid marker pair is present, `1`
  when the target file is missing or the section is absent, and `2` when marker
  pairs are asymmetric or misordered.
- `base_file_section_needs_update` returns `0` when an add/update would change the
  target file, `1` when the first existing marked section already matches, and
  `2` when marker pairs are asymmetric or misordered.
- Invalid or incomplete arguments produce a usage diagnostic and return
  nonzero without relying on unset positional parameters. Under `errexit`, use
  a conditional context when a nonzero inspection result is expected.

## Tests

BATS coverage lives in `lib/bash/file/tests/lib_file.bats`.
