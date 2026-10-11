"""Tests for the cycsound Cython extension module (Csound 7)."""

import cycsound


ORC = """
sr = 44100
ksmps = 32
nchnls = 2
0dbfs = 1

instr 1
    asig oscili 0.5, 440
    outs asig, asig
endin
"""


def test_get_version():
    """get_version returns a valid Csound 7 version number."""
    version = cycsound.get_version()
    assert isinstance(version, int)
    assert version >= 7000  # Csound 7.0+ (7.00.0 == 7000)


def test_get_size_of_myflt():
    """get_size_of_myflt returns the size of the MYFLT type."""
    size = cycsound.get_size_of_myflt()
    assert size in (4, 8)  # float=4, double=8


def test_csound_create():
    """Creating a Csound instance succeeds."""
    cs = cycsound.Csound()
    assert cs is not None


def test_csound_set_option():
    """Setting a Csound option returns success."""
    cs = cycsound.Csound()
    assert cs.set_option("-d") == 0


def test_csound_compile_orc():
    """Compiling orchestra code returns success."""
    cs = cycsound.Csound()
    cs.set_option("-d")
    cs.set_option("-n")  # no realtime audio
    assert cs.compile_orc(ORC) == 0


def test_eval_code():
    """eval_code evaluates global i-time code and returns its value."""
    cs = cycsound.Csound()
    cs.set_option("-n")
    cs.set_option("-d")
    result = cs.eval_code("i1 = 2 + 2\nreturn i1\n")
    assert result == 4.0


def test_msg_enum():
    """Msg enum values exist."""
    assert cycsound.Msg.DEFAULT.value == 0x0000
    assert cycsound.Msg.ERROR.value == 0x1000


def test_color_enum():
    """Color enum values exist."""
    assert cycsound.Color.FG_RED.value == 0x0101
    assert cycsound.Color.FG_GREEN.value == 0x0102


def test_context_manager():
    """Csound context manager support (reset on exit)."""
    with cycsound.Csound() as cs:
        cs.set_option("-n")
        cs.set_option("-d")
        assert cs.compile_orc(ORC) == 0
        cs.event_string("i1 0 0.1")
        assert cs.start() == 0
    # reset() is called automatically on exit.


def test_run_method():
    """The run() convenience method performs an entire score."""
    with cycsound.Csound() as cs:
        cs.set_option("-n")
        cs.set_option("-d")
        cs.compile_orc("""
sr = 44100
ksmps = 32
nchnls = 2
0dbfs = 1

instr 1
    print p1
endin
""")
        cs.event_string("i1 0 0.01")
        assert cs.run() == 0


def test_perform_ksmps_loop():
    """A manual perform_ksmps loop runs to completion."""
    cs = cycsound.Csound()
    cs.set_option("-n")
    cs.set_option("-d")
    cs.compile_orc(ORC)
    cs.event_string("i1 0 0.05")
    assert cs.start() == 0
    blocks = 0
    while cs.perform_ksmps() == 0:
        blocks += 1
    assert blocks > 0


def test_attributes():
    """Engine attributes report expected values after compilation."""
    cs = cycsound.Csound()
    cs.set_option("-n")
    cs.set_option("-d")
    cs.compile_orc(ORC)
    cs.start()
    assert cs.get_sr() == 44100.0
    assert cs.get_ksmps() == 32
    assert cs.get_nchnls() == 2
    assert cs.get_nchnls_input() == 2
    assert cs.get_0dBFS() == 1.0
    assert cs.get_A4() == 440.0


def test_get_params():
    """get_params returns a read-only Params view."""
    cs = cycsound.Csound()
    cs.set_option("-n")
    cs.set_option("-d")
    cs.set_option("-m0")
    cs.compile_orc(ORC)
    params = cs.get_params()
    assert isinstance(params, cycsound.Params)
    assert params.message_level == 0


def test_control_channel():
    """Control channels round-trip a value."""
    cs = cycsound.Csound()
    cs.set_option("-n")
    cs.set_option("-d")
    cs.compile_orc("""
sr = 44100
ksmps = 32
nchnls = 1
0dbfs = 1

instr 1
    kval chnget "freq"
    out a(kval)
endin
""")
    cs.event_string("i1 0 0.05")
    cs.start()
    cs.set_control_channel("freq", 220.0)
    assert cs.get_control_channel("freq") == 220.0


def test_get_instr_number():
    """get_instr_number resolves a named instrument."""
    cs = cycsound.Csound()
    cs.set_option("-n")
    cs.set_option("-d")
    cs.compile_orc("""
sr = 44100
ksmps = 32
nchnls = 1
0dbfs = 1

instr Bass
    out a(0)
endin
""")
    cs.start()
    assert cs.get_instr_number("Bass") >= 1
    assert cs.get_instr_number("Nope") == -1


def test_status_enum():
    """Status enum values."""
    assert cycsound.Status.SUCCESS == 0
    assert cycsound.Status.ERROR == -1
    assert cycsound.Status.INITIALIZATION == -2
    assert cycsound.Status.PERFORMANCE == -3
    assert cycsound.Status.MEMORY == -4
    assert cycsound.Status.SIGNAL == -5


def test_event_type_enum():
    """EventType enum values match csoundEvent() types."""
    assert cycsound.EventType.INSTR == 0
    assert cycsound.EventType.TABLE == 1
    assert cycsound.EventType.END == 2
    assert cycsound.EventType.ADVANCE == 3


def test_channel_type_enum():
    """ChannelType enum values match the bus interface constants."""
    assert cycsound.ChannelType.CONTROL == 1
    assert cycsound.ChannelType.AUDIO == 2
    assert cycsound.ChannelType.STRING == 3
    assert cycsound.ChannelType.ARRAY == 6
    assert cycsound.ChannelType.INPUT == 16
    assert cycsound.ChannelType.OUTPUT == 32


def test_initialize():
    """initialize() returns 0 on success or positive if already initialized."""
    assert cycsound.initialize() >= 0


EVENT_ORC = """
ksmps = 32
instr 1
    chnset p4, "p4"
endin
instr 99
endin
"""


def test_sync_event_before_start_raises():
    # Csound drops a synchronous csoundEvent() before csoundStart().
    import pytest
    cs = cycsound.Csound()
    cs.set_option("-n")
    assert cs.compile_orc(EVENT_ORC) == 0
    with pytest.raises(RuntimeError, match="start"):
        cs.event(cycsound.EventType.INSTR, [1, 0, 0.1, 9])


def test_async_event_before_start_plays():
    cs = cycsound.Csound()
    cs.set_option("-n")
    assert cs.compile_orc(EVENT_ORC) == 0
    cs.event_string("i 99 0 1")
    cs.event(cycsound.EventType.INSTR, [1, 0.05, 0.05, 9], async_=True)
    assert cs.start() == 0
    while cs.get_score_time() < 0.1:
        assert cs.perform_ksmps() == 0
    assert cs.get_control_channel("p4") == 9
