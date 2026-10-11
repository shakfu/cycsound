"""CsoundPerformanceThread: Csound performed on a native thread."""

import ctypes
import subprocess
import sys
import threading
import time

import pytest

import cycsound

# Declared up front: Csound creates channels without a lock, so a host read
# racing the first chnset can create a second, orphaned channel.
ORC = """
ksmps = 32
chn_k "p4", 3
instr 1
  chnset p4, "p4"
endin
instr 99
endin
"""

# -n renders ~5000x realtime: a 3600 s note ends in under a second.
LONG = "i 99 0 1e9"  # keeps the score alive until stop()


def _started(orc=ORC, score=LONG):
    c = cycsound.Csound()
    for opt in ("-n", "-d", "-m0"):
        c.set_option(opt)
    assert c.compile_orc(orc) == 0
    if score:
        c.event_string(score)
    assert c.start() == 0
    return c


def _wait(pred, timeout=10.0):
    end = time.monotonic() + timeout
    while not pred():
        assert time.monotonic() < end, "timed out"
        time.sleep(0.005)


def test_requires_started_instance():
    c = cycsound.Csound()
    c.set_option("-n")
    with pytest.raises(RuntimeError, match="start"):
        cycsound.CsoundPerformanceThread(c)


def test_play_to_end_of_score():
    c = _started(score="i 1 0 0.1 1")
    t = cycsound.CsoundPerformanceThread(c)
    assert t.csound is c
    assert t.is_running()
    t.play()
    assert t.join() > 0
    assert t.status > 0
    assert not t.is_running()
    assert c.get_control_channel("p4") == 1


def test_events_from_another_thread():
    c = _started()
    t = cycsound.CsoundPerformanceThread(c)
    t.play()
    sender = threading.Thread(target=t.score_event, args=("i", [1, 0, 0.01, 5]))
    sender.start()
    sender.join()
    _wait(lambda: c.get_control_channel("p4") == 5)
    t.input_message("i 1 0 0.01 6")
    _wait(lambda: c.get_control_channel("p4") == 6)
    t.stop()
    assert t.join() > 0


def test_score_event_validates_opcod():
    t = cycsound.CsoundPerformanceThread(_started())
    with pytest.raises(ValueError):
        t.score_event("ii", [1, 0, 1])
    t.stop()
    t.join()


def test_compile_orc_then_event():
    c = _started()
    t = cycsound.CsoundPerformanceThread(c)
    t.play()
    t.compile_orc('instr 2\nchnset p4 * 2, "p4"\nendin\n')
    t.score_event("i", [2, 0, 0.01, 21])
    _wait(lambda: c.get_control_channel("p4") == 42)
    t.stop()
    t.join()


def test_eval_code_callback():
    got = []
    t = cycsound.CsoundPerformanceThread(_started())
    t.play()
    t.eval_code("return 3 + 4", got.append)
    t.eval_code("return 1")  # no callback
    t.flush_message_queue()
    assert got == [7.0]
    t.stop()
    t.join()
    with pytest.raises(RuntimeError, match="ended"):
        t.eval_code("return 1", got.append)


def test_request_callback_runs_on_performance_thread():
    idents = []
    t = cycsound.CsoundPerformanceThread(_started())
    t.play()
    for _ in range(3):
        t.request_callback(lambda: idents.append(threading.get_ident()))
    t.flush_message_queue()
    assert len(idents) == 3
    assert threading.get_ident() not in idents
    t.stop()
    t.join()


def test_process_callback():
    count = [0]
    c = _started()
    t = cycsound.CsoundPerformanceThread(c)
    t.set_process_callback(lambda: count.__setitem__(0, count[0] + 1))
    t.play()
    _wait(lambda: count[0] >= 100)
    t.set_process_callback(None)
    t.flush_message_queue()
    before = count[0]
    _wait(lambda: c.get_kcounter() > 0)
    time.sleep(0.05)
    assert count[0] - before <= 1  # at most one call already in flight
    t.stop()
    t.join()


def test_process_hook():
    count = ctypes.c_int64(0)
    proto = ctypes.CFUNCTYPE(None, ctypes.c_void_p)

    @proto
    def hook(ctx):
        ctypes.c_int64.from_address(ctx).value += 1

    t = cycsound.CsoundPerformanceThread(_started())
    t.set_process_hook(ctypes.cast(hook, ctypes.c_void_p).value,
                       ctypes.addressof(count))
    t.play()
    _wait(lambda: count.value >= 100)
    t.set_process_hook(0)
    t.stop()
    t.join()


def test_pause_holds_score_time():
    c = _started()
    t = cycsound.CsoundPerformanceThread(c)
    t.play()
    _wait(lambda: c.get_score_time() > 0.5)
    t.pause()
    t.flush_message_queue()
    held = c.get_score_time()
    time.sleep(0.05)
    assert c.get_score_time() == held
    t.toggle_pause()
    _wait(lambda: c.get_score_time() > held)
    t.stop()
    t.join()


def test_csound_callbacks_on_performance_thread():
    # Csound callbacks now fire on a C thread; compile_orc from Python must
    # not deadlock against them.
    seen = []
    c = _started(orc=ORC + 'instr 3\nkv = 1\noutvalue "x", kv\nendin\n',
                 score=LONG + "\ni 3 0 1e9")
    c.set_output_channel_callback(lambda name, v: seen.append(threading.get_ident()))
    t = cycsound.CsoundPerformanceThread(c)
    t.play()
    _wait(lambda: len(seen) > 100)
    for i in range(20):
        assert c.compile_orc("instr %d\nendin\n" % (i + 10)) == 0
    t.stop()
    t.join()
    assert threading.get_ident() not in set(seen)


DEALLOC_SCRIPT = """
import gc, cycsound
c = cycsound.Csound()
c.set_option("-n")
c.compile_orc("instr 99\\nendin\\n")
c.event_string("i 99 0 1e9")
c.start()
c.set_message_callback(lambda attr, text: None)
t = cycsound.CsoundPerformanceThread(c)
t.set_process_callback(lambda: None)
t.play()
cycsound.sleep(100)
del t
gc.collect()
print("deleted", flush=True)
t2 = cycsound.CsoundPerformanceThread(c)
t2.set_process_callback(lambda: None)
t2.play()
cycsound.sleep(100)
print("exiting", flush=True)
"""


def test_dealloc_and_exit_while_playing():
    # Destroying a playing thread stops it; exiting with one still playing
    # (t2) stops it in the atexit handler.
    r = subprocess.run([sys.executable, "-c", DEALLOC_SCRIPT],
                       capture_output=True, text=True, timeout=60,
                       stdin=subprocess.DEVNULL)
    assert r.returncode == 0, r.stderr[-2000:]
    assert "deleted" in r.stdout and "exiting" in r.stdout


def test_record(tmp_path):
    out = tmp_path / "rec.wav"
    c = _started(orc=ORC + "instr 4\nout oscili(0.5, 440)\nendin\n",
                 score="i 4 0 1e9")
    t = cycsound.CsoundPerformanceThread(c)
    t.record(str(out), 16, 4)
    t.play()
    _wait(lambda: c.get_score_time() > 0.5)
    t.stop_record()
    t.stop()
    t.join()
    assert out.exists() and out.stat().st_size > 44  # more than a WAV header
