"""Array channels (csoundInitArrayChannel and the ARRAYDAT accessors)."""

import pytest

import cycsound

KSMPS = 4


def _instance(orc):
    c = cycsound.Csound()
    for opt in ("-n", "-d", "-m0", f"--ksmps={KSMPS}"):
        c.set_option(opt)
    assert c.compile_orc(orc) == 0
    return c


SUM_ORC = """
chn_k "sum", 2
instr 1
  kArr[] chnget "arr"
  chnset sumarray(kArr), "sum"
endin
"""


def test_numeric_array_host_to_orchestra():
    c = _instance(SUM_ORC)
    arr = c.init_array_channel("arr", "k", [2, 3])
    assert (arr.type, arr.dimensions, arr.sizes, len(arr)) == ("k", 2, (2, 3), 6)
    assert arr.get() == [0.0] * 6
    arr.set([1, 2, 3, 4, 5, 6])
    assert arr.get() == [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
    assert arr.data_address != 0
    c.event_string("i 1 0 1")
    assert c.start() == 0
    c.perform_ksmps()
    assert c.get_control_channel("sum") == 21.0
    with pytest.raises(ValueError):
        arr.set([1, 2])


def test_existing_channel_is_returned_unchanged():
    c = _instance("instr 1\nendin\n")
    a = c.init_array_channel("arr", "i", [3])
    b = c.init_array_channel("arr", "i", [5])
    assert b.sizes == (3,) and b.data_address == a.data_address


def test_audio_array_elements_are_ksmps_blocks():
    c = _instance("instr 1\nendin\n")
    arr = c.init_array_channel("aarr", "a", [2])
    assert len(arr.get()) == 2 * KSMPS
    arr.set(range(2 * KSMPS))
    assert arr.get()[KSMPS] == float(KSMPS)


STRING_ORC = """
instr 1
  Sin[] chnget "words"
  Sout[] init 2
  Sout[0] strcat Sin[0], "!"
  Sout[1] = "from orc"
  chnset Sout, "replies"
endin
"""


def test_string_array_both_directions():
    c = _instance(STRING_ORC)
    words = c.init_array_channel("words", "S", [2])
    replies = c.init_array_channel("replies", "S", [2])
    words.set_string(0, "hello")
    words.set_string(1, "x" * 500)  # grows the element's buffer
    assert words.get_string(0) == "hello"
    assert words.get_string(1) == "x" * 500
    c.event_string("i 1 0 1")
    assert c.start() == 0
    c.perform_ksmps()
    assert replies.get_string(0) == "hello!"
    assert replies.get_string(1) == "from orc"
    with pytest.raises(TypeError):
        words.get()
    with pytest.raises(IndexError):
        words.get_string(2)


def test_type_guards_and_stale_after_reset():
    c = _instance("instr 1\nendin\n")
    arr = c.init_array_channel("arr", "k", [2])
    with pytest.raises(TypeError):
        arr.get_string(0)
    with pytest.raises(ValueError):
        c.init_array_channel("arr", "k", [])
    c.reset()
    with pytest.raises(ValueError):
        arr.get()
    assert repr(arr) == "<ArrayChannel stale>"
