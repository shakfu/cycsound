# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-01-19

### Added

- Initial scikit-build-core based build system
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
- Test suite with 31 tests covering:
  - Core API functions (version, options, compilation, performance)
  - CLI commands (play, render, check, info, eval)
  - Channel control and updates
  - Threading and recompilation
  - MIDI functionality
- GIL release support for all blocking operations, enabling true multi-threading

### Changed

- **Build system**: Migrated from setuptools/Cython to scikit-build-core/CMake
- **Project structure**: Reorganized to `src/cycsound/` layout
- **GIL handling**: Added `nogil` declarations to all 177 C API functions in `csound.pxd`
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

### Fixed

- GIL contention issues that prevented effective multi-threading
- GUI freezing when calling blocking Csound operations

### API Coverage

- 91% coverage of the Csound C API (161/177 functions)
- Intentionally unwrapped: `va_list`-based message callbacks (use message buffer API instead)

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
