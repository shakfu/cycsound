"""Example 10 - More efficient Channel Communications

This example continues on from Example 10 and introduces a 
ChannelUpdater object. The ChannelUpdater will create and 
store a CsoundMYFLTArray that is wrapping a Csound Channel.
Additionally, it will store and call an object that has a 
getValue() method to update values in the channel when 
update() is called. 

This example continues the illustration of a progression of 
a project.  Note that the process has changed a little bit
where we now create a number of ChannelUpdater objects and
store them in a list.  The list is then iterated through for
updating the channel with the latest values.  In a real-world
project, this kind of scenario occurs when there are n-number of 
items to update channels and one wants to have a flexible number
that may even change dynamically at runtime.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import pytest
import cycsound
from random import randint, random


class RandomLine:
    def __init__(self, base, range):
        self.curVal = 0.0
        self.reset()
        self.base = base
        self.range = range

    def reset(self):
        self.dur = randint(256,512) 
        self.end = random() 
        self.slope = (self.end - self.curVal) / self.dur

    def getValue(self):
        self.dur -= 1
        if(self.dur < 0):
            self.reset()
        retVal = self.curVal
        self.curVal += self.slope
        return self.base + (self.range * retVal)


def createChannel(csound, channelName):
    chn, err = csound.channelPtr(channelName, 
        cycsound.CSOUND_CONTROL_CHANNEL | cycsound.CSOUND_INPUT_CHANNEL)
    if err:
    	sys.exit(1)
    return chn

class ChannelUpdater(object):
    def __init__(self, csound, channelName, updater):
        self.updater = updater
        self.channel = createChannel(csound, channelName)

    def update(self):
        self.channel[0] = self.updater.getValue()

###############################

# Our Orchestra for our project
orc = """
sr=44100
ksmps=32
nchnls=2
0dbfs=1

instr 1 
kamp chnget "amp"
kfreq chnget "freq"
kres chnget "resonance"
printk 0.5, kamp
printk 0.5, kfreq
printk 0.5, kres
aout vco2 kamp, kfreq
aout moogladder aout, 2000, kres
outs aout, aout
endin"""

@pytest.mark.skipif(True,
                    reason="c.channelPtr not yet implemented")
def test_channel_control():

    c = cycsound.Csound()    # create an instance of Csound
    c.set_option("-odac")  # Set option for Csound
    c.set_option("-m7")  # Set option for Csound
    c.compile_orc(orc)     # Compile Orchestra from String

    sco = "i1 0 60\n"

    c.read_score(sco)     # Read in Score generated from notes 

    c.start()             # When compiling from strings, this call is necessary before doing any performing

    # Create a set of ChannelUpdaters
    channels = [ChannelUpdater(c, "amp", RandomLine(.4, .2)),
                ChannelUpdater(c, "freq", RandomLine(400, 80)),
                ChannelUpdater(c, "resonance", RandomLine(0.4, .3))]

    # Initialize all Channel Values
    for chn in channels:
        chn.update()

    while (c.perform_ksmps() == 0):
        for chn in channels:   # update all channel values
            chn.update()

    c.stop()
