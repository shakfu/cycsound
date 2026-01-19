"""Tests for cycsound Cython extension module."""

import cycsound


def test_get_version():
    """Test get_version returns a valid Csound version number."""
    version = cycsound.get_version()
    assert isinstance(version, int)
    assert version >= 6000  # Csound 6.0+


def test_get_api_version():
    """Test get_api_version returns a valid API version."""
    api_version = cycsound.get_api_version()
    assert isinstance(api_version, int)
    assert api_version >= 1


def test_get_size_of_myflt():
    """Test get_size_of_myflt returns size of MYFLT type."""
    size = cycsound.get_size_of_myflt()
    assert size in (4, 8)  # float=4, double=8


def test_csound_create():
    """Test creating a Csound instance."""
    cs = cycsound.Csound()
    assert cs is not None


def test_csound_set_option():
    """Test setting Csound options."""
    cs = cycsound.Csound()
    # -d suppresses displays
    result = cs.set_option("-d")
    assert result == 0


def test_csound_compile_orc():
    """Test compiling Csound orchestra code."""
    cs = cycsound.Csound()
    cs.set_option("-d")
    cs.set_option("-n")  # no output

    orc = """
    sr = 44100
    ksmps = 32
    nchnls = 2
    0dbfs = 1

    instr 1
        asig oscil 0.5, 440
        outs asig, asig
    endin
    """

    result = cs.compile_orc(orc)
    assert result == 0


def test_msg_enum():
    """Test Msg enum values exist."""
    assert cycsound.Msg.DEFAULT.value == 0x0000
    assert cycsound.Msg.ERROR.value == 0x1000


def test_color_enum():
    """Test Color enum values exist."""
    assert cycsound.Color.FG_RED.value == 0x0101
    assert cycsound.Color.FG_GREEN.value == 0x0102


def test_context_manager():
    """Test Csound context manager support."""
    with cycsound.Csound() as cs:
        cs.set_option("-n")
        cs.set_option("-d")
        result = cs.compile_orc("""
sr = 44100
ksmps = 32
nchnls = 2
0dbfs = 1

instr 1
    asig oscil 0.5, 440
    outs asig, asig
endin
""")
        assert result == 0
        cs.read_score("i1 0 0.1")
        cs.start()
    # cleanup() should have been called automatically


def test_run_method():
    """Test Csound run() convenience method."""
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
        cs.read_score("i1 0 0.01")
        result = cs.run()
        assert result == 0


def test_initialize():
    """Test initialize() function."""
    # Should return 0 on success, positive if already initialized
    result = cycsound.initialize()
    assert result >= 0


def test_status_enum():
    """Test Status enum values."""
    assert cycsound.Status.SUCCESS == 0
    assert cycsound.Status.ERROR == -1
    assert cycsound.Status.INITIALIZATION == -2
    assert cycsound.Status.PERFORMANCE == -3
    assert cycsound.Status.MEMORY == -4
    assert cycsound.Status.SIGNAL == -5


def test_filetype_enum():
    """Test FileType enum values."""
    assert cycsound.FileType.UNKNOWN == 0
    assert cycsound.FileType.UNIFIED_CSD == 1
    assert cycsound.FileType.WAVE == 14
    assert cycsound.FileType.FLAC == 19
    assert cycsound.FileType.OGG == 22
    assert cycsound.FileType.STD_MIDI == 39
    assert cycsound.FileType.OTHER_BINARY == 65
