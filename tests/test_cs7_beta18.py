"""Host API functions added in Csound 7.0.0-beta.18."""

import pytest

import cycsound


def _instance(orc=None):
    c = cycsound.Csound()
    for opt in ("-n", "-d", "-m0"):
        c.set_option(opt)
    if orc is not None:
        assert c.compile_orc(orc) == 0
    return c


def test_type_sizes():
    # The extension is built with USE_DOUBLE.
    assert cycsound.get_size_of_cs_float() == 8
    assert cycsound.get_size_of_cs_double() == 8
    assert cycsound.get_size_of_myflt() == cycsound.get_size_of_cs_float()


def test_params_recursion_depth():
    c = _instance()
    assert c.get_params().recursion_depth >= 0


def test_command_line_args_roundtrip():
    c = _instance()
    args = ("concert.orc", "first violin", "--quiet", "")
    assert c.set_command_line_args(*args) == 0
    assert c.get_command_line_args() == list(args)
    assert c.eval_code('Sa[] argv\nreturn lenarray(Sa)') == 4

    assert c.set_command_line_args() == 0
    assert c.get_command_line_args() == []


def test_command_line_args_from_compile():
    c = cycsound.Csound()
    assert c.compile("csound", "-n", "-m0", "--code=instr 1\nendin",
                     "--", "a", "b c") == 0
    assert c.get_command_line_args() == ["a", "b c"]


def test_control_channel_hints_repeat_reads():
    # Each read releases the attributes Csound copied for the caller.
    c = _instance()
    c.set_control_channel("gain", 0.5)
    assert c.set_control_channel_hints(
        "gain", cycsound.ChannelBehavior.LIN, attributes="volume") == 0
    for _ in range(3):
        assert c.get_control_channel_hints("gain")["attributes"] == "volume"


COPY_ORC = """
chn_k "src", 3
chn_k "dst", 3
chn_S "str", 3
"""


def test_copy_channel():
    c = _instance(COPY_ORC)
    assert c.start() == 0
    c.set_control_channel("src", 0.75)
    c.set_control_channel("dst", 0.0)
    assert c.copy_channel("src", "dst") == 0
    assert c.get_control_channel("dst") == 0.75


def test_copy_channel_errors():
    c = _instance(COPY_ORC)
    assert c.start() == 0
    assert c.copy_channel("nosuch", "dst") == cycsound.Status.ERROR
    assert c.copy_channel("src", "nosuch") == cycsound.Status.ERROR
    # Type mismatch: string source, control destination.
    assert c.copy_channel("str", "dst") == cycsound.Status.ERROR


PVS_ORC = """
chn_k "winsize", 3
instr 1
finput pvsin "pvs-input"
ioverlap, inumbins, iwinsize, iformat pvsinfo finput
pvsout finput, "pvs-output"
chnset iwinsize, "winsize"
endin
"""

FFT, OVERLAP, WINSIZE = 1024, 256, 1024


def test_pvs_channel_roundtrip():
    c = _instance(PVS_ORC)
    assert c.start() == 0
    frame = [i + 0.25 for i in range(FFT + 2)]  # exact in float32

    src = c.init_pvs_channel("host-input", FFT, OVERLAP, WINSIZE)
    assert src.fft_size == FFT
    assert src.overlap == OVERLAP
    assert src.window_size == WINSIZE
    assert src.format == cycsound.PvsFormat.AMP_FREQ
    src.set_frame(frame)
    assert src.get_frame() == frame
    assert c.set_pvs_channel("pvs-input", src) == 0

    c.event(cycsound.EventType.INSTR, [1, 0, 1])
    assert c.perform_ksmps() == 0
    assert c.get_control_channel("winsize") == WINSIZE

    dst = c.init_pvs_channel("host-output", FFT, OVERLAP, WINSIZE)
    assert c.get_pvs_channel("pvs-output", dst) == 0
    assert dst.get_frame() == frame


def test_pvs_channel_too_small_destination():
    c = _instance(PVS_ORC)
    assert c.start() == 0
    src = c.init_pvs_channel("host-input", FFT, OVERLAP, WINSIZE)
    src.set_frame([0.0] * (FFT + 2))
    assert c.set_pvs_channel("pvs-input", src) == 0
    c.event(cycsound.EventType.INSTR, [1, 0, 1])
    c.perform_ksmps()

    small = c.init_pvs_channel("host-small", FFT // 2, OVERLAP, WINSIZE)
    assert c.get_pvs_channel("pvs-output", small) == cycsound.Status.ERROR
    assert small.fft_size == FFT // 2


def test_pvs_set_frame_wrong_length():
    c = _instance(PVS_ORC)
    assert c.start() == 0
    data = c.init_pvs_channel("host-input", FFT, OVERLAP, WINSIZE)
    with pytest.raises(ValueError, match="fft_size"):
        data.set_frame([0.0] * FFT)


def test_pvs_set_frame_after_smaller_copy():
    # get_pvs_channel() can shrink N below the allocated frame; set_frame()
    # must then accept exactly the new N + 2 values.
    c = _instance(PVS_ORC)
    assert c.start() == 0
    c.init_pvs_channel("pvs-small", FFT // 2, OVERLAP, WINSIZE).set_frame(
        [1.0] * (FFT // 2 + 2))
    big = c.init_pvs_channel("host-big", FFT, OVERLAP, WINSIZE)
    assert c.get_pvs_channel("pvs-small", big) == 0
    assert big.fft_size == FFT // 2
    big.set_frame([2.0] * (FFT // 2 + 2))
    assert big.get_frame() == [2.0] * (FFT // 2 + 2)


def test_pvs_init_requires_start():
    # Csound segfaults allocating the frame before csoundStart().
    c = _instance(PVS_ORC)
    with pytest.raises(RuntimeError, match="start"):
        c.init_pvs_channel("host-input", FFT, OVERLAP, WINSIZE)


def test_pvs_data_stale_after_reset():
    c = _instance(PVS_ORC)
    assert c.start() == 0
    data = c.init_pvs_channel("host-input", FFT, OVERLAP, WINSIZE)
    c.reset()
    with pytest.raises(ValueError, match="stale"):
        data.get_frame()
    with pytest.raises(ValueError):
        c.set_pvs_channel("pvs-input", data)


def test_pvs_data_unbound():
    data = cycsound.PvsData()
    with pytest.raises(ValueError):
        data.get_frame()
    c = _instance()
    with pytest.raises(ValueError):
        c.set_pvs_channel("x", data)


READLINE_ORC = """
ksmps = 1
chn_k "status", 2
chn_S "line", 2
instr 1
  Sline, kstatus readline ""
  if (kstatus == 1) then
    chnset Sline, "line"
    chnset kstatus, "status"
  endif
endin
"""


def test_readline_push_text():
    c = _instance(READLINE_ORC)
    c.event_string("i 1 0 1")
    assert c.readline_push_text("from host\n") == 0
    assert c.start() == 0
    for _ in range(32):
        assert c.perform_ksmps() == 0
        if c.get_control_channel("status") == 1.0:
            break
    assert c.get_control_channel("status") == 1.0
    assert c.get_string_channel("line") == "from host"


def test_perform_output_fade_without_realtime_output():
    # The fade acts only on a realtime output device; with -n it is a no-op.
    c = _instance("instr 1\nout oscili(0.5, 440)\nendin\n")
    c.event_string("i 1 0 10")
    assert c.start() == 0
    c.perform_ksmps()
    t0 = c.get_current_time_samples()
    assert c.perform_output_fade(256) == 0
    assert c.get_current_time_samples() == t0
