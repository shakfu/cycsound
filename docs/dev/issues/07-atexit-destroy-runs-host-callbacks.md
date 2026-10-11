# atexit destroy runs host callbacks after host shutdown

**Status:** not filed. This is a host-side problem; Csound offers an opt-out.

## Behaviour

Unless `csoundInitialize()` gets `CSOUNDINIT_NO_ATEXIT`, Csound registers
`destroy_all_instances()` with `atexit()` (`Top/csound.c:1184`, `1454`).
At process exit it sleeps 250 ms, then calls `csoundDestroy()` on every
instance still alive. `csoundDestroy()` prints messages through any installed
message callback.

## Effect in cycsound

C `atexit` handlers run after `Py_FinalizeEx()`. A `Csound` object that
outlives finalization can do so through a reference cycle, such as a traceback
stored by `sys.unraisablehook`. Its message trampoline then waits for the GIL
of a finalized interpreter, and the process hangs.

## Resolution in cycsound

- A Python `atexit` handler detaches all callbacks and hooks from live
  instances before finalization.
- The trampolines skip Python when `Py_IsInitialized()` is false or
  finalization has started.

`CSOUNDINIT_NO_ATEXIT` would also prevent the hang. It was not chosen because
it would leave leaked instances undestroyed at exit.
