"""Example 2 - Compilation with Csound without CSD

In this example, we move from using an external CSD file to 
embedding our Csound ORC and SCO code within our Python project.
Besides allowing encapsulating the code within the same file,
using the CompileOrc() and CompileSco() API calls is useful when
the SCO or ORC are generated, or perhaps coming from another 
source, such as from a database or network.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

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

def test_compile_text():
    sco = "i1 0 1"
    c = csnd.Csound()
    c.set_option("-odac")
    c.compile_orc(orc)
    c.read_score(sco)
    c.start()
    c.perform()
    c.stop()

