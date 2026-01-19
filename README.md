# cycsound

Cython bindings for the Csound 6.x API.

## Overview

cycsound is a Cython wrapper for the [Csound](https://csound.com/) audio synthesis library, providing Python bindings for the `csound.h` C API. It offers an alternative to the default ctypes-based `ctcsound.py` wrapper included with Csound.

## Features

- **91% API coverage** of the Csound C API (161/177 functions)
- **GIL release** for all blocking operations (enables true multi-threading)
- **Static linking support** on macOS (standalone wheels without Csound installation)
- **Platform support**: macOS, Linux, Windows

## Installation

```sh
pip install cycsound
```

## Building From Source

Prerequisites:

- Python >= 3.9
- Csound 6.x installed:
  - **macOS**: CsoundLib64.framework in `/Library/Frameworks/`
  - **Linux**: `libcsound64-dev` package
  - **Windows**: Csound6_x64 in `C:/Program Files/`

```bash
# Clone the repository
git clone https://github.com/yourusername/cycsound.git
cd cycsound

# Install in development mode
make sync

# Or install directly
pip install .
```

### Building Wheels

```bash
# Dynamic linking (requires Csound at runtime)
make wheel

# Static linking - standalone wheel (macOS only)
make wheel-static
```

## Command-Line Interface

cycsound includes a CLI for common Csound operations:

```bash
# Play a CSD file
cycsound play myscore.csd

# Render to audio file
cycsound render myscore.csd                    # Creates myscore.wav
cycsound render -o output.wav myscore.csd      # Specify output file
cycsound render -f flac -r 48000 myscore.csd   # FLAC format, 48kHz

# Validate CSD syntax
cycsound check myscore.csd

# Show Csound version info
cycsound info
cycsound info -v    # Verbose output

# Get help
cycsound --help
cycsound play --help
```

### CLI Commands

| Command | Description |
|---------|-------------|
| `play <file>` | Play CSD file in real-time |
| `render <file>` | Render CSD to audio file |
| `check <file>` | Validate CSD syntax |
| `info` | Show Csound version |
| `eval <code>` | Evaluate orchestra code |

### Common Options

| Option | Description |
|--------|-------------|
| `-q, --quiet` | Suppress output |
| `-o, --output` | Output file/device |
| `-h, --help` | Show help |

## Quick Start

```python
import cycsound

# Get Csound version
print(f"Csound version: {cycsound.get_version()}")

# Create a Csound instance
cs = cycsound.Csound()

# Set options
cs.set_option("-odac")  # Real-time audio output
cs.set_option("-d")     # Suppress displays

# Compile orchestra code
cs.compile_orc("""
sr = 44100
ksmps = 32
nchnls = 2
0dbfs = 1

instr 1
    asig oscil 0.5, 440
    outs asig, asig
endin
""")

# Read score
cs.read_score("i1 0 2")

# Start and perform
cs.start()
while not cs.perform_ksmps():
    pass
cs.cleanup()
```

## API Reference

### Module-level Functions

| Function | Description |
|----------|-------------|
| `get_version()` | Returns Csound version (e.g., 6180 for 6.18.0) |
| `get_api_version()` | Returns API version |
| `get_size_of_myflt()` | Returns size of MYFLT type (4 or 8) |
| `csoundInitialize(flags)` | Initialize Csound library |
| `set_opcode_dir(path)` | Set opcode directory override |

### Csound Class

Core methods for audio synthesis:

```python
cs = cycsound.Csound()

# Compilation
cs.compile_orc(orc_string)      # Compile orchestra code
cs.compile_csd(filename)        # Compile CSD file
cs.compile_csd_text(csd_string) # Compile CSD from string
cs.read_score(score_string)     # Read score events

# Performance
cs.start()           # Prepare for performance
cs.perform()         # Perform entire score (blocks)
cs.perform_ksmps()   # Perform one control period
cs.perform_buffer()  # Perform one buffer
cs.stop()            # Stop performance
cs.cleanup()         # Close audio/MIDI devices
cs.reset()           # Reset for new performance

# Configuration
cs.set_option(option)           # Set command-line option
cs.get_sr() / cs.get_kr()       # Get sample/control rate
cs.get_ksmps() / cs.get_nchnls() # Get ksmps/channels

# Channels
cs.set_control_channel(name, value)
cs.get_control_channel(name)
cs.set_string_channel(name, value)
cs.get_string_channel(name)
```

### Enums

```python
cycsound.Msg.DEFAULT   # Standard message
cycsound.Msg.ERROR     # Error message
cycsound.Msg.WARNING   # Warning message

cycsound.Color.FG_RED  # Foreground colors
cycsound.Color.FG_GREEN
cycsound.Color.FG_BOLD # Text attributes
```

## Development

### Setup

```bash
# Initial setup
make sync

# Rebuild after code changes
make build

# Run tests
make test          # All tests
make test-cli      # CLI tests only
```

### Available Make Targets

| Target | Description |
|--------|-------------|
| `make` / `make build` | Build/rebuild the extension |
| `make sync` | Initial environment setup |
| `make test` | Run test suite |
| `make wheel` | Build wheel (dynamic linking) |
| `make wheel-static` | Build standalone wheel (macOS) |
| `make clean` | Remove build artifacts |
| `make help` | Show all targets |

### Static Build Requirements (macOS)

For `make wheel-static`, install dependencies via Homebrew:

```bash
brew install libsndfile flac opus libvorbis libogg mpg123 lame
```

## Rationale

This project provides an alternative to the default ctypes-based wrapper. [Cython](https://cython.readthedocs.io/) offers several advantages over ctypes:

- Better performance for tight loops
- Direct C-level access to Csound internals
- Ability to release the GIL for true multi-threading
- Static linking for self-contained distribution

For more details, see this [comparison of wrapping approaches](https://stackoverflow.com/questions/1942298/wrapping-a-c-library-in-python-c-cython-or-ctypes).

## Status

- [x] Wrap enough to play arbitrary CSD files
- [x] Build static variant as wheel (macOS only)
- [x] 91% coverage of csound.h API
- [x] GIL release for all blocking operations
- [x] scikit-build-core based build system
- [x] Test suite (31 tests: core API, CLI, channels, threading)
- [ ] Complete wrapping of csound.h (remaining: va_list callbacks)
- [ ] Include plugin support in wheel
- [ ] Async/non-blocking performance helpers
- [ ] Feature parity with ctcsound.py

## Related Projects

- [ctcsound](https://github.com/csound/csound/blob/develop/interfaces/ctcsound.py) - Official ctypes-based Python wrapper
- [Csound](https://csound.com/) - The Csound audio synthesis system

## License

See [LICENSE](LICENSE) file.
