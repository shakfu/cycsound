import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import pytest

# Example 4 - Using Csound's Performance Thread 

# In this example, we use a CsoundPerformanceThread to run Csound in 
# a native thread.  Using a native thread is important to get the best
# runtime performance for the audio engine.  It is especially important
# for languages such as Python that do not have true native threads
# and that use a Global Interpreter Lock. CsoundPerformanceThread has
# some convenient methods for handling events, but does not have
# features for doing regular processing at block boundaries.  In general,
# use CsoundPerformanceThread when the only kinds of communication you
# are doing with Csound are through events, and not using channels.

import csnd

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

@pytest.mark.skipif(not hasattr(csnd, 'CsoundPerformanceThread'),
                    reason="requires the CsoundPerformanceThread class")
def test_thread():
    sco = "i1 0 1"
    c = csnd.Csound()
    c.set_option("-odac")
    c.compile_orc(orc)
    c.read_score(sco)
    c.start()
    t = csnd.CsoundPerformanceThread(c.csound())
    t.play()
    t.join()
    c.stop()
    c.cleanup()
