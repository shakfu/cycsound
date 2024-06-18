from libc cimport stdio

cimport csound as cs

from libc.stdio cimport printf, fprintf, stderr, FILE
from posix.unistd cimport sleep

# from libc.string cimport strcpy, strlen
# from libc.stdlib cimport malloc

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

cdef cs.CSOUND *csoundCreate(void *hostData):
    """Creates an instance of Csound.

    Returns an opaque pointer that
    must be passed to most Csound API functions.  The hostData
    parameter can be NULL, or it can be a pointer to any sort of
    data; this pointer can be accessed from the Csound instance
    that is passed to callback routines.
    """
    return cs.csoundCreate(hostData)

def csoundSetOpcodedir(s: str):
    """Sets an opcodedir override for csoundCreate()"""
    cs.csoundSetOpcodedir(s.encode())

cdef csoundLoadPlugins(cs.CSOUND* c, const char* dir):
    """Loads all plugins from a given directory."""
    return cs.csoundLoadPlugins(c, dir)

cdef csoundDestroy(cs.CSOUND* c):
    """Destroys an instance of Csound."""
    return cs.csoundDestroy(c)

def csoundGetVersion() -> int:
    """Returns the version number times 1000 (5.00.0 = 5000)."""
    return cs.csoundGetVersion()

def csoundGetAPIVersion() -> int:
    """Returns the API version number times 100 (1.00 = 100)."""
    return cs.csoundGetAPIVersion()

## ----------------------------------------------------------------------------
## Performance

cdef cs.TREE *csoundParseOrc(cs.CSOUND *c, const char *str):
    """Parse the given orchestra from an ASCII string into a TREE.

    This can be called during performance to parse new code.
    """
    return cs.csoundParseOrc(c, str)


cdef int csoundCompileTree(cs.CSOUND *c, cs.TREE *root):
    """Compile the given TREE node into structs for Csound to use.

    This can be called during performance to compile a new TREE.
    """
    return cs.csoundCompileTree(c, root)


cdef int csoundCompileTreeAsync(cs.CSOUND *c, cs.TREE *root):
    """Asynchronous version of csoundCompileTree()"""
    return cs.csoundCompileTreeAsync(c, root)


cdef csoundDeleteTree(cs.CSOUND *c, cs.TREE *tree):
    """Free the resources associated with the TREE *tree
    
    This function should be called whenever the TREE was
    created with csoundParseOrc and memory can be deallocated.
    """


cdef int csoundCompileOrc(cs.CSOUND *c, const char *str):
    """Parse, and compile the given orchestra from an ASCII string,
    also evaluating any global space code (i-time only)
    this can be called during performance to compile a new orchestra.
    /code
          char *orc = "instr 1 \n a1 rand 0dbfs/4 \n out a1 \n";
          csoundCompileOrc(csound, orc);
    /endcode
    """
    return cs.csoundCompileOrc(c, str)


cdef int csoundCompileOrcAsync(cs.CSOUND *c, const char *str):
    """Async version of csoundCompileOrc().

    The code is parsed and compiled, then placed on a queue for
    asynchronous merge into the running engine, and evaluation.
    The function returns following parsing and compilation.
    """
    return cs.csoundCompileOrcAsync(c, str)


cdef cs.MYFLT csoundEvalCode(cs.CSOUND *c, const char *str):
    """
      Parse and compile an orchestra given on an string,
      evaluating any global space code (i-time only).
      On SUCCESS it returns a value passed to the
      'return' opcode in global space
    /code
          char *code = "i1 = 2 + 2 \n return i1 \n";
          MYFLT retval = csoundEvalCode(csound, code);
    /endcode
    """
    return cs.csoundEvalCode(c, str)


cdef int csoundInitializeCscore(cs.CSOUND *c, stdio.FILE *insco, stdio.FILE *outsco):
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
    return cs.csoundInitializeCscore(c, insco, outsco)


cdef int csoundCompileArgs(cs.CSOUND *c, int argc, const char **argv):
    """Read arguments, parse and compile an orchestra, read, process and
    load a score."""
    return cs.csoundCompileArgs(c, argc, argv)


cdef int csoundStart(cs.CSOUND *c):
    """Prepares Csound for performance.

    Normally called after compiling a csd file or an orc file, 
    in which case score preprocessing is performed and performance
    terminates when the score terminates.

    However, if called before compiling a csd file or an orc file,
    score preprocessing is not performed and "i" statements are dispatched
    as real-time events, the <CsOptions> tag is ignored, and performance
    continues indefinitely or until ended using the API.
    """
    return cs.csoundStart(c)


cdef int csoundCompile(cs.CSOUND *c, int argc, const char **argv):
    """
    Compiles Csound input files (such as an orchestra and score, or CSD)
    as directed by the supplied command-line arguments,
    but does not perform them. Returns a non-zero error code on failure.
    This function cannot be called during performance, and before a
    repeated call, csoundReset() needs to be called.
    In this (host-driven) mode, the sequence of calls should be as follows:
    /code
          csoundCompile(csound, argc, argv);
          while (!csoundPerformBuffer(csound));
          csoundCleanup(csound);
          csoundReset(csound);
    /endcode
     Calls csoundStart() internally.
     Can only be called again after reset (see csoundReset())
    """
    return cs.csoundCompile(c, argc, argv)

cdef int csoundCompileCsd(cs.CSOUND *c, const char *csd_filename):
    """Compiles a Csound input file (CSD, .csd file), but does not perform it.
    Returns a non-zero error code on failure.

    If csoundStart is called before csoundCompileCsd, the <CsOptions>
    element is ignored (but csoundSetOption can be called any number of
    times), the <CsScore> element is not pre-processed, but dispatched as
    real-time events; and performance continues indefinitely, or until
    ended by calling csoundStop or some other logic. In this "real-time"
    mode, the sequence of calls should be:

    \code

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

    \endcode

    NB: this function can be called repeatedly during performance to
    replace or add new instruments and events.

    But if csoundCompileCsd is called before csoundStart, the <CsOptions>
    element is used, the <CsScore> section is pre-processed and dispatched
    normally, and performance terminates when the score terminates, or
    csoundStop is called. In this "non-real-time" mode (which can still
    output real-time audio and handle real-time events), the sequence of
    calls should be:

    \code

    csoundCompileCsd(csound, csd_filename);
    csoundStart(csound);
    while (1) {
       int finished = csoundPerformBuffer(csound);
       if (finished) break;
    }
    csoundCleanup(csound);
    csoundReset(csound);

    \endcode
    """
    return cs.csoundCompileCsd(c, csd_filename)


cdef int csoundCompileCsdText(cs.CSOUND *c, const char *csd_text):
    """Behaves the same way as csoundCompileCsd, except that the content
    of the CSD is read from the csd_text string rather than from a file.

    This is convenient when it is desirable to package the csd as part of
    an application or a multi-language piece.
    """
    return cs.csoundCompileCsdText(c, csd_text)


cdef int csoundPerform(cs.CSOUND *c):
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
    return cs.csoundPerform(c)

cdef int csoundPerformKsmps(cs.CSOUND *c):
    """Senses input events, and performs one control sample worth (ksmps) of
    audio output.

    Note that csoundCompile() or csoundCompileOrc(), csoundReadScore(),
    csoundStart() must be called first.
    Returns false during performance, and true when performance is finished.
    If called until it returns true, will perform an entire score.
    Enables external software to control the execution of Csound,
    and to synchronize performance with audio input and output.
    """
    return cs.csoundPerformKsmps(c)


cdef int csoundPerformBuffer(cs.CSOUND *c):
    """Performs Csound, sensing real-time and score events
    and processing one buffer's worth (-b frames) of interleaved audio.

    Note that csoundCompile must be called first, then call
    csoundGetOutputBuffer() and csoundGetInputBuffer() to get the pointer
    to csound's I/O buffers.
    Returns false during performance, and true when performance is finished.
    """
    return cs.csoundPerformBuffer(c)


cdef csoundStop(cs.CSOUND *c):
    """Stops a csoundPerform() running in another thread.

    Note that it is not guaranteed that csoundPerform() has already 
    stopped when this function returns.
    """
    cs.csoundStop(c)


cdef int csoundCleanup(cs.CSOUND *c):
    """Prints information about the end of a performance, and closes audio
    and MIDI devices.

    Note: after calling csoundCleanup(), the operation of the perform
    functions is undefined.
    """
    return cs.csoundCleanup(c)

cdef csoundReset(cs.CSOUND *c):
    """Resets all internal memory and state in preparation for a new performance.

    Enables external software to run successive Csound performances
    without reloading Csound. Implies csoundCleanup(), unless already called.
    """
    cs.csoundReset(c)

## ----------------------------------------------------------------------------
## UDP server


cdef int csoundUDPServerStart(cs.CSOUND *c, unsigned int port):
    """Starts the UDP server on a supplied port number.

    Returns cs.CSOUND_SUCCESS if server has been started successfully,
    otherwise, cs.CSOUND_ERROR.
    """
    return cs.csoundUDPServerStart(c, port)


cdef int csoundUDPServerStatus(cs.CSOUND *c):
    """Returns the port number on which the server is running, or
     cs.CSOUND_ERROR if the server is not running.
    """
    return cs.csoundUDPServerStatus(c)


cdef int csoundUDPServerClose(cs.CSOUND *c):
    """Closes the UDP server, returning cs.CSOUND_SUCCESS if the
    running server was successfully closed, cs.CSOUND_ERROR otherwise.
    """
    return cs.csoundUDPServerClose(c)


cdef int csoundUDPConsole(cs.CSOUND *c, const char *addr, int port, int mirror):
    """Turns on the transmission of console messages to UDP on address addr
    port port.

    If mirror is one, the messages will continue to be
    sent to the usual destination (see csoundSetMessaggeCallback())
    as well as to UDP.
    
    Returns cs.CSOUND_SUCCESS or cs.CSOUND_ERROR if the UDP transmission
    could not be set up.
    """
    return cs.csoundUDPConsole(c, addr, port, mirror)
                            

cdef csoundStopUDPConsole(cs.CSOUND *c):
    """Stop transmitting console messages via UDP."""
    cs.csoundStopUDPConsole(c)

## ----------------------------------------------------------------------------
## Attributes


cdef cs.MYFLT csoundGetSr(cs.CSOUND *c):
    """Returns the number of audio sample frames per second."""
    return cs.csoundGetSr(c)

cdef cs.MYFLT csoundGetKr(cs.CSOUND *c):
    """Returns the number of control samples per second."""
    return cs.csoundGetKr(c)

cdef cs.uint32_t csoundGetKsmps(cs.CSOUND *c):
    """Returns the number of audio sample frames per control sample."""
    return cs.csoundGetKsmps(c)

cdef cs.uint32_t csoundGetNchnls(cs.CSOUND *c):
    """Returns the number of audio output channels.

    Set through the nchnls header variable in the csd file.
    """
    return cs.csoundGetNchnls(c)

cdef cs.uint32_t csoundGetNchnlsInput(cs.CSOUND *c):
    """Returns the number of audio input channels.

    Set through the nchnls_i header variable in the csd file. If this variable is
    not set, the value is taken from nchnls.
    """
    return cs.csoundGetNchnlsInput(c)

cdef cs.MYFLT csoundGet0dBFS(cs.CSOUND *c):
    """Returns the 0dBFS level of the spin/spout buffers."""
    return cs.csoundGet0dBFS(c)

cdef cs.MYFLT csoundGetA4(cs.CSOUND *c):
    """Returns the A4 frequency reference."""
    return cs.csoundGetA4(c)

cdef cs.int64_t csoundGetCurrentTimeSamples(cs.CSOUND *c):
    """Return the current performance time in samples."""
    return cs.csoundGetCurrentTimeSamples(c)

cdef int csoundGetSizeOfMYFLT():
    """Return the size of MYFLT in bytes."""
    return cs.csoundGetSizeOfMYFLT()

cdef void *csoundGetHostData(cs.CSOUND *c):
    """Returns host data."""
    return csoundGetHostData(c)

cdef csoundSetHostData(cs.CSOUND *c, void *hostData):
    """Sets host data."""
    cs.csoundSetHostData(c, hostData)

cdef int csoundSetOption(cs.CSOUND *c, const char *option):
    """Set a single csound option (flag). Returns cs.CSOUND_SUCCESS on success.
    NB: blank spaces are not allowed
    """
    return cs.csoundSetOption(c, option)

cdef csoundSetParams(cs.CSOUND *c, cs.CSOUND_PARAMS *p):
    """Configure Csound with a given set of parameters defined in
    the cs.CSOUND_PARAMS structure. 

    These parameters are the part of the OPARMS struct that are configurable 
    through command line flags.
    
    The cs.CSOUND_PARAMS structure can be obtained using csoundGetParams().
    These options should only be changed before performance has started.
    """
    cs.csoundSetParams(c, p)

cdef csoundGetParams(cs.CSOUND *c, cs.CSOUND_PARAMS *p):
    """Get the current set of parameters from a cs.CSOUND instance in
    a cs.CSOUND_PARAMS structure. See csoundSetParams().
    """
    cs.csoundSetParams(c, p)

cdef int csoundGetDebug(cs.CSOUND *c):
    """Returns whether Csound is set to print debug messages sent through the
    DebugMsg() internal API function. Anything different to 0 means true.
    """
    return cs.csoundGetDebug(c)

cdef csoundSetDebug(cs.CSOUND *c, int debug):
    """Sets whether Csound prints debug messages from the DebugMsg() internal
    API function. Anything different to 0 means true.
    """
    cs.csoundSetDebug(c, debug)

cdef cs.MYFLT csoundSystemSr(cs.CSOUND *c, cs.MYFLT val):
    """If val > 0, sets the internal variable holding the system HW sr.
    Returns the stored value containing the system HW sr.
    """
    return cs.csoundSystemSr(c, val)

## ----------------------------------------------------------------------------
## General Input/Output

# Setting the device or filename name for Csound input and output. These
# functions are used to set the input and output command line flags that
# apply to both input and output of audio and MIDI. See command line flags
# -o, -i, -M and -Q in the Csound Reference Manual.

cdef const char *csoundGetOutputName(cs.CSOUND *c):
    """Returns the audio output name (-o)."""
    return cs.csoundGetOutputName(c)


cdef const char *csoundGetInputName(cs.CSOUND *c):
    """Returns the audio input name (-i)."""
    return cs.csoundGetInputName(c)


cdef csoundSetOutput(cs.CSOUND *c, const char *name, const char *type, const char *format):
    """Set output destination, type and format.

    type can be one of  "wav","aiff", "au","raw", "paf", "svx", "nist", "voc",
    "ircam","w64","mat4", "mat5", "pvf","xi", "htk","sds","avr","wavex","sd2",
    "flac", "caf","wve","ogg","mpc2k","rf64", or NULL (use default or
    realtime IO).

    format can be one of "alaw", "schar", "uchar", "float", "double", "long",
    "short", "ulaw", "24bit", "vorbis", or NULL (use default or realtime IO).
    For RT audio, use device_id from CS_AUDIODEVICE for a given audio device.
    """
    cs.csoundSetOutput(c, name, type, format)

cdef csoundGetOutputFormat(cs.CSOUND *c, char *type, char *format):
    """Get output type and format.
    
    type should have space for at least 5 chars excluding termination,
    and format should have space for at least 7 chars.
    
    On return, these will hold the current values for
    these parameters.
    """
    cs.csoundGetOutputFormat(c, type, format)

cdef csoundSetInput(cs.CSOUND *c, const char *name):
    """Set input source."""
    cs.csoundSetInput(c, name)

cdef csoundSetMIDIInput(cs.CSOUND *c, const char *name):
    """Set MIDI input device name/number"""
    cs.csoundSetMIDIInput(c, name)

cdef csoundSetMIDIFileInput(cs.CSOUND *c, const char *name):
    """Set MIDI file input name"""
    cs.csoundSetMIDIFileInput(c, name)

cdef csoundSetMIDIOutput(cs.CSOUND *c, const char *name):
    """Set MIDI output device name/numbe"""
    cs.csoundSetMIDIOutput(c, name)

cdef csoundSetMIDIFileOutput(cs.CSOUND *c, const char *name):
    """Set MIDI file output name"""
    cs.csoundSetMIDIFileOutput(c, name)


cdef csoundSetFileOpenCallback(cs.CSOUND *p, void (*func)(cs.CSOUND*, const char*, int, int, int) noexcept):
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
    cs.csoundSetFileOpenCallback(p, func)

## ----------------------------------------------------------------------------
## Realtime Audio I/O

cdef csoundSetRTAudioModule(cs.CSOUND *c, const char *module):
    """Sets the current RT audio module"""
    cs.csoundSetRTAudioModule(c, module)

cdef int csoundGetModule(cs.CSOUND *c, int number, char **name, char **type):
    """retrieves a module name and type ("audio" or "midi") given a
    number Modules are added to list as csound loads them returns
    cs.CSOUND_SUCCESS on success and cs.CSOUND_ERROR if module number
    was not found

        char *name, *type;
        int n = 0;
        while(!csoundGetModule(csound, n++, &name, &type))
            printf("Module %d:  %s (%s) \n", n, name, type);

    """
    return cs.csoundGetModule(c, number, name, type)


cdef long csoundGetInputBufferSize(cs.CSOUND *c):
    """Returns the number of samples in Csound's input buffer."""
    return cs.csoundGetInputBufferSize(c)

cdef long csoundGetOutputBufferSize(cs.CSOUND *c):
    """Returns the number of samples in Csound's output buffer."""
    return cs.csoundGetOutputBufferSize(c)

cdef cs.MYFLT *csoundGetInputBuffer(cs.CSOUND *c):
    """Returns the address of the Csound audio input buffer.

    Enables external software to write audio into Csound before calling
    csoundPerformBuffer.
    """
    return cs.csoundGetInputBuffer(c)

cdef cs.MYFLT *csoundGetOutputBuffer(cs.CSOUND *c):
    """Returns the address of the Csound audio output buffer.

    Enables external software to read audio from Csound after calling
    csoundPerformBuffer.
    """
    return cs.csoundGetOutputBuffer(c)

cdef cs.MYFLT *csoundGetSpin(cs.CSOUND *c):
    """Returns the address of the Csound audio input working buffer (spin).

    Enables external software to write audio into Csound before calling
    csoundPerformKsmps.
    """
    return cs.csoundGetSpin(c)

cdef csoundClearSpin(cs.CSOUND *c):
    """Clears the input buffer (spin)."""
    cs.csoundClearSpin(c)


cdef csoundAddSpinSample(cs.CSOUND *c, int frame, int channel, cs.MYFLT sample):
    """Adds the indicated sample into the audio input working buffer (spin):
    this only ever makes sense before calling csoundPerformKsmps().
    The frame and channel must be in bounds relative to ksmps and nchnls.
    NB: the spin buffer needs to be cleared at every k-cycle by calling
    csoundClearSpinBuffer().
    """
    cs.csoundAddSpinSample(c, frame, channel, sample)

cdef csoundSetSpinSample(cs.CSOUND *c, int frame, int channel, cs.MYFLT sample):
    """Sets the audio input working buffer (spin) to the indicated sample
    this only ever makes sense before calling csoundPerformKsmps().
    The frame and channel must be in bounds relative to ksmps and nchnls.
    """
    cs.csoundSetSpinSample(c, frame, channel, sample)


cdef cs.MYFLT *csoundGetSpout(cs.CSOUND *c):
    """Returns the address of the Csound audio output working buffer (spout).
    Enables external software to read audio from Csound after calling
    csoundPerformKsmps.
    """
    return cs.csoundGetSpout(c)



cdef cs.MYFLT csoundGetSpoutSample(cs.CSOUND *c, int frame, int channel):
    """Returns the indicated sample from the Csound audio output
    working buffer (spout): only ever makes sense after calling
    csoundPerformKsmps().  The frame and channel must be in bounds
    relative to ksmps and nchnls.
    """
    return cs.csoundGetSpoutSample(c, frame, channel)



cdef void **csoundGetRtRecordUserData(cs.CSOUND *c):
    """Return pointer to user data pointer for real time audio input."""
    return cs.csoundGetRtRecordUserData(c)



cdef void **csoundGetRtPlayUserData(cs.CSOUND *c):
    """Return pointer to user data pointer for real time audio output."""
    return cs.csoundGetRtPlayUserData(c)


cdef csoundSetHostImplementedAudioIO(cs.CSOUND *c, int state, int bufSize):
    """Calling this function with a non-zero 'state' value between
    csoundCreate() and the start of performance will disable all default
    handling of sound I/O by the Csound library, allowing the host
    application to use the spin/spout/input/output buffers directly.
    For applications using spin/spout, bufSize should be set to 0.
    If 'bufSize' is greater than zero, the buffer size (-b) in frames will be
    set to the integer multiple of ksmps that is nearest to the value
    specified.
    """
    cs.csoundSetHostImplementedAudioIO(c, state, bufSize)


cdef int csoundGetAudioDevList(cs.CSOUND *c, cs.CS_AUDIODEVICE *list, int isOutput):
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
    return cs.csoundGetAudioDevList(c, list, isOutput)


cdef csoundSetPlayopenCallback(cs.CSOUND *c, int (*playopen__)(cs.CSOUND *, const cs.csRtAudioParams *parm) noexcept):
    """Sets a function to be called by Csound for opening real-time audio playback."""
    cs.csoundSetPlayopenCallback(c, playopen__)

cdef csoundSetRtplayCallback(cs.CSOUND *c, void (*rtplay__)(cs.CSOUND *, const cs.MYFLT *outBuf, int nbytes) noexcept):
    """ Sets a function to be called by Csound for performing real-time audio playback."""
    cs.csoundSetRtplayCallback(c, rtplay__)

cdef csoundSetRecopenCallback(cs.CSOUND *c, int (*recopen_)(cs.CSOUND *, const cs.csRtAudioParams *parm) noexcept):
    """Sets a function to be called by Csound for opening real-time audio recording."""
    cs.csoundSetRecopenCallback(c, recopen_)

cdef csoundSetRtrecordCallback(cs.CSOUND *c, int (*rtrecord__)(cs.CSOUND *, cs.MYFLT *inBuf, int nbytes) noexcept):
    """Sets a function to be called by Csound for performing real-time audio recording."""
    cs.csoundSetRtrecordCallback(c, rtrecord__)

cdef csoundSetRtcloseCallback(cs.CSOUND *c, void (*rtclose__)(cs.CSOUND *) noexcept):
    """Sets a function to be called by Csound for closing real-time audio playback and recording."""
    cs.csoundSetRtcloseCallback(c, rtclose__)

cdef csoundSetAudioDeviceListCallback(cs.CSOUND *c, int (*audiodevlist__)(cs.CSOUND *, cs.CS_AUDIODEVICE *list, int isOutput) noexcept):
    """Sets a function that is called to obtain a list of audio devices.
    
    This should be set by rtaudio modules and should not be set by hosts.
    (See csoundGetAudioDevList())
    """
    cs.csoundSetAudioDeviceListCallback(c, audiodevlist__)


## ----------------------------------------------------------------------------
## Realtime MIDI I/O

cdef csoundSetMIDIModule(cs.CSOUND *c, const char *module):
    """Sets the current MIDI IO module"""
    cs.csoundSetMIDIModule(c, module)

cdef csoundSetHostImplementedMIDIIO(cs.CSOUND *c, int state):
    """call this function with state 1 if the host is implementing
    MIDI via the callbacks below.
    """
    cs.csoundSetHostImplementedMIDIIO(c, state)

cdef int csoundGetMIDIDevList(cs.CSOUND *c, cs.CS_MIDIDEVICE *list, int isOutput):
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
    return cs.csoundGetMIDIDevList(c, list, isOutput)

cdef csoundSetExternalMidiInOpenCallback(cs.CSOUND *c, int (*func)(cs.CSOUND *, void **userData, const char *devName) noexcept):
    """Sets callback for opening real time MIDI input."""
    cs.csoundSetExternalMidiInOpenCallback(c, func)

cdef csoundSetExternalMidiReadCallback(cs.CSOUND *c, int (*func)(cs.CSOUND *, void *userData, unsigned char *buf, int nBytes) noexcept):
    """Sets callback for reading from real time MIDI input."""
    cs.csoundSetExternalMidiReadCallback(c, func)

cdef csoundSetExternalMidiInCloseCallback(cs.CSOUND *c, int (*func)(cs.CSOUND *, void *userData) noexcept):
    """Sets callback for closing real time MIDI input."""
    cs.csoundSetExternalMidiInCloseCallback(c, func)

cdef csoundSetExternalMidiOutOpenCallback(cs.CSOUND *c, int (*func)(cs.CSOUND *, void **userData, const char *devName) noexcept):
    """Sets callback for opening real time MIDI output."""
    cs.csoundSetExternalMidiOutOpenCallback(c, func)

cdef csoundSetExternalMidiWriteCallback(cs.CSOUND *c, int (*func)(cs.CSOUND *, void *userData, const unsigned char *buf, int nBytes) noexcept):
    """Sets callback for writing to real time MIDI output."""
    cs.csoundSetExternalMidiWriteCallback(c, func)

cdef csoundSetExternalMidiOutCloseCallback(cs.CSOUND *c, int (*func)(cs.CSOUND *, void *userData) noexcept):
    """Sets callback for closing real time MIDI output."""
    cs.csoundSetExternalMidiOutCloseCallback(c, func)

cdef csoundSetExternalMidiErrorStringCallback(cs.CSOUND *c, const char *(*func)(int) noexcept):
    """Sets callback for converting MIDI error codes to strings."""
    cs.csoundSetExternalMidiErrorStringCallback(c, func)

cdef csoundSetMIDIDeviceListCallback(cs.CSOUND *c, int (*mididevlist__)(cs.CSOUND *, cs.CS_MIDIDEVICE *list, int isOutput) noexcept):
    """Sets a function that is called to obtain a list of MIDI devices.
    This should be set by IO plugins, and should not be used by hosts.
    (See csoundGetMIDIDevList())
    """
    cs.csoundSetMIDIDeviceListCallback(c, mididevlist__)


