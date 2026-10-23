#!/usr/bin/env python3
"""Run the current tests/ against a released or local cycsound wheel.

Usage:
    scripts/test_wheel.py [version] [--python X.Y] [-- pytest args...]
    scripts/test_wheel.py --wheel dist/cycsound-*.whl [-- pytest args...]

Creates a throwaway uv venv, installs the wheel (never an sdist), copies
tests/ to a temp directory and runs pytest there, as cibuildwheel does.
Running outside the repo keeps src/ and vendor/ off the import path.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def run(cmd, **kwargs):
    print("+", " ".join(map(str, cmd)), flush=True)
    return subprocess.run(cmd, **kwargs).returncode


def main():
    parser = argparse.ArgumentParser(
        description=__doc__.splitlines()[0],
        epilog="Arguments after -- go to pytest and replace the default `tests -q`.")
    parser.add_argument("version", nargs="?",
                        help="PyPI version to test (default: latest)")
    parser.add_argument("--wheel", type=Path,
                        help="local wheel file to test instead of a PyPI release")
    parser.add_argument("--python",
                        help="Python version for the venv (default: the wheel's "
                             "cpXY tag, else this interpreter's)")
    argv = sys.argv[1:]
    split = argv.index("--") if "--" in argv else len(argv)
    args = parser.parse_args(argv[:split])
    pytest_args = argv[split + 1:] or ["tests", "-q"]

    if shutil.which("uv") is None:
        sys.exit("error: uv not found on PATH")

    if args.wheel:
        if args.version:
            parser.error("give a version or --wheel, not both")
        if not args.wheel.is_file():
            parser.error(f"no such wheel: {args.wheel}")
        # Wheel filename: name-version-cpXY-abi-platform.whl. uv installs a
        # wheel given by path even when its platform tag does not match.
        tag, platform = args.wheel.stem.split("-")[2::2]
        os_tag = {"darwin": "macosx", "win32": "win"}.get(sys.platform, "linux")
        if os_tag not in platform:
            parser.error(f"{args.wheel.name} is not a {os_tag} wheel")
        spec = str(args.wheel.resolve())
        python = args.python or f"{tag[2]}.{tag[3:]}"
    else:
        spec = f"cycsound=={args.version}" if args.version else "cycsound"
        python = args.python or "{}.{}".format(*sys.version_info)

    # A caller's OPCODE7DIR64 or PYTHONPATH would bypass the wheel's own files.
    env = {k: v for k, v in os.environ.items()
           if k not in ("OPCODE7DIR64", "PYTHONPATH", "VIRTUAL_ENV")}

    with tempfile.TemporaryDirectory(prefix="cycsound-wheel-") as tmp:
        tmp = Path(tmp)
        venv = tmp / "venv"
        venv_python = venv / ("Scripts/python.exe" if os.name == "nt" else "bin/python")

        if run(["uv", "venv", "-q", "--python", python, venv], env=env):
            return 1
        if run(["uv", "pip", "install", "-q", "--python", venv_python, "--refresh",
                "--only-binary", "cycsound", spec, "pytest"], env=env):
            return 1

        shutil.copytree(ROOT / "tests", tmp / "tests",
                        ignore=shutil.ignore_patterns("__pycache__"))
        run([venv_python, "-c",
             "import importlib.metadata as m, cycsound; "
             "print('cycsound', m.version('cycsound'), 'from', cycsound.__file__)"],
            cwd=tmp, env=env)
        return run([venv_python, "-m", "pytest", *pytest_args],
                   cwd=tmp, env=env)


if __name__ == "__main__":
    sys.exit(main())
