"""Example 1 - Simple compilation with Csound.

Create a Csound instance, compile a pre-existing CSD, then run it to
completion. Ported to the Csound 7 API (csoundCompile / csoundStart /
csoundPerformKsmps; there is no csoundPerform/csoundStop in Csound 7).
"""
import os

import cycsound

HERE = os.path.dirname(__file__)


def test_compile():
    c = cycsound.Csound()
    c.set_option("-n")  # non-realtime: no audio device needed
    c.set_option("-d")
    assert c.compile("dummy", os.path.join(HERE, "test1.csd")) == 0
    assert c.run() == 0
