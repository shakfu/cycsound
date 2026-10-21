"""Csound's circular buffer (csound_circular_buffer.h)."""

from array import array

import pytest

import cycsound


@pytest.fixture
def csound():
    c = cycsound.Csound()
    c.set_option("-n")
    return c


def test_float_round_trip(csound):
    buf = csound.create_circular_buffer(8)
    assert buf.element_size == cycsound.get_size_of_cs_float() == 8
    assert (buf.size, buf.read_available(), buf.write_available()) == (8, 0, 8)
    assert buf.write(array("d", [1.0, 2.0, 3.0])) == 3
    assert buf.read_available() == 3
    assert array("d", buf.peek(2)).tolist() == [1.0, 2.0]
    assert array("d", buf.read(10)).tolist() == [1.0, 2.0, 3.0]
    assert buf.read(1) == b""
    assert buf.address != 0


def test_partial_write_when_full_and_wraparound(csound):
    buf = csound.create_circular_buffer(4, element_size=2)
    assert buf.write(bytes(range(10))) == 4  # 5 elements offered, 4 fit
    assert buf.write(b"zz") == 0
    assert buf.read(3) == bytes(range(6))
    assert buf.write(b"abcdef") == 3  # wraps past the end
    assert buf.read(4) == bytes([6, 7]) + b"abcdef"


def test_flush_and_validation(csound):
    buf = csound.create_circular_buffer(4, element_size=4)
    buf.write(b"\x00" * 8)
    buf.flush()
    assert buf.read_available() == 0
    with pytest.raises(ValueError):
        buf.write(b"abc")  # not whole elements
    assert buf.write(b"") == 0
    with pytest.raises(ValueError):
        csound.create_circular_buffer(0)


def test_stale_after_reset(csound):
    buf = csound.create_circular_buffer(4)
    csound.reset()
    with pytest.raises(ValueError):
        buf.read(1)
    del buf  # must not free pool memory reset() already freed
