"""Compile a more complex CSD (syntax check only).

diskgrain.csd targets realtime audio (-odac) and reads marimba.aif, so rather
than render it we verify that the Csound 7 compiler accepts it.
"""
import os

import cycsound

HERE = os.path.dirname(__file__)


def test_compile():
    c = cycsound.Csound()
    c.set_option("--syntax-check-only")
    c.set_option("-d")
    c.set_option("-m0")
    # diskgrain.csd references marimba.aif relatively; run from tests/.
    cwd = os.getcwd()
    os.chdir(HERE)
    try:
        assert c.compile_csd("diskgrain.csd") == 0
    finally:
        os.chdir(cwd)
