# Callback deadlock audit

Csound 7.0.0-beta.18, cycsound callbacks (A) and hooks (B). Line numbers refer
to the upstream `7.0.0-beta.18` tag.

## Mechanism

- Outside `--realtime` mode, `csoundPerformKsmps()` holds `API_lock` across
  `sense_events()` and `kperf()` (`Top/csound_perf.c:427-446`). Every message,
  `invalue`/`outvalue` and `sensekey` callback runs under that lock.
- A Python callback's trampoline takes the GIL.
- **Deadlock:** thread M holds the GIL and calls a C function that blocks on
  something the performing thread P holds. P is in a callback, waiting for
  the GIL. Neither can proceed.

`API_lock` is recursive, so a callback that calls back into Csound on P does
not deadlock itself.

## C functions that can block

| Function | Blocks on |
|-|-|
| `csoundCompileTree`, `csoundCompileOrc`, `csoundCompileCSD`, `csoundEvalCode` (sync, after start) | `API_lock` in `merge_state` (`Engine/csound_orc_compile.c:2449`) |
| `csoundTableCopyIn` / `csoundTableCopyOut` (sync) | `API_lock` (`Top/threadsafe.c:351`, `362`) |
| `csoundKillInstance` (sync; not wrapped) | `API_lock` (`Top/threadsafe.c:395`) |
| `csoundReset`, `csoundDestroy` | `API_lock` in `csound_cleanup` (`Engine/musmon.c:629`) |
| `csoundPerformKsmps`, `csoundPerformOutputFade` | `API_lock` |
| `csoundUDPServerClose` | joins the server thread, which prints on exit (`Top/server.c:406`) |

`csoundEvent`/`csoundEventString` (sync) and the score functions take no lock.
`csoundCompile` refuses once the engine has started (`Top/main.c:232`).

## Wrapper methods that hold the GIL around a blocking call

| Method | Before | Evidence | Now |
|-|-|-|-|
| `compile_tree` | GIL held | Deadlocked (killed after 20 s) during 200 sync compiles against a thread running `outvalue` at `ksmps = 1` | GIL released |
| `udp_server_close` | GIL held | Deadlocked on every run with a message callback set | GIL released |
| `__dealloc__` (`csoundDestroy`) | GIL held | Cannot overlap a performance. `run()`/`perform_ksmps()` hold a reference, and desktop backends do not perform on their own threads (only iOS/Android do) | unchanged |

Already released: `compile_orc`, `compile_csd`, `compile_csd_text`,
`eval_code`, `start`, `perform_ksmps`, `run`, `reset`, `perform_output_fade`,
`set_table`, `event`, `event_string`.

Every other method calls only non-blocking C functions:

- **Channels.** Per-channel spin locks are held only inside opcodes and never
  across a callback.
- **Message buffer.** Its mutex is held only by C code that never needs the
  GIL.
- **Plain field reads and writes:** everything else.

Any new wrapper of a function in the first table must release the GIL. This
includes `csoundTableCopyOut` and `csoundKillInstance`, which are not wrapped
yet.

## Related conflict fixed

`csoundUDPConsole` replaces the message callback, and its stop path installs
the default printer (upstream [03](issues/03-udp-console-ignores-string-callback.md)).
`udp_console` and the message callback/hook now raise `RuntimeError` while the
other is active. `stop_udp_console` re-installs the callback.

## Remaining hazards (races, not deadlocks)

1. **Keyboard callback list.** `csoundRegisterKeyboardCallback` and
   `csoundRemoveKeyboardCallback` `free()` list entries with no lock, while
   `csoundDoCallback_` walks the list on the performing thread.
   `set_keyboard_callback` now registers once and swaps only the callable;
   changing `type_mask` still re-registers. `register_keyboard_hook` and
   `remove_keyboard_hook` remain unsafe during performance. Stress runs of
   the old path (3 x 200,000 register/remove cycles) did not crash: glibc
   leaves the freed entry readable.
2. **Hook replacement.** Swapping one non-null hook for another during
   performance can pair the new function with the old `ctx`. This is
   documented on the setters.
3. **Sync events from another thread.** `event`/`event_string` default to
   `async_=False`, which inserts into the event list without a lock. Use
   `CsoundPerformanceThread` to drive Csound across threads. `async_=True`
   uses a 1024-entry queue: `message_enqueue` busy-waits when it is full
   (`Top/threadsafe.c:105-107`), so the 1025th call before `start()` hangs
   without being interruptible.
6. **Channel creation.** Csound creates a missing channel without a lock
   (upstream [08](issues/08-channel-creation-race.md)). A host read racing
   the first `chnset` loses the value in 130 of 200 C runs. Declare host
   channels with `chn_*`.
4. **User locks.** A callback that waits on a lock held by a thread blocked in
   a GIL-released Csound call deadlocks without involving the GIL. The same
   happens when Python holds `lock_channel()` and then calls a function that
   waits on the performing thread.
5. **Re-entrant lifetime calls.** Calling `reset()` from a callback, or
   dropping the last reference to the instance there, is undefined.

## Tests

`tests/test_callbacks.py`:

- `test_compile_tree_while_performing_with_callback`
- `test_udp_server_close_with_message_callback`
- `test_udp_console_and_message_callback_are_exclusive`

The deadlock cases run in a subprocess with a timeout, so a regression fails
instead of hanging the suite.

## CsoundPerformanceThread

The performance thread (`Top/csPerfThread.cpp`) runs queued messages and the
process callback with `queueLock` released (`csPerfThread.cpp:661-738`). It
holds `callbackLock` only to snapshot the process callback. Neither lock is
held while it waits for the GIL. `QueueMessage` waits on `flushLock` with a
zero timeout, so queueing never blocks.

Three calls block on the thread, and all release the GIL:

- `join`
- `flush_message_queue`
- destruction (`csoundDestroyPerformanceThread` runs Stop + Join)

Before releasing the GIL, destruction disarms the process callback. The
trampolines re-check their flag after taking the GIL, so an in-flight call
returns without touching the dying object.
