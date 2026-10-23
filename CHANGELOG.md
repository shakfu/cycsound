# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `scripts/test_wheel.py [version | --wheel PATH]` runs the current `tests/` against a PyPI release (default: latest) or a local wheel in a throwaway venv.
- `scripts/check_rtaudio.py [module]` plays a tone to `-odac` and exits 1 if Csound falls back to its dummy audio module, which the offline test suite cannot detect.

### Fixed

- `make` re-vendors Csound when `vendor/.tag` differs from `TAG` in `scripts/vendor_csound7.sh`. It previously checked only that the library existed, so after the 7.0.0 bump a stale beta.18 `libcsound64.so` stayed in `vendor/lib` and `_core` failed to import with `undefined symbol: csoundSetReadlineCallback`.

## [0.2.2]

### Fixed

- Linux wheels now ship the Csound opcode plugins as `cycsound/plugins/`, and the package points `OPCODE7DIR64` there. 0.2.0 and 0.2.1 omitted them: `__init__.py` only looked in the source tree's `vendor/plugins`, so orchestras using plugin opcodes (`vco2` and others) failed to compile from an installed wheel. `rtalsa`, `rtjack` and `pmidi` link the host's ALSA, JACK and PortMIDI rather than bundled copies, so they match the system's audio stack.
- cibuildwheel runs the full test suite against each wheel instead of an import check, which passed on the broken wheels.

## [0.2.1]

- Release includes CI changes otherwise no change from 0.2.0

## [0.2.0]

Sync to Csound **7.0.0** (from beta.16).

### Build

- `scripts/vendor_csound7.sh` now defaults to the `7.0.0` tag and vendors on Linux as well as macOS. On Linux it stages the `csound-linux-minimal-x86_64` release asset as `vendor/lib/` (the shared library) and `vendor/plugins/` (the opcode plugins), and gives the plugins an rpath to the vendored library when `patchelf` is available.

- `CMakeLists.txt`: the Linux branch links the vendored `libcsound64.so` with an rpath instead of a system `csound64`, and takes its headers from the repo-local `include/` (the Linux release ships none). It auto-runs the vendoring script when the library is missing, as the macOS branch does. A distro `csound` package is Csound 6, whose host API this wrapper does not target.

- `CMakeLists.txt`: the Windows branch points at `C:/Program Files/Csound7_x64` (was `Csound6_x64`) and exposes `CSOUND_ROOT` as a cache variable.

- `Makefile`: the vendoring prerequisite resolves per platform (`vendor/CsoundLib64.framework` on macOS, `vendor/lib/libcsound64.so` elsewhere).

- CI and `cibuildwheel` no longer install a system Csound 6 on Linux/macOS; those builds vendor Csound 7 during CMake configure.

- `include/` synced to the beta.18 headers. beta.18 renames `MYFLT` to `cs_float` (`csound_types.h`) and re-declares `MYFLT` as a deprecated typedef, so the `MYFLT=double` compile definition is dropped: it expanded that typedef to `typedef cs_float double` and broke the build.

- `include/` synced to the 7.0.0 headers. No wrapped signature changed; `OPARMS` gains a trailing `no_deprecated_warnings` field.

- Wheels: the upstream 7.0.0 binaries raise the platform floors. macOS wheels target 12.0, and Linux wheels build on `manylinux_2_34` because `libcsound64.so` needs `GLIBC_2.29`. Windows CI installs the 7.0.0 release (choco ships 6.17), and `delvewheel` bundles `csound64.dll`. `macos-13` (retired) is replaced by `macos-15-intel`. cibuildwheel settings now live only in `pyproject.toml`. The wheel workflow runs on every branch push; tag pushes, and so PyPI publishing, stay off.

- Wheels are built for Python 3.15. cibuildwheel moves from 3.3.1 to 4.3.4, the first series with the final CPython 3.15.0.

### Changed

- `Csound.event()` raises `RuntimeError` when called synchronously before `start()`. Csound dropped such events silently (both `i` and `f`). Use `event_string()`, or `async_=True` for at most 1024 queued events.

- `set_keyboard_callback()` registers its C function once and swaps only the Python callable, including on `None`. Csound frees keyboard-list entries without a lock while the performing thread walks the list.

- The C host data of a `Csound` instance now points at its callback state, not at the `host_data` object. Code that read `csoundGetHostData()` from Cython must use `Csound.host_data`.

### Fixed

- `run()` returned 0 when performance failed. In 7.0.0 `csoundPerformKsmps` returns a negative value on error, e.g. on re-entry from a callback during a render pass. `run()` now returns that value.

- `compile_tree()` and `udp_server_close()` deadlocked with a callback set. A performing thread holds `API_lock` while its callback waits for the GIL. `compile_tree` held the GIL while its sync merge waited for `API_lock`. `udp_server_close` held it while joining a server thread that prints on exit. Both now release the GIL. See `docs/dev/deadlock-audit.md`.

- `udp_console()` and a message callback or hook now raise `RuntimeError` while the other is active: the console replaces Csound's message callback. `stop_udp_console()` re-installs the callback.

- Callback workarounds for Csound behaviour, found while adding callbacks (upstream drafts in `docs/dev/issues/`):

  - `reset()` reverts the message string callback to the default printer; the wrapper re-installs it.

  - `csoundDoCallback_` returns 1 even when a keyboard callback succeeds, so `sensekey` polled stdin and overwrote the key. Registering a keyboard callback or hook now calls `csoundKeyPress(cs, 0)`, which stops the polling, and repeats it after `reset()`.

  - Csound's C atexit handler destroys live instances after Python has finalized. A message callback then blocked forever waiting for the GIL. Callbacks are now detached from live instances in a Python atexit handler, and the trampolines skip Python once finalization starts.

- `Csound.get_control_channel_hints()` leaked the `attributes` string; Csound allocates a copy per call, now released with `csoundDeleteControlChannelHints`.

- Linux: the extension is now loaded with `RTLD_GLOBAL`, and `OPCODE7DIR64` is pointed at `vendor/plugins` for a source build when it is unset. The Linux release is a minimal build whose opcode library ships as external plugins; those resolve Csound symbols out of the global symbol namespace, so without this they failed to register silently and orchestras using them (`vco2`, `moogladder`, `diskgrain`, ...) did not compile.

### Added

- `csound.pxd` now declares the full public surface of Csound 7's `csound.h`. Previously missing: the message callbacks (`csoundSetMessageCallback`, `csoundSetMessageStringCallback`, `csoundSetDefaultMessageCallback`, `csoundMessageV`), the keyboard callbacks (`csoundRegisterKeyboardCallback`/`csoundRemoveKeyboardCallback`), the input/output channel callbacks, `csoundGetChannelVarType`, the array/string/ fsig channel data accessors (`csoundInitArrayChannel`, `csoundArrayData*`, `csoundGet`/`SetArrayData`, `csoundGet`/`SetStringData`, `csoundInitPvsChannel`, `csoundPvsData*`, `csoundGet`/`SetPvsData`), `csoundAppendOpcode`/`csoundAppendOpcodes`, the `DEBUG_STATUS` levels, the `CSOUNDINIT_*` flags and the `CSOUND_CALLBACK_KBD_*` types.

- `Csound.set_audio_channel(name, block)` / `Csound.get_audio_channel(name)` - read and write a ksmps-sized block on an audio channel.

- `Csound.set_control_channel_hints(...)` / `Csound.get_control_channel_hints(name)` - control channel display hints, with a `ChannelBehavior` enum for the behaviour values.

- `Csound.run_utility(name, *args)` - `csoundRunUtility`.

- `set_global_env(name, value)` and `sleep(milliseconds)` module functions.

- beta.18 host API:

  - `Csound.set_command_line_args(*args)` / `get_command_line_args()` - the arguments after `--` that the orchestra reads with `argv`.

  - `Csound.copy_channel(source, dest)` - `csoundGetChannel` + `csoundSetChannel`; copies a channel of any type. A raw `CS_VAR_MEM` handle is not exposed: Python cannot interpret it without the type system.

  - `Csound.init_pvs_channel(...)`, `set_pvs_channel(name, data)`, `get_pvs_channel(name, data)`, and the `PvsData`, `PvsWindow` and `PvsFormat` types. `init_pvs_channel` raises before `start()` because Csound segfaults allocating the frame then. A `PvsData` raises after `reset()` instead of reading freed memory. `PvsData.set_frame` writes exactly `fft_size + 2` floats instead of calling `csoundSetPvsData`, which copies the allocated frame size and overreads once a smaller frame has been copied in.

  - `Csound.readline_push_text(text)` - input for the `readline` opcode.

  - `Csound.perform_output_fade(frames)` - a no-op without realtime output.

  - `get_size_of_cs_float()` / `get_size_of_cs_double()`; `get_size_of_myflt` is kept as an alias.

  - `Params.recursion_depth`.

- 7.0.0 host API: `Csound.set_readline_callback(callback)` and `readline_submit(request_id, text)`, host-side input for the `readline` opcode. `callback(request_id, prompt)` gets the prompt when a line request opens and `None` when it closes. 7.0.0 `readline` claims stdin for the whole process even in this mode, so a second live instance gets an init error (`docs/dev/issues/11-readline-host-mode-claims-stdin.md`).

- Host-implemented realtime MIDI (`csound_rtmidi.h`), for use with `set_host_midi_io()`: `set_midi_in_callbacks(open, read, close)`, `set_midi_out_callbacks(open, write, close)`, `set_midi_device_list_callback()` and `set_midi_error_string_hook()`. Each slot takes a Python callable or a C function address. `open` returns a handle object that `read`/`write`/`close` receive, so no `void **` user data reaches Python. A raised exception returns -1 to Csound. The wrapper re-installs the callbacks after `reset()`, which replaces them with Csound's dummies.

- Unit generator API (`ugen.h`): `Csound.ugen_factory()` returns a `UgenFactory`, which creates `Ugen`, `UgenVar`, `UgenContext` and `UgenGraph` objects and lists opcode entries. Each object keeps its parents alive, because `csoundUgenDelete()` runs the opcode's deinit against the factory's or context's state, and a wired input reads its source's memory. The objects raise after `reset()`, which frees their pool memory. `set_input_var()` rejects mismatched types, and `UgenVar.value` rejects non-scalars: Csound checks neither, and a k source on an a input reads ksmps floats from a one-float slot. `Ugen.set_in_value()`, `get_out_value()`, `set_in_string()` and `get_out_string()` call the `csoundUgen*Value`/`*String` index helpers directly with the same guards; they avoid a `UgenVar` per call (about 45 ns vs 105 ns). `UgenGraph.delete_all()` frees the graph and its Ugens immediately (`csoundUgenGraphDeleteAll`), so deinit runs without waiting for the GC. It refuses a Ugen that occurs twice, sits in another graph, or feeds a Ugen outside the graph, since each would then use freed memory; afterwards the deleted objects raise on use. `Ugen.delete()` does the same for one Ugen (`csoundUgenDelete`) and refuses while any graph holds it. An opcode init error crashes the process (`docs/dev/issues/09-ugen-init-error-longjmp.md`).

- Array channels: `Csound.init_array_channel(name, type, sizes)` returns an `ArrayChannel` with `type`, `sizes`, flat `get()`/`set()` for i/k/a arrays and `get_string()`/`set_string()` for S arrays. Element strides come from `ARRAYDAT`, so the build now includes the plugin header `csdl.h`. `set_string()` refuses elements whose buffer aliases another string: `csoundSetStringData()` would write into, or reallocate, memory it does not own.

- `Csound.create_circular_buffer(size, element_size)` returns a `CircularBuffer` (Csound's single-reader, single-writer ring buffer) that moves bytes in whole elements and exposes its `address` for C code.

- Graph display: `set_is_graphable()` and `set_graph_callbacks(make, draw, kill, exit)`. Python callbacks get a `GraphWindow` snapshot, since the `WINDAT` belongs to Csound; `make()` may return the window's `windid`. The wrapper re-applies both after `reset()`: reset clears the graphable flag, and a `-d` run leaves no-op callbacks in the block reset preserves. Csound 7.0.0 never calls `kill`.

- File callbacks: `set_file_open_callback()` (notification, with a `FileType` enum), `set_open_file_callback()` and `set_open_sound_file_callback()` (return a `FILE *` or sound-file handle address, or None to let Csound open the file), and `set_sndfile_callbacks(address)`. Csound reverts the sndfile callbacks on `reset()`, so the wrapper keeps a copy of the struct and re-applies it.

- `append_opcode()` (C function addresses) and `append_opcodes()` (an `OENTRY` array) register C opcodes; `OPDS_SIZE` locates the argument pointers. Csound keeps the name and type-string pointers instead of copying them, so `append_opcode()` holds the encoded strings until `reset()` (`docs/dev/issues/10-append-opcode-keeps-caller-strings.md`).

- `Csound.host_data` is settable. `csoundSetHostData` itself stays unexposed: the C host data routes callbacks to the instance.

- Callbacks for messages, `invalue`/`outvalue` channels and keyboard input, at two levels:

  - Python callables, called with the GIL: `set_message_callback`, `set_input_channel_callback`, `set_output_channel_callback`, `set_keyboard_callback`, with a `KeyCallbackType` enum.

  - C function pointers, passed as int addresses and called without the GIL: `set_message_hook`, `set_input_channel_hook`, `set_output_channel_hook`, `register_keyboard_hook` / `remove_keyboard_hook`. Addresses over a Cython-level API because the wheel ships no `.pxd`; any C-callable (Cython, ctypes, cffi, numba `cfunc`) works.

  A hook and a callback may share a slot; the hook runs first. A message callback and the message buffer cannot both be set, since Csound routes to one: each setter raises `RuntimeError` while the other is active.
- `Csound.host_data` returns the constructor's `host_data`.

- `CsoundPerformanceThread(csound)`: performs a started instance on a native thread, wrapping Csound's `csPerfThread` C API. Its unbounded, locked message queue is the safe way to send events, code and score changes from other threads. The Csound API's own `async` queue holds 1024 entries and busy-waits when full. Process callbacks come at both levels (`set_process_callback`, `set_process_hook`). `eval_code` and `request_callback` run Python on the performance thread. `join`, `flush_message_queue` and destruction release the GIL, and live threads are stopped at interpreter exit. `tests/test_thread.py` is rewritten for the Csound 7 API and no longer skipped.

### Known gaps

Declared in `csound.pxd` but not exposed: `csoundTableCopyOut`, `csoundScoreSort`/`csoundScoreExtract` (`FILE *` arguments), `csoundMessageV` (`va_list`), `csoundSetDefaultMessageCallback`, and `csoundGetChannelVarType` (`get_channel_var_type_name()` returns the same name).

## [0.2.0a]

Port from Csound 6 to **Csound 7** (beta). Csound 7 reworked the host C API, so this is a breaking change to both the build and the Python API.

### Build

- Target the Csound 7 `CsoundLib64.framework` on macOS, vendored into a repo-local `vendor/` directory by `scripts/vendor_csound7.sh` (downloads the beta `.pkg`, extracts the framework, repoints its install id, and re-signs). `/Library/Frameworks` is no longer used, so a Csound 6 install can coexist.

- The framework is downloaded over plain HTTPS with `curl` (with a `wget` fallback) from the public GitHub release asset -- no GitHub account or `gh` CLI required. A tag can be passed to the script, e.g. `scripts/vendor_csound7.sh 7.0.0-beta.16`.

- The framework is fetched automatically when missing: the `build`/`test`/`sync` Makefile targets carry an order-only prerequisite on `vendor/CsoundLib64.framework`, and `CMakeLists.txt` also runs the vendoring script during configure (covering `pip install .` / `uv build`, which do not go through `make`).

- `CMakeLists.txt` points at the vendored framework; macOS static linking is disabled (the framework ships dynamic libraries only).

- `include/` headers refreshed to the Csound 7 set.

- `make test` now invokes `python -m pytest`.

### Changed / Added (Python API mirrors Csound 7)

- `Csound(host_data=None, opcodedir=None)` - `csoundCreate` takes an opcode directory override.

- `compile_orc(orc, async_=False)` - merged async flag (no `compile_orc_async`).

- `compile_csd(file)` / `compile_csd_text(text)` - both call `csoundCompileCSD`.

- `event(type, params, async_=False)` and `event_string(message, async_=False)` replace `read_score`, `input_message`, and the `score_event*` family.

- `get_instr_number(name)`, `get_kcounter()`, `err_cnt()`, `lock_channel()` / `unlock_channel()`, `set_host_audio_io()` / `set_host_midi_io()`, `get_channels(is_input)` (plus `get_nchnls()`/`get_nchnls_input()` helpers).

- `get_params()` returns a **read-only** `Params` view of the `OPARMS` struct; `set_params()` was removed (options are set via `set_option`).

- New `EventType` and `ChannelType` `cpdef` enums.

- Context manager now calls `reset()` on exit (there is no `csoundCleanup`).

- Pure-Python channel/table helpers: `list_channels()`, `get_string_channel()`, `get_table()`, `get_table_args()`, `set_table()`, `get_audio_dev_list()`, `get_midi_dev_list()`, `get_module()`.

### Removed (no Csound 7 equivalent)

- `get_api_version()`, `set_opcode_dir()`, `FileType` enum.

- `perform()`, `perform_buffer()`, `stop()`, `cleanup()`.

- `read_score()`, `score_event*`, `input_message*`, `kill_instance()`.

- `table_get()` / `table_set()` single-slot accessors; the input/output buffer and spin-sample accessors; `is_named_gen()` / `get_named_gen()`.

- Low-level Cython-only helpers for threads, mutexes, circular buffers, global variables, utilities, RNG, timers, and the various callback setters were not carried over in this port and may be re-added against the Csound 7 callback API in a later release.

## [0.1.0]

### Added

- Initial scikit-build-core based build system

- **Context manager support** for `Csound` class:
  ```python
  with cycsound.Csound() as cs:
      cs.compile_csd("score.csd")
      cs.run()
  # cleanup() called automatically
  ```

- **`run()` method** - convenience method to perform entire score

- **`Status` enum** (`cpdef enum`) - Csound return status codes:

  - `Status.SUCCESS`, `Status.ERROR`, `Status.INITIALIZATION`

  - `Status.PERFORMANCE`, `Status.MEMORY`, `Status.SIGNAL`

- **`FileType` enum** (`cpdef enum`) - 66 Csound file type constants:

  - Audio: `WAVE`, `FLAC`, `OGG`, `AIFF`, `AU`, `CAF`, `MPEG`, etc.

  - Csound: `UNIFIED_CSD`, `ORCHESTRA`, `SCORE`

  - MIDI: `STD_MIDI`, `MIDI_SYSEX`, `SOUNDFONT`

  - Analysis: `HETRO`, `PVC`, `PVCEX`, `CVANAL`, `LPC`, `ATS`, `SDIF`

- Command-line interface (`cycsound` command):

  - `play` - Play CSD files in real-time

  - `render` - Render CSD to audio files (WAV, AIFF, FLAC, OGG)

  - `check` - Validate CSD syntax

  - `info` - Display Csound version information

  - `eval` - Evaluate orchestra code

- Static linking support for macOS (`make wheel-static` or `-C cmake.define.STATIC=ON`)

  - Bundles Csound and all audio codec libraries

  - Produces standalone wheel (~2MB) requiring no Csound installation

  - Only depends on system libraries and macOS frameworks

- CMakeLists.txt with platform-specific Csound library detection:

  - macOS: CsoundLib64 framework at `/Library/Frameworks/`

  - Windows: Csound6_x64 installation at `C:/Program Files/Csound6_x64/`

  - Linux: System `csound64` library

- Test suite with 36 tests covering:

  - Core API functions (version, options, compilation, performance)

  - CLI commands (play, render, check, info, eval)

  - Channel control and updates

  - Threading and recompilation

  - MIDI functionality

- GIL release support for all blocking operations, enabling true multi-threading

- GitHub Actions workflow for CI/CD with cibuildwheel

- PyPI publication support (`make publish`, `make publish-test`)

### Changed

- **Build system**: Migrated from setuptools/Cython to scikit-build-core/CMake

- **Project structure**: Reorganized to `src/cycsound/` layout

- **API naming**: Renamed `csoundInitialize()` to `initialize()` for consistency

- **GIL handling**: Added `nogil` declarations to all 219 C API functions in `csound.pxd`

- **Performance methods**: Now release the GIL during execution:

  - `perform()`, `perform_ksmps()`, `perform_buffer()`

  - `start()`, `stop()`, `cleanup()`, `reset()`

- **Compilation methods**: Now release the GIL during execution:

  - `compile_orc()`, `compile_orc_async()`, `eval_code()`

  - `compile_args()`, `compile()`, `compile_csd()`, `compile_csd_text()`

- **Score methods**: `read_score()`, `read_score_async()` now release the GIL

- **Threading primitives**: All blocking operations release the GIL:

  - `join_thread()`, `wait_thread_lock()`, `wait_thread_lock_no_timeout()`

  - `lock_mutex()`, `wait_barrier()`, `cond_wait()`, `sleep()`, `spin_lock()`

- **Status return types**: Functions now return `Status` enum instead of `int`:

  - `set_option()`, `udp_server_start()`, `udp_server_close()`, `upd_console()`

  - Allows comparison with `Status.SUCCESS`, `Status.ERROR`, etc.

### Fixed

- GIL contention issues that prevented effective multi-threading

- GUI freezing when calling blocking Csound operations

### API Coverage

- 98.6% coverage of the Csound C API (216/219 functions)

- Intentionally unwrapped (3 functions using `va_list`):

  - `csoundMessageV` - use `message()` instead

  - `csoundSetDefaultMessageCallback` - use `set_message_string_callback()` instead

  - `csoundSetMessageCallback` - use `set_message_string_callback()` instead

### Build Requirements

- Python >= 3.9

- scikit-build-core

- Cython

- CMake >= 3.15

- Csound 6.x installed:

  - macOS: CsoundLib64.framework in `/Library/Frameworks/`

  - Windows: Csound6_x64 in `C:/Program Files/`

  - Linux: libcsound64 development package

### Static Build Requirements (macOS only)

For `make wheel-static`:
- Homebrew with static libraries installed:

  - `brew install libsndfile flac opus libvorbis libogg mpg123 lame`

- Static libraries from CsoundLib64.framework:

  - `libCsoundLib64.a`, `libcsnd6.a`
