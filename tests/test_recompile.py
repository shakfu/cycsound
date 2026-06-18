"""Example 13 - Recompiling during performance.

Compile and start an instrument, run it, then recompile global code and start a
new instance. Ported to the Csound 7 API.
"""
import cycsound


def test_recompile():
    cs = cycsound.Csound()
    cs.set_option("-n")  # non-realtime
    cs.set_option("-d")
    cs.compile_orc('''
    gi1 init 1
    instr 1
    a1 oscili 0dbfs, A4*gi1
    out a1
    endin
    schedule(1,0,1)
    ''')
    assert cs.start() == 0
    i = 0
    while i < 1378:  # ~1 sec (kr = 44100/32)
        cs.perform_ksmps()
        i += 1
    # recompile instr 0 (global) and schedule a new note
    cs.compile_orc('''
    gi1 = 2
    schedule(1,0,1)
    ''')
    i = 0
    while i < 1378:
        cs.perform_ksmps()
        i += 1
