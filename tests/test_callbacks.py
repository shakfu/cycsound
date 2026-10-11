"""Python callbacks (A) and C function-pointer hooks (B)."""

import ctypes
import gc
import shutil
import subprocess
import sys

import pytest

import cycsound
from cycsound import KeyCallbackType


def _instance(orc=None):
    c = cycsound.Csound()
    for opt in ("-n", "-d"):
        c.set_option(opt)
    if orc is not None:
        assert c.compile_orc(orc) == 0
    return c


CHANNEL_ORC = """
ksmps = 32
instr 1
  kin invalue "gain"
  chnset kin, "gain_seen"
  Sin invalue "name"
  chnset Sin, "name_seen"
  outvalue "meter", 0.5
  outvalue "label", "hi"
endin
"""

KEY_ORC = """
ksmps = 32
instr 1
  kkey sensekey
  chnset kkey, "key"
endin
"""


def _perform(c, orc_events="i 1 0 1", cycles=2):
    c.event_string(orc_events)
    assert c.start() == 0
    for _ in range(cycles):
        c.perform_ksmps()


## ---------------------------------------------------------------------------
## A: Python callables


def test_host_data_property():
    marker = object()
    assert cycsound.Csound(host_data=marker).host_data is marker
    assert cycsound.Csound().host_data is None


def test_message_callback():
    got = []
    c = _instance()
    c.set_message_callback(lambda attr, text: got.append((attr, text)))
    c.message_special(cycsound.Msg.WARNING.value, "py-probe %d", 7)
    assert (cycsound.Msg.WARNING.value, "py-probe 7") in got

    c.set_message_callback(None)
    got.clear()
    c.message("after-removal")
    assert got == []


def test_message_callback_survives_reset():
    got = []
    c = _instance("instr 1\nendin\n")
    c.set_message_callback(lambda attr, text: got.append(text))
    assert c.start() == 0
    c.reset()
    got.clear()
    c.message("after-reset")
    assert got == ["after-reset"]


def test_message_callback_rejects_non_callable():
    with pytest.raises(TypeError):
        _instance().set_message_callback(42)


def test_message_callback_and_buffer_are_exclusive():
    c = _instance()
    c.create_message_buffer(0)
    with pytest.raises(RuntimeError):
        c.set_message_callback(print)
    c.destroy_message_buffer()
    c.set_message_callback(lambda attr, text: None)
    with pytest.raises(RuntimeError):
        c.create_message_buffer(0)
    c.set_message_callback(None)
    c.create_message_buffer(0)
    c.destroy_message_buffer()


def test_callback_exception_is_unraisable(monkeypatch):
    seen = []
    monkeypatch.setattr(sys, "unraisablehook", lambda u: seen.append(u))

    def boom(attr, text):
        raise ValueError("boom")

    c = _instance()
    c.set_message_callback(boom)
    c.message("x")
    assert seen and isinstance(seen[0].exc_value, ValueError)


def test_input_channel_callback():
    calls = []

    def supply(name, type_name):
        calls.append((name, type_name))
        return {"gain": 0.25, "name": "from python"}[name]

    c = _instance(CHANNEL_ORC)
    c.set_input_channel_callback(supply)
    _perform(c)
    assert ("gain", "k") in calls and ("name", "S") in calls
    assert c.get_control_channel("gain_seen") == 0.25
    assert c.get_string_channel("name_seen") == "from python"


def test_input_channel_string_truncated_on_char_boundary():
    # 200 two-byte characters: 400 bytes, cut to 254 bytes (127 chars).
    c = _instance(CHANNEL_ORC)
    c.set_input_channel_callback(
        lambda name, t: "é" * 200 if t == "S" else None)
    _perform(c)
    assert c.get_string_channel("name_seen") == "é" * 127


def test_output_channel_callback():
    got = {}
    c = _instance(CHANNEL_ORC)
    c.set_output_channel_callback(lambda name, value: got.__setitem__(name, value))
    _perform(c)
    assert got == {"meter": 0.5, "label": "hi"}

    c.set_output_channel_callback(None)
    got.clear()
    c.perform_ksmps()
    assert got == {}


def test_keyboard_callback():
    types = []

    def key(kind):
        types.append(kind)
        return ord("A")

    c = _instance(KEY_ORC)
    assert c.set_keyboard_callback(key) == 0
    _perform(c)
    assert c.get_control_channel("key") == ord("A")
    assert KeyCallbackType.KBD_TEXT in types
    assert c.set_keyboard_callback(None) == 0


def test_keyboard_callback_swap_and_remove():
    c = _instance(KEY_ORC)
    assert c.set_keyboard_callback(lambda kind: ord("A")) == 0
    _perform(c)
    assert c.get_control_channel("key") == ord("A")
    assert c.set_keyboard_callback(lambda kind: ord("C")) == 0
    c.perform_ksmps()
    assert c.get_control_channel("key") == ord("C")
    assert c.set_keyboard_callback(None) == 0
    c.perform_ksmps()
    assert c.get_control_channel("key") == -1  # no key; stdin not polled


KEY_STRESS_SCRIPT = """
import os, threading, cycsound
c = cycsound.Csound()
c.set_option("-n")
c.set_option("-m0")
c.compile_orc('ksmps = 1\\ninstr 1\\nkk sensekey\\nendin\\n')
c.set_keyboard_callback(lambda kind: 0)
c.event_string("i 1 0 3600")
threading.Thread(target=c.run, daemon=True).start()
for i in range(20000):
    c.set_keyboard_callback(None if i % 2 else (lambda kind: 0))
print("done", flush=True)
os._exit(0)
"""


def test_keyboard_callback_swap_during_performance():
    # Liveness only: the old remove/re-register path freed list entries under
    # the performing thread, but that use-after-free did not crash in testing.
    r = subprocess.run([sys.executable, "-c", KEY_STRESS_SCRIPT],
                       capture_output=True, text=True, timeout=60,
                       stdin=subprocess.DEVNULL)
    assert r.returncode == 0, r.stderr[-2000:]
    assert "done" in r.stdout


def test_dealloc_with_callbacks_installed():
    c = _instance(CHANNEL_ORC)
    c.set_message_callback(lambda attr, text: None)
    c.set_input_channel_callback(lambda name, t: None)
    c.set_output_channel_callback(lambda name, v: None)
    c.set_keyboard_callback(lambda kind: 0)
    _perform(c)
    del c
    gc.collect()


## ---------------------------------------------------------------------------
## B: C hooks

HOOKS_C = r"""
#include <stdint.h>
#include <string.h>

/* CS_TYPE starts with `char *varTypeName`. */
static const char *type_name(const void *type) {
    return *(const char *const *) type;
}

void msg_hook(void *ctx, void *cs, int32_t attr, const char *text) {
    if (strstr(text, "hook-probe")) (*(int32_t *) ctx)++;
}

void in_hook(void *ctx, void *cs, const char *name, void *value,
             const void *type) {
    if (type_name(type)[0] == 'k') *(double *) value = *(double *) ctx;
}

void out_hook(void *ctx, void *cs, const char *name, void *value,
              const void *type) {
    if (type_name(type)[0] == 'k') *(double *) ctx = *(double *) value;
}

int32_t key_hook(void *ctx, void *p, uint32_t type) {
    *(int32_t *) p = *(int32_t *) ctx;
    return 0;
}
"""


@pytest.fixture(scope="module")
def hooks(tmp_path_factory):
    cc = shutil.which("cc") or shutil.which("gcc") or shutil.which("clang")
    if cc is None:
        pytest.skip("no C compiler")
    d = tmp_path_factory.mktemp("hooks")
    (d / "hooks.c").write_text(HOOKS_C)
    so = d / "hooks.so"
    subprocess.run([cc, "-shared", "-fPIC", "-o", str(so), str(d / "hooks.c")],
                   check=True)
    lib = ctypes.CDLL(str(so))
    return {name: ctypes.cast(getattr(lib, name), ctypes.c_void_p).value
            for name in ("msg_hook", "in_hook", "out_hook", "key_hook")}


def test_message_hook(hooks):
    count = ctypes.c_int32(0)
    c = _instance()
    c.set_message_hook(hooks["msg_hook"], ctypes.addressof(count))
    c.message("hook-probe")
    c.message("other")
    assert count.value == 1
    c.set_message_hook(0)
    c.message("hook-probe")
    assert count.value == 1


def test_message_hook_and_callback_both_run(hooks):
    count = ctypes.c_int32(0)
    got = []
    c = _instance()
    c.set_message_hook(hooks["msg_hook"], ctypes.addressof(count))
    c.set_message_callback(lambda attr, text: got.append(text))
    c.message("hook-probe")
    assert count.value == 1 and got == ["hook-probe"]

    # Removing one keeps the other installed.
    c.set_message_callback(None)
    c.message("hook-probe")
    assert count.value == 2 and got == ["hook-probe"]


def test_channel_hooks(hooks):
    supply = ctypes.c_double(0.75)
    sink = ctypes.c_double(0.0)
    c = _instance(CHANNEL_ORC)
    c.set_input_channel_hook(hooks["in_hook"], ctypes.addressof(supply))
    c.set_output_channel_hook(hooks["out_hook"], ctypes.addressof(sink))
    _perform(c)
    assert c.get_control_channel("gain_seen") == 0.75
    assert sink.value == 0.5


def test_channel_hook_then_callback_overrides(hooks):
    supply = ctypes.c_double(0.75)
    c = _instance(CHANNEL_ORC)
    c.set_input_channel_hook(hooks["in_hook"], ctypes.addressof(supply))
    c.set_input_channel_callback(lambda name, t: 0.125 if t == "k" else None)
    _perform(c)
    assert c.get_control_channel("gain_seen") == 0.125


def test_keyboard_hook(hooks):
    key = ctypes.c_int32(ord("z"))
    c = _instance(KEY_ORC)
    assert c.register_keyboard_hook(
        hooks["key_hook"], ctypes.addressof(key),
        KeyCallbackType.KBD_TEXT) == 0
    _perform(c)
    assert c.get_control_channel("key") == ord("z")
    c.remove_keyboard_hook(hooks["key_hook"])


def test_keyboard_hook_rejects_null():
    with pytest.raises(ValueError):
        _instance().register_keyboard_hook(0)


def test_ctypes_function_as_hook():
    # Any C-callable address works, including a ctypes callback.
    got = []
    proto = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p,
                             ctypes.c_int32, ctypes.c_char_p)
    fn = proto(lambda ctx, cs, attr, text: got.append(text))
    c = _instance()
    c.set_message_hook(ctypes.cast(fn, ctypes.c_void_p).value)
    c.message("via-ctypes")
    assert b"via-ctypes" in got
    c.set_message_hook(0)


## ---------------------------------------------------------------------------
## Lifetime and threads


SHUTDOWN_SCRIPT = """
import sys, cycsound
seen = []
sys.unraisablehook = seen.append  # keeps a traceback -> frame -> c cycle
c = cycsound.Csound()
c.set_option("-n")
def boom(attr, text):
    raise ValueError("boom")
c.set_message_callback(boom)
c.message("x")
print("ok", len(seen))
"""


def test_interpreter_exit_with_live_callback():
    # Csound's C atexit handler destroys the still-live instance after Python
    # has finalized; its messages must not wait for the GIL.
    r = subprocess.run([sys.executable, "-c", SHUTDOWN_SCRIPT],
                       capture_output=True, text=True, timeout=30,
                       stdin=subprocess.DEVNULL)
    assert r.returncode == 0, r.stderr
    assert "ok 1" in r.stdout


def test_keyboard_callback_survives_reset():
    c = _instance(KEY_ORC)
    c.set_keyboard_callback(lambda kind: ord("B"))
    _perform(c)
    c.reset()  # also clears options
    for opt in ("-n", "-d"):
        c.set_option(opt)
    assert c.compile_orc(KEY_ORC) == 0
    _perform(c)
    assert c.get_control_channel("key") == ord("B")


def test_callbacks_from_performance_thread():
    import threading

    got = []
    c = _instance(CHANNEL_ORC)
    c.set_output_channel_callback(
        lambda name, value: got.append(threading.get_ident()))
    c.event_string("i 1 0 0.1")
    t = threading.Thread(target=c.run)
    t.start()
    t.join(timeout=30)
    assert not t.is_alive()
    assert got and set(got) == {t.ident}


## ---------------------------------------------------------------------------
## Deadlocks: a performing thread holds API_lock while a callback waits for
## the GIL. Each case runs in a subprocess so a regression fails, not hangs.

def _run_bounded(script, timeout=30):
    r = subprocess.run([sys.executable, "-c", script], capture_output=True,
                       text=True, timeout=timeout, stdin=subprocess.DEVNULL)
    assert r.returncode == 0, r.stderr[-2000:]
    return r.stdout


COMPILE_TREE_SCRIPT = """
import os, threading, time, cycsound
c = cycsound.Csound()
c.set_option("-n")
c.set_option("-m0")
c.compile_orc('ksmps = 1\\ninstr 1\\nkv = 1\\noutvalue "x", kv\\nendin\\n')
n = [0]
def cb(name, value):
    n[0] += 1
c.set_output_channel_callback(cb)
c.event_string("i 1 0 3600")
threading.Thread(target=c.run, daemon=True).start()
while n[0] < 1000:
    time.sleep(0.01)
for i in range(100):
    tree = c.parse_orc("instr %d\\nendin\\n" % (i + 10))
    assert c.compile_tree(tree) == 0
    c.delete_tree(tree)
print("done", flush=True)
os._exit(0)
"""


def test_compile_tree_while_performing_with_callback():
    assert "done" in _run_bounded(COMPILE_TREE_SCRIPT)


UDP_CLOSE_SCRIPT = """
import cycsound
c = cycsound.Csound()
c.set_option("-n")
c.set_message_callback(lambda attr, text: None)
assert c.udp_server_start(%d) == 0
cycsound.sleep(100)
print("close", c.udp_server_close())
"""


def test_udp_server_close_with_message_callback():
    # The server thread prints on exit while close() joins it.
    import socket
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    assert "close 0" in _run_bounded(UDP_CLOSE_SCRIPT % port)


def test_udp_console_and_message_callback_are_exclusive():
    c = _instance()
    c.set_message_callback(lambda attr, text: None)
    with pytest.raises(RuntimeError):
        c.udp_console("127.0.0.1", 9, 0)
    c.set_message_callback(None)
    assert c.udp_console("127.0.0.1", 9, 0) == 0
    with pytest.raises(RuntimeError):
        c.set_message_callback(lambda attr, text: None)
    c.stop_udp_console()
    c.set_message_callback(lambda attr, text: None)
