# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
