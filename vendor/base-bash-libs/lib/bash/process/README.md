# `lib_process.sh`

`lib_process.sh` contains reusable process-supervision primitives for Bash
scripts. It is an optional companion module layered on `lib_std.sh`; the
stdlib's stable `base_std_run` and `base_std_run_or_exit` APIs remain in
`lib_std.sh`. The module was first shipped in `v2.1.0` and remains preview;
its symbols are not part of the stable API.

This module is preview-only rather than part of the stable API. It is included
in the immutable `v2.1.0` release but is not part of the immutable `v2.0.0`
release; consumers pinned to v2.0.0 must not import it.

## Loading the library

Source the stdlib first, then import this module through the package-relative
loader:

```bash
source "/path/to/base-bash-libs/lib/bash/std/lib_std.sh"
base_std_import process/lib_process.sh
```

The GitHub module imports this dependency when it is loaded because its retry
capture path uses the internal owner-guardian lifecycle.

## Public API

- `base_process_owner_alive <owner_pid> <guardian_pid>`: returns zero when the
  guardian PID is still directly parented by the owner PID. If the host cannot
  report a parent relationship through `ps`, it falls back to a non-invasive
  owner liveness probe. Invalid arity or PID values return `2`; a false
  relationship returns `1`.

The predicate is useful to a guardian that must distinguish an owner that has
gone away from an unrelated process that later receives the same numeric PID.
It does not send signals or mutate caller state.

## Internal lifecycle

The module also contains private helpers for starting and stopping an
owner-guardian around a caller-owned FIFO and readiness marker. They validate
the owner relationship, close inherited descriptors, remove the control
channel before invoking the caller's cleanup callback, and bound teardown
waiting. These helpers use the `__base_bash_libs_process_...__` namespace and
are not application API.

The process module does not own logging policy, temporary-path ownership, or
GitHub capture semantics. Callers provide a cleanup callback for their
resource-specific policy; the process module owns only supervision mechanics.

## Tests

BATS coverage lives in `lib/bash/process/tests/lib_process.bats`.
