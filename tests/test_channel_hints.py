"""Control-channel hints and audio-channel access (Csound 7 bus interface)."""

import cycsound


orc = """
sr=44100
ksmps=32
nchnls=1
0dbfs=1

instr 1
kg chnget "gain"
aout oscili kg, 440
chnset aout, "abus"
endin"""


def _instance():
    c = cycsound.Csound()
    c.set_option("-n")
    c.set_option("-d")
    c.set_option("-m0")
    assert c.compile_orc(orc) == 0
    return c


def test_control_channel_hints_roundtrip():
    c = _instance()
    # The channel has to exist before hints can be attached to it.
    c.set_control_channel("gain", 0.5)

    assert c.set_control_channel_hints(
        "gain", cycsound.ChannelBehavior.LIN, dflt=0.5, min=0.0, max=1.0,
        x=10, y=20, width=100, height=40, attributes="volume") == 0

    hints = c.get_control_channel_hints("gain")
    assert hints["behav"] == cycsound.ChannelBehavior.LIN
    assert hints["dflt"] == 0.5
    assert hints["min"] == 0.0
    assert hints["max"] == 1.0
    assert (hints["x"], hints["y"]) == (10, 20)
    assert (hints["width"], hints["height"]) == (100, 40)
    assert hints["attributes"] == "volume"


def test_control_channel_hints_missing_channel():
    c = _instance()
    assert c.get_control_channel_hints("nosuch") is None


def test_audio_channel_roundtrip():
    c = _instance()
    c.set_control_channel("gain", 0.5)
    assert c.start() == 0
    c.event_string("i1 0 1\n")
    for _ in range(4):
        c.perform_ksmps()

    block = c.get_audio_channel("abus")
    assert len(block) == c.get_ksmps()
    assert max(abs(x) for x in block) > 0.0

    c.set_audio_channel("abus", [0.0] * c.get_ksmps())
    assert max(abs(x) for x in c.get_audio_channel("abus")) == 0.0


def test_audio_channel_wrong_size():
    c = _instance()
    try:
        c.set_audio_channel("abus", [0.0, 0.0, 0.0])
    except ValueError as exc:
        assert "ksmps" in str(exc)
    else:
        raise AssertionError("expected ValueError for a non-ksmps block")


def test_set_global_env():
    assert cycsound.set_global_env("CYCSOUND_TEST_VAR", "1") == 0
    c = _instance()
    assert c.get_env("CYCSOUND_TEST_VAR") == "1"
    assert cycsound.set_global_env("CYCSOUND_TEST_VAR", None) == 0
