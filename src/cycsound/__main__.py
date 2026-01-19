"""
cycsound CLI - Command-line interface for Csound operations.

Usage:
    cycsound play <file.csd>       Play a CSD file
    cycsound render <file.csd>     Render CSD to audio file
    cycsound info                  Show Csound version info
    cycsound check <file.csd>      Validate a CSD file
"""

import argparse
import sys
from pathlib import Path

from cycsound import Csound, get_version, get_api_version


def _setup_quiet(cs):
    """Configure Csound for quiet operation."""
    cs.set_message_level(0)  # Suppress all messages first
    cs.set_option("-d")  # Suppress displays
    cs.set_option("-m0")  # Minimal messages
    cs.set_option("-+msg_color=0")  # Disable color codes
    cs.set_option("-O null")  # Send output info to null


def cmd_play(args):
    """Play a CSD file in real-time."""
    csd_path = Path(args.file)
    if not csd_path.exists():
        print(f"Error: File not found: {csd_path}", file=sys.stderr)
        return 1

    cs = Csound()

    # Set options
    cs.set_option("-odac")  # Real-time audio output

    if args.quiet:
        _setup_quiet(cs)

    if args.input:
        cs.set_option(f"-iadc:{args.input}")

    if args.output:
        cs.set_option(f"-odac:{args.output}")

    # Compile and perform
    result = cs.compile_csd(str(csd_path))
    if result != 0:
        print(f"Error: Failed to compile {csd_path}", file=sys.stderr)
        return 1

    cs.start()

    try:
        while not cs.perform_ksmps():
            pass
    except KeyboardInterrupt:
        print("\nInterrupted by user")

    cs.cleanup()
    return 0


def cmd_render(args):
    """Render a CSD file to an audio file."""
    csd_path = Path(args.file)
    if not csd_path.exists():
        print(f"Error: File not found: {csd_path}", file=sys.stderr)
        return 1

    # Determine output filename
    if args.output:
        output_path = args.output
    else:
        output_path = csd_path.with_suffix(".wav")

    cs = Csound()

    # Set options
    cs.set_option(f"-o{output_path}")

    if args.format:
        cs.set_option(f"--format={args.format}")

    if args.sample_rate:
        cs.set_option(f"-r{args.sample_rate}")

    if args.ksmps:
        cs.set_option(f"-k{args.ksmps}")

    if args.quiet:
        _setup_quiet(cs)
    else:
        print(f"Rendering: {csd_path} -> {output_path}")

    # Compile and perform
    result = cs.compile_csd(str(csd_path))
    if result != 0:
        print(f"Error: Failed to compile {csd_path}", file=sys.stderr)
        return 1

    cs.start()

    try:
        while not cs.perform_ksmps():
            pass
    except KeyboardInterrupt:
        print("\nInterrupted by user", file=sys.stderr)
        cs.cleanup()
        return 1

    cs.cleanup()

    if not args.quiet:
        print(f"Done: {output_path}")

    return 0


def cmd_info(args):
    """Display Csound version information."""
    version = get_version()
    api_version = get_api_version()

    major = version // 1000
    minor = (version % 1000) // 10
    patch = version % 10

    print(f"Csound version: {major}.{minor}.{patch} ({version})")
    print(f"API version: {api_version}")

    if args.verbose:
        from cycsound import get_size_of_myflt
        myflt_size = get_size_of_myflt()
        myflt_type = "double" if myflt_size == 8 else "float"
        print(f"MYFLT type: {myflt_type} ({myflt_size} bytes)")

    return 0


def cmd_check(args):
    """Validate a CSD file without performing it."""
    csd_path = Path(args.file)
    if not csd_path.exists():
        print(f"Error: File not found: {csd_path}", file=sys.stderr)
        return 1

    cs = Csound()

    # Syntax check only
    cs.set_option("--syntax-check-only")

    if args.quiet:
        _setup_quiet(cs)
    else:
        cs.set_option("-d")
        cs.set_option("-m0")

    result = cs.compile_csd(str(csd_path))

    if result == 0:
        if not args.quiet:
            print(f"OK: {csd_path}")
        return 0
    else:
        if not args.quiet:
            print(f"FAILED: {csd_path}", file=sys.stderr)
        return 1


def cmd_eval(args):
    """Evaluate Csound orchestra code."""
    cs = Csound()
    cs.set_option("-n")  # No audio output

    if args.quiet:
        _setup_quiet(cs)
    else:
        cs.set_option("-d")
        cs.set_option("-m0")

    # Set up basic header if not provided
    code = args.code
    if "sr" not in code and "sr=" not in code:
        code = "sr = 44100\nksmps = 32\nnchnls = 2\n0dbfs = 1\n" + code

    result = cs.compile_orc(code)
    if result != 0:
        print("Error: Failed to compile orchestra code", file=sys.stderr)
        return 1

    # If code contains return statement, evaluate and print result
    if "return" in code.lower():
        try:
            value = cs.eval_code(code)
            print(value)
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1

    return 0


def main(argv=None):
    """Main entry point for the cycsound CLI."""
    parser = argparse.ArgumentParser(
        prog="cycsound",
        description="Csound CLI powered by cycsound",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  cycsound play myscore.csd           Play a CSD file
  cycsound render myscore.csd         Render to myscore.wav
  cycsound render -o out.wav file.csd Render to specific file
  cycsound check myscore.csd          Validate CSD syntax
  cycsound info                       Show Csound version
""",
    )

    parser.add_argument(
        "--version",
        action="version",
        version=f"cycsound {get_version() // 1000}.{(get_version() % 1000) // 10}",
    )

    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # Play command
    play_parser = subparsers.add_parser("play", help="Play a CSD file in real-time")
    play_parser.add_argument("file", help="CSD file to play")
    play_parser.add_argument("-q", "--quiet", action="store_true", help="Suppress output")
    play_parser.add_argument("-i", "--input", help="Audio input device")
    play_parser.add_argument("-o", "--output", help="Audio output device")
    play_parser.set_defaults(func=cmd_play)

    # Render command
    render_parser = subparsers.add_parser("render", help="Render CSD to audio file")
    render_parser.add_argument("file", help="CSD file to render")
    render_parser.add_argument("-o", "--output", help="Output audio file")
    render_parser.add_argument("-f", "--format", help="Output format (wav, aiff, flac, ogg)")
    render_parser.add_argument("-r", "--sample-rate", type=int, help="Sample rate override")
    render_parser.add_argument("-k", "--ksmps", type=int, help="ksmps override")
    render_parser.add_argument("-q", "--quiet", action="store_true", help="Suppress output")
    render_parser.set_defaults(func=cmd_render)

    # Info command
    info_parser = subparsers.add_parser("info", help="Show Csound version info")
    info_parser.add_argument("-v", "--verbose", action="store_true", help="Show detailed info")
    info_parser.set_defaults(func=cmd_info)

    # Check command
    check_parser = subparsers.add_parser("check", help="Validate a CSD file")
    check_parser.add_argument("file", help="CSD file to validate")
    check_parser.add_argument("-q", "--quiet", action="store_true", help="Suppress output")
    check_parser.set_defaults(func=cmd_check)

    # Eval command
    eval_parser = subparsers.add_parser("eval", help="Evaluate orchestra code")
    eval_parser.add_argument("code", help="Orchestra code to evaluate")
    eval_parser.add_argument("-q", "--quiet", action="store_true", help="Suppress output")
    eval_parser.set_defaults(func=cmd_eval)

    args = parser.parse_args(argv)

    if args.command is None:
        parser.print_help()
        return 0

    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
