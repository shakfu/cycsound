"""Host-implemented realtime MIDI (csound_rtmidi.h external callbacks)."""

import ctypes
import sys

import pytest

import cycsound


IN_ORC = """
ksmps = 32
chn_k "note", 2
chn_k "vel", 2
instr 1
  chnset notnum(), "note"
  chnset veloc(), "vel"
endin
"""

OUT_ORC = """
ksmps = 32
instr 1
  midiout_i 144, 1, 60, 100
endin
"""


@pytest.fixture
def unraisable(monkeypatch):
    seen = []
    monkeypatch.setattr(sys, "unraisablehook", seen.append)
    return seen


def _host_midi(orc, *opts):
    c = cycsound.Csound()
    for opt in ("-n", "-d", "-m0", *opts):
        c.set_option(opt)
    c.set_host_midi_io()
    assert c.compile_orc(orc) == 0
    return c


def test_midi_in_callbacks():
    c = _host_midi(IN_ORC, "-Mhostdev")
    pending = [bytes([0x90, 61, 99])]
    calls = []

    def on_open(device):
        calls.append(("open", device))
        return "handle"

    def on_read(handle, nbytes):
        assert handle == "handle"
        assert nbytes > 0
        return pending.pop() if pending else b""

    def on_close(handle):
        calls.append(("close", handle))

    c.set_midi_in_callbacks(on_open, on_read, on_close)
    assert c.start() == 0
    for _ in range(8):
        assert c.perform_ksmps() == 0
    assert c.get_control_channel("note") == 61.0
    assert c.get_control_channel("vel") == 99.0
    c.reset()
    assert calls == [("open", "hostdev"), ("close", "handle")]


def test_midi_out_callbacks():
    c = _host_midi(OUT_ORC, "-Qhostout")
    written = []
    c.set_midi_out_callbacks(
        open=lambda device: device,
        write=lambda handle, data: written.append((handle, data)),
    )
    c.event_string("i 1 0 0.01")
    assert c.start() == 0
    for _ in range(8):
        c.perform_ksmps()
    assert ("hostout", bytes([0x90, 60, 100])) in written


def test_midi_callbacks_survive_reset():
    c = _host_midi(IN_ORC, "-Mhostdev")
    pending = [bytes([0x90, 62, 90])]
    c.set_midi_in_callbacks(
        open=lambda device: None,
        read=lambda handle, n: pending.pop() if pending else None,
    )
    c.reset()  # reallocates Csound's MIDI globals with dummy callbacks
    for opt in ("-n", "-d", "-m0", "-Mhostdev"):
        c.set_option(opt)
    assert c.compile_orc(IN_ORC) == 0
    assert c.start() == 0
    for _ in range(8):
        c.perform_ksmps()
    assert c.get_control_channel("note") == 62.0


def test_midi_read_too_long_is_error(unraisable):
    c = _host_midi(IN_ORC, "-Mhostdev")
    messages = []
    c.set_message_callback(lambda attr, text: messages.append(text))
    c.set_midi_in_callbacks(
        open=lambda device: None,
        read=lambda handle, n: bytes(n + 1),
    )
    assert c.start() == 0
    c.perform_ksmps()
    assert any("error reading MIDI device" in m for m in messages)
    assert isinstance(unraisable[0].exc_value, ValueError)


def test_midi_open_failure_and_error_string_hook(unraisable):
    c = _host_midi(IN_ORC, "-Mhostdev")
    messages = []
    c.set_message_callback(lambda attr, text: messages.append(text))
    text = ctypes.create_string_buffer(b"host refused")
    hook = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_int32)(
        lambda code: ctypes.addressof(text))
    c.set_midi_error_string_hook(ctypes.cast(hook, ctypes.c_void_p).value)

    def on_open(device):
        raise OSError("no such device")

    c.set_midi_in_callbacks(open=on_open, read=lambda handle, n: None)
    assert c.start() != 0
    assert any("host refused" in m for m in messages)
    assert isinstance(unraisable[0].exc_value, OSError)
    c.set_midi_error_string_hook(0)
    # Clean up while the message callback still captures the error count.
    c.reset()
    assert any("1 errors in performance" in m for m in messages)


def test_midi_device_list_callback():
    c = _host_midi(IN_ORC)
    devices = {
        False: [{"device_name": "in A", "device_id": "0"},
                {"device_name": "in B", "device_id": "1",
                 "interface_name": "usb", "midi_module": "host"}],
        True: [],
    }
    c.set_midi_device_list_callback(lambda is_output: devices[is_output])
    listed = c.get_midi_dev_list(0)
    assert [d["device_name"] for d in listed] == ["in A", "in B"]
    assert listed[1]["interface_name"] == "usb"
    assert listed[1]["midi_module"] == "host"
    assert listed[0]["interface_name"] == ""
    assert c.get_midi_dev_list(1) == []


def test_midi_callback_type_check():
    c = cycsound.Csound()
    with pytest.raises(TypeError):
        c.set_midi_in_callbacks(open="not callable")
    c.set_midi_in_callbacks()  # all None: nothing installed
