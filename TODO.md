# TODO

## Critical

## High

- [ ] Bundle the Csound driver plugins in the macOS and Windows wheels, as 0.2.2 did on Linux.
  0.2.2 macOS wheels ship only `.dylibs/CsoundLib64`. The framework's `Resources/Opcodes64` (`librtauhal`, `librtpa`, `libpmidi`, `libcmidi`, `libipmidi`, `libosc`, `libstdutil`, `libdeprecated`) and `libs/` (`libportaudio`, `libportmidi`, `liblo`) are missing. Windows wheels lack the 8 DLLs in `plugins64`. `csound64.dll` has no audio driver of its own, so realtime audio likely falls back to the dummy module. The offline test suite cannot detect this.
  - [x] Confirm on macOS (below). 0.2.2: `auhal` and `pa` both FAIL with the dummy module.
  - [x] Get the names of the 8 Windows `plugins64` DLLs (`innoextract` on `Csound7-windows_x86_64-7.0.0-7619.exe`, or log them in `wheels-windows-noplugins.yml`). From the arm64 zip (innoextract 1.9 cannot read the x64 installer): `rtpa`, `rtwinmm`, `rtwasapi`, `pmidi`, `ipmidi`, `osc`, `stdutil`, `deprecated`. All import only system DLLs.
  - [x] Copy the plugins and their libraries into `cycsound/plugins/` (`delocate` on macOS, `delvewheel --add-path` on Windows).
  - [x] Set `OPCODE7DIR64` in `__init__.py` on all platforms, not only Linux. Otherwise the macOS binary falls back to `/Applications/Csound/.../Opcodes64` and may load a mismatched system install.
  - [x] Add a device-free test that the realtime modules are present.
  - [ ] Confirm on Windows (below). The plugin list and the `OPCODE7DIR64` handling are untested there.
  - [ ] Once Windows module names are known, extend `DRIVER_MODULES["win32"]` in `tests/test_plugins.py` (now `pa_cb` only).

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

  **Windows check.** PowerShell, run outside the repo, with a wheel from this branch:

  1. Get a wheel. Either download the CI artifact (`gh run download <run-id> -n wheels-windows-latest`), or build locally with Csound 7 installed at `C:\Program Files\Csound7_x64`.
  2. Clear `OPCODE7DIR64`, or `__init__.py` will not override it. The Csound installer may also set it machine-wide (unverified):
     ```
     Remove-Item Env:OPCODE7DIR64 -ErrorAction SilentlyContinue
     [Environment]::GetEnvironmentVariable('OPCODE7DIR64', 'Machine')
     [Environment]::GetEnvironmentVariable('OPCODE7DIR64', 'User')
     ```
  3. Check the wheel holds 8 plugin DLLs, and compare the names with `C:\Program Files\Csound7_x64\plugins64`. Expected (from arm64): `rtpa`, `rtwinmm`, `rtwasapi`, `pmidi`, `ipmidi`, `osc`, `stdutil`, `deprecated`.
     ```
     python -m zipfile -l <wheel> | Select-String plugins
     ```
  4. Run the suite against the wheel. `test_driver_modules_registered` must pass:
     ```
     uv run python <repo>\scripts\test_wheel.py --wheel <wheel>
     ```
  5. List the registered modules, to fill in `DRIVER_MODULES["win32"]`:
     ```
     uv run --isolated --no-project --with <wheel> python -c "import cycsound; cs = cycsound.Csound(); print([cs.get_module(i) for i in range(20)])"
     ```
  6. Play a tone with each audio module from step 5 (`pa`, and probably `winmm` and `wasapi`):
     ```
     uv run --isolated --no-project --with <wheel> python <repo>\scripts\check_rtaudio.py pa
     ```
  7. If step 4 or 5 finds no modules, set `$env:OPCODE7DIR64` to the installed `cycsound\plugins` path and repeat. If that passes, `csound7_64.dll` does not see variables set from Python, probably because it links a static C runtime (inferred: it imports no CRT DLL). The fix then belongs in `__init__.py`, for example `set_global_env` or the `opcodedir` constructor argument.

## Medium

- [ ] add `hostData` -> pyobject to class constructor
- [ ] unittests (partially implemented)
- [ ] threaded / async / non-blocking performance
- [ ] complete wrapping of csound.h
- [ ] feature parity with `ctcsound.py`

## Low

- [ ] Report upstream: the `macos_build_installer` job in Csound's `.github/workflows/csound_builds.yml` builds PortMidi, PortAudio and liblo without `-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0`, so the framework's `libs/` copies require macOS 26.0. Once a release fixes this, drop `build_macos_deps` from `scripts/vendor_csound7.sh`.
