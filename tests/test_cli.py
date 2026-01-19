"""Tests for cycsound CLI."""

import subprocess
import tempfile
from pathlib import Path

import pytest


def run_cli(*args):
    """Run cycsound CLI and return result."""
    result = subprocess.run(
        ["uv", "run", "cycsound", *args],
        capture_output=True,
        text=True,
    )
    return result


class TestCLI:
    """Test CLI commands."""

    def test_help(self):
        """Test --help flag."""
        result = run_cli("--help")
        assert result.returncode == 0
        assert "cycsound" in result.stdout
        assert "play" in result.stdout
        assert "render" in result.stdout
        assert "check" in result.stdout
        assert "info" in result.stdout

    def test_version(self):
        """Test --version flag."""
        result = run_cli("--version")
        assert result.returncode == 0
        assert "cycsound" in result.stdout

    def test_info(self):
        """Test info command."""
        result = run_cli("info")
        assert result.returncode == 0
        assert "Csound version:" in result.stdout
        assert "API version:" in result.stdout

    def test_info_verbose(self):
        """Test info -v command."""
        result = run_cli("info", "-v")
        assert result.returncode == 0
        assert "MYFLT type:" in result.stdout

    def test_check_valid_file(self):
        """Test check command with valid CSD file."""
        result = run_cli("check", "tests/test1.csd")
        assert result.returncode == 0
        assert "OK:" in result.stdout

    def test_check_missing_file(self):
        """Test check command with missing file."""
        result = run_cli("check", "/nonexistent/file.csd")
        assert result.returncode == 1
        assert "Error:" in result.stderr
        assert "not found" in result.stderr

    def test_render(self):
        """Test render command."""
        with tempfile.TemporaryDirectory() as tmpdir:
            output_path = Path(tmpdir) / "output.wav"
            result = run_cli("render", "tests/test1.csd", "-o", str(output_path))
            assert result.returncode == 0
            assert output_path.exists()
            assert output_path.stat().st_size > 0

    def test_render_quiet(self):
        """Test render command with quiet flag."""
        with tempfile.TemporaryDirectory() as tmpdir:
            output_path = Path(tmpdir) / "output.wav"
            result = run_cli("render", "-q", "tests/test1.csd", "-o", str(output_path))
            assert result.returncode == 0
            assert output_path.exists()
            # Quiet mode should not print "Rendering:" or "Done:"
            assert "Rendering:" not in result.stdout
            assert "Done:" not in result.stdout

    def test_render_missing_file(self):
        """Test render command with missing file."""
        result = run_cli("render", "/nonexistent/file.csd")
        assert result.returncode == 1
        assert "Error:" in result.stderr

    def test_play_missing_file(self):
        """Test play command with missing file."""
        result = run_cli("play", "/nonexistent/file.csd")
        assert result.returncode == 1
        assert "Error:" in result.stderr

    def test_eval(self):
        """Test eval command."""
        result = run_cli("eval", "print 1 + 1")
        assert result.returncode == 0

    def test_no_command(self):
        """Test running without a command shows help."""
        result = run_cli()
        assert result.returncode == 0
        assert "usage:" in result.stdout.lower() or "usage:" in result.stderr.lower()
