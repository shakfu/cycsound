"""Example 4 - Using Csound's Performance Thread 

In this example, we use a CsoundPerformanceThread to run Csound in 
a native thread.  Using a native thread is important to get the best
runtime performance for the audio engine.  It is especially important
for languages such as Python that do not have true native threads
and that use a Global Interpreter Lock. CsoundPerformanceThread has
some convenient methods for handling events, but does not have
features for doing regular processing at block boundaries.  In general,
use CsoundPerformanceThread when the only kinds of communication you
are doing with Csound are through events, and not using channels.
"""

import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import cycsound
import pytest

# Defining our Csound ORC code within a triple-quoted, multiline String
orc = """
sr=44100
ksmps=32
nchnls=2
0dbfs=1

instr 1 
aout vco2 0.5, 440
outs aout, aout
endin"""

def test_thread():
    # Csound 7: events are queued with event_string() and the thread wraps
    # the Csound object. -n replaces -odac so the test needs no audio device.
    sco = "i1 0 1"
    c = cycsound.Csound()
    c.set_option("-n")
    c.compile_orc(orc)
    c.event_string(sco)
    assert c.start() == 0
    t = cycsound.CsoundPerformanceThread(c)
    t.play()
    assert t.join() > 0  # end of score
