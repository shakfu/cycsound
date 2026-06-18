"""Example 7 - Communicating continuous values via Csound's channel system.

Drive two control channels (amplitude and frequency) from the host while
performing one block at a time. Ported to the Csound 7 API, run non-realtime.
"""
from random import randint, random

import cycsound


class RandomLine:
    def __init__(self, base, range_):
        self.curVal = 0.0
        self.reset()
        self.base = base
        self.range = range_

    def reset(self):
        self.dur = randint(256, 512)
        self.end = random()
        self.increment = (self.end - self.curVal) / self.dur

    def get_value(self):
        self.dur -= 1
        if self.dur < 0:
            self.reset()
        ret = self.curVal
        self.curVal += self.increment
        return self.base + (self.range * ret)


orc = """
sr=44100
ksmps=32
nchnls=2
0dbfs=1

instr 1
kamp chnget "amp"
kfreq chnget "freq"
aout vco2 kamp, kfreq
aout moogladder aout, 2000, 0.25
outs aout, aout
endin"""


def test_channels():
    c = cycsound.Csound()
    c.set_option("-n")
    c.set_option("-d")
    c.set_option("-m0")
    c.compile_orc(orc)

    c.event_string("i1 0 0.5\n")
    assert c.start() == 0

    amp = RandomLine(.4, .2)
    freq = RandomLine(400, 80)

    c.set_control_channel("amp", amp.get_value())
    c.set_control_channel("freq", freq.get_value())

    while c.perform_ksmps() == 0:
        c.set_control_channel("amp", amp.get_value())
        c.set_control_channel("freq", freq.get_value())
