"""Example 3 - Using our own performance loop.

Perform Csound one audio block at a time, which allows processing at block
boundaries. Ported to the Csound 7 API.
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


def test_loop():
    sco = "i1 0 0.2"
    c = cycsound.Csound()
    c.set_option("-n")
    c.set_option("-d")
    c.compile_orc(orc)
    c.event_string(sco)
    assert c.start() == 0
    while c.perform_ksmps() == 0:
        pass
