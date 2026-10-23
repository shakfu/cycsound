#!/usr/bin/env python3
"""Run the current tests/ against a cycsound wheel released on PyPI.

Usage:
    scripts/test_wheel.py [version] [--python X.Y] [-- pytest args...]

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
                        help="cycsound version to test (default: latest)")
    parser.add_argument("--python", default="{}.{}".format(*sys.version_info),
                        help="Python version for the venv (default: %(default)s)")
    argv = sys.argv[1:]
    split = argv.index("--") if "--" in argv else len(argv)
    args = parser.parse_args(argv[:split])
    pytest_args = argv[split + 1:] or ["tests", "-q"]

    if shutil.which("uv") is None:
        sys.exit("error: uv not found on PATH")

    spec = f"cycsound=={args.version}" if args.version else "cycsound"

    # A caller's OPCODE7DIR64 or PYTHONPATH would bypass the wheel's own files.
    env = {k: v for k, v in os.environ.items()
           if k not in ("OPCODE7DIR64", "PYTHONPATH", "VIRTUAL_ENV")}

    with tempfile.TemporaryDirectory(prefix="cycsound-wheel-") as tmp:
        tmp = Path(tmp)
        venv = tmp / "venv"
        python = venv / ("Scripts/python.exe" if os.name == "nt" else "bin/python")

        if run(["uv", "venv", "-q", "--python", args.python, venv], env=env):
            return 1
        if run(["uv", "pip", "install", "-q", "--python", python, "--refresh",
                "--only-binary", "cycsound", spec, "pytest"], env=env):
            return 1

        shutil.copytree(ROOT / "tests", tmp / "tests",
                        ignore=shutil.ignore_patterns("__pycache__"))
        run([python, "-c",
             "import importlib.metadata as m, cycsound; "
             "print('cycsound', m.version('cycsound'), 'from', cycsound.__file__)"],
            cwd=tmp, env=env)
        return run([python, "-m", "pytest", *pytest_args],
                   cwd=tmp, env=env)


if __name__ == "__main__":
    sys.exit(main())
