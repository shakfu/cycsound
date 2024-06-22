from libc cimport stdio
from cpython.ref cimport PyObject


cimport csound as cs

from libc.stdio cimport printf, fprintf, stderr, FILE
# from posix.unistd cimport sleep

from libc.string cimport strcpy, strlen
from libc.stdlib cimport malloc, free

cdef extern from "Python.h":
    char* PyUnicode_AsUTF8(object unicode)

## ----------------------------------------------------------------------------
## Instantiation

def csoundInitialize(flags: int) -> int:
    """Initialise Csound library with specific flags. 

    Called internally by `csoundCreate()`, so there is generally no need to use it
    explicitly unless you need to avoid default initilization that sets
    signal handlers and atexit() callbacks.

    Return value is zero on success, positive if initialisation was
    done already, and negative on error.
    """
    return cs.csoundInitialize(flags)

# see: https://cython.readthedocs.io/en/latest/src/userguide/faq.html#what-is-the-difference-between-pyobject-and-object
# cdef cs.CSOUND *csoundCreate(void *hostData):
#     """Creates an instance of Csound.

#     Returns an opaque pointer that
#     must be passed to most Csound API functions.  The hostData
#     parameter can be NULL, or it can be a pointer to any sort of
#     data; this pointer can be accessed from the Csound instance
#     that is passed to callback routines.
#     """
#     return cs.csoundCreate(hostData)

def set_opcode_dir(s: str):
    """Sets an opcodedir override for csoundCreate()"""
    cs.csoundSetOpcodedir(s.encode())

def get_version() -> int:
    """Returns the version number times 1000 (5.00.0 = 5000)."""
    return cs.csoundGetVersion()

def get_api_version() -> int:
    """Returns the API version number times 100 (1.00 = 100)."""
    return cs.csoundGetAPIVersion()

def get_size_of_myflt() -> int:
    """Return the size of MYFLT in bytes."""
    return cs.csoundGetSizeOfMYFLT()

## ----------------------------------------------------------------------------
## Utility classes

cdef class ArgArray:
    """wrapper classs around arg array"""
    cdef const char ** argv
    cdef int argc

    def __cinit__(self, tuple args):
        self.argc = len(args)
        self.argv = <const char **>malloc(self.argc * sizeof(char *))
        for i in range(self.argc):
            self.argv[i] = PyUnicode_AsUTF8(args[i])

    def __dealloc__(self):
        if self.argv:
            free(self.argv)

    def __iter__(self):
        for i in range(self.argc):
            yield self.argv[i].decode()

    def dump(self):
        for i in self:
            print(i)

    def as_list(self):
        return list(self)



## ----------------------------------------------------------------------------
## Opaque classes

cdef class Tree:
    """csound TREE class"""

    cdef cs.TREE* ptr
    cdef bint ptr_owner

    @staticmethod
    cdef Tree from_ptr(cs.TREE* ptr, bint owner=False):
        cdef Tree obj = Csound.__new__(Csound)
        obj.ptr = ptr
        obj.ptr_owner = owner
        return obj

cdef class Params:
    """csound params class"""

    cdef cs.CSOUND_PARAMS* ptr
    cdef bint ptr_owner

    def __cinit__(self):
        self.ptr_owner = False

    def __dealloc__(self):
        if self.ptr is not NULL and self.ptr_owner is True:
            free(self.ptr)
            self.ptr = NULL

    def __init__(self):
        raise TypeError("This cannot be instatiated directly")

    @staticmethod
    cdef Params from_ptr(cs.CSOUND_PARAMS* ptr, bint owner=False):
        cdef Params params = Params.__new__(Params)
        params.ptr = ptr
        params.ptr_owner = owner
        return params

    @staticmethod
    cdef Params new():
        cdef cs.CSOUND_PARAMS *ptr = <cs.CSOUND_PARAMS*>malloc(sizeof(cs.CSOUND_PARAMS))
        if ptr is NULL:
            raise MemoryError
        ptr.debug_mode = 0
        ptr.buffer_frames = 0
        ptr.hardware_buffer_frames = 0
        ptr.displays = 0
        ptr.ascii_graphs = 0
        ptr.postscript_graphs = 0
        ptr.message_level = 0
        ptr.tempo = 0
        ptr.ring_bell = 0
        ptr.defer_gen01_load = 0
        ptr.midi_key = 0
        ptr.midi_key_cps = 0
        ptr.midi_key_oct = 0
        ptr.midi_key_pch = 0
        ptr.midi_velocity = 0
        ptr.midi_velocity_amp = 0
        ptr.no_default_paths = 0
        ptr.number_of_threads = 0
        ptr.syntax_check_only = 0
        ptr.csd_line_counts = 0
        ptr.compute_weights = 0
        ptr.realtime_mode = 0
        ptr.sample_accurate = 0
        ptr.sample_rate_override = 0.0
        ptr.control_rate_override = 0.0
        ptr.nchnls_override = 0
        ptr.nchnls_i_override = 0
        ptr.e0dbfs_override = 0.0
        ptr.daemon = 0
        ptr.ksmps_override = 0
        ptr.FFT_library = 0
        return Params.from_ptr(ptr, owner=True)

    @property
    def debug_mode(self):
        return self.ptr.debug_mode

    @property
    def buffer_frames(self):
        return self.ptr.buffer_frames

    @property
    def hardware_buffer_frames(self):
        return self.ptr.hardware_buffer_frames

    @property
    def displays(self):
        return self.ptr.displays

    @property
    def ascii_graphs(self):
        return self.ptr.ascii_graphs

    @property
    def postscript_graphs(self):
        return self.ptr.postscript_graphs

    @property
    def message_level(self):
        return self.ptr.message_level

    @property
    def tempo(self):
        return self.ptr.tempo

    @property
    def ring_bell(self):
        return self.ptr.ring_bell

    @property
    def defer_gen01_load(self):
        return self.ptr.defer_gen01_load

    @property
    def midi_key(self):
        return self.ptr.midi_key

    @property
    def midi_key_cps(self):
        return self.ptr.midi_key_cps

    @property
    def midi_key_oct(self):
        return self.ptr.midi_key_oct

    @property
    def midi_key_pch(self):
        return self.ptr.midi_key_pch

    @property
    def midi_velocity(self):
        return self.ptr.midi_velocity

    @property
    def midi_velocity_amp(self):
        return self.ptr.midi_velocity_amp

    @property
    def no_default_paths(self):
        return self.ptr.no_default_paths

    @property
    def number_of_threads(self):
        return self.ptr.number_of_threads

    @property
    def syntax_check_only(self):
        return self.ptr.syntax_check_only

    @property
    def csd_line_counts(self):
        return self.ptr.csd_line_counts

    @property
    def compute_weights(self):
        return self.ptr.compute_weights

    @property
    def realtime_mode(self):
        return self.ptr.realtime_mode

    @property
    def sample_accurate(self):
        return self.ptr.sample_accurate

    @property
    def sample_rate_override(self):
        return self.ptr.sample_rate_override

    @property
    def control_rate_override(self):
        return self.ptr.control_rate_override

    @property
    def nchnls_override(self):
        return self.ptr.nchnls_override

    @property
    def nchnls_i_override(self):
        return self.ptr.nchnls_i_override

    @property
    def e0dbfs_override(self):
        return self.ptr.e0dbfs_override

    @property
    def daemon(self):
        return self.ptr.daemon

    @property
    def ksmps_override(self):
        return self.ptr.ksmps_override

    @property
    def FFT_library(self):
        return self.ptr.FFT_library

## ----------------------------------------------------------------------------
## Csound class

cdef class Csound:
    """main csound class."""

    cdef cs.CSOUND* ptr
    cdef bint ptr_owner

    def __cinit__(self):
        self.ptr = NULL
        self.ptr_owner = False

    def __dealloc__(self):
        if self.ptr is not NULL and self.ptr_owner is True:
            cs.csoundDestroy(self.ptr)
            self.ptr = NULL

    def __init__(self, hostData=None):
        """Creates an instance of Csound.
       
        Gets an opaque pointer that must be passed to most Csound API
        functions.
        """
        self.ptr = cs.csoundCreate(<PyObject*>hostData)
        self.ptr_owner = True

    @staticmethod
    cdef Csound from_ptr(cs.CSOUND* ptr, bint owner=False):
        cdef Csound obj = Csound.__new__(Csound)
        obj.ptr = ptr
        obj.ptr_owner = owner
        return obj

    def load_plugins(self, str directory):
        """Loads all plugins from a given directory."""
        return cs.csoundLoadPlugins(self.ptr, directory.encode())

    ## ----------------------------------------------------------------------------
    ## Performance

    def parse_orc(self, str orc) -> Tree:
        """Parse the given orchestra from an ASCII string into a TREE.

        This can be called during performance to parse new code.
        """
        cdef cs.TREE *tree = cs.csoundParseOrc(self.ptr, orc.encode())
        return Tree.from_ptr(tree)

    def compile_tree(self, Tree root) -> int:
        """Compile the given TREE node into structs for Csound to use.

        This can be called during performance to compile a new TREE.
        """
        return cs.csoundCompileTree(self.ptr, root.ptr)

    def compile_tree_async(self, Tree root) -> int:
        """Asynchronous version of csoundCompileTree()"""
        return cs.csoundCompileTreeAsync(self.ptr, root.ptr)

    def delete_tree(self, Tree tree):
        """Free the resources associated with the TREE *tree
        
        This function should be called whenever the TREE was
        created with csoundParseOrc and memory can be deallocated.
        """
        cs.csoundDeleteTree(self.ptr, tree.ptr)

    def compile_orc(self, str orc) -> int:
        """Parse, and compile the given orchestra from an ASCII string,
        also evaluating any global space code (i-time only)
        this can be called during performance to compile a new orchestra.
            char *orc = "instr 1 \n a1 rand 0dbfs/4 \n out a1 \n";
            csoundCompileOrc(csound, orc);
        """
        return cs.csoundCompileOrc(self.ptr, orc.encode())

    def compile_orc_async(self, str orc) -> int:
        """Async version of csoundCompileOrc().

        The code is parsed and compiled, then placed on a queue for
        asynchronous merge into the running engine, and evaluation.
        The function returns following parsing and compilation.
        """
        return cs.csoundCompileOrcAsync(self.ptr, orc.encode())

    def eval_code(self, str code) -> float:
        """Parse and compile an orchestra given on an string,
          evaluating any global space code (i-time only).
          
          On SUCCESS it returns a value passed to the
          'return' opcode in global space
              char *code = "i1 = 2 + 2 \n return i1 \n";
              MYFLT retval = csoundEvalCode(csound, code);
        """
        return cs.csoundEvalCode(self.ptr, code.encode())


    cdef int initialize_cscore(self, stdio.FILE *insco, stdio.FILE *outsco):
        """Prepares an instance of Csound for Cscore processing outside of running an orchestra (i.e. "standalone Cscore").

        It is an alternative to csoundCompile(), and csoundPerform*() and should
        not be used with these functions.

        You must call this function before using the interface in "cscore.h"
        when you do not wish to compile an orchestra.
        
        Pass it the already open FILE* pointers to the input and
        output score files.
        
        It returns cs.CSOUND_SUCCESS on success and cs.CSOUND_INITIALIZATION or other
        error code if it fails.
        """
        return cs.csoundInitializeCscore(self.ptr, insco, outsco)

    def compile_args(self, *args) -> int:
        """Read arguments, parse and compile an orchestra, read, process and
        load a score."""
        cdef ArgArray params = ArgArray(args)
        return cs.csoundCompileArgs(self.ptr, params.argc, params.argv)

    def start(self) -> int:
        """Prepares Csound for performance.

        Normally called after compiling a csd file or an orc file, 
        in which case score preprocessing is performed and performance
        terminates when the score terminates.

        However, if called before compiling a csd file or an orc file,
        score preprocessing is not performed and "i" statements are dispatched
        as real-time events, the <CsOptions> tag is ignored, and performance
        continues indefinitely or until ended using the API.
        """
        return cs.csoundStart(self.ptr)

    def compile(self, *args) -> int:
        """Compiles Csound input files (such as an orchestra and score, or CSD)
        as directed by the supplied command-line arguments,
        but does not perform them.

        Returns a non-zero error code on failure.

        This function cannot be called during performance, and before a
        repeated call, csoundReset() needs to be called.
        In this (host-driven) mode, the sequence of calls should be as follows:

              csoundCompile(csound, argc, argv);
              while (!csoundPerformBuffer(csound));
              csoundCleanup(csound);
              csoundReset(csound);

        Calls csoundStart() internally.
        Can only be called again after reset (see csoundReset())
        """
        cdef ArgArray params = ArgArray(args)
        return cs.csoundCompile(self.ptr, params.argc, params.argv)

    def compile_csd(self, str csd_filename) -> int:
        """Compiles a Csound input file (CSD, .csd file), but does not perform it.
        Returns a non-zero error code on failure.

        If csoundStart is called before csoundCompileCsd, the <CsOptions>
        element is ignored (but csoundSetOption can be called any number of
        times), the <CsScore> element is not pre-processed, but dispatched as
        real-time events; and performance continues indefinitely, or until
        ended by calling csoundStop or some other logic. In this "real-time"
        mode, the sequence of calls should be:

            csoundSetOption("-an_option");
            csoundSetOption("-another_option");
            csoundStart(csound);
            csoundCompileCsd(csound, csd_filename);
            while (1) {
               csoundPerformBuffer(csound);
               // Something to break out of the loop
               // when finished here...
            }
            csoundCleanup(csound);
            csoundReset(csound);

        NB: this function can be called repeatedly during performance to
        replace or add new instruments and events.

        But if csoundCompileCsd is called before csoundStart, the <CsOptions>
        element is used, the <CsScore> section is pre-processed and dispatched
        normally, and performance terminates when the score terminates, or
        csoundStop is called. In this "non-real-time" mode (which can still
        output real-time audio and handle real-time events), the sequence of
        calls should be:

            csoundCompileCsd(csound, csd_filename);
            csoundStart(csound);
            while (1) {
               int finished = csoundPerformBuffer(csound);
               if (finished) break;
            }
            csoundCleanup(csound);
            csoundReset(csound);
        """
        return cs.csoundCompileCsd(self.ptr, csd_filename.encode())


    def compile_csd_text(self, str csd_text) -> int:
        """Behaves the same way as csoundCompileCsd, except that the content
        of the CSD is read from the csd_text string rather than from a file.

        This is convenient when it is desirable to package the csd as part of
        an application or a multi-language piece.
        """
        return cs.csoundCompileCsdText(self.ptr, csd_text.encode())


    def perform(self) -> int:
        """Senses input events and performs audio output until the end of score
        is reached (positive return value), an error occurs (negative return
        value), or performance is stopped by calling csoundStop() from another
        thread (zero return value).

        Note that csoundCompile() or csoundCompileOrc(), csoundReadScore(),
        csoundStart() must be called first.

        In the case of zero return value, csoundPerform() can be called again
        to continue the stopped performance. Otherwise, csoundReset() should be
        called to clean up after the finished or failed performance.
        """
        return cs.csoundPerform(self.ptr)

    def perform_ksmps(self) -> int:
        """Senses input events, and performs one control sample worth (ksmps) of
        audio output.

        Note that csoundCompile() or csoundCompileOrc(), csoundReadScore(),
        csoundStart() must be called first.
        Returns false during performance, and true when performance is finished.
        If called until it returns true, will perform an entire score.
        Enables external software to control the execution of Csound,
        and to synchronize performance with audio input and output.
        """
        return cs.csoundPerformKsmps(self.ptr)


    def perform_buffer(self) -> int:
        """Performs Csound, sensing real-time and score events
        and processing one buffer's worth (-b frames) of interleaved audio.

        Note that csoundCompile must be called first, then call
        csoundGetOutputBuffer() and csoundGetInputBuffer() to get the pointer
        to csound's I/O buffers.
        Returns false during performance, and true when performance is finished.
        """
        return cs.csoundPerformBuffer(self.ptr)

    def stop(self):
        """Stops a csoundPerform() running in another thread.

        Note that it is not guaranteed that csoundPerform() has already 
        stopped when this function returns.
        """
        cs.csoundStop(self.ptr)

    def cleanup(self) -> int:
        """Prints information about the end of a performance, and closes audio
        and MIDI devices.

        Note: after calling csoundCleanup(), the operation of the perform
        functions is undefined.
        """
        return cs.csoundCleanup(self.ptr)

    def reset(self):
        """Resets all internal memory and state in preparation for a new performance.

        Enables external software to run successive Csound performances
        without reloading Csound. Implies csoundCleanup(), unless already called.
        """
        cs.csoundReset(self.ptr)

    ## ----------------------------------------------------------------------------
    ## UDP server

    def udp_server_start(self, int port) -> int:
        """Starts the UDP server on a supplied port number.

        Returns cs.CSOUND_SUCCESS if server has been started successfully,
        otherwise, cs.CSOUND_ERROR.
        """
        assert port > 0, "port number must be above 0"
        return cs.csoundUDPServerStart(self.ptr, port)

    def udp_server_status(self) -> int:
        """Returns the port number on which the server is running, or
        cs.CSOUND_ERROR if the server is not running.
        """
        return cs.csoundUDPServerStatus(self.ptr)

    def udp_server_close(self) -> int:
        """Closes the UDP server, returning cs.CSOUND_SUCCESS if the
        running server was successfully closed, cs.CSOUND_ERROR otherwise.
        """
        return cs.csoundUDPServerClose(self.ptr)

    def upd_console(self, str addr, int port, int mirror) -> int:
        """Turns on the transmission of console messages to UDP on address addr
        port port.

        If mirror is one, the messages will continue to be
        sent to the usual destination (see csoundSetMessaggeCallback())
        as well as to UDP.
        
        Returns cs.CSOUND_SUCCESS or cs.CSOUND_ERROR if the UDP transmission
        could not be set up.
        """
        return cs.csoundUDPConsole(self.ptr, addr.encode(), port, mirror)

    def stop_udp_console(self):
        """Stop transmitting console messages via UDP."""
        cs.csoundStopUDPConsole(self.ptr)

    ## ----------------------------------------------------------------------------
    ## Attributes

    def get_sr(self) -> float:
        """Returns the number of audio sample frames per second."""
        return cs.csoundGetSr(self.ptr)

    def get_kr(self) -> float:
        """Returns the number of control samples per second."""
        return cs.csoundGetKr(self.ptr)

    def get_ksmps(self) -> int:
        """Returns the number of audio sample frames per control sample."""
        return cs.csoundGetKsmps(self.ptr)

    def get_nchnls(self) -> int:
        """Returns the number of audio output channels.

        Set through the nchnls header variable in the csd file.
        """
        return cs.csoundGetNchnls(self.ptr)

    def get_nchnls_input(self) -> int:
        """Returns the number of audio input channels.

        Set through the nchnls_i header variable in the csd file. If this variable is
        not set, the value is taken from nchnls.
        """
        return cs.csoundGetNchnlsInput(self.ptr)

    def get_0dBFS(self) -> float:
        """Returns the 0dBFS level of the spin/spout buffers."""
        return cs.csoundGet0dBFS(self.ptr)

    def get_A4(self) -> float:
        """Returns the A4 frequency reference."""
        return cs.csoundGetA4(self.ptr)

    def get_current_time_samples(self) -> int:
        """Return the current performance time in samples."""
        return cs.csoundGetCurrentTimeSamples(self.ptr)

    cdef void *get_host_data(self):
        """Returns host data."""
        return cs.csoundGetHostData(self.ptr)

    cdef set_host_data(self, void *hostData):
        """Sets host data."""
        cs.csoundSetHostData(self.ptr, hostData)

    def set_option(self, str option) -> int:
        """Set a single csound option (flag). Returns cs.CSOUND_SUCCESS on success.
        NB: blank spaces are not allowed
        """
        return cs.csoundSetOption(self.ptr, option.encode())

    def set_params(self, Params params):
        """Configure Csound with a given set of parameters defined in
        the cs.CSOUND_PARAMS structure. 

        These parameters are the part of the OPARMS struct that are configurable 
        through command line flags.
        
        The cs.CSOUND_PARAMS structure can be obtained using csoundGetParams().
        These options should only be changed before performance has started.
        """
        cs.csoundSetParams(self.ptr, params.ptr)

    def get_params(self) -> Params:
        """Get the current set of parameters from a cs.CSOUND instance in
        a cs.CSOUND_PARAMS structure. See csoundSetParams().
        """
        cdef Params p = Params.new()
        cs.csoundGetParams(self.ptr, p.ptr)
        return p

    def get_debug(self):
        """Returns whether Csound is set to print debug messages sent through the
        DebugMsg() internal API function. Anything different to 0 means true.
        """
        return cs.csoundGetDebug(self.ptr)

    def set_debug(self, int debug):
        """Sets whether Csound prints debug messages from the DebugMsg() internal
        API function. Anything different to 0 means true.
        """
        cs.csoundSetDebug(self.ptr, debug)

    def system_sr(self, float val) -> float:
        """If val > 0, sets the internal variable holding the system HW sr.
        Returns the stored value containing the system HW sr.
        """
        return cs.csoundSystemSr(self.ptr, val)

    ## ----------------------------------------------------------------------------
    ## General Input/Output

    # Setting the device or filename name for Csound input and output. These
    # functions are used to set the input and output command line flags that
    # apply to both input and output of audio and MIDI. See command line flags
    # -o, -i, -M and -Q in the Csound Reference Manual.

    def get_output_name(self) -> str:
        """Returns the audio output name (-o)."""
        cdef const char * name = cs.csoundGetOutputName(self.ptr)
        return name.decode()


    def get_input_name(self) -> str:
        """Returns the audio input name (-i)."""
        cdef const char * name = cs.csoundGetInputName(self.ptr)
        return name.decode()


    def set_output(self, str name, str type, str format):
        """Set output destination, type and format.

        type can be one of  "wav","aiff", "au","raw", "paf", "svx", "nist", "voc",
        "ircam","w64","mat4", "mat5", "pvf","xi", "htk","sds","avr","wavex","sd2",
        "flac", "caf","wve","ogg","mpc2k","rf64", or NULL (use default or
        realtime IO).

        format can be one of "alaw", "schar", "uchar", "float", "double", "long",
        "short", "ulaw", "24bit", "vorbis", or NULL (use default or realtime IO).
        For RT audio, use device_id from CS_AUDIODEVICE for a given audio device.
        """
        cs.csoundSetOutput(self.ptr, name.encode(), type.encode(), format.encode())

    cdef get_output_format(self, char *type, char *format):
        """Get output type and format.
        
        type should have space for at least 5 chars excluding termination,
        and format should have space for at least 7 chars.
        
        On return, these will hold the current values for
        these parameters.
        """
        cs.csoundGetOutputFormat(self.ptr, type, format)

    cdef set_input(self, str name):
        """Set input source."""
        cs.csoundSetInput(self.ptr, name.encode())

    cdef set_midi_input(self, str name):
        """Set MIDI input device name/number"""
        cs.csoundSetMIDIInput(self.ptr, name.encode())

    cdef set_midi_file_input(self, str name):
        """Set MIDI file input name"""
        cs.csoundSetMIDIFileInput(self.ptr, name.encode())

    cdef set_midi_output(self, str name):
        """Set MIDI output device name/numbe"""
        cs.csoundSetMIDIOutput(self.ptr, name.encode())

    cdef set_midi_file_output(self, str name):
        """Set MIDI file output name"""
        cs.csoundSetMIDIFileOutput(self.ptr, name.encode())

    cdef set_file_open_callback(self, void (*func)(cs.CSOUND*, const char*, int, int, int) noexcept):
        """Sets an external callback for receiving notices whenever Csound opens
        a file.  The callback is made after the file is successfully opened.
        The following information is passed to the callback:
            char*  pathname of the file; either full or relative to current dir
            int    a file type code from the enumeration cs.CSOUND_FILETYPES
            int    1 if Csound is writing the file, 0 if reading
            int    1 if a temporary file that Csound will delete; 0 if not

        Pass NULL to disable the callback.
        This callback is retained after a csoundReset() call.
        """
        cs.csoundSetFileOpenCallback(self.ptr, func)

    ## ----------------------------------------------------------------------------
    ## Realtime Audio I/O

    cdef set_rtaudio_Module(self, str module):
        """Sets the current RT audio module"""
        cs.csoundSetRTAudioModule(self.ptr, module.encode())

    cdef int get_module(self, int number, char **name, char **type):
        """retrieves a module name and type ("audio" or "midi") given a
        number Modules are added to list as csound loads them returns
        cs.CSOUND_SUCCESS on success and cs.CSOUND_ERROR if module number
        was not found

            char *name, *type;
            int n = 0;
            while(!csoundGetModule(csound, n++, &name, &type))
                printf("Module %d:  %s (%s) \n", n, name, type);

        """
        return cs.csoundGetModule(self.ptr, number, name, type)


    def get_input_buffersize(self) -> int:
        """Returns the number of samples in Csound's input buffer."""
        return cs.csoundGetInputBufferSize(self.ptr)

    def get_output_buffersize(self) -> int:
        """Returns the number of samples in Csound's output buffer."""
        return cs.csoundGetOutputBufferSize(self.ptr)

    cdef cs.MYFLT *get_input_buffer(self):
        """Returns the address of the Csound audio input buffer.

        Enables external software to write audio into Csound before calling
        csoundPerformBuffer.
        """
        return cs.csoundGetInputBuffer(self.ptr)

    cdef cs.MYFLT *get_output_buffer(self):
        """Returns the address of the Csound audio output buffer.

        Enables external software to read audio from Csound after calling
        csoundPerformBuffer.
        """
        return cs.csoundGetOutputBuffer(self.ptr)

    cdef cs.MYFLT *get_spin(self):
        """Returns the address of the Csound audio input working buffer (spin).

        Enables external software to write audio into Csound before calling
        csoundPerformKsmps.
        """
        return cs.csoundGetSpin(self.ptr)

    def clear_spin(self):
        """Clears the input buffer (spin)."""
        cs.csoundClearSpin(self.ptr)


    def add_spin_sample(self, int frame, int channel, float sample):
        """Adds the indicated sample into the audio input working buffer (spin):
        this only ever makes sense before calling csoundPerformKsmps().
        The frame and channel must be in bounds relative to ksmps and nchnls.
        NB: the spin buffer needs to be cleared at every k-cycle by calling
        csoundClearSpinBuffer().
        """
        cs.csoundAddSpinSample(self.ptr, frame, channel, sample)

    def set_spin_sample(self, int frame, int channel, float sample):
        """Sets the audio input working buffer (spin) to the indicated sample
        this only ever makes sense before calling csoundPerformKsmps().
        The frame and channel must be in bounds relative to ksmps and nchnls.
        """
        cs.csoundSetSpinSample(self.ptr, frame, channel, sample)


    cdef cs.MYFLT *get_spout(self):
        """Returns the address of the Csound audio output working buffer (spout).
        Enables external software to read audio from Csound after calling
        csoundPerformKsmps.
        """
        return cs.csoundGetSpout(self.ptr)



    def get_spout_sample(self, int frame, int channel) -> float:
        """Returns the indicated sample from the Csound audio output
        working buffer (spout): only ever makes sense after calling
        csoundPerformKsmps().  The frame and channel must be in bounds
        relative to ksmps and nchnls.
        """
        return cs.csoundGetSpoutSample(self.ptr, frame, channel)



    cdef void **get_rt_record_userdata(self):
        """Return pointer to user data pointer for real time audio input."""
        return cs.csoundGetRtRecordUserData(self.ptr)



    cdef void **get_rt_play_userdata(self):
        """Return pointer to user data pointer for real time audio output."""
        return cs.csoundGetRtPlayUserData(self.ptr)


    def set_host_implemented_audio_io(self, int state, int bufSize):
        """Calling this function with a non-zero 'state' value between
        csoundCreate() and the start of performance will disable all default
        handling of sound I/O by the Csound library, allowing the host
        application to use the spin/spout/input/output buffers directly.
        For applications using spin/spout, bufSize should be set to 0.
        If 'bufSize' is greater than zero, the buffer size (-b) in frames will be
        set to the integer multiple of ksmps that is nearest to the value
        specified.
        """
        cs.csoundSetHostImplementedAudioIO(self.ptr, state, bufSize)


    cdef int get_audio_dev_list(self, cs.CS_AUDIODEVICE *list, int isOutput):
        """This function can be called to obtain a list of available
        input or output audio devices. If list is NULL, the function
        will only return the number of devices (isOutput=1 for out
        devices, 0 for in devices).

        If list is non-NULL, then it should contain enough memory for
        one CS_AUDIODEVICE structure per device.
        Hosts will typically call this function twice: first to obtain
        a number of devices, then, after allocating space for each
        device information structure, pass an array of CS_AUDIODEVICE
        structs to be filled:

            int i,n = csoundGetAudioDevList(csound,NULL,1);
            CS_AUDIODEVICE *devs = (CS_AUDIODEVICE *)
              malloc(n*sizeof(CS_AUDIODEVICE)):
            csoundGetAudioDevList(csound,devs,1):
            for(i=0; i < n; i++)
              csound->Message(csound, " %d: %s (%s)\n",
                    i, devs[i].device_id, devs[i].device_name):
            free(devs);
        """
        return cs.csoundGetAudioDevList(self.ptr, list, isOutput)


    cdef set_play_open_callback(self, int (*playopen__)(cs.CSOUND *, const cs.csRtAudioParams *parm) noexcept):
        """Sets a function to be called by Csound for opening real-time audio playback."""
        cs.csoundSetPlayopenCallback(self.ptr, playopen__)

    cdef set_rt_play_callback(self, void (*rtplay__)(cs.CSOUND *, const cs.MYFLT *outBuf, int nbytes) noexcept):
        """ Sets a function to be called by Csound for performing real-time audio playback."""
        cs.csoundSetRtplayCallback(self.ptr, rtplay__)

    cdef set_rec_open_callback(self, int (*recopen_)(cs.CSOUND *, const cs.csRtAudioParams *parm) noexcept):
        """Sets a function to be called by Csound for opening real-time audio recording."""
        cs.csoundSetRecopenCallback(self.ptr, recopen_)

    cdef set_rt_record_callback(self, int (*rtrecord__)(cs.CSOUND *, cs.MYFLT *inBuf, int nbytes) noexcept):
        """Sets a function to be called by Csound for performing real-time audio recording."""
        cs.csoundSetRtrecordCallback(self.ptr, rtrecord__)

    cdef set_rt_closecallback(self, void (*rtclose__)(cs.CSOUND *) noexcept):
        """Sets a function to be called by Csound for closing real-time audio playback and recording."""
        cs.csoundSetRtcloseCallback(self.ptr, rtclose__)

    cdef set_audio_device_list_callback(self, int (*audiodevlist__)(cs.CSOUND *, cs.CS_AUDIODEVICE *list, int isOutput) noexcept):
        """Sets a function that is called to obtain a list of audio devices.
        
        This should be set by rtaudio modules and should not be set by hosts.
        (See csoundGetAudioDevList())
        """
        cs.csoundSetAudioDeviceListCallback(self.ptr, audiodevlist__)


    ## ----------------------------------------------------------------------------
    ## Realtime MIDI I/O

    def set_midi_module(self, str module):
        """Sets the current MIDI IO module"""
        cs.csoundSetMIDIModule(self.ptr, module.encode())

    def set_host_implemented_midi_io(self, int state):
        """call this function with state 1 if the host is implementing
        MIDI via the callbacks below.
        """
        cs.csoundSetHostImplementedMIDIIO(self.ptr, state)

    cdef int get_midi_dev_list(self, cs.CS_MIDIDEVICE *list, int isOutput):
        """Obtain a list of available input or output midi devices. 

        If list is NULL, the function will only return the number of devices
        (isOutput=1 for out devices, 0 for in devices).

        If list is non-NULL, then it should contain enough memory for
        one CS_MIDIDEVICE structure per device.

        Hosts will typically call this function twice: first to obtain
        a number of devices, then, after allocating space for each
        device information structure, pass an array of CS_MIDIDEVICE
        structs to be filled. (see also csoundGetAudioDevList())
        """
        return cs.csoundGetMIDIDevList(self.ptr, list, isOutput)

    cdef set_external_midi_in_open_callback(self, int (*func)(cs.CSOUND *, void **userData, const char *devName) noexcept):
        """Sets callback for opening real time MIDI input."""
        cs.csoundSetExternalMidiInOpenCallback(self.ptr, func)

    cdef set_external_midi_read_callback(self, int (*func)(cs.CSOUND *, void *userData, unsigned char *buf, int nBytes) noexcept):
        """Sets callback for reading from real time MIDI input."""
        cs.csoundSetExternalMidiReadCallback(self.ptr, func)

    cdef set_external_midi_in_close_callback(self, int (*func)(cs.CSOUND *, void *userData) noexcept):
        """Sets callback for closing real time MIDI input."""
        cs.csoundSetExternalMidiInCloseCallback(self.ptr, func)

    cdef set_external_midi_out_open_callback(self, int (*func)(cs.CSOUND *, void **userData, const char *devName) noexcept):
        """Sets callback for opening real time MIDI output."""
        cs.csoundSetExternalMidiOutOpenCallback(self.ptr, func)

    cdef set_external_midi_write_callback(self, int (*func)(cs.CSOUND *, void *userData, const unsigned char *buf, int nBytes) noexcept):
        """Sets callback for writing to real time MIDI output."""
        cs.csoundSetExternalMidiWriteCallback(self.ptr, func)

    cdef set_external_midi_out_close_callback(self, int (*func)(cs.CSOUND *, void *userData) noexcept):
        """Sets callback for closing real time MIDI output."""
        cs.csoundSetExternalMidiOutCloseCallback(self.ptr, func)

    cdef set_external_midi_error_string_callback(self, const char *(*func)(int) noexcept):
        """Sets callback for converting MIDI error codes to strings."""
        cs.csoundSetExternalMidiErrorStringCallback(self.ptr, func)

    cdef set_midi_device_list_callback(self, int (*mididevlist__)(cs.CSOUND *, cs.CS_MIDIDEVICE *list, int isOutput) noexcept):
        """Sets a function that is called to obtain a list of MIDI devices.
        This should be set by IO plugins, and should not be used by hosts.
        (See csoundGetMIDIDevList())
        """
        cs.csoundSetMIDIDeviceListCallback(self.ptr, mididevlist__)


    ## ----------------------------------------------------------------------------
    ## Score Handling

    def read_score(self, str score):
        """Read, preprocess, and load a score from an ASCII string
        It can be called repeatedly, with the new score events
        being added to the currently scheduled ones.
        """
        return cs.csoundReadScore(self.ptr, score.encode())

    def read_score_async(self, str score):
        """Asynchronous version of csoundReadScore()."""
        return cs.csoundReadScoreAsync(self.ptr, score.encode())

    def get_score_time(self) -> float:
        """Returns the current score time in seconds
        since the beginning of performance.
        """
        return cs.csoundGetScoreTime(self.ptr)

    def is_score_pending(self) -> int:
        """Sets whether Csound score events are performed or not, independently
        of real-time MIDI events (see csoundSetScorePending()).
        """
        return cs.csoundIsScorePending(self.ptr)

    def set_score_pending(self, int pending):
        """Sets whether Csound score events are performed or not (real-time
        events will continue to be performed). Can be used by external software,
        such as a VST host, to turn off performance of score events (while
        continuing to perform real-time events), for example to
        mute a Csound score while working on other tracks of a piece, or
        to play the Csound instruments live.
        """
        return cs.csoundSetScorePending(self.ptr, pending)

    def get_score_offset_seconds(self) -> float:
        """Returns the score time beginning at which score events will
        actually immediately be performed (see csoundSetScoreOffsetSeconds()).
        """
        return cs.csoundGetScoreOffsetSeconds(self.ptr)

    def set_score_offset_seconds(self, float time):
        """Csound score events prior to the specified time are not performed, and
        performance begins immediately at the specified time (real-time events
        will continue to be performed as they are received).

        Can be used by external software, such as a VST host,
        to begin score performance midway through a Csound score,
        for example to repeat a loop in a sequencer, or to synchronize
        other events with the Csound score.
        """
        return cs.csoundSetScoreOffsetSeconds(self.ptr, time)

    def rewind_score(self):
        """Rewinds a compiled Csound score to the time specified with
        csoundSetScoreOffsetSeconds().
        """
        cs.csoundRewindScore(self.ptr)

    cdef set_cscore_callback(self, void (*cscoreCallback_)(cs.CSOUND *) noexcept):
        """Sets an external callback for Cscore processing.
        Pass NULL to reset to the internal cscore() function
        (which does nothing).

        This callback is retained after a csoundReset() call.
        """
        cs.csoundSetCscoreCallback(self.ptr, cscoreCallback_)

    cdef int score_sort(self, stdio.FILE *inFile, stdio.FILE *outFile):
        """Sorts score file 'inFile' and writes the result to 'outFile'.
        The Csound instance should be initialised
        before calling this function, and csoundReset() should be called
        after sorting the score to clean up. On success, zero is returned.
        """
        return cs.csoundScoreSort(self.ptr, inFile, outFile)

    cdef int score_extract(self, stdio.FILE *inFile, stdio.FILE *outFile, stdio.FILE *extractFile):
        """Extracts from 'inFile', controlled by 'extractFile', and writes
        the result to 'outFile'. The Csound instance should be initialised
        before calling this function, and csoundReset()
        should be called after score extraction to clean up.
        The return value is zero on success.
        """
        return cs.csoundScoreExtract(self.ptr, inFile, outFile, extractFile)


    ## ----------------------------------------------------------------------------
    ## Messages and Text

    # cdef CS_PRINTF2 void csoundMessage(self, const char* format, ...)
    #     """Displays an informational message."""

    # cdef CS_PRINTF3 void csoundMessageS(self, int attr, const char* format, ...)
    #     """Print message with special attributes (see msg_attr.h for the list of
    #     available attributes). With attr=0, csoundMessageS() is identical to
    #     csoundMessage().
    #     """

    # cdef void csoundMessageV(self, int attr, const char* format, va_list args)
    
    # cdef void csoundSetDefaultMessageCallback(void (*csoundMessageCallback_)(CSOUND*, int attr, const char* format, va_list valist))
    
    # cdef void csoundSetMessageCallback(self, void (*csoundMessageCallback_)(CSOUND*, int attr, const char* format,va_list valist))
        # """Sets a function to be called by Csound to print an informational message.
        # This callback is never called on --realtime mode
        # """

    cdef set_message_string_callback(self, void (*csoundMessageStrCallback)(cs.CSOUND* csound, int attr, const char* str) noexcept):
        """Sets an alternative function to be called by Csound to print an
        informational message, using a less granular signature.
        This callback can be set for --realtime mode.
        This callback is cleared after csoundReset
        """
        cs.csoundSetMessageStringCallback(self.ptr, csoundMessageStrCallback)


    def get_message_level(self) -> int:
        """Returns the Csound message level (from 0 to 231)."""
        return cs.csoundGetMessageLevel(self.ptr)

    def set_message_level(self, int messageLevel):
        """Sets the Csound message level (from 0 to 231)."""
        cs.csoundSetMessageLevel(self.ptr, messageLevel)

    cdef create_message_buffer(self, int toStdOut):
        """Creates a buffer for storing messages printed by Csound.
        Should be called after creating a Csound instance andthe buffer
        can be freed by calling csoundDestroyMessageBuffer() before
        deleting the Csound instance. You will generally want to call
        csoundCleanup() to make sure the last messages are flushed to
        the message buffer before destroying Csound.
        
        If 'toStdOut' is non-zero, the messages are also printed to
        stdout and stderr (depending on the type of the message),
        in addition to being stored in the buffer.
        Using the message buffer ties up the internal message callback, so
        csoundSetMessageCallback should not be called after creating the
        message buffer.
        """
        cs.csoundCreateMessageBuffer(self.ptr, toStdOut)

    def get_first_message(self) -> str:
        """Returns the first message from the buffer."""
        cdef const char* msg = cs.csoundGetFirstMessage(self.ptr)
        return msg.decode()

    def get_first_message_attr(self) -> int:
        """Returns the attribute parameter (see msg_attr.h) of the first message
        in the buffer.
        """
        return cs.csoundGetFirstMessageAttr(self.ptr)

    def pop_first_message(self):
        """Removes the first message from the buffer."""
        cs.csoundPopFirstMessage(self.ptr)

    def get_message_cnt(self) -> int:
        """Returns the number of pending messages in the buffer."""
        return cs.csoundGetMessageCnt(self.ptr)

    def destroy_message_buffer(self):
        """Releases all memory used by the message buffer."""
        cs.csoundDestroyMessageBuffer(self.ptr)



    ## ----------------------------------------------------------------------------
    ## Channels, Control and Events
    
    cdef int get_channel_ptr(self, cs.MYFLT** p, str name, int type):
        """Stores a pointer to the specified channel of the bus in *p,
        creating the channel first if it does not exist yet.

        'type' must be the bitwise OR of exactly one of the following values,
          cs.CSOUND_CONTROL_CHANNEL
            control data (one MYFLT value)
          cs.CSOUND_AUDIO_CHANNEL
            audio data (csoundGetKsmps(csound) MYFLT values)
          cs.CSOUND_STRING_CHANNEL
            string data (MYFLT values with enough space to store
            csoundGetChannelDatasize() characters, including the
            NULL character at the end of the string)
        and at least one of these:
          cs.CSOUND_INPUT_CHANNEL
          cs.CSOUND_OUTPUT_CHANNEL
        If the channel already exists, it must match the data type
        (control, audio, or string), however, the input/output bits are
        OR'd with the new value. Note that audio and string channels
        can only be created after calling csoundCompile(), because the
        storage size is not known until then.

        Return value is zero on success, or a negative error code,
          cs.CSOUND_MEMORY  there is not enough memory for allocating the channel
          cs.CSOUND_ERROR   the specified name or type is invalid
        or, if a channel with the same name but incompatible type
        already exists, the type of the existing channel. In the case
        of any non-zero return value, *p is set to NULL.
        Note: to find out the type of a channel without actually
        creating or changing it, set 'type' to zero, so that the return
        value will be either the type of the channel, or cs.CSOUND_ERROR
        if it does not exist.

        Operations on **p are not thread-safe by default. The host is required
        to take care of threadsafety by
        1) with control channels use __atomic_load() or
           __atomic_store() gcc atomic builtins to get or set a channel,
           if available.
        2) For string and audio channels (and controls if option 1 is not
           available), retrieve the channel lock with csoundGetChannelLock()
           and use csoundSpinLock() and csoundSpinUnLock() to protect access
           to **p.
        See Top/threadsafe.c in the Csound library sources for
        examples.  Optionally, use the channel get/set functions
        provided below, which are threadsafe by default.
        """
        return cs.csoundGetChannelPtr(self.ptr, p, name.encode(), type)

    
    cdef int list_channels(self, cs.controlChannelInfo_t **lst):
        """Returns a list of allocated channels in *lst. A controlChannelInfo_t
        structure contains the channel characteristics.

        The return value is the number of channels, which may be zero if there
        are none, or cs.CSOUND_MEMORY if there is not enough memory for allocating
        the list. In the case of no channels or an error, *lst is set to NULL.
        Notes: the caller is responsible for freeing the list returned in *lst
        with csoundDeleteChannelList(). The name pointers may become invalid
        after calling csoundReset().
        """
        return cs.csoundListChannels(self.ptr, lst)

    cdef delete_channel_list(self, cs.controlChannelInfo_t *lst):
        """Releases a channel list previously returned by csoundListChannels()."""
        cs.csoundDeleteChannelList(self.ptr, lst)


    cdef int set_control_channel_hints(self, str name, cs.controlChannelHints_t hints):
        """Set parameters hints for a control channel.

        These hints have no internal
        function but can be used by front ends to construct GUIs or to constrain
        values. See the controlChannelHints_t structure for details.
        Returns zero on success, or a non-zero error code on failure:
          cs.CSOUND_ERROR:  the channel does not exist, is not a control channel,
                         or the specified parameters are invalid
          cs.CSOUND_MEMORY: could not allocate memory
        """
        return cs.csoundSetControlChannelHints(self.ptr, name.encode(), hints)

    cdef int get_control_channel_hints(self, str name, cs.controlChannelHints_t *hints):
        """Returns special parameters (assuming there are any) of a control channel,
        previously set with csoundSetControlChannelHints() or the chnparams
        opcode.

        If the channel exists, is a control channel, the channel hints
        are stored in the preallocated controlChannelHints_t structure. The
        attributes member of the structure will be allocated inside this function
        so it is necessary to free it explicitly in the host.
         *
        The return value is zero if the channel exists and is a control
        channel, otherwise, an error code is returned.
        """
        return cs.csoundGetControlChannelHints(self.ptr, name.encode(), hints)


    cdef int* get_channel_lock(self, str name):
        """Recovers a pointer to a lock for the specified channel called 'name'.

        The returned lock can be locked/unlocked  with the csoundSpinLock()
        and csoundSpinUnLock() functions.
        @returns the address of the lock or NULL if the channel does not exist
        """
        return cs.csoundGetChannelLock(self.ptr, name.encode())

    cdef cs.MYFLT get_control_channel(self, str name, int* err):
        """retrieves the value of control channel identified by *name.
        If the err argument is not NULL, the error (or success) code
        finding or accessing the channel is stored in it.
        """
        return cs.csoundGetControlChannel(self.ptr, name.encode(), err)

    def set_control_channel(self, str name, float val):
        """sets the value of control channel identified by *name
        """
        cs.csoundSetControlChannel(self.ptr, name.encode(), val)

    cdef get_audio_channel(self, str name, cs.MYFLT* samples):
        """copies the audio channel identified by *name into array
        *samples which should contain enough memory for ksmps cs.MYFLTs
        """
        cs.csoundGetAudioChannel(self.ptr, name.encode(), samples)

    cdef set_audio_channel(self, str name, cs.MYFLT* samples):
        """sets the audio channel identified by *name with data from array
        *samples which should contain at least ksmps cs.MYFLTs
        """
        cs.csoundSetAudioChannel(self.ptr, name.encode(), samples)

    cdef get_string_channel(self, str name, str string):
        """copies the string channel identified by *name into *string
        which should contain enough memory for the string
        (see csoundGetChannelDatasize() below)
        """
        cs.csoundGetStringChannel(self.ptr, name.encode(), string.encode())

    cdef set_string_channel(self, str name, str string):
        """sets the string channel identified by *name with *string
        """
        cs.csoundSetStringChannel(self.ptr, name.encode(), string.encode())

    def get_channel_datasize(self, str name) -> int:
        """returns the size of data stored in a channel; for string channels
        this might change if the channel space gets reallocated
        Since string variables use dynamic memory allocation in Csound6,
        this function can be called to get the space required for
        csoundGetStringChannel()
        """
        return cs.csoundGetChannelDatasize(self.ptr, name.encode())

    # cdef set_input_channel_callback(self, cs.channelCallback_t inputChannelCallback):
    #     """Sets the function which will be called whenever the invalue opcode
    #     is used.
    #     """
    #     cs.csoundSetInputChannelCallback(self.ptr, inputChannelCallback)

    # cdef set_output_channel_callback(self, cs.channelCallback_t outputChannelCallback):
    #     """Sets the function which will be called whenever the outvalue opcode
    #     is used.
    #     """
    #     cs.csoundSetOutputChannelCallback(self.ptr, outputChannelCallback)

    cdef int set_pvs_channel(self, const cs.PVSDATEXT *fin, str name):
        """Sends a PVSDATEX fin to the pvsin opcode (f-rate) for channel 'name'.
        Returns zero on success, cs.CSOUND_ERROR if the index is invalid or
        fsig framesizes are incompatible.
        cs.CSOUND_MEMORY if there is not enough memory to extend the bus.
        """
        return cs.csoundSetPvsChannel(self.ptr, fin, name.encode())

    cdef int get_pvs_channel(self, cs.PVSDATEXT *fout, str name):
        """Receives a PVSDAT fout from the pvsout opcode (f-rate) at channel 'name'
        Returns zero on success, cs.CSOUND_ERROR if the index is invalid or
        if fsig framesizes are incompatible.
        cs.CSOUND_MEMORY if there is not enough memory to extend the bus
        """
        return cs.csoundGetPvsChannel(self.ptr, fout, name.encode())

    cdef int score_event(self, char type, const cs.MYFLT *pFields, long numFields):
        """Send a new score event. 'type' is the score event type ('a', 'i', 'q',
        'f', or 'e').
        'numFields' is the size of the pFields array.  'pFields' is an array of
        floats with all the pfields for this event, starting with the p1 value
        specified in pFields[0].
        """
        return cs.csoundScoreEvent(self.ptr, type, pFields, numFields)

    cdef score_event_async(self, char type, const cs.MYFLT *pFields, long numFields):
        """Asynchronous version of csoundScoreEvent().
        """
        cs.csoundScoreEventAsync(self.ptr, type, pFields, numFields)

    cdef int score_event_absolute(self, char type, const cs.MYFLT *pfields, long numFields, double time_ofs):
        """Like csoundScoreEvent(), this function inserts a score event, but
        at absolute time with respect to the start of performance, or from an
        offset set with time_ofs
        """
        return cs.csoundScoreEventAbsolute(self.ptr, type, pfields, numFields, time_ofs)

    cdef score_event_absolute_async(self, char type, const cs.MYFLT *pfields, long numFields, double time_ofs):
        """Asynchronous version of csoundScoreEventAbsolute().
        """
        cs.csoundScoreEventAbsoluteAsync(self.ptr, type, pfields, numFields, time_ofs)

    cdef input_message(self, str message):
        """Input a NULL-terminated string (as if from a console), used for line events."""
        cs.csoundInputMessage(self.ptr, message.encode())

    cdef input_message_async(self, const char *message):
        """Asynchronous version of csoundInputMessage().
        """
        cs.csoundInputMessageAsync(self.ptr, message)

    cdef int kill_instance(self, cs.MYFLT instr, char *instrName, int mode, int allow_release):
        """Kills off one or more running instances of an instrument identified
        by instr (number) or instrName (name). If instrName is NULL, the
        instrument number is used.
        Mode is a sum of the following values:
        0,1,2: kill all instances (1), oldest only (1), or newest (2)
        4: only turnoff notes with exactly matching (fractional) instr number
        8: only turnoff notes with indefinite duration (p3 < 0 or MIDI)
        allow_release, if non-zero, the killed instances are allowed to release.
        """
        return cs.csoundKillInstance(self.ptr, instr, instrName, mode, allow_release)


    cdef int register_sense_event_callback(self, void (*func)(cs.CSOUND *, void *) noexcept, void *userData):
        """Register a function to be called once in every control period
        by sensevents(). Any number of functions may be registered,
        and will be called in the order of registration.
        The callback function takes two arguments: the Csound instance
        pointer, and the userData pointer as passed to this function.
        This facility can be used to ensure a function is called synchronously
        before every csound control buffer processing. It is important
        to make sure no blocking operations are performed in the callback.
        The callbacks are cleared on csoundCleanup().
        Returns zero on success.
        """
        return cs.csoundRegisterSenseEventCallback(self.ptr, func, userData)

    cdef key_press(self, char c):
        """Set the ASCII code of the most recent key pressed.
        This value is used by the 'sensekey' opcode if a callback
        for returning keyboard events is not set (see
        csoundRegisterKeyboardCallback()).
        """
        cs.csoundKeyPress(self.ptr, c)

    cdef int register_keyboard_callback(self, int (*func)(void *userData, void *p, unsigned int type) noexcept, void *userData, unsigned int type):
        """Registers general purpose callback functions that will be called to query
        keyboard events. These callbacks are called on every control period by
        the sensekey opcode.
        The callback is preserved on csoundReset(), and multiple
        callbacks may be set and will be called in reverse order of
        registration. If the same function is set again, it is only moved
        in the list of callbacks so that it will be called first, and the
        user data and type mask parameters are updated. 'typeMask' can be the
        bitwise OR of callback types for which the function should be called,
        or zero for all types.
        Returns zero on success, cs.CSOUND_ERROR if the specified function
        pointer or type mask is invalid, and cs.CSOUND_MEMORY if there is not
        enough memory.

        The callback function takes the following arguments:
          void *userData
            the "user data" pointer, as specified when setting the callback
          void *p
            data pointer, depending on the callback type
          unsigned int type
            callback type, can be one of the following (more may be added in
            future versions of Csound):
              cs.CSOUND_CALLBACK_KBD_EVENT
              cs.CSOUND_CALLBACK_KBD_TEXT
                called by the sensekey opcode to fetch key codes. The data
                pointer is a pointer to a single value of type 'int', for
                returning the key code, which can be in the range 1 to 65535,
                or 0 if there is no keyboard event.
                For cs.CSOUND_CALLBACK_KBD_EVENT, both key press and release
                events should be returned (with 65536 (0x10000) added to the
                key code in the latter case) as unshifted ASCII codes.
                cs.CSOUND_CALLBACK_KBD_TEXT expects key press events only as the
                actual text that is typed.
        The return value should be zero on success, negative on error, and
        positive if the callback was ignored (for example because the type is
        not known).
        """
        return cs.csoundRegisterKeyboardCallback(self.ptr, func, userData, type)

    cdef remove_keyboard_callback(self, int (*func)(void *, void *, unsigned int) noexcept):
        """Removes a callback previously set with csoundRegisterKeyboardCallback().
        """
        cs.csoundRemoveKeyboardCallback(self.ptr, func)
    
    ## ----------------------------------------------------------------------------
    ## Tables

    def table_length(self, int table) -> int:
        """Returns the length of a function table (not including the guard point),
        or -1 if the table does not exist.
        """
        return cs.csoundTableLength(self.ptr, table)

    def table_get(self, int table, int index) -> float:
        """Returns the value of a slot in a function table.
        The table number and index are assumed to be valid.
        """
        return cs.csoundTableGet(self.ptr, table, index)

    def table_set(self, int table, int index, cs.MYFLT value):
        """Sets the value of a slot in a function table.
        The table number and index are assumed to be valid.
        """
        cs.csoundTableSet(self.ptr, table, index, value)

    cdef table_copy_out(self, int table, cs.MYFLT *dest):
        """Copy the contents of a function table into a supplied array *dest
        The table number is assumed to be valid, and the destination needs to
        have sufficient space to receive all the function table contents.
        """
        cs.csoundTableCopyOut(self.ptr, table, dest)

    cdef table_copy_out_async(self, int table, cs.MYFLT *dest):
        """Asynchronous version of csoundTableCopyOut()
        """
        cs.csoundTableCopyOutAsync(self.ptr, table, dest)

    cdef table_copy_in(self, int table, cs.MYFLT *src):
        """Copy the contents of an array *src into a given function table
        The table number is assumed to be valid, and the table needs to
        have sufficient space to receive all the array contents.
        """
        cs.csoundTableCopyIn(self.ptr, table, src)

    cdef table_copy_in_async(self, int table, cs.MYFLT *src):
        """Asynchronous version of csoundTableCopyIn()
        """
        cs.csoundTableCopyInAsync(self.ptr, table, src)

    cdef int get_table(self, cs.MYFLT **tablePtr, int tableNum):
        """Stores pointer to function table 'tableNum' in *tablePtr,
        and returns the table length (not including the guard point).
        If the table does not exist, *tablePtr is set to NULL and
        -1 is returned.
        """
        return cs.csoundGetTable(self.ptr, tablePtr, tableNum)

    cdef int get_table_args(self, cs.MYFLT **argsPtr, int tableNum):
        """Stores pointer to the arguments used to generate
        function table 'tableNum' in *argsPtr,
        and returns the number of arguments used.
        If the table does not exist, *argsPtr is set to NULL and
        -1 is returned.
        NB: the argument list starts with the GEN number and is followed by
        its parameters. eg. f 1 0 1024 10 1 0.5  yields the list {10.0,1.0,0.5}
        """
        return cs.csoundGetTableArgs(self.ptr, argsPtr, tableNum)

    def is_named_gen(self, int num) -> int:
        """Checks if a given GEN number num is a named GEN
        if so, it returns the string length (excluding terminating NULL char)
        Otherwise it returns 0.
        """
        return cs.csoundIsNamedGEN(self.ptr, num)

    cdef get_named_gen(self, int num, char *name, int len):
        """Gets the GEN name from a number num, if this is a named GEN
        The final parameter is the max len of the string (excluding termination)
        """
        cs.csoundGetNamedGEN(self.ptr, num, name, len)


    ## ----------------------------------------------------------------------------
    ## Function table display

    def set_is_graphable(self, int isGraphable) -> int:
        """Tells Csound whether external graphic table display is supported.
        Returns the previously set value (initially zero).
        """
        return cs.csoundSetIsGraphable(self.ptr, isGraphable)

    cdef set_make_graph_callback(self, void (*makeGraphCallback_)(cs.CSOUND*, cs.WINDAT* windat, const char* name) noexcept):
        """Called by external software to set Csound's MakeGraph function.
        """
        cs.csoundSetMakeGraphCallback(self.ptr, makeGraphCallback_)

    cdef set_draw_graph_callback(self, void (*drawGraphCallback_)(cs.CSOUND*, cs.WINDAT* windat) noexcept):
        """Called by external software to set Csound's DrawGraph function.
        """
        cs.csoundSetDrawGraphCallback(self.ptr, drawGraphCallback_)

    cdef set_kill_graph_callback(self, void (*killGraphCallback_)(cs.CSOUND*, cs.WINDAT* windat) noexcept):
        """Called by external software to set Csound's KillGraph function.
        """
        cs.csoundSetKillGraphCallback(self.ptr, killGraphCallback_)

    cdef set_exit_graph_callback(self, int (*exitGraphCallback_)(cs.CSOUND*) noexcept):
        """Called by external software to set Csound's ExitGraph function.
        """
        cs.csoundSetExitGraphCallback(self.ptr, exitGraphCallback_)


    ## ----------------------------------------------------------------------------
    ## Opcodes

    cdef void* get_named_gens(self):
        """Finds the list of named gens"""
        return cs.csoundGetNamedGens(self.ptr)

    cdef int new_opcode_list(self, cs.opcodeListEntry** opcodelist):
        """Gets an alphabetically sorted list of all opcodes.
        Should be called after externals are loaded by csoundCompile().
        Returns the number of opcodes, or a negative error code on failure.
        Make sure to call csoundDisposeOpcodeList() when done with the list.
        """
        return cs.csoundNewOpcodeList(self.ptr, opcodelist)

    cdef dispose_opcode_list(self, cs.opcodeListEntry* opcodelist):
        """Releases an opcode list."""
        cs.csoundDisposeOpcodeList(self.ptr, opcodelist)

    cdef int append_opcode(self, const char *opname,
                                  int dsblksiz, int flags, int thread,
                                  const char *outypes, const char *intypes,
                                  int (*iopadr)(cs.CSOUND *, void *) noexcept,
                                  int (*kopadr)(cs.CSOUND *, void *) noexcept,
                                  int (*aopadr)(cs.CSOUND *, void *) noexcept):
        """
        Appends an opcode implemented by external software
        to Csound's internal opcode list.

        The opcode list is extended by one slot,
        and the parameters are copied into the new slot.
        Returns zero on success.
        """
        return cs.csoundAppendOpcode(self.ptr, opname, dsblksiz, flags, thread, 
            outypes, intypes, iopadr, kopadr, aopadr)

    ## ----------------------------------------------------------------------------
    ## Utilities
    
    cdef get_env(self, str name):
        """Get pointer to the value of environment variable 'name', searching
        in this order: local environment of 'csound' (if not NULL), variables
        set with csoundSetGlobalEnv(), and system environment variables.
        If 'csound' is not NULL, should be called after csoundCompile().
        Return value is NULL if the variable is not set.
        """
        cdef const char *value = cs.csoundGetEnv(self.ptr, name.encode())
        return value.decode()

    cdef int create_global_variable(self, const char *name, size_t nbytes):
        """Allocate nbytes bytes of memory that can be accessed later by calling
        csoundQueryGlobalVariable() with the specified name; the space is
        cleared to zero.
        Returns cs.CSOUND_SUCCESS on success, cs.CSOUND_ERROR in case of invalid
        parameters (zero nbytes, invalid or already used name), or
        cs.CSOUND_MEMORY if there is not enough memory.
        """
        return cs.csoundCreateGlobalVariable(self.ptr, name, nbytes)

    cdef void *query_global_variable(self, const char *name):
        """
        Get pointer to space allocated with the name "name".
        Returns NULL if the specified name is not defined.
        """
        return cs.csoundQueryGlobalVariable(self.ptr, name)

    cdef void *query_global_variable_nocheck(self, const char *name):
        """
        This function is the same as csoundQueryGlobalVariable(), except the
        variable is assumed to exist and no error checking is done.
        Faster, but may crash or return an invalid pointer if 'name' is
        not defined.
        """
        return cs.csoundQueryGlobalVariableNoCheck(self.ptr, name)

    cdef int destroy_global_variable(self, const char *name):
        """Free memory allocated for "name" and remove "name" from the database.
        Return value is cs.CSOUND_SUCCESS on success, or cs.CSOUND_ERROR if the name is
        not defined.
        """
        return cs.csoundDestroyGlobalVariable(self.ptr, name)

    cdef int run_utility(self, const char *name, int argc, char **argv):
        """Run utility with the specified name and command line arguments.
        Should be called after loading utility plugins.
        Use csoundReset() to clean up after calling this function.
        Returns zero if the utility was run successfully.
        """
        return cs.csoundRunUtility(self.ptr, name, argc, argv)

    cdef char **list_utilities(self):
        """
        Returns a NULL terminated list of registered utility names.
        The caller is responsible for freeing the returned array with
        csoundDeleteUtilityList(), however, the names should not be
        changed or freed.
        The return value may be NULL in case of an error.
        """
        return cs.csoundListUtilities(self.ptr)

    cdef delete_utility_list(self, char **lst):
        """Releases an utility list previously returned by csoundListUtilities()."""
        cs.csoundDeleteUtilityList(self.ptr, lst)

    cdef const char *get_utility_description(self, const char *utilName):
        """Get utility description.
        Returns NULL if the utility was not found, or it has no description,
        or an error occured.
        """
        return cs.csoundGetUtilityDescription(self.ptr, utilName)

    cdef void *create_circular_buffer(self, int numelem, int elemsize):
        """Create circular buffer with numelem number of elements. The
        element's size is set from elemsize. It should be used like:

            void *rb = csoundCreateCircularBuffer(csound, 1024, sizeof(cs.MYFLT)):
        """
        return cs.csoundCreateCircularBuffer(self.ptr, numelem, elemsize)

    cdef int read_circular_buffer(self, void *circular_buffer, void *out, int items):
        """Read from circular buffer
        @param csound This value is currently ignored.
        @param circular_buffer pointer to an existing circular buffer
        @param out preallocated buffer with at least items number of elements, where
                     buffer contents will be read into
        @param items number of samples to be read
        @returns the actual number of items read (0 <= n <= items)
        """
        return cs.csoundReadCircularBuffer(self.ptr, circular_buffer, out, items)

    cdef int peek_circular_buffer(self, void *circular_buffer, void *out, int items):
        """Read from circular buffer without removing them from the buffer.
        @param circular_buffer pointer to an existing circular buffer
        @param out preallocated buffer with at least items number of elements, where
                     buffer contents will be read into
        @param items number of samples to be read
        @returns the actual number of items read (0 <= n <= items)
        """
        return cs.csoundPeekCircularBuffer(self.ptr, circular_buffer, out, items)

    cdef int write_circular_buffer(self, void *p, const void *inp, int items):
        """Write to circular buffer
        @param csound This value is currently ignored.
        @param p pointer to an existing circular buffer
        @param inp buffer with at least items number of elements to be written into
                     circular buffer
        @param items number of samples to write
        @returns the actual number of items written (0 <= n <= items)
        """
        return cs.csoundWriteCircularBuffer(self.ptr, p, inp, items)

    cdef flush_circular_buffer(self, void *p):
        """Empty circular buffer of any remaining data. This function should only be
        used if there is no reader actively getting data from the buffer.
        @param csound This value is currently ignored.
        @param p pointer to an existing circular buffer
        """
        cs.csoundFlushCircularBuffer(self.ptr, p)

    cdef destroy_circular_buffer(self, void *circularbuffer):
        """Free circular buffer
        """
        cs.csoundDestroyCircularBuffer(self.ptr, circularbuffer)


## ----------------------------------------------------------------------------
## Threading and concurrency


    cdef set_yield_callback(self, int (*yieldCallback_)(cs.CSOUND *) noexcept):
        """Called by external software to set a function for checking system
        events, yielding cpu time for coopertative multitasking, etc.

        This function is optional. It is often used as a way to 'turn off'
        Csound, allowing it to exit gracefully. In addition, some operations
        like utility analysis routines are not reentrant and you should use
        this function to do any kind of updating during the operation.

        Returns an 'OK to continue' boolean.
        """
        cs.csoundSetYieldCallback(self.ptr, yieldCallback_)


cdef void *create_thread(cs.uintptr_t (*threadRoutine)(void *) noexcept, void *userdata):
    """
    Creates and starts a new thread of execution.
    Returns an opaque pointer that represents the thread on success,
    or NULL for failure.
    The userdata pointer is passed to the thread routine.
    """
    return cs.csoundCreateThread(threadRoutine, userdata)

cdef void *create_thread2(cs.uintptr_t (*threadRoutine)(void *) noexcept, unsigned int stack, void *userdata):
    """
    Creates and starts a new thread of execution
    with a user-defined stack size.
    Returns an opaque pointer that represents the thread on success,
    or NULL for failure.
    The userdata pointer is passed to the thread routine.
    """
    return cs.csoundCreateThread2(threadRoutine, stack, userdata)


cdef void *get_current_thread_id():
    """
    Returns the ID of the currently executing thread,
    or NULL for failure.
     *
    NOTE: The return value can be used as a pointer
    to a thread object, but it should not be compared
    as a pointer. The pointed to values should be compared,
    and the user must free the pointer after use.
    """
    return cs.csoundGetCurrentThreadId()


cdef cs.uintptr_t join_thread(void *thread):
    """Waits until the indicated thread's routine has finished.
    Returns the value returned by the thread routine.
    """
    return cs.csoundJoinThread(thread)

cdef void *create_thread_lock():
    """
    Creates and returns a monitor object, or NULL if not successful.
    The object is initially in signaled (notified) state.
    """
    return cs.csoundCreateThreadLock()

cdef int wait_thread_lock(void *lock, size_t milliseconds):
    """Waits on the indicated monitor object for the indicated period.
    The function returns either when the monitor object is notified,
    or when the period has elapsed, whichever is sooner; in the first case,
    zero is returned.
    If 'milliseconds' is zero and the object is not notified, the function
    will return immediately with a non-zero status.
    """
    return cs.csoundWaitThreadLock(lock, milliseconds)

cdef wait_thread_lock_no_timeout(void *lock):
    """Waits on the indicated monitor object until it is notified.
    This function is similar to csoundWaitThreadLock() with an infinite
    wait time, but may be more efficient.
    """
    cs.csoundWaitThreadLockNoTimeout(lock)

cdef notify_thread_lock(void *lock):
    """Notifies the indicated monitor object.
    """
    cs.csoundNotifyThreadLock(lock)

cdef destroy_thread_lock(void *lock):
    """Destroys the indicated monitor object.
    """
    cs.csoundDestroyThreadLock(lock)

# ERROR:  cdef void *csoundCreateMutex(int isRecursive):


cdef void *create_mutex(int isRecursive):
    """
    Creates and returns a mutex object, or NULL if not successful.
    Mutexes can be faster than the more general purpose monitor objects
    returned by csoundCreateThreadLock() on some platforms, and can also
    be recursive, but the result of unlocking a mutex that is owned by
    another thread or is not locked is undefined.
    If 'isRecursive' is non-zero, the mutex can be re-locked multiple
    times by the same thread, requiring an equal number of unlock calls;
    otherwise, attempting to re-lock the mutex results in undefined
    behavior.
    Note: the handles returned by csoundCreateThreadLock() and
    csoundCreateMutex() are not compatible.
    """
    return cs.csoundCreateMutex(isRecursive)

cdef lock_mutex(void *mutex_):
    """Acquires the indicated mutex object; if it is already in use by
    another thread, the function waits until the mutex is released by
    the other thread.
    """
    cs.csoundLockMutex(mutex_)

cdef int lock_mutex_no_wait(void *mutex_):
    """Acquires the indicated mutex object and returns zero, unless it is
    already in use by another thread, in which case a non-zero value is
    returned immediately, rather than waiting until the mutex becomes
    available.
    Note: this function may be unimplemented on Windows.
    """
    return cs.csoundLockMutexNoWait(mutex_)

cdef unlock_mutex(void *mutex_):
    """Releases the indicated mutex object, which should be owned by
    the current thread, otherwise the operation of this function is
    undefined. A recursive mutex needs to be unlocked as many times
    as it was locked previously.
    """
    cs.csoundUnlockMutex(mutex_)

cdef destroy_mutex(void *mutex_):
    """Destroys the indicated mutex object. Destroying a mutex that
    is currently owned by a thread results in undefined behavior.
    """
    cs.csoundDestroyMutex(mutex_)

cdef void *csoundCreateBarrier(unsigned int max):
    """
    Create a Thread Barrier. Max value parameter should be equal to
    number of child threads using the barrier plus one for the
    master thread"""
    return cs.csoundCreateBarrier(max)


cdef int destroy_barrier(void *barrier):
    """Destroy a Thread Barrier.
    """
    return cs.csoundDestroyBarrier(barrier)

cdef int wait_barrier(void *barrier):
    """Wait on the thread barrier.
    """
    return cs.csoundWaitBarrier(barrier)

cdef void* create_cond_var():
    """ Creates a conditional variable"""
    return cs.csoundCreateCondVar()

cdef cond_wait(void* condVar, void* mutex):
    """Waits up on a conditional variable and mutex
    """
    cs.csoundCondWait(condVar, mutex)

cdef cond_signal(void* condVar):
    """Signals a conditional variable
    """
    cs.csoundCondSignal(condVar)

cdef destroy_cond_var(void* condVar):
    """Destroys a conditional variable
    """
    cs.csoundDestroyCondVar(condVar)

cdef sleep(size_t milliseconds):
    """Waits for at least the specified number of milliseconds,
    yielding the CPU to other threads.
    """
    cs.csoundSleep(milliseconds)

# cdef int spin_lock_init(cs.spin_lock_t *spinlock):
#     """If the spinlock is not locked, lock it and return;
#     if is is locked, wait until it is unlocked, then lock it and return.
#     Uses atomic compare and swap operations that are safe across processors
#     and safe for out of order operations,
#     and which are more efficient than operating system locks.
#     Use spinlocks to protect access to shared data, especially in functions
#     that do little more than read or write such data, for example:
#      *
#     @code
#     static spin_lock_t lock = SPINLOCK_INIT;
#     csoundSpinLockInit(&lock):
#     void write(size_t frames, int* signal)
#     {
#       csoundSpinLock(&lock):
#       for (size_t frame = 0; i < frames; frame++) {
#         global_buffer[frame] += signal[frame];
#       }
#       csoundSpinUnlock(&lock):
#     }
#     @endcode
#     """
#     return cs.csoundSpinLockInit(spinlock)

# cdef spin_lock(cs.spin_lock_t *spinlock):
#     """Locks the spinlock
#     """
#     cs.csoundSpinLock( )

# cdef int spin_try_lock(cs.spin_lock_t *spinlock):
#     """Tries the lock, returns cs.CSOUND_SUCCESS if lock could be acquired,
#         cs.CSOUND_ERROR, otherwise.
#     """
#     return cs.csoundSpinTryLock(spinlock)

# cdef  spin_un_lock(cs.spin_lock_t *spinlock):
#     """Unlocks the spinlock
#     """
#     cs.csoundSpinUnLock(spinlock)


## ----------------------------------------------------------------------------
## Miscellaneous functions

cdef long run_command(const char * const *argv, int noWait):
    """Runs an external command with the arguments specified in 'argv'.
    argv[0] is the name of the program to execute (if not a full path
    file name, it is searched in the directories defined by the PATH
    environment variable). The list of arguments should be terminated
    by a NULL pointer.
    If 'noWait' is zero, the function waits until the external program
    finishes, otherwise it returns immediately. In the first case, a
    non-negative return value is the exit status of the command (0 to
    255), otherwise it is the PID of the newly created process.
    On error, a negative value is returned.
    """
    return cs.csoundRunCommand(argv, noWait)

cdef init_timer_struct(cs.RTCLOCK *clock):
    """Initialise a timer structure.
    """
    cs.csoundInitTimerStruct(clock)

cdef double get_real_time(cs.RTCLOCK *clock):
    """Return the elapsed real time (in seconds) since the specified timer
    structure was initialised.
    """
    return cs.csoundGetRealTime(clock)

cdef double get_cpu_time(cs.RTCLOCK *clock):
    """Return the elapsed CPU time (in seconds) since the specified timer
    structure was initialised.
    """
    return cs.csoundGetCPUTime(clock)

cdef cs.uint32_t get_random_seed_from_time():
    """Return a 32-bit unsigned integer to be used as seed from current time.
    """
    return cs.csoundGetRandomSeedFromTime()

# cdef set_language(cs.cslanguage_t lang_code):
#     """Set language to 'lang_code' (lang_code can be for example
#     CSLANGUAGE_ENGLISH_UK or CSLANGUAGE_FRENCH or many others,
#     see n_getstr.h for the list of languages). This affects all
#     Csound instances running in the address space of the current
#     process. The special language code CSLANGUAGE_DEFAULT can be
#     used to disable translation of messages and free all memory
#     allocated by a previous call to csoundSetLanguage().
#     csoundSetLanguage() loads all files for the selected language
#     from the directory specified by the CSSTRNGS environment
#     variable.
#     """
#     cs.csoundSetLanguage(lang_code)



cdef int set_global_env(const char *name, const char *value):
    """Set the global value of environment variable 'name' to 'value',
    or delete variable if 'value' is NULL.
    It is not safe to call this function while any Csound instances
    are active.
    Returns zero on success.
    """
    return cs.csoundSetGlobalEnv(name, value)


cdef int rand31(int *seedVal):
    """Simple linear congruential random number generator:
      (*seedVal) = (*seedVal)742938285 % 2147483647
    the initial value of *seedVal must be in the range 1 to 2147483646.
    Returns the next number from the pseudo-random sequence,
    in the range 1 to 2147483646.
    """
    return cs.csoundRand31(seedVal)

cdef seed_rand_mt(cs.CsoundRandMTState *p, const cs.uint32_t *initKey, cs.uint32_t keyLength):
    """Initialise Mersenne Twister (MT19937) random number generator,
    using 'keyLength' unsigned 32 bit values from 'initKey' as seed.
    If the array is NULL, the length parameter is used for seeding.
    """
    cs.csoundSeedRandMT(p, initKey, keyLength)

cdef cs.uint32_t rand_mt(cs.CsoundRandMTState *p):
    """Returns next random number from MT19937 generator.
    The PRNG must be initialised first by calling csoundSeedRandMT().
    """
    return cs.csoundRandMT(p)

cdef int open_library(void **library, const char *libraryPath):
    """Platform-independent function to load a shared library.
    """
    return cs.csoundOpenLibrary(library, libraryPath)

cdef int close_library(void *library):
    """Platform-independent function to unload a shared library.
    """
    return cs.csoundCloseLibrary(library)

cdef void *get_library_symbol(void *library, const char *symbolName):
    """Platform-independent function to get a symbol address in a shared library.
    """
    return cs.csoundGetLibrarySymbol(library, symbolName)


