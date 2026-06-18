"""Example 5 - Generating a score.

Generate score events programmatically and feed them to Csound 7 via
event_string(). Ported to the Csound 7 API and run non-realtime.
"""
from random import randint

import cycsound

orc = """
sr=44100
ksmps=32
nchnls=2
0dbfs=1

instr 1
ipch = cps2pch(p5, 12)
kenv linsegr 0, .05, 1, .05, .7, .4, 0
aout vco2 p4 * kenv, ipch
aout moogladder aout, 2000, 0.25
outs aout, aout
endin"""


def test_generate():
    c = cycsound.Csound()
    c.set_option("-n")
    c.set_option("-d")
    c.compile_orc(orc)

    # Build a score string from an intermediate list-of-lists.
    vals = []
    for i in range(13):
        vals.append([1, i * .05, .05, 0.5, "8.%02g" % (randint(0, 15))])
    vals = ["i" + " ".join(map(str, a)) for a in vals]
    sco = "\n".join(vals)

    c.event_string(sco)
    assert c.start() == 0
    while c.perform_ksmps() == 0:
        pass
