"""Opcode plugins load from an installed wheel as well as a source build."""

import os
import sys

import pytest

import cycsound

linux_only = pytest.mark.skipif(
    not sys.platform.startswith("linux"),
    reason="only Linux ships opcodes as external plugins",
)


@linux_only
def test_plugin_dir_selected():
    plugins = os.environ.get("OPCODE7DIR64")
    assert plugins and os.path.isdir(plugins)
    assert any(f.endswith(".so") for f in os.listdir(plugins))


def test_plugin_opcode_compiles():
    # vco2 is a plugin opcode on Linux and built in on macOS.
    cs = cycsound.Csound()
    cs.set_option("-n")
    assert cs.compile_orc("instr 1\na1 vco2 0.1, 440\nout a1\nendin\n") == 0
