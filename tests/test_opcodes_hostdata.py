"""C opcode registration (csoundAppendOpcode/s) and Python host data."""

import ctypes
import gc

import cycsound

OPCODE_FN = ctypes.CFUNCTYPE(ctypes.c_int32, ctypes.c_void_p, ctypes.c_void_p)


def _write_first_output(value):
    """An init function that stores ``value`` through the first argument."""
    def init(csound, p):
        out = ctypes.c_void_p.from_address(p + cycsound.OPDS_SIZE).value
        ctypes.c_double.from_address(out).value = value
        return 0
    return OPCODE_FN(init)


def _instance():
    c = cycsound.Csound()
    for opt in ("-n", "-d", "-m0"):
        c.set_option(opt)
    return c


def _run(c, orc):
    assert c.compile_orc(orc) == 0
    c.event_string("i 1 0 0.01")
    assert c.start() == 0
    c.perform_ksmps()


def test_append_opcode():
    c = _instance()
    init = _write_first_output(42.0)
    size = cycsound.OPDS_SIZE + ctypes.sizeof(ctypes.c_void_p)
    addr = ctypes.cast(init, ctypes.c_void_p).value
    # Temporary strings: the wrapper keeps the encoded copies alive.
    assert c.append_opcode("host" + "const", size, 0, "i", "", init=addr) == 0
    gc.collect()
    _run(c, 'chn_k "out", 2\ninstr 1\ni1 hostconst\nchnset i1, "out"\nendin\n')
    assert c.get_control_channel("out") == 42.0


class OENTRY(ctypes.Structure):
    _fields_ = [("opname", ctypes.c_char_p), ("dsblksiz", ctypes.c_size_t),
                ("flags", ctypes.c_int32), ("outypes", ctypes.c_char_p),
                ("intypes", ctypes.c_char_p), ("init", ctypes.c_void_p),
                ("perf", ctypes.c_void_p), ("deinit", ctypes.c_void_p),
                ("useropinfo", ctypes.c_void_p), ("deprecated", ctypes.c_int32)]


def test_append_opcodes():
    c = _instance()
    fns = [_write_first_output(1.5), _write_first_output(2.5)]
    size = cycsound.OPDS_SIZE + ctypes.sizeof(ctypes.c_void_p)
    entries = (OENTRY * 2)(
        OENTRY(b"hosta", size, 0, b"i", b"", ctypes.cast(fns[0], ctypes.c_void_p).value),
        OENTRY(b"hostb", size, 0, b"i", b"", ctypes.cast(fns[1], ctypes.c_void_p).value))
    assert c.append_opcodes(ctypes.addressof(entries), 2) == 0
    _run(c, 'chn_k "out", 2\ninstr 1\nchnset hosta() + hostb(), "out"\nendin\n')
    assert c.get_control_channel("out") == 4.0


def test_host_data_is_settable():
    c = cycsound.Csound(host_data={"a": 1})
    assert c.host_data == {"a": 1}
    c.host_data = "other"
    assert c.host_data == "other"
