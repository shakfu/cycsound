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
- **Host-implemented MIDI** I/O callbacks and the **unit generator API**
  (`ugen.h`: run opcodes directly from Python)
- **Array channels**, **circular buffers**, **graph display** and **file**
  callbacks, and C **opcode registration**
- **Context manager support** (calls `reset()` on exit)
- **GIL release** for the blocking operations (compile/start/perform/reset)
- **CLI** for common operations (play, render, check, info, eval)
- **macOS and Linux** support via a repo-local (vendored) Csound 7 runtime

## Building From Source

The wrapper tracks Csound **7.0.0**. Prerequisites:

- Python >= 3.10
- macOS (Apple Silicon or Intel) or Linux (x86_64)
- `curl` (or `wget`) and `unzip` to download the release binaries
- Linux only: `patchelf`, optional, to give the vendored opcode plugins an
  rpath to the vendored library

A package-manager `csound` is still Csound 6, whose host API this wrapper does
not target, so the build stages the official Csound 7 release binaries in a
repo-local `vendor/` directory instead. Any Csound 6 install on the machine is
left untouched.

- **macOS**: the release ships a `.pkg` whose `CsoundLib64.framework` has an
  absolute install name. The framework is extracted to
  `vendor/CsoundLib64.framework` and its install id is repointed at that path,
  so nothing is written to `/Library/Frameworks`.
- **Linux**: the `linux-minimal` release ships `libcsound64.so` plus its opcode
  plugins. They are staged as `vendor/lib/` and `vendor/plugins/`, and the
  extension is built with an rpath to `vendor/lib`. That release carries no
  headers, so the build uses the repo-local `include/` directory, which tracks
  the same tag.

The runtime is fetched automatically when missing. The `make` targets (`sync`,
`build`, `test`) carry an order-only prerequisite that runs the vendoring
script, and CMake runs it during configure as well (so `pip install .` /
`uv build`, which bypass `make`, are covered too). The usual flow is just:

```bash
git clone https://github.com/shakfu/cycsound.git
cd cycsound

make sync     # initial setup
make build    # auto-vendors the Csound 7 runtime on first build
```

To vendor manually (or pin a different tag), run the script directly:

```bash
scripts/vendor_csound7.sh                 # default tag (7.0.0)
scripts/vendor_csound7.sh 7.0.0-beta.18   # explicit tag
```

> Windows builds still reference a system Csound 7 install in `CMakeLists.txt`
> (`C:/Program Files/Csound7_x64`, overridable via `CSOUND_ROOT`) and have not
> been updated for the vendoring flow.

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

On **macOS** the built-in opcodes work out of the box, and the vendored
framework's plugin opcodes live in
`vendor/CsoundLib64.framework/Resources/Opcodes64`. To load them (for realtime
audio/MIDI modules such as `rtauhal`/`portaudio`, etc.), point the instance at
that directory:

```python
cs = cycsound.Csound(opcodedir="vendor/CsoundLib64.framework/Resources/Opcodes64")
```

On **Linux** the release is a minimal build whose opcode library ships as
external plugins, so most opcodes (`vco2`, `moogladder`, `diskgrain`, the
realtime modules, ...) come from `vendor/plugins`. Two things make that work
and both are handled by `cycsound/__init__.py` on import:

- `OPCODE7DIR64` is pointed at `vendor/plugins` when it is unset and that
  directory exists (a source build). Set the variable yourself to override.
- The extension is loaded with `RTLD_GLOBAL`, because the plugins resolve
  Csound symbols out of the global symbol namespace. Without it they fail to
  register silently and orchestras using their opcodes do not compile.

Note that Csound reads `OPCODE7DIR64` when the instance is created, so set it
(or call `cycsound.set_global_env("OPCODE7DIR64", ...)`) before constructing a
`Csound`.

## API Reference

### Module-level functions

| Function | Description |
|----------|-------------|
| `get_version()` | Csound version times 1000 (7.00.0 -> 7000) |
| `get_size_of_myflt()` | Size of MYFLT in bytes (4 or 8) |
| `initialize(flags=0)` | Initialize the library (rarely needed) |
| `set_global_env(name, value)` | Set a process-wide Csound env var (`None` deletes) |
| `sleep(milliseconds)` | Suspend the calling thread (releases the GIL) |

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
cs.set_audio_channel(name, block) / cs.get_audio_channel(name)  # ksmps samples
cs.set_control_channel_hints(name, behav, dflt=, min=, max=, ...)
cs.get_control_channel_hints(name)      # -> dict, or None if unset
cs.list_channels() / cs.lock_channel(name) / cs.unlock_channel(name)
cs.get_channel_datasize(name) / cs.get_channel_var_type_name(name)

# Utilities
cs.run_utility("lpanal", *args)

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

# Control channel hint behaviours
cycsound.ChannelBehavior.NO_HINTS  # 0
cycsound.ChannelBehavior.INT       # 1
cycsound.ChannelBehavior.LIN       # 2
cycsound.ChannelBehavior.EXP       # 3

# Message types / colors (for message_special)
cycsound.Msg.DEFAULT / cycsound.Msg.ERROR / cycsound.Msg.WARNING
cycsound.Color.FG_RED / cycsound.Color.FG_GREEN / cycsound.Color.FG_BOLD
```

## Development

```bash
make sync                   # initial environment setup (auto-vendors Csound 7)
make build                  # rebuild after source changes
make test                   # run the test suite
make test-cli               # CLI tests only
make vendor                 # (re)fetch the Csound 7 runtime explicitly
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
