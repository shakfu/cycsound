"""Example 2 - Compilation with Csound without a CSD.

Embed the orchestra and score as Python strings and feed them to Csound 7 with
compile_orc() and event_string() (the latter replaces the old read_score()).
"""
import cycsound

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
    sco = "i1 0 0.2"
    c = cycsound.Csound()
    c.set_option("-n")  # non-realtime
    c.set_option("-d")
    assert c.compile_orc(orc) == 0
    c.event_string(sco)
    assert c.run() == 0
