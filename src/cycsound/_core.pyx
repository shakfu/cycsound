# cython: language_level=3
"""Cython bindings for the Csound 7 Host API."""

from enum import Enum

from libc cimport stdio
from libc.stdint cimport int32_t
from libc.stdlib cimport malloc, free
from cpython.ref cimport PyObject

cimport csound as cs


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


def get_size_of_myflt() -> int:
    """Return the size of MYFLT in bytes (4 for float, 8 for double)."""
    return cs.csoundGetSizeOfMYFLT()


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


## ----------------------------------------------------------------------------
## Csound

cdef class Csound:
    """Main Csound 7 instance."""

    cdef cs.CSOUND *ptr
    cdef bint ptr_owner
    cdef object _hostdata

    def __cinit__(self):
        self.ptr = NULL
        self.ptr_owner = False
        self._hostdata = None

    def __init__(self, object host_data=None, str opcodedir=None):
        """Create an instance of Csound.

        ``host_data`` may be any Python object (kept alive for the instance and
        retrievable from callback routines). ``opcodedir``, if given, overrides
        the plugin/opcode directory search path.
        """
        cdef bytes odir_b
        cdef const char *odir = NULL
        if opcodedir is not None:
            odir_b = opcodedir.encode()
            odir = odir_b
        cdef void *hd = NULL
        if host_data is not None:
            self._hostdata = host_data
            hd = <void *><PyObject *>host_data
        self.ptr = cs.csoundCreate(hd, odir)
        if self.ptr is NULL:
            raise MemoryError("csoundCreate failed")
        self.ptr_owner = True

    def __dealloc__(self):
        if self.ptr is not NULL and self.ptr_owner:
            cs.csoundDestroy(self.ptr)
            self.ptr = NULL

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
        return cs.csoundCompileTree(self.ptr, root.ptr, async_)

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
        cdef cs.MYFLT result
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
        of p-field MYFLT values. No-op before :meth:`start`.
        """
        cdef int n = len(params)
        cdef cs.MYFLT *arr = <cs.MYFLT *>malloc(n * sizeof(cs.MYFLT)) if n else NULL
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
        return cs.csoundUDPServerClose(self.ptr)

    def udp_console(self, str addr, int port, int mirror) -> int:
        """Send console messages to UDP at ``addr``:``port``."""
        return cs.csoundUDPConsole(self.ptr, addr.encode(), port, mirror)

    def stop_udp_console(self):
        """Stop transmitting console messages via UDP."""
        cs.csoundStopUDPConsole(self.ptr)

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
        """Create a buffer that captures messages printed by Csound."""
        cs.csoundCreateMessageBuffer(self.ptr, to_stdout)

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
        cdef cs.MYFLT *buf = <cs.MYFLT *>malloc(n * sizeof(cs.MYFLT))
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
        cdef cs.MYFLT *buf = <cs.MYFLT *>malloc(n * sizeof(cs.MYFLT))
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
        cdef cs.MYFLT *p = NULL
        cdef int n = cs.csoundGetTable(self.ptr, &p, table_num)
        if n < 0 or p is NULL:
            return None
        return [p[i] for i in range(n)]

    def get_table_args(self, int table_num):
        """Return the GEN arguments used to create a table as a list, or None."""
        cdef cs.MYFLT *p = NULL
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
        cdef cs.MYFLT *buf = <cs.MYFLT *>malloc(n * sizeof(cs.MYFLT)) if n else NULL
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

    cdef cs.MYFLT *get_spin(self):
        """Return the address of the audio input working buffer (spin)."""
        return cs.csoundGetSpin(self.ptr)

    cdef const cs.MYFLT *get_spout(self):
        """Return the address of the audio output working buffer (spout)."""
        return cs.csoundGetSpout(self.ptr)

    cdef int get_channel_ptr(self, void **p, str name, int type):
        """Store a pointer to the named channel in ``*p`` (creating it)."""
        return cs.csoundGetChannelPtr(self.ptr, p, name.encode(), type)
