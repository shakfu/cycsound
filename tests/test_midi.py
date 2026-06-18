"""Example 6 - Generating a score with a Note class.

Build score events from Note objects and feed them to Csound 7 via
event_string(). Ported to the Csound 7 API, run non-realtime.
"""
from random import randint

import cycsound


def midi2pch(num):
    "Convert MIDI note numbers to Csound PCH format."
    return "%d.%02g" % (3 + (num // 12), num % 12)


class Note:
    def __init__(self, *args):
        self.pfields = list(args)

    def __str__(self):
        out = "i"
        for i in range(len(self.pfields)):
            if i == 4:
                out += " " + midi2pch(self.pfields[i])
            else:
                out += " " + str(self.pfields[i])
        return out


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


def test_midi():
    c = cycsound.Csound()
    c.set_option("-n")
    c.set_option("-d")
    c.compile_orc(orc)

    notes = []
    for i in range(13):
        notes.append(Note(1, i * .05, .05, 0.5, randint(60, 75)))

    sco = ""
    for n in notes:
        sco += "%s\n" % n

    c.event_string(sco)
    assert c.start() == 0
    while c.perform_ksmps() == 0:
        pass
