# cython: language_level=3
"""Cython bindings for the Csound 7 Host API."""

import atexit
import weakref
from collections import deque, namedtuple
from enum import Enum, IntEnum

from libc cimport stdio
from libc.stdint cimport int32_t, uint32_t, uintptr_t
from libc.stdlib cimport malloc, free
from libc.string cimport memcpy, strncpy
from cpython.exc cimport PyErr_SetObject, PyErr_WriteUnraisable
from cpython.ref cimport PyObject, Py_INCREF, Py_DECREF

cimport csound as cs


## ----------------------------------------------------------------------------
## Callback hooks
##
## A hook is a C function called without the GIL. A Python callback runs after
## the hook (if both are set), with the GIL. Each slot has one trampoline
## installed in Csound; it finds the hooks through the instance's host data,
## which points at Csound.hooks.

ctypedef void (*message_hook_t)(void *ctx, cs.CSOUND *csound, int32_t attr,
                                const char *text) noexcept nogil
ctypedef void (*channel_hook_t)(void *ctx, cs.CSOUND *csound, const char *name,
                                void *value, const void *channel_type) noexcept nogil
ctypedef int32_t (*keyboard_hook_t)(void *ctx, void *p,
                                    uint32_t type) noexcept nogil

cdef struct HookState:
    void *owner  # borrowed Csound *; the instance outlives its CSOUND
    message_hook_t message_hook
    void *message_ctx
    channel_hook_t input_hook
    void *input_ctx
    channel_hook_t output_hook
    void *output_ctx
    bint py_message
    bint py_input
    bint py_output
    bint py_midi  # some MIDI slot holds a Python callable
    bint py_graph
    bint py_file

# External MIDI slots: Csound._midi index of each callback.
cdef enum:
    MIDI_IN_OPEN = 0
    MIDI_READ = 1
    MIDI_IN_CLOSE = 2
    MIDI_OUT_OPEN = 3
    MIDI_WRITE = 4
    MIDI_OUT_CLOSE = 5
    MIDI_DEV_LIST = 6
    MIDI_ERROR_STRING = 7
    MIDI_SLOTS = 8

# Graph display and file callback slots: Csound._graph / Csound._file index.
cdef enum:
    GRAPH_MAKE = 0
    GRAPH_DRAW = 1
    GRAPH_KILL = 2
    GRAPH_EXIT = 3
    GRAPH_SLOTS = 4
    FILE_OPEN_SOUND = 0
    FILE_OPEN = 1
    FILE_NOTIFY = 2
    FILE_SLOTS = 3

# Input string channels: invalue sizes the destination to at least 256 bytes.
cdef enum:
    INVALUE_STRING_MAX = 256

cdef extern from *:
    """
    #if PY_VERSION_HEX >= 0x030D0000
    #define cycsound_py_finalizing() Py_IsFinalizing()
    #else
    #define cycsound_py_finalizing() _Py_IsFinalizing()
    #endif
    """
    int cycsound_py_finalizing() nogil
    int Py_IsInitialized() nogil

# Instances with callbacks, detached before Python finalizes. Csound's own
# C atexit handler destroys live instances later, and its messages must not
# reach a trampoline that needs the GIL of a finalized interpreter.
_with_callbacks = weakref.WeakSet()


# Live CsoundPerformanceThread objects by CS_PERF_THREAD address. Also maps
# request_callback()'s C callback, which gets only that address, back.
_perf_threads = weakref.WeakValueDictionary()


@atexit.register
def _detach_all():
    # Stop performance threads first: a running one calls into Csound and
    # into callbacks after Python finalizes.
    for t in list(_perf_threads.values()):
        (<CsoundPerformanceThread>t)._shutdown()
    for c in list(_with_callbacks):
        (<Csound>c)._detach()


## ----------------------------------------------------------------------------
## Message Types

class Msg(Enum):
    """Message types (only one can be specified).

    For example: ``Msg.DEFAULT | Color.FG_CYAN | Color.FG_BOLD``
    """
    DEFAULT       = 0x0000    # standard message
    ERROR         = 0x1000    # error message (initerror, perferror, etc.)
    ORCH          = 0x2000    # orchestra opcodes (e.g. printks)
    REALTIME      = 0x3000    # for progress display and heartbeat characters
    WARNING       = 0x4000    # warning messages
    STDOUT        = 0x5000    # stdout messages


class Color(Enum):
    """Use the bitwise OR of any of these with messages."""

    FG_BLACK      = 0x0100
    FG_RED        = 0x0101
    FG_GREEN      = 0x0102
    FG_YELLOW     = 0x0103
    FG_BLUE       = 0x0104
    FG_MAGENTA    = 0x0105
    FG_CYAN       = 0x0106
    FG_WHITE      = 0x0107

    FG_BOLD       = 0x0008
    FG_UNDERLINE  = 0x0080

    BG_BLACK      = 0x0200
    BG_RED        = 0x0210
    BG_GREEN      = 0x0220
    BG_ORANGE     = 0x0230
    BG_BLUE       = 0x0240
    BG_MAGENTA    = 0x0250
    BG_CYAN       = 0x0260
    BG_GREY       = 0x0270


class Mask(Enum):
    """Use the bitwise OR of any of these with messages."""

    TYPE_MASK     = 0x7000
    FG_COLOR_MASK = 0x0107
    FG_ATTR_MASK  = 0x0088
    BG_COLOR_MASK = 0x0270


## ----------------------------------------------------------------------------
## Status and Event Type Enums (cpdef for Python accessibility)

cpdef enum Status:
    """Csound return status codes."""
    SUCCESS = 0
    ERROR = -1
    INITIALIZATION = -2
    PERFORMANCE = -3
    MEMORY = -4
    SIGNAL = -5


cpdef enum EventType:
    """csoundEvent() event types."""
    INSTR = 0     # instrument instance (a numeric "i" event)
    TABLE = 1     # function table instance (an "f" event)
    END = 2       # end event (an "e" event)
    ADVANCE = 3   # score advance event


cpdef enum ChannelBehavior:
    """Control channel hint behaviours (csoundSetControlChannelHints())."""
    NO_HINTS = 0
    INT = 1
    LIN = 2
    EXP = 3


cpdef enum ChannelType:
    """Channel kinds and direction flags for the bus interface."""
    CONTROL = 1
    AUDIO = 2
    STRING = 3
    PVS = 4
    VAR = 5
    ARRAY = 6
    TYPE_MASK = 15
    INPUT = 16
    OUTPUT = 32


cpdef enum PvsWindow:
    """Analysis window types for :meth:`Csound.init_pvs_channel`."""
    HAMMING = 0
    HANN = 1
    KAISER = 2
    CUSTOM = 3
    BLACKMAN = 4
    BLACKMAN_EXACT = 5
    NUTTALLC3 = 6
    BHARRIS_3 = 7
    BHARRIS_MIN = 8
    RECT = 9


cpdef enum PvsFormat:
    """Analysis data formats for :meth:`Csound.init_pvs_channel`."""
    AMP_FREQ = 0
    AMP_PHASE = 1
    COMPLEX = 2
    TRACKS = 3


cpdef enum KeyCallbackType:
    """Keyboard callback types (``csoundRegisterKeyboardCallback``)."""
    KBD_EVENT = 1  # key press and release events (sensekey with two outputs)
    KBD_TEXT = 2   # typed text (sensekey, readline)


cpdef enum UgenArgType:
    """Unit generator argument types (``UGEN_ARG_TYPE``)."""
    I = 0        # i-rate scalar
    K = 1        # k-rate scalar
    A = 2        # a-rate block of ksmps samples
    S = 3        # string
    F = 4        # fsig
    UNKNOWN = 5


cpdef enum GraphPolarity:
    """``GraphWindow.polarity`` values (cwindow.h)."""
    NOPOL = 0
    NEGPOL = 1
    POSPOL = 2
    BIPOL = 3


class FileType(IntEnum):
    """File types reported to the file-open callback (``CSOUND_FILETYPES``)."""
    UNKNOWN = 0
    UNIFIED_CSD = 1
    ORCHESTRA = 2
    SCORE = 3
    ORC_INCLUDE = 4
    SCO_INCLUDE = 5
    SCORE_OUT = 6
    SCOT = 7
    OPTIONS = 8
    EXTRACT_PARMS = 9
    RAW_AUDIO = 10
    IRCAM = 11
    AIFF = 12
    AIFC = 13
    WAVE = 14
    AU = 15
    SD2 = 16
    W64 = 17
    WAVEX = 18
    FLAC = 19
    CAF = 20
    WVE = 21
    OGG = 22
    MPC2K = 23
    RF64 = 24
    AVR = 25
    HTK = 26
    MAT4 = 27
    MAT5 = 28
    NIST = 29
    PAF = 30
    PVF = 31
    SDS = 32
    SVX = 33
    VOC = 34
    XI = 35
    MPEG = 36
    UNKNOWN_AUDIO = 37
    SOUNDFONT = 38
    STD_MIDI = 39
    MIDI_SYSEX = 40
    HETRO = 41
    HETROT = 42
    PVC = 43
    PVCEX = 44
    CVANAL = 45
    LPC = 46
    ATS = 47
    LORIS = 48
    SDIF = 49
    HRTF = 50
    UNUSED = 51
    LADSPA_PLUGIN = 52
    SNAPSHOT = 53
    FTABLES_TEXT = 54
    FTABLES_BINARY = 55
    XSCANU_MATRIX = 56
    FLOATS_TEXT = 57
    FLOATS_BINARY = 58
    INTEGER_TEXT = 59
    INTEGER_BINARY = 60
    IMAGE_PNG = 61
    POSTSCRIPT = 62
    SCRIPT_TEXT = 63
    OTHER_TEXT = 64
    OTHER_BINARY = 65


GraphWindow = namedtuple("GraphWindow", (
    "windid", "caption", "data", "polarity", "max", "min", "absmax",
    "oabsmax", "danflag", "absflag", "waitflg"))
GraphWindow.__doc__ = """Snapshot of a Csound graph window (``WINDAT``) for graph callbacks."""


## ----------------------------------------------------------------------------
## Module-level functions

def initialize(flags: int = 0) -> int:
    """Initialize the Csound library with specific flags.

    Called internally by ``Csound()``, so there is generally no need to use it
    explicitly unless you need to avoid default initialization that sets signal
    handlers and ``atexit()`` callbacks.

    Returns zero on success, positive if already initialized, negative on error.
    """
    return cs.csoundInitialize(flags)


def get_version() -> int:
    """Return the version number times 1000 (7.00.0 = 7000)."""
    return cs.csoundGetVersion()


def get_size_of_cs_float() -> int:
    """Return the size of cs_float in bytes (4 for float, 8 for double)."""
    return cs.csoundGetSizeOfCsFloat()


def get_size_of_cs_double() -> int:
    """Return the size of cs_double in bytes."""
    return cs.csoundGetSizeOfCsDouble()


# Pre-beta.18 name; Csound keeps csoundGetSizeOfMYFLT only for compatibility.
get_size_of_myflt = get_size_of_cs_float


def set_global_env(str name, value) -> int:
    """Set an environment variable for all Csound instances in this process.

    Pass ``None`` as ``value`` to delete the variable. Returns zero on
    success. This must be called before creating any ``Csound`` instance for
    variables that are read at creation time (e.g. ``OPCODE7DIR64``).
    """
    cdef bytes value_b
    if value is None:
        return cs.csoundSetGlobalEnv(name.encode(), NULL)
    value_b = value.encode()
    return cs.csoundSetGlobalEnv(name.encode(), value_b)


def sleep(int milliseconds):
    """Suspend the calling thread for at least the given number of ms."""
    cdef size_t ms = milliseconds
    with nogil:
        cs.csoundSleep(ms)


## ----------------------------------------------------------------------------
## Helper classes

cdef class ArgArray:
    """Builds a NULL-terminated ``const char**`` argv from Python strings."""

    cdef const char **argv
    cdef int argc
    cdef list _refs  # keeps the encoded bytes objects alive

    def __cinit__(self, tuple args):
        self.argc = len(args)
        self._refs = []
        self.argv = <const char **>malloc((self.argc + 1) * sizeof(char *))
        if self.argv is NULL:
            raise MemoryError()
        cdef bytes encoded
        for i, arg in enumerate(args):
            encoded = arg.encode() if isinstance(arg, str) else bytes(arg)
            self._refs.append(encoded)
            self.argv[i] = <const char *>encoded
        self.argv[self.argc] = NULL

    def __dealloc__(self):
        if self.argv is not NULL:
            free(self.argv)
            self.argv = NULL

    def as_list(self):
        return [self.argv[i].decode() for i in range(self.argc)]


cdef class Tree:
    """Wraps a parsed orchestra abstract syntax tree (``TREE *``)."""

    cdef cs.TREE *ptr

    @staticmethod
    cdef Tree from_ptr(cs.TREE *ptr):
        cdef Tree obj = Tree.__new__(Tree)
        obj.ptr = ptr
        return obj

    @property
    def is_null(self) -> bool:
        return self.ptr is NULL


cdef class Params:
    """Read-only view of a Csound instance's options (``const OPARMS *``).

    In Csound 7 the parameters structure is read-only; options are configured
    with command-line flags via :meth:`Csound.set_option`. The wrapped pointer
    is owned by the Csound instance and is valid for its lifetime.
    """

    cdef const cs.OPARMS *ptr

    @staticmethod
    cdef Params from_ptr(const cs.OPARMS *ptr):
        cdef Params obj = Params.__new__(Params)
        obj.ptr = ptr
        return obj

    @property
    def debug_mode(self) -> int:
        return self.ptr.odebug

    @property
    def message_level(self) -> int:
        return self.ptr.msglevel

    @property
    def displays(self) -> int:
        return self.ptr.displays

    @property
    def ring_bell(self) -> int:
        return self.ptr.ringbell

    @property
    def heartbeat(self) -> int:
        return self.ptr.heartbeat

    @property
    def in_buffer_samples(self) -> int:
        return self.ptr.inbufsamps

    @property
    def out_buffer_samples(self) -> int:
        return self.ptr.outbufsamps

    @property
    def hardware_buffer_frames(self) -> int:
        return self.ptr.oMaxLag

    @property
    def tempo(self) -> float:
        return self.ptr.cmdTempo

    @property
    def sample_rate_override(self) -> float:
        return self.ptr.sr_override

    @property
    def control_rate_override(self) -> float:
        return self.ptr.kr_override

    @property
    def ksmps_override(self) -> int:
        return self.ptr.ksmps_override

    @property
    def nchnls_override(self) -> int:
        return self.ptr.nchnls_override

    @property
    def nchnls_i_override(self) -> int:
        return self.ptr.nchnls_i_override

    @property
    def e0dbfs_override(self) -> float:
        return self.ptr.e0dbfs_override

    @property
    def number_of_threads(self) -> int:
        return self.ptr.numThreads

    @property
    def syntax_check_only(self) -> int:
        return self.ptr.syntaxCheckOnly

    @property
    def use_csd_line_counts(self) -> int:
        return self.ptr.useCsdLineCounts

    @property
    def sample_accurate(self) -> int:
        return self.ptr.sampleAccurate

    @property
    def realtime_mode(self) -> int:
        return self.ptr.realtime

    @property
    def daemon(self) -> int:
        return self.ptr.daemon

    @property
    def recursion_depth(self) -> int:
        return self.ptr.recursion_depth

    @property
    def input_filename(self):
        if self.ptr.infilename is NULL:
            return None
        return self.ptr.infilename.decode()

    @property
    def output_filename(self):
        if self.ptr.outfilename is NULL:
            return None
        return self.ptr.outfilename.decode()

    def __repr__(self):
        return (f"<Params msglevel={self.message_level} "
                f"sr_override={self.sample_rate_override} "
                f"ksmps_override={self.ksmps_override}>")


cdef class PvsData:
    """An fsig channel's analysis frame (``PVSDAT *``).

    Returned by :meth:`Csound.init_pvs_channel`. The data is owned by the
    Csound instance and is invalid after :meth:`Csound.reset`.
    """

    cdef cs.PVSDAT *ptr
    cdef object _owner  # keeps the Csound instance alive
    cdef unsigned long _generation  # owner's reset count at creation

    @staticmethod
    cdef PvsData from_ptr(cs.PVSDAT *ptr, object owner):
        cdef PvsData obj = PvsData.__new__(PvsData)
        obj.ptr = ptr
        obj._owner = owner
        obj._generation = owner._generation
        return obj

    cdef _check(self):
        if self.ptr is NULL:
            raise ValueError("PvsData is not bound to an fsig channel")
        if self._owner._generation != self._generation:
            # reset() freed the channel storage behind ptr.
            self.ptr = NULL
            raise ValueError("PvsData is stale: its Csound instance was reset")

    @property
    def fft_size(self) -> int:
        self._check()
        return cs.csoundPvsDataFFTSize(self.ptr)

    @property
    def overlap(self) -> int:
        self._check()
        return cs.csoundPvsDataOverlap(self.ptr)

    @property
    def window_size(self) -> int:
        self._check()
        return cs.csoundPvsDataWindowSize(self.ptr)

    @property
    def format(self) -> int:
        self._check()
        return cs.csoundPvsDataFormat(self.ptr)

    @property
    def framecount(self) -> int:
        self._check()
        return cs.csoundPvsDataFramecount(self.ptr)

    def get_frame(self) -> list:
        """Return the frame as ``fft_size + 2`` floats (bin pairs)."""
        self._check()
        cdef const float *p = cs.csoundGetPvsData(self.ptr)
        if p is NULL:
            return []
        cdef int n = cs.csoundPvsDataFFTSize(self.ptr) + 2
        return [p[i] for i in range(n)]

    def set_frame(self, object values):
        """Overwrite the frame with exactly ``fft_size + 2`` floats."""
        self._check()
        cdef int n = cs.csoundPvsDataFFTSize(self.ptr) + 2
        if len(values) != n:
            raise ValueError(f"frame expects {n} values (fft_size + 2), "
                             f"got {len(values)}")
        # Not csoundSetPvsData(): it copies frame.size bytes, which exceeds
        # (N + 2) floats once get_pvs_channel() has copied in a smaller N.
        cdef float *p = <float *>cs.csoundGetPvsData(self.ptr)
        if p is NULL:
            raise ValueError("fsig channel has no frame storage")
        for i in range(n):
            p[i] = values[i]

    def __repr__(self):
        if self.ptr is NULL:
            return "<PvsData unbound>"
        return (f"<PvsData fft_size={self.fft_size} overlap={self.overlap} "
                f"window_size={self.window_size} format={self.format}>")


# Size of the OPDS header that starts every opcode's data block; the argument
# pointers follow it (see Csound.append_opcode).
OPDS_SIZE = sizeof(cs.OPDS)


cdef class ArrayChannel:
    """An array channel (``ARRAYDAT *``) from :meth:`Csound.init_array_channel`.

    The storage belongs to the Csound instance and is invalid after
    :meth:`Csound.reset`. Accesses take no lock: do not write while the
    orchestra reads the channel.
    """

    cdef cs.ARRAYDAT *ptr
    cdef Csound _owner
    cdef unsigned long _generation

    @staticmethod
    cdef ArrayChannel from_ptr(cs.ARRAYDAT *ptr, Csound owner):
        cdef ArrayChannel obj = ArrayChannel.__new__(ArrayChannel)
        obj.ptr = ptr
        obj._owner = owner
        obj._generation = owner._generation
        return obj

    cdef _check(self):
        if self._owner is None or self._owner._generation != self._generation:
            raise ValueError("ArrayChannel is stale: its Csound instance was reset")

    @property
    def type(self) -> str:
        """Element type name, e.g. "k", "a" or "S"."""
        self._check()
        cdef const char *t = cs.csoundArrayDataType(self.ptr)
        return "" if t is NULL else t.decode()

    @property
    def dimensions(self) -> int:
        self._check()
        return cs.csoundArrayDataDimensions(self.ptr)

    @property
    def sizes(self) -> tuple:
        """Length of each dimension."""
        self._check()
        cdef const int32_t *z = cs.csoundArrayDataSizes(self.ptr)
        return tuple(z[i] for i in range(cs.csoundArrayDataDimensions(self.ptr)))

    @property
    def data_address(self) -> int:
        self._check()
        return <uintptr_t>cs.csoundGetArrayData(self.ptr)

    def __len__(self):
        """Number of elements (the product of :attr:`sizes`)."""
        n = 1
        for z in self.sizes:
            n *= z
        return n

    cdef size_t _floats(self) except? 0:
        # Numeric element types are whole cs_floats: 1 for i/k, ksmps for a.
        if self.type not in ("i", "k", "a"):
            raise TypeError(f"{self.type!r} array: use get_string/set_string "
                            "or data_address")
        return len(self) * (self.ptr.arrayMemberSize // sizeof(cs.cs_float))

    def get(self) -> list:
        """Return the elements of an i/k/a array, flattened in row-major order."""
        self._check()
        cdef size_t n = self._floats()
        cdef const cs.cs_float *p = <const cs.cs_float *>cs.csoundGetArrayData(self.ptr)
        return [p[i] for i in range(n)]

    def set(self, object values):
        """Overwrite every element of an i/k/a array from a flat sequence."""
        self._check()
        cdef size_t n = self._floats()
        if len(values) != n:
            raise ValueError(f"array expects {n} values, got {len(values)}")
        cdef cs.cs_float *buf = <cs.cs_float *>malloc(n * sizeof(cs.cs_float))
        if buf is NULL:
            raise MemoryError()
        try:
            for i in range(n):
                buf[i] = values[i]
            if cs.csoundSetArrayData(self.ptr, buf) != 0:
                raise ValueError("csoundSetArrayData rejected the array")
        finally:
            free(buf)

    cdef cs.STRINGDAT *_string(self, Py_ssize_t index) except NULL:
        self._check()
        if self.type != "S":
            raise TypeError(f"{self.type!r} array has no strings")
        if not 0 <= index < len(self):
            raise IndexError(f"array has no element {index}")
        return <cs.STRINGDAT *>(<char *>cs.csoundGetArrayData(self.ptr)
                                + index * self.ptr.arrayMemberSize)

    def get_string(self, Py_ssize_t index) -> str:
        """Return element ``index`` (row-major) of an S array."""
        cdef cs.STRINGDAT *sd = self._string(index)
        cdef const char *t = cs.csoundGetStringData(self._owner.ptr, sd)
        return "" if t is NULL else t.decode("utf-8", "replace")

    def set_string(self, Py_ssize_t index, str value):
        """Set element ``index`` (row-major) of an S array."""
        cdef cs.STRINGDAT *sd = self._string(index)
        # csoundSetStringData() writes into, or reallocates, an alias's
        # buffer, which belongs to another variable.
        if sd.refcount != 0:
            raise RuntimeError(f"element {index} shares another string's buffer")
        cs.csoundSetStringData(self._owner.ptr, sd, value.encode())

    def __repr__(self):
        if self._owner is None or self._owner._generation != self._generation:
            return "<ArrayChannel stale>"
        return f"<ArrayChannel {self.type}[{']['.join(map(str, self.sizes))}]>"


cdef class CircularBuffer:
    """Csound's single-reader, single-writer ring buffer.

    Created by :meth:`Csound.create_circular_buffer`. Data moves as bytes in
    whole elements of :attr:`element_size` bytes. Pass :attr:`address` to C
    code (e.g. a callback hook) that reads or writes the other end. One
    thread may write while another reads; reading, peeking and flushing
    share the reader role. Invalid after :meth:`Csound.reset`.
    """

    cdef void *ptr
    cdef Csound _owner
    cdef unsigned long _generation

    def __cinit__(self, Csound csound not None, int size, int element_size):
        self.ptr = cs.csoundCreateCircularBuffer(csound.ptr, size, element_size)
        if self.ptr is NULL:
            raise ValueError(f"cannot create a buffer of {size} x {element_size} bytes")
        self._owner = csound
        self._generation = csound._generation

    def __dealloc__(self):
        if (self.ptr is not NULL and self._owner is not None
                and self._owner._generation == self._generation):
            cs.csoundDestroyCircularBuffer(self._owner.ptr, self.ptr)

    cdef _check(self):
        if self._owner is None or self._owner._generation != self._generation:
            raise ValueError("CircularBuffer is stale: its Csound instance was reset")

    @property
    def size(self) -> int:
        """Capacity in elements."""
        self._check()
        return cs.csoundGetSizeCircularBuffer(self._owner.ptr, self.ptr)

    @property
    def element_size(self) -> int:
        """Bytes per element."""
        self._check()
        return cs.csoundGetElementSizeCircularBuffer(self._owner.ptr, self.ptr)

    @property
    def address(self) -> int:
        self._check()
        return <uintptr_t>self.ptr

    def read_available(self) -> int:
        """Elements ready to read."""
        self._check()
        return cs.csoundCheckCircularBuffer(self._owner.ptr, self.ptr, 0)

    def write_available(self) -> int:
        """Free space in elements."""
        self._check()
        return cs.csoundCheckCircularBuffer(self._owner.ptr, self.ptr, 1)

    def write(self, data) -> int:
        """Write whole elements from a bytes-like object; returns elements written."""
        self._check()
        cdef const unsigned char[::1] view = memoryview(data).cast("B")
        if view.shape[0] % self.element_size:
            raise ValueError(f"data is not a whole number of "
                             f"{self.element_size}-byte elements")
        cdef int items = view.shape[0] // self.element_size
        if items == 0:
            return 0
        return cs.csoundWriteCircularBuffer(self._owner.ptr, self.ptr, &view[0], items)

    cdef bytes _read(self, int items, bint peek):
        self._check()
        if items <= 0:
            return b""
        cdef bytearray out = bytearray(items * self.element_size)
        cdef unsigned char *p = out
        cdef int n
        if peek:
            n = cs.csoundPeekCircularBuffer(self._owner.ptr, self.ptr, p, items)
        else:
            n = cs.csoundReadCircularBuffer(self._owner.ptr, self.ptr, p, items)
        return bytes(out[:n * self.element_size])

    def read(self, int items) -> bytes:
        """Remove and return up to ``items`` elements."""
        return self._read(items, False)

    def peek(self, int items) -> bytes:
        """Return up to ``items`` elements without removing them."""
        return self._read(items, True)

    def flush(self):
        """Discard all readable elements. Only call with no active reader."""
        self._check()
        cs.csoundFlushCircularBuffer(self._owner.ptr, self.ptr)


## ----------------------------------------------------------------------------
## Csound

cdef class Csound:
    """Main Csound 7 instance."""

    cdef cs.CSOUND *ptr
    cdef bint ptr_owner
    cdef object _hostdata
    cdef bint _started
    cdef readonly unsigned long _generation  # bumped by reset()
    cdef HookState hooks
    cdef object _message_cb
    cdef object _input_cb
    cdef object _output_cb
    cdef object _keyboard_cb
    cdef object _readline_cb
    cdef bint _keyboard_registered
    cdef unsigned int _keyboard_mask
    cdef bint _message_installed
    cdef bint _message_buffer
    cdef set _keyboard_hooks  # registered hook addresses
    cdef list _midi  # per MIDI_* slot: callable, C address (int) or None
    cdef object _midi_in_handle  # in-open callback's return value
    cdef object _midi_out_handle
    cdef int _midi_dev_count[2]  # device-list sizes Csound allocated for
    cdef list _graph  # per GRAPH_* slot: callable, C address (int) or None
    cdef int _graphable  # last set_is_graphable() value, -1 if never set
    cdef list _file  # per FILE_* slot: callable, C address (int) or None
    cdef cs.SNDFILE_CALLBACKS *_sndfile  # copy re-applied after reset()
    cdef list _opcode_strings  # append_opcode() names/types Csound points at
    cdef object __weakref__

    def __cinit__(self):
        self.ptr = NULL
        self.ptr_owner = False
        self._hostdata = None
        self._started = False
        self._generation = 0
        self.hooks.owner = <void *>self
        self._keyboard_hooks = set()
        self._midi = [None] * MIDI_SLOTS
        self._graph = [None] * GRAPH_SLOTS
        self._graphable = -1
        self._file = [None] * FILE_SLOTS
        self._opcode_strings = []

    def __init__(self, object host_data=None, str opcodedir=None):
        """Create an instance of Csound.

        ``host_data`` may be any Python object; it is kept alive for the
        instance and available as :attr:`host_data`. ``opcodedir``, if given,
        overrides the plugin/opcode directory search path.
        """
        cdef bytes odir_b
        cdef const char *odir = NULL
        if opcodedir is not None:
            odir_b = opcodedir.encode()
            odir = odir_b
        self._hostdata = host_data
        # The C host data is reserved for callback dispatch.
        self.ptr = cs.csoundCreate(&self.hooks, odir)
        if self.ptr is NULL:
            raise MemoryError("csoundCreate failed")
        self.ptr_owner = True

    def __dealloc__(self):
        if self.ptr is not NULL and self.ptr_owner:
            # csoundDestroy() prints messages; no callback may reach this
            # half-deallocated instance.
            self._detach()
            cs.csoundDestroy(self.ptr)
            self.ptr = NULL
        free(self._sndfile)

    cdef _detach(self):
        """Uninstall every callback and hook from the CSOUND instance."""
        if self.ptr is NULL:
            return
        if self._message_installed:
            cs.csoundSetMessageCallback(self.ptr, NULL)
            self._message_installed = False
        self.hooks.py_message = self.hooks.py_input = self.hooks.py_output = False
        self._message_cb = self._input_cb = self._output_cb = None
        self.hooks.message_hook = NULL
        self.hooks.input_hook = self.hooks.output_hook = NULL
        cs.csoundSetInputChannelCallback(self.ptr, NULL)
        cs.csoundSetOutputChannelCallback(self.ptr, NULL)
        cs.csoundRemoveKeyboardCallback(self.ptr, _keyboard_trampoline)
        self._keyboard_registered = False
        # None if the GC cleared it before __dealloc__ (reference cycle).
        hooks = self._keyboard_hooks
        if hooks:
            for addr in hooks:
                cs.csoundRemoveKeyboardCallback(
                    self.ptr, <keyboard_hook_t><uintptr_t>addr)
            hooks.clear()
        self._keyboard_cb = None
        if self._readline_cb is not None:
            cs.csoundSetReadlineCallback(self.ptr, NULL, NULL)
            self._readline_cb = None
        # The MIDI trampolines return without Python once py_midi is clear.
        # Close callbacks are optional, so csoundDestroy() skips them.
        if self.hooks.py_midi:
            self.hooks.py_midi = False
            cs.csoundSetExternalMidiInCloseCallback(self.ptr, NULL)
            cs.csoundSetExternalMidiOutCloseCallback(self.ptr, NULL)
        # The graph and file trampolines return without Python once clear.
        self.hooks.py_graph = self.hooks.py_file = False

    cdef _track(self):
        _with_callbacks.add(self)

    cdef _keyboard_host_input(self):
        # inChar_ starts at -1, which makes sensekey poll stdin and overwrite
        # the callback's key: csoundDoCallback_ returns 1 even on success.
        if self._keyboard_registered or self._keyboard_hooks:
            cs.csoundKeyPress(self.ptr, 0)

    @property
    def host_data(self):
        """Any Python object the host attaches to this instance.

        Settable; the C host data (``csoundSetHostData``) is reserved for
        callback dispatch.
        """
        return self._hostdata

    @host_data.setter
    def host_data(self, object value):
        self._hostdata = value

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        # Csound 7 has no csoundCleanup(); reset() returns the engine to a
        # clean state and releases performance resources.
        self.reset()
        return False

    ## ------------------------------------------------------------------------
    ## Compilation

    def load_plugins(self, str directory) -> int:
        """Load all plugins from a given directory."""
        return cs.csoundLoadPlugins(self.ptr, directory.encode())

    def parse_orc(self, str orc) -> Tree:
        """Parse the given orchestra from a string into a :class:`Tree`."""
        cdef cs.TREE *tree = cs.csoundParseOrc(self.ptr, orc.encode())
        return Tree.from_ptr(tree)

    def compile_tree(self, Tree root, bint async_=False) -> int:
        """Compile a parsed :class:`Tree` into the running engine."""
        cdef int result
        cdef int is_async = async_
        cdef cs.CSOUND *ptr = self.ptr
        cdef cs.TREE *tree = root.ptr
        # A sync merge waits for API_lock, which a performing thread holds
        # while it runs callbacks that need the GIL.
        with nogil:
            result = cs.csoundCompileTree(ptr, tree, is_async)
        return result

    def delete_tree(self, Tree tree):
        """Free the resources associated with a :class:`Tree`."""
        cs.csoundDeleteTree(self.ptr, tree.ptr)
        tree.ptr = NULL

    def compile_orc(self, str orc, bint async_=False) -> int:
        """Parse and compile an orchestra from a string.

        Evaluates any global (i-time) code. Can be called during performance to
        compile new code. With ``async_=True`` the work is queued for an
        asynchronous merge into the running engine.
        """
        cdef bytes encoded = orc.encode()
        cdef const char *cstr = encoded
        cdef int is_async = async_
        cdef int result
        cdef cs.CSOUND *ptr = self.ptr
        with nogil:
            result = cs.csoundCompileOrc(ptr, cstr, is_async)
        return result

    def eval_code(self, str code) -> float:
        """Compile orchestra ``code`` and return the value of its ``return``
        opcode in global (i-time) space, or 0.0 if evaluation fails."""
        cdef bytes encoded = code.encode()
        cdef const char *cstr = encoded
        cdef cs.cs_float result
        cdef cs.CSOUND *ptr = self.ptr
        with nogil:
            result = cs.csoundEvalCode(ptr, cstr)
        return result

    def compile(self, *args) -> int:
        """Compile input files as directed by command-line ``args``.

        Mirrors ``csoundCompile``. Call :meth:`start` (or :meth:`run`)
        afterwards to perform.
        """
        cdef ArgArray params = ArgArray(args)
        return cs.csoundCompile(self.ptr, params.argc, params.argv)

    def compile_csd(self, str csd_filename, bint async_=False) -> int:
        """Compile a CSD file. Returns a non-zero error code on failure."""
        cdef bytes encoded = csd_filename.encode()
        cdef const char *cstr = encoded
        cdef int is_async = async_
        cdef int result
        cdef cs.CSOUND *ptr = self.ptr
        with nogil:
            result = cs.csoundCompileCSD(ptr, cstr, 0, is_async)
        return result

    def compile_csd_text(self, str csd_text, bint async_=False) -> int:
        """Compile CSD code supplied directly as a string (``mode = 1``)."""
        cdef bytes encoded = csd_text.encode()
        cdef const char *cstr = encoded
        cdef int is_async = async_
        cdef int result
        cdef cs.CSOUND *ptr = self.ptr
        with nogil:
            result = cs.csoundCompileCSD(ptr, cstr, 1, is_async)
        return result

    ## ------------------------------------------------------------------------
    ## Performance

    def start(self) -> int:
        """Prepare Csound for performance."""
        cdef int result
        cdef cs.CSOUND *ptr = self.ptr
        with nogil:
            result = cs.csoundStart(ptr)
        if result == 0:
            self._started = True
        return result

    def perform_ksmps(self) -> int:
        """Perform one control block (ksmps frames) of audio.

        Returns 0 during performance, a positive value when the performance
        is finished, or a negative value on error.
        """
        cdef int result
        cdef cs.CSOUND *ptr = self.ptr
        with nogil:
            result = cs.csoundPerformKsmps(ptr)
        return result

    def reset(self):
        """Reset all internal memory and state for a new performance."""
        cdef cs.CSOUND *ptr = self.ptr
        with nogil:
            cs.csoundReset(ptr)
        self._started = False
        self._generation += 1
        if self._message_installed:
            # reset() reverts the string callback to the default printer.
            cs.csoundSetMessageStringCallback(self.ptr, _message_trampoline)
        self._keyboard_host_input()
        # reset() reallocates the MIDI globals with Csound's dummy callbacks.
        for slot in range(MIDI_SLOTS):
            if self._midi[slot] is not None:
                self._install_midi(slot)
        self._midi_in_handle = self._midi_out_handle = None
        # reset() clears isGraphable and the sndfile callbacks. The graph
        # callbacks survive it, unless -d replaced them with dummies.
        if self._graphable >= 0:
            cs.csoundSetIsGraphable(self.ptr, self._graphable)
        for slot in range(GRAPH_SLOTS):
            if self._graph[slot] is not None:
                self._install_graph(slot)
        if self._sndfile is not NULL:
            cs.csoundSetSndfileCallbacks(self.ptr, self._sndfile)
        self._opcode_strings = []  # reset() freed the opcode table

    def run(self) -> int:
        """Convenience: :meth:`start` then loop :meth:`perform_ksmps` to the end.

        Returns 0 on success, the non-zero error code from :meth:`start`, or
        the negative error code from :meth:`perform_ksmps`.
        """
        cdef int result = self.start()
        if result != 0:
            return result
        cdef cs.CSOUND *ptr = self.ptr
        with nogil:
            result = cs.csoundPerformKsmps(ptr)
            while result == 0:
                result = cs.csoundPerformKsmps(ptr)
        return result if result < 0 else 0

    def perform_output_fade(self, unsigned int frames) -> int:
        """Render ``frames`` more sample frames with a linear fade-out.

        Call from the thread that owns performance, after stopping it and
        before destroying the instance. A no-op unless realtime audio output
        is open. Returns zero on success.
        """
        cdef int result
        cdef cs.CSOUND *ptr = self.ptr
        with nogil:
            result = cs.csoundPerformOutputFade(ptr, frames)
        return result

    ## ------------------------------------------------------------------------
    ## Events and score

    def run_utility(self, str name, *args) -> int:
        """Run a utility (e.g. ``"lpanal"``) with the given arguments.

        Returns zero on success.
        """
        cdef ArgArray params = ArgArray(args)
        return cs.csoundRunUtility(self.ptr, name.encode(), params.argc,
                                   <char **>params.argv)

    def event(self, int event_type, object params, bint async_=False):
        """Schedule a realtime event.

        ``event_type`` is an :class:`EventType` value; ``params`` is a sequence
        of p-field cs_float values. Before :meth:`start`, Csound drops a
        synchronous event, so this raises ``RuntimeError``; use
        :meth:`event_string` or ``async_=True`` (at most 1024 queued).
        """
        if not async_ and not self._started:
            raise RuntimeError("event() before start() is dropped by Csound; "
                               "use event_string() or async_=True")
        cdef int n = len(params)
        cdef cs.cs_float *arr = <cs.cs_float *>malloc(n * sizeof(cs.cs_float)) if n else NULL
        if n and arr is NULL:
            raise MemoryError()
        cdef int is_async = async_
        cdef cs.CSOUND *ptr = self.ptr
        try:
            for i in range(n):
                arr[i] = params[i]
            with nogil:
                cs.csoundEvent(ptr, event_type, arr, n, is_async)
        finally:
            if arr is not NULL:
                free(arr)

    def event_string(self, str message, bint async_=False):
        """Schedule score or realtime event(s) given as a string.

        Before :meth:`start`, the events are added to the score (this is the
        Csound 7 replacement for the old ``read_score``). After the engine has
        started, they are dispatched to the realtime queue.
        """
        cdef bytes encoded = message.encode()
        cdef const char *cstr = encoded
        cdef int is_async = async_
        cdef cs.CSOUND *ptr = self.ptr
        with nogil:
            cs.csoundEventString(ptr, cstr, is_async)

    def get_instr_number(self, str name) -> int:
        """Return the instrument number for a named instrument, or -1."""
        return cs.csoundGetInstrNumber(self.ptr, name.encode())

    def key_press(self, str c):
        """Set the ASCII code of the most recent key pressed (for sensekey)."""
        cdef bytes b = c.encode()
        if len(b) != 1:
            raise ValueError("key_press expects a single character")
        cs.csoundKeyPress(self.ptr, b[0])

    def readline_push_text(self, str text) -> int:
        """Queue text for the ``readline`` opcode; a newline ends a line.

        Returns zero on success, or a negative status if the input queue
        lacks space for the whole text.
        """
        return cs.csoundReadlinePushText(self.ptr, text.encode())

    def set_readline_callback(self, callback):
        """Take ``readline`` input from the host via ``callback(request_id, prompt)``.

        ``prompt`` is a str when a line request opens and None when it closes.
        Answer with :meth:`readline_submit`. The callback runs on the
        performing thread and must not block. None restores terminal input.
        Set before performance; the callback survives :meth:`reset`.
        """
        if callback is not None and not callable(callback):
            raise TypeError("callback must be callable or None")
        self._readline_cb = callback
        if callback is None:
            cs.csoundSetReadlineCallback(self.ptr, NULL, NULL)
            return
        cs.csoundSetReadlineCallback(self.ptr, _readline_trampoline, &self.hooks)
        self._track()

    def readline_submit(self, uint32_t request_id, str text) -> int:
        """Submit one line (newline appended) to an open readline request.

        Returns zero on success, or CSOUND_ERROR for a closed or stale
        request, a full queue, or control characters other than tab.
        """
        return cs.csoundReadlineSubmit(self.ptr, request_id, text.encode())

    def get_score_time(self) -> float:
        """Return the current score time in seconds."""
        return cs.csoundGetScoreTime(self.ptr)

    def is_score_pending(self) -> int:
        """Return whether score events are currently performed."""
        return cs.csoundIsScorePending(self.ptr)

    def set_score_pending(self, int pending):
        """Set whether score events are performed (realtime events continue)."""
        cs.csoundSetScorePending(self.ptr, pending)

    def get_score_offset_seconds(self) -> float:
        """Return the score offset time."""
        return cs.csoundGetScoreOffsetSeconds(self.ptr)

    def set_score_offset_seconds(self, float time):
        """Skip score events before ``time`` and start performance there."""
        cs.csoundSetScoreOffsetSeconds(self.ptr, time)

    def rewind_score(self):
        """Rewind a compiled score to the set offset time."""
        cs.csoundRewindScore(self.ptr)

    ## ------------------------------------------------------------------------
    ## UDP server

    def udp_server_start(self, int port) -> int:
        """Start the UDP server on the given port."""
        assert port > 0, "port number must be above 0"
        return cs.csoundUDPServerStart(self.ptr, port)

    def udp_server_status(self) -> int:
        """Return the UDP server port, or CSOUND_ERROR if not running."""
        return cs.csoundUDPServerStatus(self.ptr)

    def udp_server_close(self) -> int:
        """Close the UDP server."""
        cdef int result
        cdef cs.CSOUND *ptr = self.ptr
        # Joins the server thread, which prints a message on exit.
        with nogil:
            result = cs.csoundUDPServerClose(ptr)
        return result

    def udp_console(self, str addr, int port, int mirror) -> int:
        """Send console messages to UDP at ``addr``:``port``.

        Raises ``RuntimeError`` while a message callback or hook is set: the
        console replaces Csound's message callback and cannot mirror to it.
        """
        if self._message_installed:
            raise RuntimeError("a message callback or hook is set")
        return cs.csoundUDPConsole(self.ptr, addr.encode(), port, mirror)

    def stop_udp_console(self):
        """Stop transmitting console messages via UDP."""
        cs.csoundStopUDPConsole(self.ptr)
        if self._message_installed:
            # Stopping restores a va_list callback, which outranks ours.
            cs.csoundSetMessageStringCallback(self.ptr, _message_trampoline)

    ## ------------------------------------------------------------------------
    ## Attributes

    def get_sr(self) -> float:
        """Return the sample rate (frames per second)."""
        return cs.csoundGetSr(self.ptr)

    def get_kr(self) -> float:
        """Return the control rate (control samples per second)."""
        return cs.csoundGetKr(self.ptr)

    def get_ksmps(self) -> int:
        """Return the number of audio frames per control sample."""
        return cs.csoundGetKsmps(self.ptr)

    def get_kcounter(self) -> int:
        """Return the current performance time in control frames."""
        return cs.csoundGetKcounter(self.ptr)

    def get_channels(self, is_input: int = 0) -> int:
        """Return the number of audio channels (``nchnls``; ``nchnls_i`` if
        ``is_input`` is non-zero)."""
        return cs.csoundGetChannels(self.ptr, 1 if is_input else 0)

    def get_nchnls(self) -> int:
        """Return the number of audio output channels (``nchnls``)."""
        return cs.csoundGetChannels(self.ptr, 0)

    def get_nchnls_input(self) -> int:
        """Return the number of audio input channels (``nchnls_i``)."""
        return cs.csoundGetChannels(self.ptr, 1)

    def get_0dBFS(self) -> float:
        """Return the 0dBFS level of the spin/spout buffers."""
        return cs.csoundGet0dBFS(self.ptr)

    def get_A4(self) -> float:
        """Return the A4 frequency reference."""
        return cs.csoundGetA4(self.ptr)

    def get_current_time_samples(self) -> int:
        """Return the current performance time in sample frames."""
        return cs.csoundGetCurrentTimeSamples(self.ptr)

    def err_cnt(self) -> int:
        """Return the total error count of the current performance."""
        return cs.csoundErrCnt(self.ptr)

    def get_env(self, str name):
        """Return the value of a Csound environment variable, or None."""
        cdef const char *value = cs.csoundGetEnv(self.ptr, name.encode())
        if value is NULL:
            return None
        return value.decode()

    def set_option(self, str option) -> int:
        """Set a single Csound option/flag. Returns 0 on success."""
        return cs.csoundSetOption(self.ptr, option.encode())

    def set_command_line_args(self, *args) -> int:
        """Replace the application arguments exposed to the orchestra.

        These are the arguments passed after ``--`` to :meth:`compile`. Call
        with no arguments to clear them. Returns zero on success.
        """
        cdef ArgArray params = ArgArray(args)
        return cs.csoundSetCommandLineArgs(self.ptr, params.argc, params.argv)

    def get_command_line_args(self) -> list:
        """Return the application arguments exposed to the orchestra."""
        cdef int n = cs.csoundGetCommandLineArgCount(self.ptr)
        cdef const char *arg
        cdef list out = []
        for i in range(n):
            arg = cs.csoundGetCommandLineArg(self.ptr, i)
            out.append(None if arg is NULL else arg.decode())
        return out

    def get_params(self) -> Params:
        """Return a read-only :class:`Params` view of the current options."""
        return Params.from_ptr(cs.csoundGetParams(self.ptr))

    def get_debug(self) -> int:
        """Return whether Csound prints internal debug messages."""
        return cs.csoundGetDebug(self.ptr)

    def set_debug(self, int debug):
        """Set whether Csound prints internal debug messages."""
        cs.csoundSetDebug(self.ptr, debug)

    def system_sr(self, float val) -> float:
        """Get/set (when ``val > 0``) the stored system hardware sample rate."""
        return cs.csoundSystemSr(self.ptr, val)

    def get_output_name(self):
        """Return the audio output name (-o)."""
        cdef const char *name = cs.csoundGetOutputName(self.ptr)
        return None if name is NULL else name.decode()

    def get_input_name(self):
        """Return the audio input name (-i)."""
        cdef const char *name = cs.csoundGetInputName(self.ptr)
        return None if name is NULL else name.decode()

    ## ------------------------------------------------------------------------
    ## Realtime audio / MIDI modules

    def set_rtaudio_module(self, str module):
        """Set the current realtime audio module."""
        cs.csoundSetRTAudioModule(self.ptr, module.encode())

    def set_host_audio_io(self):
        """Disable the library's default audio I/O (use spin/spout directly)."""
        cs.csoundSetHostAudioIO(self.ptr)

    def set_midi_module(self, str module):
        """Set the current realtime MIDI module."""
        cs.csoundSetMIDIModule(self.ptr, module.encode())

    def set_host_midi_io(self):
        """Disable the library's default MIDI I/O (host implements callbacks)."""
        cs.csoundSetHostMIDIIO(self.ptr)

    def set_midi_in_callbacks(self, open=None, read=None, close=None):
        """Implement realtime MIDI input (``-M``) on the host.

        Each argument is a Python callable, a C function address (int) with
        the ``csoundSetExternalMidi*Callback`` signature, or None to remove.

        - ``open(device) -> handle``: ``device`` is the ``-M`` name. The
          return value, any object, is passed to ``read`` and ``close``.
        - ``read(handle, nbytes) -> bytes``: at most ``nbytes`` raw MIDI
          bytes; empty or None when there is no input.
        - ``close(handle)``: optional.

        A raised exception is reported as unraisable and returns -1 to
        Csound; Csound aborts on an open error. Call :meth:`set_host_midi_io`
        and set these before :meth:`start`. They survive :meth:`reset`.
        """
        self._set_midi((MIDI_IN_OPEN, MIDI_READ, MIDI_IN_CLOSE),
                       (open, read, close))

    def set_midi_out_callbacks(self, open=None, write=None, close=None):
        """Implement realtime MIDI output (``-Q``) on the host.

        As :meth:`set_midi_in_callbacks`, with ``write(handle, data) -> int``
        receiving the raw MIDI bytes. Return the count written; None counts
        as all of ``data``.
        """
        self._set_midi((MIDI_OUT_OPEN, MIDI_WRITE, MIDI_OUT_CLOSE),
                       (open, write, close))

    def set_midi_device_list_callback(self, callback):
        """List host MIDI devices for :meth:`get_midi_dev_list`.

        ``callback(is_output) -> list`` returns dicts with the keys of
        :meth:`get_midi_dev_list` entries (missing keys are empty). Accepts
        a C function address or None, as :meth:`set_midi_in_callbacks`.
        """
        self._set_midi((MIDI_DEV_LIST,), (callback,))

    def set_midi_error_string_hook(self, uintptr_t hook):
        """Set the C function that maps MIDI error codes to messages.

        ``const char *hook(int32_t errcode)`` gets no Csound instance, so
        it has no Python level. 0 removes it.
        """
        self._set_midi((MIDI_ERROR_STRING,), (hook or None,))

    ## ------------------------------------------------------------------------
    ## Graph display

    def set_is_graphable(self, bint graphable) -> bool:
        """Declare that the host draws graphs; returns the previous flag.

        With the flag set, Csound keeps the :meth:`set_graph_callbacks`
        callbacks instead of loading FLTK or substituting ASCII graphs.
        Re-applied after :meth:`reset`, which clears it.
        """
        self._graphable = graphable
        return bool(cs.csoundSetIsGraphable(self.ptr, graphable))

    def set_graph_callbacks(self, make=None, draw=None, kill=None, exit=None):
        """Draw Csound's table and signal displays on the host.

        Each argument is a Python callable, a C function address (int) or
        None, as :meth:`set_midi_in_callbacks`. Python callbacks receive a
        :class:`GraphWindow` snapshot, not the live ``WINDAT``.

        - ``make(window, name) -> windid``: an int return becomes the
          window's ``windid``, passed back to later calls.
        - ``draw(window)``: ``window.data`` holds the values to plot.
        - ``kill(window)``: Csound 7.0.0 stores it but never calls it.
        - ``exit() -> int``: for ``csoundDeinitDisplay`` at cleanup. Csound
          7.0.0 called it on neither reset nor destroy in testing.

        Without :meth:`set_is_graphable`, the ``-d`` option replaces these
        with no-ops; the wrapper re-installs them after :meth:`reset`.
        """
        values = (make, draw, kill, exit)
        _check_slots(values)
        for slot in range(GRAPH_SLOTS):
            old = self._graph[slot]
            self._graph[slot] = values[slot]
            if values[slot] is not None or old is not None:
                self._install_graph(slot)
        self.hooks.py_graph = any(callable(v) for v in self._graph)
        if self.hooks.py_graph:
            self._track()

    cdef _install_graph(self, int slot):
        v = self._graph[slot]
        cdef bint py = v is not None and not isinstance(v, int)
        cdef void *fn = <void *><uintptr_t>v if isinstance(v, int) else NULL
        if slot == GRAPH_MAKE:
            cs.csoundSetMakeGraphCallback(
                self.ptr, _graph_make_trampoline if py else <cs.makeGraphFunc_t>fn)
        elif slot == GRAPH_DRAW:
            cs.csoundSetDrawGraphCallback(
                self.ptr, _graph_draw_trampoline if py else <cs.drawGraphFunc_t>fn)
        elif slot == GRAPH_KILL:
            cs.csoundSetKillGraphCallback(
                self.ptr, _graph_kill_trampoline if py else <cs.drawGraphFunc_t>fn)
        else:
            cs.csoundSetExitGraphCallback(
                self.ptr, _graph_exit_trampoline if py else <cs.exitGraphFunc_t>fn)

    ## ------------------------------------------------------------------------
    ## File callbacks

    def set_file_open_callback(self, callback):
        """Be notified as ``callback(path, type, writing, temporary)`` per opened file.

        ``type`` is a :class:`FileType` (an int if unknown). Takes a C
        function address or None, as :meth:`set_midi_in_callbacks`. Survives
        :meth:`reset`.
        """
        self._set_file(FILE_NOTIFY, callback)

    def set_open_file_callback(self, callback):
        """Open non-audio files as ``callback(path, mode) -> FILE * address``.

        Return None to let Csound open the file itself. Csound closes the
        returned ``FILE *`` with the C library's ``fclose``. Survives
        :meth:`reset`.
        """
        self._set_file(FILE_OPEN, callback)

    def set_open_sound_file_callback(self, callback):
        """Open sound files as ``callback(path, mode, sfinfo) -> handle address``.

        ``sfinfo`` is the address of the ``SFLIB_INFO`` to fill; the handle
        must suit the active sndfile callbacks (see
        :meth:`set_sndfile_callbacks`). Return None to fall back to Csound.
        Survives :meth:`reset`.
        """
        self._set_file(FILE_OPEN_SOUND, callback)

    def set_sndfile_callbacks(self, uintptr_t callbacks):
        """Replace Csound's soundfile I/O with a ``SNDFILE_CALLBACKS`` struct.

        ``callbacks`` is the struct's address; Csound copies its function
        pointers, and NULL members select no-op stubs. 0 restores the
        defaults. The wrapper keeps a copy and re-applies it after
        :meth:`reset`, which restores the defaults.
        """
        if callbacks == 0:
            free(self._sndfile)
            self._sndfile = NULL
            cs.csoundSetSndfileCallbacks(self.ptr, NULL)
            return
        if self._sndfile is NULL:
            self._sndfile = <cs.SNDFILE_CALLBACKS *>malloc(sizeof(cs.SNDFILE_CALLBACKS))
            if self._sndfile is NULL:
                raise MemoryError()
        memcpy(self._sndfile, <void *>callbacks, sizeof(cs.SNDFILE_CALLBACKS))
        cs.csoundSetSndfileCallbacks(self.ptr, self._sndfile)

    cdef _set_file(self, int slot, object v):
        _check_slots((v,))
        self._file[slot] = v
        cdef bint py = v is not None and not isinstance(v, int)
        cdef void *fn = <void *><uintptr_t>v if isinstance(v, int) else NULL
        if slot == FILE_OPEN_SOUND:
            cs.csoundSetOpenSoundFileCallback(
                self.ptr, _open_sound_file_trampoline if py
                else <cs.openSoundFileFunc_t>fn)
        elif slot == FILE_OPEN:
            cs.csoundSetOpenFileCallback(
                self.ptr, _open_file_trampoline if py else <cs.openFileFunc_t>fn)
        else:
            cs.csoundSetFileOpenCallback(
                self.ptr, _file_open_trampoline if py else <cs.fileOpenFunc_t>fn)
        self.hooks.py_file = any(callable(x) for x in self._file)
        if self.hooks.py_file:
            self._track()

    cdef _set_midi(self, tuple slots, tuple values):
        _check_slots(values)
        for slot, v in zip(slots, values):
            old = self._midi[slot]
            self._midi[slot] = v
            if v is not None or old is not None:
                self._install_midi(slot)
        self.hooks.py_midi = any(callable(v) for v in self._midi)
        if self.hooks.py_midi:
            self._track()

    cdef _install_midi(self, int slot):
        v = self._midi[slot]
        cdef bint py = v is not None and not isinstance(v, int)
        cdef void *fn = <void *><uintptr_t>v if isinstance(v, int) else NULL
        if slot == MIDI_IN_OPEN:
            cs.csoundSetExternalMidiInOpenCallback(
                self.ptr, _midi_in_open_trampoline if py else <cs.midiOpenFunc_t>fn)
        elif slot == MIDI_READ:
            cs.csoundSetExternalMidiReadCallback(
                self.ptr, _midi_read_trampoline if py else <cs.midiReadFunc_t>fn)
        elif slot == MIDI_IN_CLOSE:
            cs.csoundSetExternalMidiInCloseCallback(
                self.ptr, _midi_in_close_trampoline if py else <cs.midiCloseFunc_t>fn)
        elif slot == MIDI_OUT_OPEN:
            cs.csoundSetExternalMidiOutOpenCallback(
                self.ptr, _midi_out_open_trampoline if py else <cs.midiOpenFunc_t>fn)
        elif slot == MIDI_WRITE:
            cs.csoundSetExternalMidiWriteCallback(
                self.ptr, _midi_write_trampoline if py else <cs.midiWriteFunc_t>fn)
        elif slot == MIDI_OUT_CLOSE:
            cs.csoundSetExternalMidiOutCloseCallback(
                self.ptr, _midi_out_close_trampoline if py else <cs.midiCloseFunc_t>fn)
        elif slot == MIDI_DEV_LIST:
            cs.csoundSetMIDIDeviceListCallback(
                self.ptr, _midi_dev_list_trampoline if py else <cs.midiDevListFunc_t>fn)
        else:
            cs.csoundSetExternalMidiErrorStringCallback(
                self.ptr, <cs.midiErrorStringFunc_t>fn)

    def get_module(self, int number):
        """Return ``(name, type)`` for loaded module ``number``, or None."""
        cdef char *name = NULL
        cdef char *typ = NULL
        if cs.csoundGetModule(self.ptr, number, &name, &typ) != 0:
            return None
        return (name.decode() if name is not NULL else None,
                typ.decode() if typ is not NULL else None)

    def get_audio_dev_list(self, is_output: int = 1) -> list:
        """Return a list of audio device info dicts."""
        return self._dev_list(1 if is_output else 0, True)

    def get_midi_dev_list(self, is_output: int = 1) -> list:
        """Return a list of MIDI device info dicts."""
        return self._dev_list(1 if is_output else 0, False)

    cdef list _dev_list(self, int is_output, bint audio):
        cdef int n
        cdef list out = []
        cdef cs.CS_AUDIODEVICE *adevs
        cdef cs.CS_MIDIDEVICE *mdevs
        if audio:
            n = cs.csoundGetAudioDevList(self.ptr, NULL, is_output)
            if n <= 0:
                return out
            adevs = <cs.CS_AUDIODEVICE *>malloc(n * sizeof(cs.CS_AUDIODEVICE))
            if adevs is NULL:
                raise MemoryError()
            try:
                n = cs.csoundGetAudioDevList(self.ptr, adevs, is_output)
                for i in range(n):
                    out.append({
                        "device_name": adevs[i].device_name.decode(),
                        "device_id": adevs[i].device_id.decode(),
                        "rt_module": adevs[i].rt_module.decode(),
                        "max_nchnls": adevs[i].max_nchnls,
                        "is_output": bool(adevs[i].isOutput),
                    })
            finally:
                free(adevs)
        else:
            n = cs.csoundGetMIDIDevList(self.ptr, NULL, is_output)
            if n <= 0:
                return out
            mdevs = <cs.CS_MIDIDEVICE *>malloc(n * sizeof(cs.CS_MIDIDEVICE))
            if mdevs is NULL:
                raise MemoryError()
            try:
                n = cs.csoundGetMIDIDevList(self.ptr, mdevs, is_output)
                for i in range(n):
                    out.append({
                        "device_name": mdevs[i].device_name.decode(),
                        "interface_name": mdevs[i].interface_name.decode(),
                        "device_id": mdevs[i].device_id.decode(),
                        "midi_module": mdevs[i].midi_module.decode(),
                        "is_output": bool(mdevs[i].isOutput),
                    })
            finally:
                free(mdevs)
        return out

    ## ------------------------------------------------------------------------
    ## Messages

    def message(self, str fmt, *args):
        """Display an informational message."""
        text = fmt % args if args else fmt
        cdef bytes encoded = text.encode()
        cs.csoundMessage(self.ptr, "%s", <const char *>encoded)

    def message_special(self, int attr, str fmt, *args):
        """Display a message with special attributes (see :class:`Msg`/:class:`Color`)."""
        text = fmt % args if args else fmt
        cdef bytes encoded = text.encode()
        cs.csoundMessageS(self.ptr, attr, "%s", <const char *>encoded)

    def get_message_level(self) -> int:
        """Return the message level (0 to 231)."""
        return cs.csoundGetMessageLevel(self.ptr)

    def set_message_level(self, int message_level):
        """Set the message level (0 to 231)."""
        cs.csoundSetMessageLevel(self.ptr, message_level)

    def create_message_buffer(self, int to_stdout=0):
        """Create a buffer that captures messages printed by Csound.

        Raises ``RuntimeError`` while a message callback or hook is set:
        Csound routes messages to one or the other.
        """
        if self._message_installed:
            raise RuntimeError("a message callback or hook is set")
        cs.csoundCreateMessageBuffer(self.ptr, to_stdout)
        self._message_buffer = True

    def get_first_message(self):
        """Return the first message in the buffer, or None."""
        cdef const char *msg = cs.csoundGetFirstMessage(self.ptr)
        return None if msg is NULL else msg.decode()

    def get_first_message_attr(self) -> int:
        """Return the attribute of the first message in the buffer."""
        return cs.csoundGetFirstMessageAttr(self.ptr)

    def pop_first_message(self):
        """Remove the first message from the buffer."""
        cs.csoundPopFirstMessage(self.ptr)

    def get_message_cnt(self) -> int:
        """Return the number of pending messages in the buffer."""
        return cs.csoundGetMessageCnt(self.ptr)

    def destroy_message_buffer(self):
        """Release the message buffer."""
        cs.csoundDestroyMessageBuffer(self.ptr)
        self._message_buffer = False

    ## ------------------------------------------------------------------------
    ## Callbacks (Python callables, called with the GIL)
    ##
    ## Callbacks run on the thread that performs, usually inside
    ## perform_ksmps() or run(). Exceptions are reported with
    ## sys.unraisablehook and do not stop the performance.

    def set_message_callback(self, callback):
        """Receive Csound messages as ``callback(attr, text)``; None removes.

        ``attr`` combines :class:`Msg`, :class:`Color` and :class:`Mask`
        bits. Messages are truncated by Csound to its formatting buffer.
        Raises ``RuntimeError`` while a message buffer or UDP console exists.
        """
        if callback is not None and not callable(callback):
            raise TypeError("callback must be callable or None")
        self._message_cb = callback
        self.hooks.py_message = callback is not None
        self._sync_message()

    def set_input_channel_callback(self, callback):
        """Supply ``invalue`` values via ``callback(name, type_name)``.

        ``type_name`` is ``"k"`` or ``"S"``. Return a number for ``"k"``, a
        str for ``"S"`` (cut to 255 UTF-8 bytes), or None to leave the value
        unchanged. None removes the callback.
        """
        if callback is not None and not callable(callback):
            raise TypeError("callback must be callable or None")
        self._input_cb = callback
        self.hooks.py_input = callback is not None
        self._sync_input()

    def set_output_channel_callback(self, callback):
        """Receive ``outvalue`` data as ``callback(name, value)``.

        ``value`` is a float for control channels and a str for string
        channels. None removes the callback.
        """
        if callback is not None and not callable(callback):
            raise TypeError("callback must be callable or None")
        self._output_cb = callback
        self.hooks.py_output = callback is not None
        self._sync_output()

    def set_keyboard_callback(self, callback,
                              unsigned int type_mask=(KeyCallbackType.KBD_EVENT
                                                      | KeyCallbackType.KBD_TEXT)):
        """Supply ``sensekey``/``readline`` keys via ``callback(type)``.

        ``type`` is a :class:`KeyCallbackType`. Return the key code (1 to
        65535; add 0x10000 for a release under ``KBD_EVENT``), or 0 / None for
        no key. Returns zero on success. None removes the callback. Changing
        ``type_mask`` re-registers, which is unsafe during performance.
        """
        if callback is not None and not callable(callback):
            raise TypeError("callback must be callable or None")
        # Csound frees list entries without a lock while the performing
        # thread walks the list, so the trampoline stays registered and only
        # the callable is swapped. Only a new type_mask re-registers.
        self._keyboard_cb = callback
        if callback is None or (self._keyboard_registered
                                and self._keyboard_mask == type_mask):
            return 0
        cdef int result = cs.csoundRegisterKeyboardCallback(
            self.ptr, _keyboard_trampoline, &self.hooks, type_mask)
        if result != 0:
            self._keyboard_cb = None
            return result
        self._keyboard_registered = True
        self._keyboard_mask = type_mask
        self._track()
        self._keyboard_host_input()
        return result

    ## ------------------------------------------------------------------------
    ## Hooks (C function pointers, called without the GIL)
    ##
    ## Pass a function address as an int (Cython ``<uintptr_t>fn``, ctypes
    ## ``ctypes.cast(fn, ctypes.c_void_p).value``, cffi, numba ``cfunc``), and
    ## an opaque ``ctx`` address handed back on each call; 0 removes the hook.
    ## The address is not validated: a wrong one crashes the process. Replace
    ## a hook only while not performing, or remove it first.

    def set_message_hook(self, uintptr_t hook, uintptr_t ctx=0):
        """Set ``void hook(void *ctx, CSOUND *, int32_t attr, const char *text)``."""
        self.hooks.message_hook = NULL
        self.hooks.message_ctx = <void *>ctx
        self.hooks.message_hook = <message_hook_t>hook
        self._sync_message()

    def set_input_channel_hook(self, uintptr_t hook, uintptr_t ctx=0):
        """Set ``void hook(void *ctx, CSOUND *, const char *name, void *value,
        const CS_TYPE *type)`` for ``invalue``.

        ``value`` is a ``cs_float *`` for ``k`` channels and a ``char *``
        buffer of at least 256 bytes for ``S`` channels.
        """
        self.hooks.input_hook = NULL
        self.hooks.input_ctx = <void *>ctx
        self.hooks.input_hook = <channel_hook_t>hook
        self._sync_input()

    def set_output_channel_hook(self, uintptr_t hook, uintptr_t ctx=0):
        """Set ``void hook(void *ctx, CSOUND *, const char *name, void *value,
        const CS_TYPE *type)`` for ``outvalue`` (``cs_float *`` or ``char *``)."""
        self.hooks.output_hook = NULL
        self.hooks.output_ctx = <void *>ctx
        self.hooks.output_hook = <channel_hook_t>hook
        self._sync_output()

    def register_keyboard_hook(self, uintptr_t hook, uintptr_t ctx=0,
                               unsigned int type_mask=(KeyCallbackType.KBD_EVENT
                                                       | KeyCallbackType.KBD_TEXT)) -> int:
        """Register ``int32_t hook(void *ctx, void *p, uint32_t type)``.

        Maps directly to ``csoundRegisterKeyboardCallback``: write the key
        code to ``*(int *)p`` and return 0, or return a positive value to
        pass. Several hooks may be registered; one address registers once.
        Returns zero on success. Registering or removing frees list entries
        Csound walks without a lock: do it only while not performing.
        """
        if hook == 0:
            raise ValueError("hook address must be non-zero")
        cdef int result = cs.csoundRegisterKeyboardCallback(
            self.ptr, <keyboard_hook_t>hook, <void *>ctx, type_mask)
        if result == 0:
            self._keyboard_hooks.add(hook)
            self._track()
            self._keyboard_host_input()
        return result

    def remove_keyboard_hook(self, uintptr_t hook):
        """Remove a hook added with :meth:`register_keyboard_hook`.

        Unsafe during performance; see :meth:`register_keyboard_hook`.
        """
        cs.csoundRemoveKeyboardCallback(self.ptr, <keyboard_hook_t>hook)
        self._keyboard_hooks.discard(hook)

    cdef _sync_message(self):
        cdef bint want = self.hooks.py_message or self.hooks.message_hook is not NULL
        if want and not self._message_installed:
            if (self._message_buffer or
                    cs.csoundQueryGlobalVariable(self.ptr, "::UDPCONS") is not NULL):
                self._message_cb = None
                self.hooks.py_message = False
                self.hooks.message_hook = NULL
                raise RuntimeError("destroy the message buffer or stop the "
                                   "UDP console first")
            cs.csoundSetMessageStringCallback(self.ptr, _message_trampoline)
            self._track()
        elif not want and self._message_installed:
            # NULL restores the default printer; the string setter ignores it.
            cs.csoundSetMessageCallback(self.ptr, NULL)
        self._message_installed = want

    cdef _sync_input(self):
        cdef cs.channelCallback_t fn = NULL
        if self.hooks.py_input or self.hooks.input_hook is not NULL:
            fn = _input_trampoline
            self._track()
        cs.csoundSetInputChannelCallback(self.ptr, fn)

    cdef _sync_output(self):
        cdef cs.channelCallback_t fn = NULL
        if self.hooks.py_output or self.hooks.output_hook is not NULL:
            fn = _output_trampoline
            self._track()
        cs.csoundSetOutputChannelCallback(self.ptr, fn)

    ## ------------------------------------------------------------------------
    ## Channels

    def set_control_channel(self, str name, float value):
        """Set the value of a control channel."""
        cs.csoundSetControlChannel(self.ptr, name.encode(), value)

    def get_control_channel(self, str name) -> float:
        """Return the value of a control channel."""
        cdef int32_t err = 0
        return cs.csoundGetControlChannel(self.ptr, name.encode(), &err)

    def set_string_channel(self, str name, str value):
        """Set the value of a string channel."""
        cs.csoundSetStringChannel(self.ptr, name.encode(), value.encode())

    def get_string_channel(self, str name) -> str:
        """Return the value of a string channel."""
        cdef int size = cs.csoundGetChannelDatasize(self.ptr, name.encode())
        if size <= 0:
            return ""
        cdef char *buf = <char *>malloc(size + 1)
        if buf is NULL:
            raise MemoryError()
        try:
            cs.csoundGetStringChannel(self.ptr, name.encode(), buf)
            buf[size] = 0
            return buf.decode()
        finally:
            free(buf)

    def set_audio_channel(self, str name, object samples):
        """Copy a ksmps-sized block of samples into an audio channel."""
        cdef int ksmps = cs.csoundGetKsmps(self.ptr)
        cdef int n = len(samples)
        if n != ksmps:
            raise ValueError(
                f"audio channel expects {ksmps} samples (ksmps), got {n}")
        cdef cs.cs_float *buf = <cs.cs_float *>malloc(n * sizeof(cs.cs_float))
        if buf is NULL:
            raise MemoryError()
        try:
            for i in range(n):
                buf[i] = samples[i]
            cs.csoundSetAudioChannel(self.ptr, name.encode(), buf)
        finally:
            free(buf)

    def get_audio_channel(self, str name) -> list:
        """Return a ksmps-sized block of samples read from an audio channel."""
        cdef int n = cs.csoundGetKsmps(self.ptr)
        cdef cs.cs_float *buf = <cs.cs_float *>malloc(n * sizeof(cs.cs_float))
        if buf is NULL:
            raise MemoryError()
        try:
            cs.csoundGetAudioChannel(self.ptr, name.encode(), buf)
            return [buf[i] for i in range(n)]
        finally:
            free(buf)

    def set_control_channel_hints(self, str name, int behav=0, float dflt=0.0,
                                  float min=0.0, float max=0.0, int x=0, int y=0,
                                  int width=0, int height=0,
                                  str attributes=None) -> int:
        """Attach display hints to a control channel.

        ``behav`` is a ``ChannelBehavior`` value. Returns zero on success,
        or a negative status if the channel does not exist or is not a
        control channel.
        """
        cdef cs.controlChannelHints_t hints
        cdef bytes attr_b
        hints.behav = <cs.controlChannelBehavior>behav
        hints.dflt = dflt
        hints.min = min
        hints.max = max
        hints.x = x
        hints.y = y
        hints.width = width
        hints.height = height
        if attributes is None:
            hints.attributes = NULL
        else:
            attr_b = attributes.encode()
            hints.attributes = attr_b
        return cs.csoundSetControlChannelHints(self.ptr, name.encode(), hints)

    def get_control_channel_hints(self, str name):
        """Return a control channel's hints as a dict, or None if it has none."""
        cdef cs.controlChannelHints_t hints
        if cs.csoundGetControlChannelHints(self.ptr, name.encode(), &hints) != 0:
            return None
        try:
            return {
                "behav": <int>hints.behav,
                "dflt": hints.dflt,
                "min": hints.min,
                "max": hints.max,
                "x": hints.x,
                "y": hints.y,
                "width": hints.width,
                "height": hints.height,
                "attributes": (None if hints.attributes is NULL
                               else hints.attributes.decode()),
            }
        finally:
            # attributes are a Csound-allocated copy owned by the caller.
            cs.csoundDeleteControlChannelHints(self.ptr, &hints)

    def copy_channel(self, str source, str dest) -> int:
        """Copy the value of channel ``source`` into channel ``dest``.

        Works for any channel type (including arrays and structs); both
        channels must exist and share a type. Returns zero on success. Not
        suitable for a realtime thread: managed types may allocate.
        """
        cdef const cs.CS_VAR_MEM *var = cs.csoundGetChannel(self.ptr, source.encode())
        if var is NULL:
            return cs.CSOUND_ERROR
        return cs.csoundSetChannel(self.ptr, dest.encode(), var)

    def init_pvs_channel(self, str name, int fft_size, int overlap,
                         int window_size, int window_type=PvsWindow.HANN,
                         int format=PvsFormat.AMP_FREQ):
        """Create an fsig channel and return its :class:`PvsData`, or None.

        A no-op returning the existing data if the channel is already
        initialised. Use the returned object as the host-side frame for
        :meth:`set_pvs_channel` and :meth:`get_pvs_channel`. Requires a
        started engine: Csound crashes if the frame is allocated before
        :meth:`start`.
        """
        if not self._started:
            raise RuntimeError("init_pvs_channel() requires start() first")
        cdef cs.PVSDAT *p = cs.csoundInitPvsChannel(
            self.ptr, name.encode(), fft_size, overlap, window_size,
            window_type, format)
        if p is NULL:
            return None
        return PvsData.from_ptr(p, self)

    def init_array_channel(self, str name, str type, sizes):
        """Create an array channel and return its :class:`ArrayChannel`, or None.

        ``type`` is an element type name ("i", "k", "a", "S", ...) and
        ``sizes`` the length of each dimension. Returns the existing array,
        unchanged, if the channel is already initialised.
        """
        cdef int dims = len(sizes)
        if dims == 0:
            raise ValueError("sizes must have at least one dimension")
        cdef int32_t *c_sizes = <int32_t *>malloc(dims * sizeof(int32_t))
        if c_sizes is NULL:
            raise MemoryError()
        cdef cs.ARRAYDAT *a
        try:
            for i in range(dims):
                c_sizes[i] = sizes[i]
            a = cs.csoundInitArrayChannel(self.ptr, name.encode(), type.encode(),
                                          dims, c_sizes)
        finally:
            free(c_sizes)
        if a is NULL:
            return None
        return ArrayChannel.from_ptr(a, self)

    def create_circular_buffer(self, int size, int element_size=sizeof(cs.cs_float)):
        """Return a :class:`CircularBuffer` holding ``size`` elements."""
        return CircularBuffer(self, size, element_size)

    def append_opcode(self, str opname, size_t dsblksiz, int flags, str outtypes,
                      str intypes, uintptr_t init=0, uintptr_t perf=0,
                      uintptr_t deinit=0) -> int:
        """Register a C opcode; returns zero on success.

        ``init``/``perf``/``deinit`` are addresses of
        ``int32_t fn(CSOUND *, void *p)`` functions, or 0. ``p`` points at
        ``dsblksiz`` bytes: an ``OPDS`` header (:data:`OPDS_SIZE` bytes),
        then one ``cs_float *`` per output and input argument. Register
        before compiling code that uses the opcode.
        """
        # Csound keeps these string pointers in its opcode table until reset.
        cdef tuple keep = (opname.encode(), outtypes.encode(), intypes.encode())
        self._opcode_strings.append(keep)
        return cs.csoundAppendOpcode(
            self.ptr, keep[0], dsblksiz, flags, keep[1],
            keep[2], <int32_t (*)(cs.CSOUND *, void *) noexcept nogil>init,
            <int32_t (*)(cs.CSOUND *, void *) noexcept nogil>perf,
            <int32_t (*)(cs.CSOUND *, void *) noexcept nogil>deinit)

    def append_opcodes(self, uintptr_t oentries, int count) -> int:
        """Register ``count`` opcodes from an ``OENTRY`` array at address ``oentries``.

        Csound copies the entries but not the strings they point to, which
        must outlive the instance.
        """
        return cs.csoundAppendOpcodes(self.ptr, <const cs.OENTRY *>oentries, count)

    def ugen_factory(self):
        """Return a :class:`UgenFactory` for running opcodes as unit generators.

        Requires :meth:`start`: the factory copies sr and ksmps at creation.
        """
        return UgenFactory(self)

    def set_pvs_channel(self, str name, PvsData data not None) -> int:
        """Copy ``data`` into the fsig input channel ``name``.

        Returns zero on success, or a negative status if the channel is
        missing or the frame is invalid.
        """
        data._check()
        return cs.csoundSetPvsChannel(self.ptr, name.encode(), data.ptr)

    def get_pvs_channel(self, str name, PvsData data not None) -> int:
        """Copy the fsig output channel ``name`` into ``data``.

        ``data`` must have room for the channel's frame (same or larger FFT
        size). Returns zero on success, or a negative status.
        """
        data._check()
        return cs.csoundGetPvsChannel(self.ptr, name.encode(), data.ptr)

    def get_channel_datasize(self, str name) -> int:
        """Return the size in bytes of the data stored in a channel."""
        return cs.csoundGetChannelDatasize(self.ptr, name.encode())

    def get_channel_var_type_name(self, str name):
        """Return the variable type name of a channel, or None."""
        cdef const char *t = cs.csoundGetChannelVarTypeName(self.ptr, name.encode())
        return None if t is NULL else t.decode()

    def lock_channel(self, str name):
        """Lock a channel for threadsafe access to its data pointer."""
        cs.csoundLockChannel(self.ptr, name.encode())

    def unlock_channel(self, str name):
        """Unlock a previously locked channel."""
        cs.csoundUnlockChannel(self.ptr, name.encode())

    def list_channels(self) -> list:
        """Return a list of ``(name, type)`` tuples for allocated channels."""
        cdef cs.controlChannelInfo_t *lst = NULL
        cdef int n = cs.csoundListChannels(self.ptr, &lst)
        cdef list out = []
        if n <= 0 or lst is NULL:
            return out
        try:
            for i in range(n):
                out.append((lst[i].name.decode(), lst[i].type))
        finally:
            cs.csoundDeleteChannelList(self.ptr, lst)
        return out

    ## ------------------------------------------------------------------------
    ## Tables

    def table_length(self, int table) -> int:
        """Return the length of a function table, or -1 if it does not exist."""
        return cs.csoundTableLength(self.ptr, table)

    def get_table(self, int table_num):
        """Return the contents of a function table as a list, or None."""
        cdef cs.cs_float *p = NULL
        cdef int n = cs.csoundGetTable(self.ptr, &p, table_num)
        if n < 0 or p is NULL:
            return None
        return [p[i] for i in range(n)]

    def get_table_args(self, int table_num):
        """Return the GEN arguments used to create a table as a list, or None."""
        cdef cs.cs_float *p = NULL
        cdef int n = cs.csoundGetTableArgs(self.ptr, &p, table_num)
        if n < 0 or p is NULL:
            return None
        return [p[i] for i in range(n)]

    def set_table(self, int table_num, object values, bint async_=False):
        """Copy ``values`` into an existing function table.

        ``values`` must be at least as long as the table size plus the guard
        point.
        """
        cdef int n = len(values)
        cdef cs.cs_float *buf = <cs.cs_float *>malloc(n * sizeof(cs.cs_float)) if n else NULL
        if n and buf is NULL:
            raise MemoryError()
        cdef int is_async = async_
        cdef cs.CSOUND *ptr = self.ptr
        try:
            for i in range(n):
                buf[i] = values[i]
            with nogil:
                cs.csoundTableCopyIn(ptr, table_num, buf, is_async)
        finally:
            if buf is not NULL:
                free(buf)

    ## ------------------------------------------------------------------------
    ## Low-level pointer accessors (Cython-only)

    cdef cs.cs_float *get_spin(self):
        """Return the address of the audio input working buffer (spin)."""
        return cs.csoundGetSpin(self.ptr)

    cdef const cs.cs_float *get_spout(self):
        """Return the address of the audio output working buffer (spout)."""
        return cs.csoundGetSpout(self.ptr)

    cdef int get_channel_ptr(self, void **p, str name, int type):
        """Store a pointer to the named channel in ``*p`` (creating it)."""
        return cs.csoundGetChannelPtr(self.ptr, p, name.encode(), type)


## ----------------------------------------------------------------------------
## Trampolines installed in Csound

cdef inline HookState *_hooks(cs.CSOUND *csound) noexcept nogil:
    return <HookState *>cs.csoundGetHostData(csound)


cdef inline bint _python_alive() noexcept nogil:
    # A thread still performing during shutdown must not wait for the GIL.
    return Py_IsInitialized() and not cycsound_py_finalizing()


cdef inline str _type_name(const void *channel_type):
    cdef const cs.CS_TYPE *t = <const cs.CS_TYPE *>channel_type
    if t is NULL or t.varTypeName is NULL:
        return ""
    return t.varTypeName.decode()


cdef void _message_trampoline(cs.CSOUND *csound, int32_t attr,
                              const char *text) noexcept nogil:
    cdef HookState *h = _hooks(csound)
    if h is NULL:
        return
    if h.message_hook is not NULL:
        h.message_hook(h.message_ctx, csound, attr, text)
    if h.py_message and _python_alive():
        with gil:
            if not h.py_message:  # cleared while this thread waited
                return
            cb = (<Csound>h.owner)._message_cb
            if cb is not None:
                cb(attr, text.decode("utf-8", "replace"))


cdef void _input_trampoline(cs.CSOUND *csound, const char *name, void *value,
                            const void *channel_type) noexcept nogil:
    cdef HookState *h = _hooks(csound)
    if h is NULL:
        return
    if h.input_hook is not NULL:
        h.input_hook(h.input_ctx, csound, name, value, channel_type)
    if h.py_input and _python_alive():
        with gil:
            if h.py_input:  # may be cleared while this thread waited
                _input_py(<Csound>h.owner, name, value, channel_type)


cdef void _input_py(Csound owner, const char *name, void *value,
                    const void *channel_type):
    cb = owner._input_cb
    if cb is None or value is NULL:
        return
    type_name = _type_name(channel_type)
    result = cb(name.decode(), type_name)
    if result is None:
        return
    cdef bytes encoded
    if type_name == "S":
        # Cut on a character boundary so the C string stays valid UTF-8.
        encoded = (str(result).encode()[:INVALUE_STRING_MAX - 1]
                   .decode("utf-8", "ignore").encode())
        strncpy(<char *>value, encoded, INVALUE_STRING_MAX - 1)
        (<char *>value)[len(encoded)] = 0
    else:
        (<cs.cs_float *>value)[0] = result


cdef void _output_trampoline(cs.CSOUND *csound, const char *name, void *value,
                             const void *channel_type) noexcept nogil:
    cdef HookState *h = _hooks(csound)
    if h is NULL:
        return
    if h.output_hook is not NULL:
        h.output_hook(h.output_ctx, csound, name, value, channel_type)
    if h.py_output and _python_alive():
        with gil:
            if h.py_output:  # may be cleared while this thread waited
                _output_py(<Csound>h.owner, name, value, channel_type)


cdef void _output_py(Csound owner, const char *name, void *value,
                     const void *channel_type):
    cb = owner._output_cb
    if cb is None or value is NULL:
        return
    if _type_name(channel_type) == "S":
        cb(name.decode(), (<const char *>value).decode("utf-8", "replace"))
    else:
        cb(name.decode(), (<cs.cs_float *>value)[0])


cdef int32_t _keyboard_trampoline(void *user_data, void *p,
                                  uint32_t type) noexcept nogil:
    cdef HookState *h = <HookState *>user_data
    if h is NULL or p is NULL or not _python_alive():
        return 1
    with gil:
        cb = (<Csound>h.owner)._keyboard_cb
        if cb is None:
            return 1
        key = cb(KeyCallbackType(type))
        (<int32_t *>p)[0] = 0 if key is None else key
    return 0


cdef void _readline_trampoline(cs.CSOUND *csound, void *user_data,
                               uint32_t request_id,
                               const char *prompt) noexcept nogil:
    cdef HookState *h = <HookState *>user_data
    if h is NULL or not _python_alive():
        return
    with gil:
        cb = (<Csound>h.owner)._readline_cb
        if cb is not None:
            cb(request_id,
               None if prompt is NULL else prompt.decode("utf-8", "replace"))


cdef _check_slots(tuple values):
    for v in values:
        if v is not None and not callable(v) and not isinstance(v, int):
            raise TypeError("expected a callable, a C function address or None")


cdef void _unraisable(BaseException e, object where):
    PyErr_SetObject(type(e), e)
    PyErr_WriteUnraisable(where)


cdef inline HookState *_midi_hooks(cs.CSOUND *csound) noexcept nogil:
    cdef HookState *h = _hooks(csound)
    if h is NULL or not h.py_midi or not _python_alive():
        return NULL
    return h


cdef int32_t _midi_py(Csound owner, int slot, const char *dev,
                      unsigned char *buf, int32_t n) noexcept:
    cb = owner._midi[slot]
    cdef bytes data
    try:
        if slot == MIDI_IN_OPEN:
            owner._midi_in_handle = cb(dev.decode("utf-8", "replace") if dev else "")
            return 0
        if slot == MIDI_OUT_OPEN:
            owner._midi_out_handle = cb(dev.decode("utf-8", "replace") if dev else "")
            return 0
        if slot == MIDI_READ:
            result = cb(owner._midi_in_handle, n)
            if result is None:
                return 0
            data = bytes(result)
            if len(data) > n:
                raise ValueError(f"MIDI read returned {len(data)} bytes, max {n}")
            memcpy(buf, <const char *>data, len(data))
            return len(data)
        if slot == MIDI_WRITE:
            result = cb(owner._midi_out_handle, (<const char *>buf)[:n])
            return n if result is None else result
        if slot == MIDI_IN_CLOSE:
            result = cb(owner._midi_in_handle)
            owner._midi_in_handle = None
        else:
            result = cb(owner._midi_out_handle)
            owner._midi_out_handle = None
        return 0 if result is None else result
    except BaseException as e:
        _unraisable(e, cb)
        return -1


cdef int32_t _midi_in_open_trampoline(cs.CSOUND *csound, void **user_data,
                                      const char *dev) noexcept nogil:
    cdef HookState *h = _midi_hooks(csound)
    if h is NULL:
        return -1
    with gil:
        return _midi_py(<Csound>h.owner, MIDI_IN_OPEN, dev, NULL, 0)


cdef int32_t _midi_out_open_trampoline(cs.CSOUND *csound, void **user_data,
                                       const char *dev) noexcept nogil:
    cdef HookState *h = _midi_hooks(csound)
    if h is NULL:
        return -1
    with gil:
        return _midi_py(<Csound>h.owner, MIDI_OUT_OPEN, dev, NULL, 0)


cdef int32_t _midi_read_trampoline(cs.CSOUND *csound, void *user_data,
                                   unsigned char *buf, int32_t n) noexcept nogil:
    cdef HookState *h = _midi_hooks(csound)
    if h is NULL:
        return 0
    with gil:
        return _midi_py(<Csound>h.owner, MIDI_READ, NULL, buf, n)


cdef int32_t _midi_write_trampoline(cs.CSOUND *csound, void *user_data,
                                    const unsigned char *buf,
                                    int32_t n) noexcept nogil:
    cdef HookState *h = _midi_hooks(csound)
    if h is NULL:
        return n
    with gil:
        return _midi_py(<Csound>h.owner, MIDI_WRITE, NULL,
                        <unsigned char *>buf, n)


cdef int32_t _midi_in_close_trampoline(cs.CSOUND *csound,
                                       void *user_data) noexcept nogil:
    cdef HookState *h = _midi_hooks(csound)
    if h is NULL:
        return 0
    with gil:
        return _midi_py(<Csound>h.owner, MIDI_IN_CLOSE, NULL, NULL, 0)


cdef int32_t _midi_out_close_trampoline(cs.CSOUND *csound,
                                        void *user_data) noexcept nogil:
    cdef HookState *h = _midi_hooks(csound)
    if h is NULL:
        return 0
    with gil:
        return _midi_py(<Csound>h.owner, MIDI_OUT_CLOSE, NULL, NULL, 0)


cdef void _copy_field(char *dest, size_t size, object value):
    # Cut on a character boundary so the C string stays valid UTF-8.
    cdef bytes b = str(value).encode()[:size - 1].decode("utf-8", "ignore").encode()
    memcpy(dest, <const char *>b, len(b))
    dest[len(b)] = 0


cdef int32_t _midi_dev_list_py(Csound owner, cs.CS_MIDIDEVICE *lst,
                               int32_t is_output) noexcept:
    cb = owner._midi[MIDI_DEV_LIST]
    cdef int out = 1 if is_output else 0
    cdef int n
    try:
        devs = list(cb(bool(is_output)))
        if lst is NULL:
            owner._midi_dev_count[out] = len(devs)
            return len(devs)
        # Csound sized lst from the count call; never write past it.
        n = min(len(devs), owner._midi_dev_count[out])
        for i in range(n):
            d = devs[i]
            _copy_field(lst[i].device_name, sizeof(lst[i].device_name),
                        d.get("device_name", ""))
            _copy_field(lst[i].interface_name, sizeof(lst[i].interface_name),
                        d.get("interface_name", ""))
            _copy_field(lst[i].device_id, sizeof(lst[i].device_id),
                        d.get("device_id", ""))
            _copy_field(lst[i].midi_module, sizeof(lst[i].midi_module),
                        d.get("midi_module", ""))
            lst[i].isOutput = is_output
        return n
    except BaseException as e:
        _unraisable(e, cb)
        return 0


cdef int32_t _midi_dev_list_trampoline(cs.CSOUND *csound, cs.CS_MIDIDEVICE *lst,
                                       int32_t is_output) noexcept nogil:
    cdef HookState *h = _midi_hooks(csound)
    if h is NULL:
        return 0
    with gil:
        return _midi_dev_list_py(<Csound>h.owner, lst, is_output)


cdef object _graph_window(cs.WINDAT *w):
    cdef int n = w.npts if w.fdata is not NULL else 0
    return GraphWindow(
        w.windid, w.caption.decode("utf-8", "replace"),
        [w.fdata[i] for i in range(n)], w.polarity, w.max, w.min,
        w.absmax, w.oabsmax, w.danflag, w.absflag, w.waitflg)


cdef inline HookState *_graph_hooks(cs.CSOUND *csound) noexcept nogil:
    cdef HookState *h = _hooks(csound)
    if h is NULL or not h.py_graph or not _python_alive():
        return NULL
    return h


cdef int32_t _graph_py(Csound owner, int slot, cs.WINDAT *w,
                       const char *name) noexcept:
    cb = owner._graph[slot]
    try:
        if slot == GRAPH_EXIT:
            result = cb()
            return 0 if result is None else result
        win = _graph_window(w)
        if slot == GRAPH_MAKE:
            result = cb(win, name.decode("utf-8", "replace") if name else "")
            if result is not None:
                w.windid = result
        else:
            cb(win)
        return 0
    except BaseException as e:
        _unraisable(e, cb)
        return 0


cdef void _graph_make_trampoline(cs.CSOUND *csound, cs.WINDAT *w,
                                 const char *name) noexcept nogil:
    cdef HookState *h = _graph_hooks(csound)
    if h is not NULL and w is not NULL:
        with gil:
            _graph_py(<Csound>h.owner, GRAPH_MAKE, w, name)


cdef void _graph_draw_trampoline(cs.CSOUND *csound, cs.WINDAT *w) noexcept nogil:
    cdef HookState *h = _graph_hooks(csound)
    if h is not NULL and w is not NULL:
        with gil:
            _graph_py(<Csound>h.owner, GRAPH_DRAW, w, NULL)


cdef void _graph_kill_trampoline(cs.CSOUND *csound, cs.WINDAT *w) noexcept nogil:
    cdef HookState *h = _graph_hooks(csound)
    if h is not NULL and w is not NULL:
        with gil:
            _graph_py(<Csound>h.owner, GRAPH_KILL, w, NULL)


cdef int32_t _graph_exit_trampoline(cs.CSOUND *csound) noexcept nogil:
    cdef HookState *h = _graph_hooks(csound)
    if h is NULL:
        return 0
    with gil:
        return _graph_py(<Csound>h.owner, GRAPH_EXIT, NULL, NULL)


cdef inline HookState *_file_hooks(cs.CSOUND *csound) noexcept nogil:
    cdef HookState *h = _hooks(csound)
    if h is NULL or not h.py_file or not _python_alive():
        return NULL
    return h


cdef void *_file_open_py(Csound owner, int slot, const char *path,
                         const char *mode, int32_t imode, void *sfinfo) noexcept:
    # Both open callbacks return an address; 0 makes Csound open the file.
    cb = owner._file[slot]
    try:
        p = path.decode("utf-8", "replace")
        if slot == FILE_OPEN:
            result = cb(p, mode.decode())
        else:
            result = cb(p, imode, <uintptr_t>sfinfo)
        return <void *><uintptr_t>(0 if result is None else result)
    except BaseException as e:
        _unraisable(e, cb)
        return NULL


cdef void *_open_sound_file_trampoline(cs.CSOUND *csound, const char *path,
                                       int32_t mode, void *sfinfo) noexcept nogil:
    cdef HookState *h = _file_hooks(csound)
    if h is NULL:
        return NULL
    with gil:
        return _file_open_py(<Csound>h.owner, FILE_OPEN_SOUND, path, NULL,
                             mode, sfinfo)


cdef stdio.FILE *_open_file_trampoline(cs.CSOUND *csound, const char *path,
                                       const char *mode) noexcept nogil:
    cdef HookState *h = _file_hooks(csound)
    if h is NULL:
        return NULL
    with gil:
        return <stdio.FILE *>_file_open_py(<Csound>h.owner, FILE_OPEN, path,
                                           mode, 0, NULL)


cdef void _file_open_py_notify(Csound owner, const char *path, int32_t type,
                               int32_t writing, int32_t temporary) noexcept:
    cb = owner._file[FILE_NOTIFY]
    try:
        try:
            ftype = FileType(type)
        except ValueError:
            ftype = type
        cb(path.decode("utf-8", "replace"), ftype, bool(writing), bool(temporary))
    except BaseException as e:
        _unraisable(e, cb)


cdef void _file_open_trampoline(cs.CSOUND *csound, const char *path, int32_t type,
                                int32_t writing, int32_t temporary) noexcept nogil:
    cdef HookState *h = _file_hooks(csound)
    if h is not NULL:
        with gil:
            _file_open_py_notify(<Csound>h.owner, path, type, writing, temporary)


## ----------------------------------------------------------------------------
## Unit generators (ugen.h)
##
## Csound allocates every UGEN object from the instance's memory pool, which
## reset() and destroy free wholesale. Each wrapper holds its Csound and its
## parents, and frees its C object only while those references are intact
## and no reset() happened since creation. Otherwise (a reset, or the GC
## clearing a reference cycle) it leaves the memory to the pool.

cdef inline bint _ugen_live(Csound owner, unsigned long generation):
    return owner is not None and owner._generation == generation


cdef inline _ugen_check(Csound owner, unsigned long generation):
    if not _ugen_live(owner, generation):
        raise ValueError("stale unit generator object: its Csound instance "
                         "was reset")


cdef class UgenFactory:
    """Creates opcode instances outside an orchestra (``UGEN_FACTORY``).

    Get one from :meth:`Csound.ugen_factory`. The factory and everything it
    creates are invalid after :meth:`Csound.reset`. The UGEN API takes no
    locks: do not use it concurrently with performance of the same instance.
    """

    cdef cs.UGEN_FACTORY *ptr
    cdef Csound _owner
    cdef unsigned long _generation

    def __cinit__(self, Csound csound not None):
        if not csound._started:
            raise RuntimeError("ugen_factory() requires start() first")
        self.ptr = cs.csoundUgenFactoryNew(csound.ptr)
        if self.ptr is NULL:
            raise MemoryError("csoundUgenFactoryNew failed")
        self._owner = csound
        self._generation = csound._generation

    def __dealloc__(self):
        if self.ptr is not NULL and _ugen_live(self._owner, self._generation):
            cs.csoundUgenFactoryDelete(self.ptr)

    cdef _check(self):
        _ugen_check(self._owner, self._generation)

    def new_ugen(self, str opname, str outtypes, str intypes) -> Ugen:
        """Instantiate the opcode entry whose type strings match exactly.

        ``outtypes``/``intypes`` are OENTRY type strings, e.g.
        ``new_ugen("oscils", "a", "iiio")``. See :meth:`list_opcodes`.
        Raises ``ValueError`` if no entry matches.
        """
        self._check()
        cdef bytes n = opname.encode(), o = outtypes.encode(), i = intypes.encode()
        cdef cs.UGEN *u = cs.csoundUgenNew(self.ptr, n, o, i)
        if u is NULL:
            raise ValueError(f"no opcode entry {opname}:{outtypes}:{intypes}")
        cdef Ugen obj = Ugen.__new__(Ugen)
        obj.ptr = u
        obj._owner = self._owner
        obj._generation = self._generation
        obj._factory = self
        obj._inputs = {}
        obj._dependents = weakref.WeakSet()
        obj._graphs = weakref.WeakSet()
        obj.opname = opname
        obj.outtypes = outtypes
        obj.intypes = intypes
        return obj

    def new_var(self, UgenArgType type) -> UgenVar:
        """Create a standalone variable, e.g. a k-rate control input."""
        self._check()
        if type == UgenArgType.UNKNOWN:
            raise ValueError("cannot create a variable of unknown type")
        cdef cs.UGEN_VAR *v = cs.csoundUgenVarNew(self.ptr, <cs.UGEN_ARG_TYPE>type)
        if v is NULL:
            raise MemoryError("csoundUgenVarNew failed")
        return UgenVar.wrap(v, self._owner, self._generation, self, True)

    def new_context(self) -> UgenContext:
        """Create instrument-like state (hold/release) for :meth:`Ugen.set_context`."""
        self._check()
        cdef cs.UGEN_CONTEXT *c = cs.csoundUgenContextNew(self.ptr)
        if c is NULL:
            raise MemoryError("csoundUgenContextNew failed")
        cdef UgenContext obj = UgenContext.__new__(UgenContext)
        obj.ptr = c
        obj._owner = self._owner
        obj._generation = self._generation
        obj._factory = self
        return obj

    def new_graph(self) -> UgenGraph:
        """Create an empty graph that inits and performs unit generators in order."""
        self._check()
        cdef cs.UGEN_GRAPH *g = cs.csoundUgenGraphNew(self.ptr)
        if g is NULL:
            raise MemoryError("csoundUgenGraphNew failed")
        cdef UgenGraph obj = UgenGraph.__new__(UgenGraph)
        obj.ptr = g
        obj._owner = self._owner
        obj._generation = self._generation
        obj._factory = self
        obj._ugens = []
        return obj

    def list_opcodes(self) -> list:
        """Return ``(opname, outtypes, intypes)`` for every opcode entry."""
        self._check()
        cdef cs.UGEN_OPCODE_INFO *lst = NULL
        cdef int32_t n = 0
        if cs.csoundUgenListOpcodes(self.ptr, &lst, &n) != 0:
            raise MemoryError("csoundUgenListOpcodes failed")
        try:
            return [(lst[i].opname.decode(), lst[i].outypes.decode(),
                     lst[i].intypes.decode()) for i in range(n)]
        finally:
            cs.csoundUgenFreeOpcodeList(self.ptr, lst)

    def find_opcode(self, str opname, str outtypes=None, str intypes=None) -> bool:
        """Return whether an entry matches; a None type string matches any."""
        self._check()
        cdef bytes n = opname.encode()
        cdef bytes o = outtypes.encode() if outtypes is not None else None
        cdef bytes i = intypes.encode() if intypes is not None else None
        return cs.csoundUgenFindOpcode(self.ptr, n, <const char *>o if o is not None else NULL,
                                       <const char *>i if i is not None else NULL)


cdef class UgenContext:
    """Instrument-like state shared by unit generators (``UGEN_CONTEXT``)."""

    cdef cs.UGEN_CONTEXT *ptr
    cdef Csound _owner
    cdef unsigned long _generation
    cdef UgenFactory _factory

    def __dealloc__(self):
        if (self.ptr is not NULL and self._factory is not None
                and _ugen_live(self._owner, self._generation)):
            cs.csoundUgenContextDelete(self.ptr)


cdef class Ugen:
    """One opcode instance run by the host (``UGEN``).

    Create with :meth:`UgenFactory.new_ugen`. Set inputs, call :meth:`init`
    once, then :meth:`perform` once per ksmps block.

    An opcode init error (bad arguments, a missing table) crashes the
    process: Csound 7.0.0 long-jumps to a stale ``exitjmp`` outside an init
    pass. A var-arg parameter always expands to 8 inputs, so opcodes that
    check their argument count may fail this way.
    """

    cdef cs.UGEN *ptr
    cdef Csound _owner
    cdef unsigned long _generation
    cdef UgenFactory _factory
    cdef UgenContext _context
    cdef dict _inputs  # input index -> wired UgenVar, keeping its data alive
    cdef object _dependents  # WeakSet of Ugens wired to this one's vars
    cdef object _graphs  # WeakSet of graphs holding this Ugen
    cdef readonly str opname
    cdef readonly str outtypes
    cdef readonly str intypes
    cdef object __weakref__

    def __dealloc__(self):
        # Delete runs the opcode's deinit, which may read the context's or
        # the factory's instrument state: both are still referenced here.
        if (self.ptr is not NULL and self._factory is not None
                and self._inputs is not None
                and _ugen_live(self._owner, self._generation)):
            cs.csoundUgenDelete(self.ptr)

    cdef _check(self):
        _ugen_check(self._owner, self._generation)
        if self.ptr is NULL:
            raise ValueError(f"{self.opname} was deleted")

    cdef bint _reads(self, Ugen source):
        # Whether an input is still wired to one of source's variables.
        for v in self._inputs.values():
            if (<UgenVar>v)._parent is source:
                return True
        return False

    cdef _check_deletable(self, set members, UgenGraph graph):
        # Deleting self, with members deleted alongside it, must leave no
        # live graph or Ugen holding a pointer into its memory.
        for g in self._graphs:
            if g is not graph and (<UgenGraph>g).ptr is not NULL:
                raise ValueError(f"{self!r} is in a graph" if graph is None
                                 else f"{self!r} is also in another graph")
        for d in self._dependents:
            if (d not in members and (<Ugen>d).ptr is not NULL
                    and (<Ugen>d)._reads(self)):
                raise ValueError(f"{d!r} reads {self!r}")

    cdef _mark_deleted(self):
        self.ptr = NULL
        self._inputs.clear()

    def delete(self):
        """Delete this unit generator now (``csoundUgenDelete``), running its deinit.

        Afterwards it and its variables raise on use. Raises ``ValueError``,
        deleting nothing, if a graph holds it (use
        :meth:`UgenGraph.delete_all`) or another Ugen reads its variables.
        """
        self._check()
        self._check_deletable({self}, None)
        cs.csoundUgenDelete(self.ptr)
        self._mark_deleted()

    cdef int _in_index(self, int index) except -1:
        self._check()
        if not 0 <= index < cs.csoundUgenGetInCount(self.ptr):
            raise IndexError(f"{self.opname} has no input {index}")
        return index

    cdef int _out_index(self, int index) except -1:
        self._check()
        if not 0 <= index < cs.csoundUgenGetOutCount(self.ptr):
            raise IndexError(f"{self.opname} has no output {index}")
        return index

    def get_in_count(self) -> int:
        """Return the number of inputs; a var-arg parameter expands to 8."""
        self._check()
        return cs.csoundUgenGetInCount(self.ptr)

    def get_out_count(self) -> int:
        self._check()
        return cs.csoundUgenGetOutCount(self.ptr)

    def get_in_type(self, int index) -> UgenArgType:
        return UgenArgType(cs.csoundUgenGetInType(self.ptr, self._in_index(index)))

    def get_out_type(self, int index) -> UgenArgType:
        return UgenArgType(cs.csoundUgenGetOutType(self.ptr, self._out_index(index)))

    def get_in_var(self, int index) -> UgenVar:
        """Return input ``index``; after :meth:`set_input_var` it shares the wired data."""
        cdef cs.UGEN_VAR *v = cs.csoundUgenGetInVar(self.ptr, self._in_index(index))
        return UgenVar.wrap(v, self._owner, self._generation, self, False)

    def get_out_var(self, int index) -> UgenVar:
        cdef cs.UGEN_VAR *v = cs.csoundUgenGetOutVar(self.ptr, self._out_index(index))
        return UgenVar.wrap(v, self._owner, self._generation, self, False)

    def set_input_var(self, int index, UgenVar var not None):
        """Make input ``index`` read ``var``'s data directly (no copy).

        Typically another unit generator's output. The types must match;
        i- and k-rate scalars are interchangeable.
        """
        self._in_index(index)
        var._check()
        if var._owner is not self._owner:
            raise ValueError("var belongs to another Csound instance")
        cdef int want = cs.csoundUgenGetInType(self.ptr, index)
        cdef int have = cs.csoundUgenVarGetType(var.ptr)
        if want != have and not (want <= UgenArgType.K and have <= UgenArgType.K):
            raise TypeError(f"input {index} of {self.opname} is "
                            f"{UgenArgType(want).name}, var is "
                            f"{UgenArgType(have).name}")
        cs.csoundUgenSetInputVar(self.ptr, index, var.ptr)
        self._inputs[index] = var
        if not var._owned:
            (<Ugen>var._parent)._dependents.add(self)

    def set_context(self, UgenContext context not None):
        """Use ``context``'s instrument state. Call before :meth:`init`."""
        self._check()
        if context._owner is not self._owner:
            raise ValueError("context belongs to another Csound instance")
        cs.csoundUgenSetContext(self.ptr, context.ptr)
        self._context = context

    def set_value(self, int index, double value):
        """Set i- or k-rate input ``index``."""
        self.get_in_var(index).value = value

    def get_value(self, int index) -> float:
        """Return i- or k-rate output ``index``."""
        return self.get_out_var(index).value

    def set_string(self, int index, str value):
        """Set string input ``index``."""
        self.get_in_var(index).string = value

    def get_string(self, int index) -> str:
        """Return string output ``index``."""
        return self.get_out_var(index).string

    # Direct calls to the ugen.h index helpers, without a UgenVar per call.
    # Csound checks neither index nor type for the value helpers.

    cdef _require_scalar(self, int t):
        if t != UgenArgType.I and t != UgenArgType.K:
            raise TypeError(f"{UgenArgType(t).name}-type variable")

    def set_in_value(self, int index, double value):
        """Set i- or k-rate input ``index`` (``csoundUgenSetValue``)."""
        self._require_scalar(cs.csoundUgenGetInType(self.ptr, self._in_index(index)))
        cs.csoundUgenSetValue(self.ptr, index, value)

    def get_out_value(self, int index) -> float:
        """Return i- or k-rate output ``index`` (``csoundUgenGetValue``)."""
        self._require_scalar(cs.csoundUgenGetOutType(self.ptr, self._out_index(index)))
        return cs.csoundUgenGetValue(self.ptr, index)

    def set_in_string(self, int index, str value):
        """Set string input ``index`` (``csoundUgenSetString``)."""
        self._in_index(index)
        if not cs.csoundUgenSetString(self.ptr, index, value.encode()):
            raise TypeError(f"input {index} of {self.opname} is not a string")

    def get_out_string(self, int index) -> str:
        """Return string output ``index`` (``csoundUgenGetString``)."""
        self._out_index(index)
        if <int>cs.csoundUgenGetOutType(self.ptr, index) != UgenArgType.S:
            raise TypeError(f"output {index} of {self.opname} is not a string")
        cdef const char *t = cs.csoundUgenGetString(self.ptr, index)
        return "" if t is NULL else t.decode("utf-8", "replace")

    def init(self) -> int:
        """Run the opcode's init pass; returns zero on success."""
        self._check()
        return cs.csoundUgenInit(self.ptr)

    def perform(self) -> int:
        """Run the opcode's perf pass for one ksmps block; returns zero on success."""
        self._check()
        return cs.csoundUgenPerform(self.ptr)

    def __repr__(self):
        return f"<Ugen {self.opname}:{self.outtypes}:{self.intypes}>"


cdef class UgenVar:
    """A typed argument slot of a :class:`Ugen`, or a standalone variable.

    Access the data as :attr:`value` (i/k), :attr:`samples` (a) or
    :attr:`string` (S). :attr:`data_address` gives the raw data pointer.
    """

    cdef cs.UGEN_VAR *ptr
    cdef Csound _owner
    cdef unsigned long _generation
    cdef object _parent  # the Ugen owning the slot, or the factory (standalone)
    cdef bint _owned

    @staticmethod
    cdef UgenVar wrap(cs.UGEN_VAR *ptr, Csound owner, unsigned long generation,
                      object parent, bint owned):
        cdef UgenVar obj = UgenVar.__new__(UgenVar)
        obj.ptr = ptr
        obj._owner = owner
        obj._generation = generation
        obj._parent = parent
        obj._owned = owned
        return obj

    def __dealloc__(self):
        if (self._owned and self.ptr is not NULL and self._parent is not None
                and _ugen_live(self._owner, self._generation)):
            cs.csoundUgenVarDelete(self.ptr)

    cdef _check(self):
        _ugen_check(self._owner, self._generation)
        if not self._owned and (self._parent is None or (<Ugen>self._parent).ptr is NULL):
            raise ValueError("the variable's Ugen was deleted")

    cdef _require(self, int a, int b):
        self._check()
        cdef int t = cs.csoundUgenVarGetType(self.ptr)
        if t != a and t != b:
            raise TypeError(f"{UgenArgType(t).name}-type variable")

    @property
    def type(self) -> UgenArgType:
        self._check()
        return UgenArgType(cs.csoundUgenVarGetType(self.ptr))

    @property
    def size(self) -> int:
        """Size of the data in bytes."""
        self._check()
        return cs.csoundUgenVarGetSize(self.ptr)

    @property
    def data_address(self) -> int:
        """Address of the data: a cs_float, cs_float[ksmps], STRINGDAT or PVSDAT."""
        self._check()
        return <uintptr_t>cs.csoundUgenVarGetData(self.ptr)

    @property
    def value(self) -> float:
        """The scalar of an i- or k-rate variable."""
        self._require(UgenArgType.I, UgenArgType.K)
        return cs.csoundUgenVarGetValue(self.ptr)

    @value.setter
    def value(self, double v):
        self._require(UgenArgType.I, UgenArgType.K)
        cs.csoundUgenVarSetValue(self.ptr, v)

    @property
    def samples(self) -> list:
        """The ksmps samples of an a-rate variable."""
        self._require(UgenArgType.A, UgenArgType.A)
        cdef cs.cs_float *p = <cs.cs_float *>cs.csoundUgenVarGetData(self.ptr)
        cdef size_t n = cs.csoundUgenVarGetSize(self.ptr) // sizeof(cs.cs_float)
        return [p[i] for i in range(n)]

    @samples.setter
    def samples(self, object values):
        self._require(UgenArgType.A, UgenArgType.A)
        cdef cs.cs_float *p = <cs.cs_float *>cs.csoundUgenVarGetData(self.ptr)
        cdef size_t n = cs.csoundUgenVarGetSize(self.ptr) // sizeof(cs.cs_float)
        if len(values) != n:
            raise ValueError(f"a-rate variable expects {n} samples (ksmps), "
                             f"got {len(values)}")
        for i in range(n):
            p[i] = values[i]

    @property
    def string(self) -> str:
        """The text of an S variable."""
        self._require(UgenArgType.S, UgenArgType.S)
        cdef const char *t = cs.csoundUgenVarGetString(self.ptr)
        return "" if t is NULL else t.decode("utf-8", "replace")

    @string.setter
    def string(self, str v):
        self._require(UgenArgType.S, UgenArgType.S)
        cs.csoundUgenVarSetString(self.ptr, v.encode())

    def __repr__(self):
        if not _ugen_live(self._owner, self._generation):
            return "<UgenVar stale>"
        return f"<UgenVar {self.type.name} size={self.size}>"


cdef class UgenGraph:
    """Unit generators run in insertion order (``UGEN_GRAPH``).

    The graph references its unit generators; it does not own them unless
    :meth:`delete_all` is called.
    """

    cdef cs.UGEN_GRAPH *ptr
    cdef Csound _owner
    cdef unsigned long _generation
    cdef UgenFactory _factory
    cdef list _ugens
    cdef object __weakref__

    def __dealloc__(self):
        # csoundUgenGraphDelete() reads the factory; the Ugens stay alive.
        if (self.ptr is not NULL and self._factory is not None
                and _ugen_live(self._owner, self._generation)):
            cs.csoundUgenGraphDelete(self.ptr)

    cdef _check(self):
        _ugen_check(self._owner, self._generation)
        if self.ptr is NULL:
            raise ValueError("graph was deleted by delete_all()")

    def add(self, Ugen ugen not None) -> int:
        """Append ``ugen`` and return its index in the graph."""
        self._check()
        ugen._check()
        if ugen._owner is not self._owner:
            raise ValueError("ugen belongs to another Csound instance")
        cdef int32_t idx = cs.csoundUgenGraphAdd(self.ptr, ugen.ptr)
        if idx < 0:
            raise MemoryError("csoundUgenGraphAdd failed")
        self._ugens.append(ugen)
        ugen._graphs.add(self)
        return idx

    def delete_all(self):
        """Delete the graph and its unit generators now (``csoundUgenGraphDeleteAll``).

        Runs each opcode's deinit without waiting for garbage collection.
        Afterwards the graph, its Ugens and their variables raise on use.
        Raises ``ValueError``, deleting nothing, if a Ugen occurs twice, is
        in another graph, or feeds a Ugen outside this graph: each would
        then use freed memory.
        """
        self._check()
        members = set()
        for u in self._ugens:
            if u in members:
                raise ValueError(f"{u!r} occurs twice; it would be deleted twice")
            members.add(u)
        for u in self._ugens:
            (<Ugen>u)._check_deletable(members, self)
        cs.csoundUgenGraphDeleteAll(self.ptr)
        self.ptr = NULL
        for u in self._ugens:
            (<Ugen>u)._mark_deleted()
        self._ugens = []

    def init(self) -> int:
        """Init every unit generator in order; stops at the first error."""
        self._check()
        return cs.csoundUgenGraphInit(self.ptr)

    def perform(self) -> int:
        """Perform one ksmps block of every unit generator in order."""
        self._check()
        return cs.csoundUgenGraphPerform(self.ptr)

    def __len__(self):
        return len(self._ugens)

    def __getitem__(self, int index) -> Ugen:
        return self._ugens[index]


## ----------------------------------------------------------------------------
## CsoundPerformanceThread

ctypedef void (*process_hook_t)(void *ctx) noexcept nogil

cdef struct ProcessState:
    void *owner  # borrowed CsoundPerformanceThread *
    process_hook_t hook
    void *ctx
    bint py


cdef class CsoundPerformanceThread:
    """Performs a started :class:`Csound` instance on a native thread.

    Use this to drive Csound from other Python threads. Every method queues a
    message that the performance thread runs between control cycles, through
    an unbounded queue. The thread starts paused; call :meth:`play`. Do not
    call :meth:`Csound.perform_ksmps` or :meth:`Csound.run` meanwhile.
    """

    cdef cs.CS_PERF_THREAD *ptr
    cdef readonly Csound csound
    cdef ProcessState process
    cdef object _process_cb
    cdef object _requests  # callables for queued request_callback() messages
    cdef object __weakref__

    def __cinit__(self):
        self.ptr = NULL
        self.process.owner = <void *>self
        self._requests = deque()

    def __init__(self, Csound csound not None):
        if not csound._started:
            raise RuntimeError("call start() on the Csound instance first")
        self.csound = csound
        cdef cs.CS_PERF_THREAD *pt = cs.csoundCreatePerformanceThread(csound.ptr)
        if pt is NULL:
            raise MemoryError("csoundCreatePerformanceThread failed")
        if cs.csoundPerformanceThreadGetStatus(pt) != 0:
            with nogil:
                cs.csoundDestroyPerformanceThread(pt)
            raise RuntimeError("could not create the performance thread")
        self.ptr = pt
        _perf_threads[<uintptr_t>pt] = self

    def __dealloc__(self):
        self._shutdown()
        cdef cs.CS_PERF_THREAD *pt = self.ptr
        self.ptr = NULL
        if pt is not NULL:
            with nogil:
                cs.csoundDestroyPerformanceThread(pt)

    cdef _shutdown(self):
        """Disarm callbacks, then stop and join the thread."""
        if self.ptr is NULL:
            return
        self.process.py = False
        self.process.hook = NULL
        cs.csoundPerformanceThreadSetProcessCB(self.ptr, NULL, NULL)
        cdef cs.CS_PERF_THREAD *pt = self.ptr
        with nogil:
            if cs.csoundPerformanceThreadGetStatus(pt) == 0:
                cs.csoundPerformanceThreadStop(pt)
            cs.csoundPerformanceThreadJoin(pt)

    cdef _check(self):
        if cs.csoundPerformanceThreadGetStatus(self.ptr) != 0:
            raise RuntimeError("the performance has ended")

    @property
    def status(self) -> int:
        """0 while playing, positive after the end or stop(), negative on error."""
        return cs.csoundPerformanceThreadGetStatus(self.ptr)

    def is_running(self) -> bool:
        """Return whether the performance thread is running."""
        return bool(cs.csoundPerformanceThreadIsRunning(self.ptr))

    def play(self):
        """Start or resume performance."""
        cs.csoundPerformanceThreadPlay(self.ptr)

    def pause(self):
        """Pause performance."""
        cs.csoundPerformanceThreadPause(self.ptr)

    def toggle_pause(self):
        """Pause if playing, play if paused."""
        cs.csoundPerformanceThreadTogglePause(self.ptr)

    def stop(self):
        """Stop performance; :meth:`join` waits for the thread to end."""
        cs.csoundPerformanceThreadStop(self.ptr)

    def join(self) -> int:
        """Wait for the performance to end and return :attr:`status`."""
        cdef int result
        cdef cs.CS_PERF_THREAD *pt = self.ptr
        with nogil:
            result = cs.csoundPerformanceThreadJoin(pt)
        return result

    def flush_message_queue(self):
        """Wait until all queued messages have been processed.

        Ignored (with a warning) when called from the performance thread.
        """
        cdef cs.CS_PERF_THREAD *pt = self.ptr
        with nogil:
            cs.csoundPerformanceThreadFlushMessageQueue(pt)

    def record(self, str filename, int samplebits=16, int numbufs=4):
        """Start recording the output to ``filename``."""
        cs.csoundPerformanceThreadRecord(self.ptr, filename.encode(),
                                         samplebits, numbufs)

    def stop_record(self):
        """Stop recording and close the file."""
        cs.csoundPerformanceThreadStopRecord(self.ptr)

    def score_event(self, str opcod, object pfields, bint absp2mode=False):
        """Queue a score event, e.g. ``score_event("i", [1, 0, 1])``.

        With ``absp2mode``, p2 counts from the start of performance instead
        of from now.
        """
        cdef bytes op = opcod.encode()
        if len(op) != 1:
            raise ValueError("opcod must be a single character")
        cdef int n = len(pfields)
        cdef cs.cs_float *arr = <cs.cs_float *>malloc(n * sizeof(cs.cs_float)) if n else NULL
        if n and arr is NULL:
            raise MemoryError()
        try:
            for i in range(n):
                arr[i] = pfields[i]
            # The message copies the p-fields.
            cs.csoundPerformanceThreadScoreEvent(self.ptr, absp2mode, op[0], n, arr)
        finally:
            if arr is not NULL:
                free(arr)

    def input_message(self, str message):
        """Queue score line(s) given as a string."""
        cs.csoundPerformanceThreadInputMessage(self.ptr, message.encode())

    def set_score_offset_seconds(self, double seconds):
        """Move the playback position to ``seconds``."""
        cs.csoundPerformanceThreadSetScoreOffsetSeconds(self.ptr, seconds)

    def compile_orc(self, str code):
        """Queue orchestra code for compilation on the performance thread."""
        cs.csoundPerformanceThreadCompileOrc(self.ptr, code.encode())

    def eval_code(self, str code, callback=None):
        """Queue ``code``; ``callback(value)`` gets its ``return`` value.

        The callback runs on the performance thread. Raises
        ``RuntimeError`` once the performance has ended.
        """
        if callback is not None and not callable(callback):
            raise TypeError("callback must be callable or None")
        self._check()
        cdef void *ud = NULL
        if callback is not None:
            Py_INCREF(callback)  # released by _eval_trampoline
            ud = <void *>callback
        cs.csoundPerformanceThreadEvalCodeWithData(
            self.ptr, code.encode(), _eval_trampoline, ud)

    def request_callback(self, callback):
        """Run ``callback()`` on the performance thread, between cycles."""
        if not callable(callback):
            raise TypeError("callback must be callable")
        self._check()
        self._requests.append(callback)
        cs.csoundPerformanceThreadRequestCallback(self.ptr, _request_trampoline)

    def set_process_callback(self, callback):
        """Call ``callback()`` before every control cycle; None removes.

        Runs on the performance thread with the GIL, once per ksmps.
        """
        if callback is not None and not callable(callback):
            raise TypeError("callback must be callable or None")
        self._process_cb = callback
        self.process.py = callback is not None
        self._sync_process()

    def set_process_hook(self, uintptr_t hook, uintptr_t ctx=0):
        """Set ``void hook(void *ctx)``, called before every control cycle
        without the GIL; 0 removes. See :meth:`Csound.set_message_hook`."""
        self.process.hook = NULL
        self.process.ctx = <void *>ctx
        self.process.hook = <process_hook_t>hook
        self._sync_process()

    cdef _sync_process(self):
        if self.process.py or self.process.hook is not NULL:
            cs.csoundPerformanceThreadSetProcessCB(
                self.ptr, _process_trampoline, &self.process)
        else:
            cs.csoundPerformanceThreadSetProcessCB(self.ptr, NULL, NULL)


cdef void _process_trampoline(void *data) noexcept nogil:
    cdef ProcessState *h = <ProcessState *>data
    if h.hook is not NULL:
        h.hook(h.ctx)
    if h.py and _python_alive():
        with gil:
            if h.py:  # cleared while this thread waited
                cb = (<CsoundPerformanceThread>h.owner)._process_cb
                if cb is not None:
                    cb()


cdef void _eval_trampoline(cs.cs_float value, void *ud) noexcept nogil:
    if ud is NULL or not _python_alive():
        return
    with gil:
        cb = <object>ud
        Py_DECREF(cb)  # the reference taken in eval_code(); cb holds another
        cb(value)


cdef void _request_trampoline(void *pt) noexcept nogil:
    if not _python_alive():
        return
    with gil:
        t = _perf_threads.get(<uintptr_t>pt)
        if t is not None and (<CsoundPerformanceThread>t)._requests:
            (<CsoundPerformanceThread>t)._requests.popleft()()
