"""Csound plugins load from an installed wheel as well as a source build."""

import os
import sys

import pytest

import cycsound

PLUGIN_SUFFIX = {"darwin": ".dylib", "win32": ".dll"}.get(sys.platform, ".so")

# Realtime driver modules the shipped plugins register, per platform. On Linux
# rtalsa and rtjack load only if the host has ALSA or JACK, so none is assumed.
DRIVER_MODULES = {
    "darwin": {("auhal", "audio"), ("pa_cb", "audio"), ("coremidi", "midi")},
    "win32": {("pa_cb", "audio")},
}


def test_plugin_dir_selected():
    plugins = os.environ.get("OPCODE7DIR64")
    assert plugins and os.path.isdir(plugins)
    assert any(f.endswith(PLUGIN_SUFFIX) for f in os.listdir(plugins))


@pytest.mark.skipif(sys.platform not in DRIVER_MODULES,
                    reason="driver modules depend on the host's audio stack")
def test_driver_modules_registered():
    # Lists the modules registered at csoundCreate(); opens no device.
    cs = cycsound.Csound()
    modules = set()
    while (m := cs.get_module(len(modules))) is not None:
        modules.add(m)
    assert DRIVER_MODULES[sys.platform] <= modules


def test_plugin_opcode_compiles():
    # vco2 is a plugin opcode on Linux and built in on macOS.
    cs = cycsound.Csound()
    cs.set_option("-n")
    assert cs.compile_orc("instr 1\na1 vco2 0.1, 440\nout a1\nendin\n") == 0
