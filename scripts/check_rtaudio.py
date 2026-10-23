#!/usr/bin/env python3
"""Check that a realtime audio module loads: play a 440 Hz tone to -odac.

Usage:
    scripts/check_rtaudio.py [module] [--seconds N]

module is a -+rtaudio name (auhal, pa, alsa, jack, ...); omit it for
Csound's default. Exits 1 if Csound falls back to its dummy module, which
happens when the module's plugin is missing. start() returns 0 either way.

To check a released wheel rather than the source build, run it outside
the repo:
    cd /tmp && env -u OPCODE7DIR64 uv run --isolated --no-project \\
        --with cycsound==0.2.2 python /path/to/scripts/check_rtaudio.py auhal
"""

import argparse
import os
import sys

import cycsound

ORC = """
sr = 44100
ksmps = 64
nchnls = 2
0dbfs = 1
instr 1
  a1 oscili 0.1, 440
  outs a1, a1
endin
"""

# Default plugin path compiled into the macOS framework binary.
MACOS_SYSTEM_OPCODES = "/Applications/Csound/CsoundLib64.framework/Resources/Opcodes64"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("module", nargs="?", help="-+rtaudio module (default: Csound's)")
    parser.add_argument("--seconds", type=float, default=1.0)
    args = parser.parse_args()

    print("cycsound:", cycsound.__file__)
    print("OPCODE7DIR64:", os.environ.get("OPCODE7DIR64"))
    if sys.platform == "darwin" and os.path.isdir(MACOS_SYSTEM_OPCODES):
        print(f"warning: {MACOS_SYSTEM_OPCODES} exists; plugins may load "
              "from the system install, not the wheel")

    messages = []
    cs = cycsound.Csound()
    cs.set_message_callback(lambda attr, text: messages.append(text))
    cs.set_option("-odac")
    if args.module:
        cs.set_option(f"-+rtaudio={args.module}")
    cs.compile_orc(ORC)
    cs.event_string(f"i1 0 {args.seconds}")
    rc = cs.start()
    if rc == 0:
        for _ in range(int(args.seconds * 44100 / 64)):
            if cs.perform_ksmps():
                break

    log = "".join(messages)
    relevant = [ln for ln in log.splitlines()
                if any(k in ln.lower() for k in ("rtaudio", "dummy", "error", "module"))]
    print("\n".join(relevant))

    if "dummy module" in log or rc != 0:
        print(f"FAIL: realtime audio module {args.module or '(default)'} "
              f"not available (start={rc})")
        return 1
    print(f"OK: realtime audio module {args.module or '(default)'} loaded")
    return 0


if __name__ == "__main__":
    sys.exit(main())
