# TODO

## Critical

## High

- [ ] Bundle the Csound driver plugins in the macOS and Windows wheels, as 0.2.2 did on Linux.
  0.2.2 macOS wheels ship only `.dylibs/CsoundLib64`. The framework's `Resources/Opcodes64` (`librtauhal`, `librtpa`, `libpmidi`, `libcmidi`, `libipmidi`, `libosc`, `libstdutil`, `libdeprecated`) and `libs/` (`libportaudio`, `libportmidi`, `liblo`) are missing. Windows wheels lack the 8 DLLs in `plugins64`. `csound64.dll` has no audio driver of its own, so realtime audio likely falls back to the dummy module. The offline test suite cannot detect this.
  - [ ] Confirm on macOS (below).
  - [ ] Get the names of the 8 Windows `plugins64` DLLs (`innoextract` on `Csound7-windows_x86_64-7.0.0-7619.exe`, or log them in `wheels-windows-noplugins.yml`).
  - [ ] Copy the plugins and their libraries into `cycsound/plugins/` (`delocate` on macOS, `delvewheel --add-path` on Windows).
  - [ ] Set `OPCODE7DIR64` in `__init__.py` on all platforms, not only Linux. Otherwise the macOS binary falls back to `/Applications/Csound/.../Opcodes64` and may load a mismatched system install.
  - [ ] Add a device-free test that the realtime modules are present.

  **macOS check.** Run outside the repo, so the source build and `vendor/` are not used:

  1. If `/Applications/Csound/CsoundLib64.framework/Resources/Opcodes64` exists, rename `/Applications/Csound` first. Otherwise an OK result may come from the system install.
  2. Run:
     ```
     cd /tmp
     env -u OPCODE7DIR64 uv run --isolated --no-project --with cycsound==0.2.2 \
         python ~/projects/cycsound/scripts/check_rtaudio.py auhal
     env -u OPCODE7DIR64 uv run --isolated --no-project --with cycsound==0.2.2 \
         python ~/projects/cycsound/scripts/check_rtaudio.py pa
     ```
  3. Read the result:
     - `FAIL` with `unknown rtaudio module: '<name>', using dummy module` (exit 1) confirms the plugin is missing from the wheel.
     - `OK` and an audible 1 s tone (exit 0) means the module loaded, so the inference above is wrong for that module.
  4. Optional: run the full suite against the wheel with `scripts/test_wheel.py 0.2.2`.

## Medium

- [ ] add `hostData` -> pyobject to class constructor
- [ ] unittests (partially implemented)
- [ ] threaded / async / non-blocking performance
- [ ] complete wrapping of csound.h
- [ ] feature parity with `ctcsound.py`

## Low
