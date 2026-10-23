"""Graph display (csound_graph_display.h) and file callbacks (csound_files.h)."""

import ctypes
import os
import sys
from pathlib import Path

import pytest

import cycsound
from cycsound import FileType

HERE = os.path.dirname(os.path.abspath(__file__))
# Forward slashes: orc string literals treat "\t" etc. as escapes.
MARIMBA = Path(HERE, "marimba.aif").as_posix()
GEN01 = f'gi2 ftgen 2, 0, 0, 1, "{MARIMBA}", 0, 0, 0\ninstr 1\nendin\n'


def _run(c, orc):
    # Global ftgen code runs at start(), not at compile time.
    assert c.compile_orc(orc) == 0
    assert c.start() == 0


def _instance(*opts):
    c = cycsound.Csound()
    for opt in ("-n", "-m0", *opts):
        c.set_option(opt)
    return c


def test_graph_callbacks_draw_tables():
    c = _instance()
    events = []
    assert c.set_is_graphable(True) is False
    assert c.set_is_graphable(True) is True

    def make(win, name):
        events.append(("make", name, win.caption, len(win.data)))
        return 7

    c.set_graph_callbacks(make=make, draw=lambda win: events.append(("draw", win)))
    _run(c, "gi1 ftgen 1, 0, 16, 10, 1\ninstr 1\nendin\n")
    assert events[0] == ("make", "ftable", "ftable 1:", 16)
    win = events[1][1]
    assert isinstance(win, cycsound.GraphWindow)
    assert win.windid == 7  # make()'s return value
    assert win.polarity == cycsound.GraphPolarity.BIPOL
    assert win.max == 1.0 and win.min < 0
    assert len(win.data) == 16


def test_graph_callbacks_reinstalled_after_reset():
    # -d replaces the callbacks with no-ops in the reset-preserved block.
    c = _instance("-d")
    makes = []
    c.set_graph_callbacks(make=lambda win, name: makes.append(name),
                          draw=lambda win: None)
    assert c.compile_orc("instr 1\nendin\n") == 0
    assert c.start() == 0
    c.reset()
    for opt in ("-n", "-m0"):
        c.set_option(opt)
    _run(c, "gi1 ftgen 1, 0, 16, 10, 1\ninstr 1\nendin\n")
    assert makes == ["ftable"]


def test_file_open_notification_and_fallbacks():
    c = _instance("-d")
    notes, sound_opens = [], []
    c.set_file_open_callback(lambda *args: notes.append(args))
    c.set_open_sound_file_callback(
        lambda path, mode, sfinfo: sound_opens.append((path, sfinfo != 0)))
    _run(c, GEN01)
    assert sound_opens == [(MARIMBA, True)]  # None: Csound opened it itself
    assert notes == [(MARIMBA, FileType.AIFF, False, False)]
    assert c.table_length(2) > 0


# csound64.dll links a static CRT (/MT): no FILE* from outside it is valid there.
@pytest.mark.skipif(sys.platform == "win32", reason="Csound uses a private static CRT")
def test_open_file_callback_returns_file_pointer(tmp_path):
    numbers = tmp_path / "numbers.txt"
    numbers.write_text("1 2 3 4\n")
    libc = ctypes.CDLL(None)
    libc.fopen.restype = ctypes.c_void_p
    libc.fopen.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    opened = []

    def open_file(path, mode):
        opened.append((path, mode))
        return libc.fopen(path.encode(), mode.encode())

    c = _instance("-d")
    c.set_open_file_callback(open_file)
    _run(c, f'gi1 ftgen 1, 0, 4, -23, "{numbers}"\ninstr 1\nendin\n')
    assert opened == [(str(numbers), "r")]
    assert list(c.get_table(1)) == [1.0, 2.0, 3.0, 4.0]


def test_sndfile_callbacks_survive_reset():
    # All-NULL members select Csound's no-op stubs: GEN01 cannot read.
    stubs = (ctypes.c_void_p * 11)()
    c = _instance("-d")
    c.set_sndfile_callbacks(ctypes.addressof(stubs))
    c.compile_orc(GEN01)
    c.start()
    assert c.table_length(2) < 0
    c.reset()  # restores Csound's defaults; the wrapper re-applies the copy
    for opt in ("-n", "-d", "-m0"):
        c.set_option(opt)
    c.compile_orc(GEN01)
    c.start()
    assert c.table_length(2) < 0
    c.set_sndfile_callbacks(0)  # back to the defaults
    c.reset()
    for opt in ("-n", "-d", "-m0"):
        c.set_option(opt)
    _run(c, GEN01)
    assert c.table_length(2) > 0
