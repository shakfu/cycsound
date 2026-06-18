# cycsound

Cython bindings for the Csound 7 API.

## Overview

cycsound is a Cython wrapper for the [Csound](https://csound.com/) audio
synthesis library, providing Python bindings for the Csound 7 `csound.h` C API.
It offers an alternative to the default ctypes-based `ctcsound.py` wrapper.

> **Note:** This branch targets **Csound 7** (currently in beta). Csound 7
> reworked the host C API substantially relative to Csound 6: `csoundPerform`,
> `csoundStop`, `csoundCleanup`, `csoundReadScore`, the `csoundScoreEvent*`
> family, and the writable `CSOUND_PARAMS` model were all removed or replaced.
> The Python API here mirrors the Csound 7 surface directly. See the
> [CHANGELOG](CHANGELOG.md) for the full migration notes.

## Features

- **Csound 7 host API** coverage for the common host operations (compile,
  perform, events, channels, tables, score, messages, UDP server)
- **Context manager support** (calls `reset()` on exit)
- **GIL release** for the blocking operations (compile/start/perform/reset)
- **CLI** for common operations (play, render, check, info, eval)
- **macOS** support via a repo-local (vendored) Csound 7 framework

## Building From Source

Prerequisites:

- Python >= 3.10
- macOS (Apple Silicon or Intel)
- `curl` (preinstalled on macOS) to download the beta framework

The Csound 7 macOS release ships as a `.pkg` whose framework has an absolute
install name. The vendoring step downloads the public release asset over plain
HTTPS (no GitHub account needed), extracts the `CsoundLib64.framework` into a
repo-local `vendor/` directory, and repoints its install id so the built
extension can find it at runtime -- without touching `/Library/Frameworks`
(where a Csound 6 install can remain untouched).

The framework is fetched automatically when missing. The `make` targets
(`sync`, `build`, `test`) carry an order-only prerequisite that runs the
vendoring script if `vendor/CsoundLib64.framework` is absent, and CMake runs it
during configure as well (so `pip install .` / `uv build`, which bypass `make`,
are covered too). The usual flow is just:

```bash
git clone https://github.com/shakfu/cycsound.git
cd cycsound

make sync     # initial setup
make build    # auto-vendors the Csound 7 framework on first build
```

To vendor manually (or pin a different beta tag), run the script directly:

```bash
scripts/vendor_csound7.sh                 # default tag
scripts/vendor_csound7.sh 7.0.0-beta.16   # explicit tag
```

> Linux and Windows builds still reference a system Csound install in
> `CMakeLists.txt` and have not yet been updated for the Csound 7 vendoring
> flow.

## Command-Line Interface

```bash
# Play a CSD file in real-time
cycsound play myscore.csd

# Render to an audio file
cycsound render myscore.csd                    # Creates myscore.wav
cycsound render -o output.wav myscore.csd      # Specify output file
cycsound render -f flac -r 48000 myscore.csd   # FLAC format, 48kHz

# Validate CSD syntax
cycsound check myscore.csd

# Show Csound version info
cycsound info
cycsound info -v

# Evaluate orchestra code
cycsound eval "print 1 + 1"
```

## Quick Start

```python
import cycsound

# Using the context manager (reset() is called automatically on exit)
with cycsound.Csound() as cs:
    cs.set_option("-odac")  # real-time audio output
    cs.set_option("-d")     # suppress displays
    cs.compile_orc("""
sr = 44100
ksmps = 32
nchnls = 2
0dbfs = 1

instr 1
    asig oscili 0.5, 440
    outs asig, asig
endin
""")
    cs.event_string("i1 0 2")  # add a score event (replaces read_score)
    cs.run()                   # start() + perform to the end of the score

# Manual performance loop
with cycsound.Csound() as cs:
    cs.compile_csd("myscore.csd")
    cs.start()
    while not cs.perform_ksmps():
        pass  # process each k-cycle
```

### Plugin opcodes / realtime modules

Built-in opcodes work out of the box. The vendored framework's plugin opcodes
live in `vendor/CsoundLib64.framework/Resources/Opcodes64`. To load them (for
realtime audio/MIDI modules such as `rtauhal`/`portaudio`, etc.), point the
instance at that directory:

```python
cs = cycsound.Csound(opcodedir="vendor/CsoundLib64.framework/Resources/Opcodes64")
```

## API Reference

### Module-level functions

| Function | Description |
|----------|-------------|
| `get_version()` | Csound version times 1000 (7.00.0 -> 7000) |
| `get_size_of_myflt()` | Size of MYFLT in bytes (4 or 8) |
| `initialize(flags=0)` | Initialize the library (rarely needed) |

### Csound class

```python
cs = cycsound.Csound(host_data=None, opcodedir=None)

# Compilation
cs.compile_orc(orc, async_=False)       # compile orchestra code
cs.compile_csd(filename)                # compile a CSD file
cs.compile_csd_text(csd_string)         # compile CSD code from a string
cs.compile(*args)                       # csoundCompile with argv
cs.eval_code(code)                      # evaluate global i-time code -> float
cs.parse_orc(orc) / cs.compile_tree(t)  # parse to a Tree, then compile

# Performance
cs.start()                              # prepare for performance
cs.perform_ksmps()                      # perform one control period
cs.run()                                # start() + loop perform_ksmps()
cs.reset()                              # reset for a new performance

# Events and score (replaces read_score / score_event)
cs.event_string("i1 0 1")               # score/realtime events from a string
cs.event(cycsound.EventType.INSTR, [1, 0, 1])  # event from p-fields
cs.get_instr_number("Bass")             # number for a named instrument

# Attributes
cs.get_sr() / cs.get_kr() / cs.get_ksmps() / cs.get_kcounter()
cs.get_nchnls() / cs.get_nchnls_input() / cs.get_channels(is_input=0)
cs.get_0dBFS() / cs.get_A4() / cs.err_cnt()
cs.set_option(option) / cs.get_params()  # get_params() is read-only

# Channels
cs.set_control_channel(name, value) / cs.get_control_channel(name)
cs.set_string_channel(name, value) / cs.get_string_channel(name)
cs.list_channels() / cs.lock_channel(name) / cs.unlock_channel(name)

# Tables
cs.table_length(n) / cs.get_table(n) / cs.set_table(n, values)
```

### Enums

```python
# Return status codes
cycsound.Status.SUCCESS        # 0
cycsound.Status.ERROR          # -1
# ... INITIALIZATION, PERFORMANCE, MEMORY, SIGNAL

# csoundEvent() event types
cycsound.EventType.INSTR       # 0 (i-event)
cycsound.EventType.TABLE       # 1 (f-event)
cycsound.EventType.END         # 2 (e-event)
cycsound.EventType.ADVANCE     # 3

# Channel kinds / direction flags (bus interface)
cycsound.ChannelType.CONTROL   # 1
cycsound.ChannelType.AUDIO     # 2
cycsound.ChannelType.STRING    # 3
cycsound.ChannelType.INPUT     # 16
cycsound.ChannelType.OUTPUT    # 32

# Message types / colors (for message_special)
cycsound.Msg.DEFAULT / cycsound.Msg.ERROR / cycsound.Msg.WARNING
cycsound.Color.FG_RED / cycsound.Color.FG_GREEN / cycsound.Color.FG_BOLD
```

## Development

```bash
make sync                   # initial environment setup (auto-vendors framework)
make build                  # rebuild after source changes
make test                   # run the test suite
make test-cli               # CLI tests only
make vendor                 # (re)fetch the Csound 7 framework explicitly
```

## Rationale

This project provides an alternative to the default ctypes-based wrapper.
[Cython](https://cython.readthedocs.io/) offers better performance for tight
loops, direct C-level access, and the ability to release the GIL for true
multi-threading.

## Related Projects

- [ctcsound](https://github.com/csound/csound/blob/develop/interfaces/ctcsound.py) - Official ctypes-based Python wrapper
- [Csound](https://csound.com/) - The Csound audio synthesis system

## License

See [LICENSE](LICENSE) file.
