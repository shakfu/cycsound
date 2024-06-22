"""Example 3 - Using our own performance loop

In this example, we use a while loop to perform Csound one audio block at a time.
This technique is important to know as it will allow us to do further processing
safely at block boundaries.  We will explore the technique further in later examples.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import cycsound

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
    c = cycsound.Csound()
    c.set_option("-odac")
    c.compile_orc(orc)
    c.read_score(sco)
    c.start()
    while (c.perform_ksmps() == 0):
        pass
    c.stop()

