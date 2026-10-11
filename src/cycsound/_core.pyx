# cython: language_level=3
"""Cython bindings for the Csound 7 Host API."""

import atexit
import weakref
from collections import deque
from enum import Enum

from libc cimport stdio
from libc.stdint cimport int32_t, uint32_t, uintptr_t
from libc.stdlib cimport malloc, free
from libc.string cimport strncpy
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
    cdef bint _keyboard_registered
    cdef unsigned int _keyboard_mask
    cdef bint _message_installed
    cdef bint _message_buffer
    cdef set _keyboard_hooks  # registered hook addresses
    cdef object __weakref__

    def __cinit__(self):
        self.ptr = NULL
        self.ptr_owner = False
        self._hostdata = None
        self._started = False
        self._generation = 0
        self.hooks.owner = <void *>self
        self._keyboard_hooks = set()

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

    cdef _track(self):
        _with_callbacks.add(self)

    cdef _keyboard_host_input(self):
        # inChar_ starts at -1, which makes sensekey poll stdin and overwrite
        # the callback's key: csoundDoCallback_ returns 1 even on success.
        if self._keyboard_registered or self._keyboard_hooks:
            cs.csoundKeyPress(self.ptr, 0)

    @property
    def host_data(self):
        """The ``host_data`` object passed to the constructor."""
        return self._hostdata

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

        Returns 0 (false) during performance and non-zero (true) when the
        performance is finished.
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

    def run(self) -> int:
        """Convenience: :meth:`start` then loop :meth:`perform_ksmps` to the end.

        Returns 0 on success, or the non-zero error code from :meth:`start`.
        """
        cdef int result = self.start()
        if result != 0:
            return result
        cdef cs.CSOUND *ptr = self.ptr
        with nogil:
            while cs.csoundPerformKsmps(ptr) == 0:
                pass
        return 0

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
