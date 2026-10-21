# Cython declarations for the Csound 7 Host API (csound.h and friends).
#
# The Csound 7 API splits the former monolithic csound.h into several
# headers. csound.h is declared first so its #include precedes the modular
# headers (which rely on the CSOUND type and friends being visible).

from libc cimport stdio
from libc.stdint cimport (
    int16_t, int32_t, int64_t, uint32_t, uint64_t, uintptr_t, int_least64_t,
)


cdef extern from "stdarg.h":
    ctypedef struct va_list:
        pass


cdef extern from "sysdep.h":
    ctypedef int32_t spin_lock_t
    ctypedef int32_t int32


cdef extern from "csound.h":
    # Defined in csound_types.h; double under USE_DOUBLE (set in CMakeLists).
    ctypedef double cs_float
    ctypedef double cs_double

    ctypedef enum CSOUND_STATUS:
        CSOUND_SUCCESS = 0
        CSOUND_ERROR = -1
        CSOUND_INITIALIZATION = -2
        CSOUND_PERFORMANCE = -3
        CSOUND_MEMORY = -4
        CSOUND_SIGNAL = -5

    ctypedef enum DEBUG_STATUS:
        DEBUG_NONE = 0
        DEBUG_RUNTIME = 0x01
        DEBUG_COMPILER = 0x02
        DEBUG_SEMANTICS = 0x04
        DEBUG_EXPRESSIONS = 0x08
        DEBUG_PARSER = 0x10
        DEBUG_TREE = 0x20
        DEBUG_INSTR = 0x40
        DEBUG_OPCODES = 0x80
        DEBUG_PARCS = 0x100
        DEBUG_FULL = 0x7FFFFFFF

    # Compilation/performance aborted without an error (e.g. --help).
    cdef int CSOUND_EXITJMP_SUCCESS

    # Flags for csoundInitialize().
    cdef int CSOUNDINIT_NO_SIGNAL_HANDLER
    cdef int CSOUNDINIT_NO_ATEXIT

    # Types for keyboard callbacks (csoundRegisterKeyboardCallback()).
    cdef uint32_t CSOUND_CALLBACK_KBD_EVENT
    cdef uint32_t CSOUND_CALLBACK_KBD_TEXT

    # csoundEvent() event types
    cdef enum:
        CS_INSTR_EVENT = 0
        CS_TABLE_EVENT
        CS_END_EVENT
        CS_ADV_EVENT

    # Opaque/forward-declared types.
    ctypedef struct CSOUND
    ctypedef struct PVSDAT
    # Full definition in csound_type_system.h (included below).
    ctypedef struct CS_TYPE:
        char *varTypeName
    # Opaque in csound.h; the fields come from csoundCore.h (via csdl.h).
    ctypedef struct STRINGDAT:
        char *data
        size_t size
        int32_t refcount  # 0 owned, -1 alias of another variable's buffer
    ctypedef struct ARRAYDAT:
        int32_t dimensions
        int32_t *sizes
        int32_t arrayMemberSize
        cs_float *data
    ctypedef struct OENTRY
    ctypedef struct CS_VAR_MEM

    # csoundInitPvsChannel() window types and analysis formats.
    enum PVS_WINTYPE:
        PVS_WIN_HAMMING
        PVS_WIN_HANN
        PVS_WIN_KAISER
        PVS_WIN_CUSTOM
        PVS_WIN_BLACKMAN
        PVS_WIN_BLACKMAN_EXACT
        PVS_WIN_NUTTALLC3
        PVS_WIN_BHARRIS_3
        PVS_WIN_BHARRIS_MIN
        PVS_WIN_RECT

    enum PVS_ANALFORMAT:
        PVS_AMP_FREQ
        PVS_AMP_PHASE
        PVS_COMPLEX
        PVS_TRACKS

    # Read-only options/parameters structure returned by csoundGetParams().
    # Only the members exposed by the Python wrapper are declared here; the
    # full struct is defined in csound.h.
    ctypedef struct OPARMS:
        int32_t odebug
        int32_t sfread
        int32_t sfwrite
        int32_t filetyp
        int32_t inbufsamps
        int32_t outbufsamps
        int32_t informat
        int32_t outformat
        int32_t displays
        int32_t graphsoff
        int32_t postscript
        int32_t msglevel
        int32_t Beatmode
        int32_t oMaxLag
        int32_t Midiin
        int32_t FMidiin
        int32_t ringbell
        int32_t heartbeat
        cs_double cmdTempo
        cs_float sr_override
        cs_float kr_override
        int32_t nchnls_override
        int32_t nchnls_i_override
        char *infilename
        char *outfilename
        int32_t midiKey
        int32_t midiVelocity
        int32_t numThreads
        int32_t syntaxCheckOnly
        int32_t useCsdLineCounts
        int32_t sampleAccurate
        int32_t realtime
        cs_float e0dbfs_override
        int32_t daemon
        int32_t ksmps_override
        int32_t recursion_depth

    ctypedef struct CS_AUDIODEVICE:
        char device_name[128]
        char device_id[128]
        char rt_module[128]
        int32_t max_nchnls
        int32_t isOutput

    ctypedef struct CS_MIDIDEVICE:
        char device_name[128]
        char interface_name[128]
        char device_id[128]
        char midi_module[128]
        int32_t isOutput

    # Bus interface constants (csoundGetChannelPtr() etc.).
    ctypedef enum controlChannelType:
        CSOUND_CONTROL_CHANNEL = 1
        CSOUND_AUDIO_CHANNEL = 2
        CSOUND_STRING_CHANNEL = 3
        CSOUND_PVS_CHANNEL = 4
        CSOUND_VAR_CHANNEL = 5
        CSOUND_ARRAY_CHANNEL = 6
        CSOUND_CHANNEL_TYPE_MASK = 15
        CSOUND_INPUT_CHANNEL = 16
        CSOUND_OUTPUT_CHANNEL = 32

    ctypedef enum controlChannelBehavior:
        CSOUND_CONTROL_CHANNEL_NO_HINTS = 0
        CSOUND_CONTROL_CHANNEL_INT = 1
        CSOUND_CONTROL_CHANNEL_LIN = 2
        CSOUND_CONTROL_CHANNEL_EXP = 3

    ctypedef struct controlChannelHints_t:
        controlChannelBehavior behav
        cs_float dflt
        cs_float min
        cs_float max
        int32_t x
        int32_t y
        int32_t width
        int32_t height
        char *attributes

    ctypedef struct controlChannelInfo_t:
        char *name
        int32_t type
        controlChannelHints_t hints

    ctypedef void (*channelCallback_t)(CSOUND *csound,
                                       const char *channelName,
                                       void *channelValuePtr,
                                       const void *channelType) noexcept nogil

    # ---- Instantiation ----
    int32_t csoundInitialize(int32_t flags) nogil
    CSOUND *csoundCreate(void *hostData, const char *opcodedir) nogil
    void csoundDestroy(CSOUND *) nogil

    # ---- Attributes ----
    int32_t csoundGetVersion() nogil
    cs_float csoundGetSr(CSOUND *) nogil
    cs_float csoundGetKr(CSOUND *) nogil
    uint32_t csoundGetKsmps(CSOUND *) nogil
    uint64_t csoundGetKcounter(CSOUND *) nogil
    uint32_t csoundGetChannels(CSOUND *, int32_t isInput) nogil
    cs_float csoundGet0dBFS(CSOUND *) nogil
    cs_float csoundGetA4(CSOUND *) nogil
    int64_t csoundGetCurrentTimeSamples(CSOUND *) nogil
    int32_t csoundGetSizeOfCsFloat() nogil
    int32_t csoundGetSizeOfCsDouble() nogil
    void *csoundGetHostData(CSOUND *) nogil
    void csoundSetHostData(CSOUND *, void *hostData) nogil
    int32_t csoundErrCnt(CSOUND *) nogil
    const char *csoundGetEnv(CSOUND *, const char *name) nogil
    int32_t csoundSetGlobalEnv(const char *name, const char *value) nogil
    int32_t csoundSetOption(CSOUND *, const char *option) nogil
    int32_t csoundSetCommandLineArgs(CSOUND *, int32_t argc, const char **argv) nogil
    int32_t csoundGetCommandLineArgCount(CSOUND *) nogil
    const char *csoundGetCommandLineArg(CSOUND *, int32_t index) nogil
    const OPARMS *csoundGetParams(CSOUND *) nogil
    int32_t csoundGetDebug(CSOUND *) nogil
    void csoundSetDebug(CSOUND *, int32_t debug) nogil
    cs_float csoundSystemSr(CSOUND *, cs_float val) nogil
    int32_t csoundGetModule(CSOUND *, int32_t number, char **name, char **type) nogil
    int32_t csoundGetAudioDevList(CSOUND *, CS_AUDIODEVICE *lst, int32_t isOutput) nogil
    int32_t csoundGetMIDIDevList(CSOUND *, CS_MIDIDEVICE *lst, int32_t isOutput) nogil
    int32_t csoundGetMessageLevel(CSOUND *) nogil
    void csoundSetMessageLevel(CSOUND *, int32_t messageLevel) nogil

    # ---- Compilation and performance ----
    int32_t csoundCompile(CSOUND *, int32_t argc, const char **argv) nogil
    int32_t csoundCompileOrc(CSOUND *, const char *str, int32_t is_async) nogil
    cs_float csoundEvalCode(CSOUND *, const char *str) nogil
    int32_t csoundCompileCSD(CSOUND *, const char *csd, int32_t mode, int32_t is_async) nogil
    int32_t csoundStart(CSOUND *) nogil
    int32_t csoundPerformKsmps(CSOUND *) nogil
    int32_t csoundRunUtility(CSOUND *, const char *name, int32_t argc, char **argv) nogil
    void csoundReset(CSOUND *) nogil

    # ---- Audio I/O ----
    cs_float *csoundGetSpin(CSOUND *) nogil
    const cs_float *csoundGetSpout(CSOUND *) nogil

    # ---- Messages ----
    void csoundMessage(CSOUND *, const char *format, ...) nogil
    void csoundMessageS(CSOUND *, int32_t attr, const char *format, ...) nogil
    void csoundMessageV(CSOUND *, int32_t attr, const char *format, va_list args) nogil
    void csoundSetDefaultMessageCallback(
        void (*csoundMessageCallback_)(CSOUND *, int32_t attr,
                                       const char *format, va_list valist) noexcept nogil) nogil
    void csoundSetMessageCallback(
        CSOUND *,
        void (*csoundMessageCallback_)(CSOUND *, int32_t attr,
                                       const char *format, va_list valist) noexcept nogil) nogil
    void csoundSetMessageStringCallback(
        CSOUND *csound,
        void (*csoundMessageStrCallback)(CSOUND *csound, int32_t attr,
                                         const char *str) noexcept nogil) nogil
    void csoundCreateMessageBuffer(CSOUND *, int32_t toStdOut) nogil
    const char *csoundGetFirstMessage(CSOUND *) nogil
    int32_t csoundGetFirstMessageAttr(CSOUND *) nogil
    void csoundPopFirstMessage(CSOUND *) nogil
    int32_t csoundGetMessageCnt(CSOUND *) nogil
    void csoundDestroyMessageBuffer(CSOUND *) nogil

    # ---- Channels, control and events ----
    int32_t csoundGetChannelPtr(CSOUND *, void **p, const char *name, int32_t type) nogil
    const char *csoundGetChannelVarTypeName(CSOUND *, const char *name) nogil
    int32_t csoundListChannels(CSOUND *, controlChannelInfo_t **lst) nogil
    void csoundDeleteChannelList(CSOUND *, controlChannelInfo_t *lst) nogil
    int32_t csoundSetControlChannelHints(CSOUND *, const char *name, controlChannelHints_t hints) nogil
    int32_t csoundGetControlChannelHints(CSOUND *, const char *name, controlChannelHints_t *hints) nogil
    void csoundDeleteControlChannelHints(CSOUND *, controlChannelHints_t *hints) nogil
    int32_t csoundSetChannel(CSOUND *, const char *name, const CS_VAR_MEM *var) nogil
    const CS_VAR_MEM *csoundGetChannel(CSOUND *, const char *name) nogil
    void csoundLockChannel(CSOUND *, const char *channel) nogil
    void csoundUnlockChannel(CSOUND *, const char *channel) nogil
    cs_float csoundGetControlChannel(CSOUND *, const char *name, int32_t *err) nogil
    void csoundSetControlChannel(CSOUND *, const char *name, cs_float val) nogil
    void csoundGetAudioChannel(CSOUND *, const char *name, cs_float *samples) nogil
    void csoundSetAudioChannel(CSOUND *, const char *name, const cs_float *samples) nogil
    void csoundGetStringChannel(CSOUND *, const char *name, char *string) nogil
    void csoundSetStringChannel(CSOUND *, const char *name, const char *string) nogil
    const CS_TYPE *csoundGetChannelVarType(CSOUND *, const char *name) nogil
    int32_t csoundGetChannelDatasize(CSOUND *, const char *name) nogil
    void csoundSetInputChannelCallback(CSOUND *, channelCallback_t inputChannelCalback) nogil
    void csoundSetOutputChannelCallback(CSOUND *, channelCallback_t outputChannelCalback) nogil

    # ---- Array, string and fsig channel data ----
    ARRAYDAT *csoundInitArrayChannel(CSOUND *, const char *name, const char *type,
                                     int32_t dimensions, const int32_t *sizes) nogil
    const char *csoundArrayDataType(const ARRAYDAT *adat) nogil
    int32_t csoundArrayDataDimensions(const ARRAYDAT *adat) nogil
    const int32_t *csoundArrayDataSizes(const ARRAYDAT *adat) nogil
    int32_t csoundSetArrayData(ARRAYDAT *adat, const void *data) nogil
    const void *csoundGetArrayData(const ARRAYDAT *adat) nogil
    const char *csoundGetStringData(CSOUND *, STRINGDAT *sdata) nogil
    void csoundSetStringData(CSOUND *, STRINGDAT *sdata, const char *str) nogil
    PVSDAT *csoundInitPvsChannel(CSOUND *, const char *name, int32_t size,
                                 int32_t overlap, int32_t winsize,
                                 int32_t wintype, int32_t format) nogil
    int32_t csoundPvsDataFFTSize(const PVSDAT *pvsdat) nogil
    int32_t csoundPvsDataOverlap(const PVSDAT *pvsdat) nogil
    int32_t csoundPvsDataWindowSize(const PVSDAT *pvsdat) nogil
    int32_t csoundPvsDataFormat(const PVSDAT *pvsdat) nogil
    uint32_t csoundPvsDataFramecount(const PVSDAT *pvsdat) nogil
    const float *csoundGetPvsData(const PVSDAT *pvsdat) nogil
    void csoundSetPvsData(PVSDAT *pvsdat, const float *frame) nogil
    int32_t csoundSetPvsChannel(CSOUND *, const char *name, const PVSDAT *pvsdat) nogil
    int32_t csoundGetPvsChannel(CSOUND *, const char *name, PVSDAT *pvsdat) nogil

    void csoundEvent(CSOUND *, int32_t type, const cs_float *params, int32_t nparams, int32_t is_async) nogil
    void csoundEventString(CSOUND *, const char *message, int32_t is_async) nogil
    int32 csoundGetInstrNumber(CSOUND *, const char *name) nogil
    void csoundKeyPress(CSOUND *, char c) nogil
    int32_t csoundReadlinePushText(CSOUND *, const char *text) nogil
    ctypedef void (*readlineCallback_t)(CSOUND *csound, void *userData,
                                        uint32_t requestId,
                                        const char *prompt) noexcept nogil
    void csoundSetReadlineCallback(CSOUND *, readlineCallback_t callback,
                                   void *userData) nogil
    int32_t csoundReadlineSubmit(CSOUND *, uint32_t requestId, const char *text) nogil
    int32_t csoundRegisterKeyboardCallback(
        CSOUND *,
        int32_t (*func)(void *userData, void *p, uint32_t type) noexcept nogil,
        void *userData, uint32_t type) nogil
    void csoundRemoveKeyboardCallback(
        CSOUND *,
        int32_t (*func)(void *, void *, uint32_t) noexcept nogil) nogil

    # ---- Tables ----
    int32_t csoundTableLength(CSOUND *, int32_t table) nogil
    int32_t csoundGetTable(CSOUND *, cs_float **tablePtr, int32_t tableNum) nogil
    int32_t csoundGetTableArgs(CSOUND *, cs_float **argsPtr, int32_t tableNum) nogil
    void csoundTableCopyIn(CSOUND *, int32_t table, const cs_float *ptable, int32_t is_async) nogil
    void csoundTableCopyOut(CSOUND *, int32_t table, cs_float *ptable, int32_t is_async) nogil

    # ---- Score handling ----
    cs_double csoundGetScoreTime(CSOUND *) nogil
    int32_t csoundIsScorePending(CSOUND *) nogil
    void csoundSetScorePending(CSOUND *, int32_t pending) nogil
    cs_float csoundGetScoreOffsetSeconds(CSOUND *) nogil
    void csoundSetScoreOffsetSeconds(CSOUND *, cs_float time) nogil
    void csoundRewindScore(CSOUND *) nogil
    int32_t csoundScoreSort(CSOUND *, stdio.FILE *inFile, stdio.FILE *outFile) nogil
    int32_t csoundScoreExtract(CSOUND *, stdio.FILE *inFile, stdio.FILE *outFile, stdio.FILE *extractFile) nogil
    void csoundSleep(size_t milliseconds) nogil

    # ---- Opcodes ----
    int32_t csoundLoadPlugins(CSOUND *, const char *dir) nogil
    int32_t csoundAppendOpcode(CSOUND *, const char *opname, size_t dsblksiz,
                               int32_t flags, const char *outypes,
                               const char *intypes,
                               int32_t (*init)(CSOUND *, void *) noexcept nogil,
                               int32_t (*perf)(CSOUND *, void *) noexcept nogil,
                               int32_t (*deinit)(CSOUND *, void *) noexcept nogil) nogil
    int32_t csoundAppendOpcodes(CSOUND *, const OENTRY *oplist, int32_t len) nogil


cdef extern from "csound_type_system.h":
    pass


cdef extern from "csound_compiler.h":
    ctypedef struct ORCTOKEN:
        int32_t type
        char *lexeme
        int32_t value
        cs_double fvalue
        char *optype
        uint32_t first_column
        uint32_t last_column
        ORCTOKEN *next

    ctypedef struct TREE:
        int32_t type
        ORCTOKEN *value
        int32_t rate
        int32_t len
        int32_t line
        uint64_t locn
        TREE *left
        TREE *right
        TREE *next
        void *markup

    TREE *csoundParseOrc(CSOUND *, const char *str) nogil
    int32_t csoundCompileTree(CSOUND *, TREE *root, int32_t is_async) nogil
    void csoundDeleteTree(CSOUND *, TREE *tree) nogil


cdef extern from "csound_misc.h":
    void *csoundQueryGlobalVariable(CSOUND *, const char *name) nogil
    const char *csoundGetOutputName(CSOUND *) nogil
    const char *csoundGetInputName(CSOUND *) nogil


cdef extern from "csound_server.h":
    int32_t csoundUDPServerStart(CSOUND *, uint32_t port) nogil
    int32_t csoundUDPServerStatus(CSOUND *) nogil
    int32_t csoundUDPServerClose(CSOUND *) nogil
    int32_t csoundUDPConsole(CSOUND *, const char *addr, int32_t port, int32_t mirror) nogil
    void csoundStopUDPConsole(CSOUND *) nogil


cdef extern from "csound_rtaudio.h":
    void csoundSetRTAudioModule(CSOUND *, const char *module) nogil
    void csoundSetHostAudioIO(CSOUND *) nogil
    int32_t csoundPerformOutputFade(CSOUND *, uint32_t frames) nogil


# Plugin header: full STRINGDAT/ARRAYDAT/OPDS definitions for host code that
# indexes array channels or registers C opcodes.
cdef extern from "csdl.h":
    ctypedef struct OPDS:
        pass


cdef extern from "csound_circular_buffer.h":
    void *csoundCreateCircularBuffer(CSOUND *, int32_t numelem, int32_t elemsize) nogil
    int32_t csoundReadCircularBuffer(CSOUND *, void *cb, void *out, int32_t items) nogil
    int32_t csoundPeekCircularBuffer(CSOUND *, void *cb, void *out, int32_t items) nogil
    int32_t csoundWriteCircularBuffer(CSOUND *, void *cb, const void *inp,
                                      int32_t items) nogil
    void csoundFlushCircularBuffer(CSOUND *, void *cb) nogil
    int32_t csoundCheckCircularBuffer(CSOUND *, void *cb, int32_t flag) nogil
    int32_t csoundGetSizeCircularBuffer(CSOUND *, void *cb) nogil
    int32_t csoundGetElementSizeCircularBuffer(CSOUND *, void *cb) nogil
    void csoundDestroyCircularBuffer(CSOUND *, void *cb) nogil


cdef extern from "cwindow.h":
    cdef enum:
        CAPSIZE
    ctypedef struct WINDAT:
        uintptr_t windid
        cs_float *fdata
        int32 npts
        char caption[60]
        int16_t waitflg
        int16_t polarity
        cs_float max
        cs_float min
        cs_float absmax
        cs_float oabsmax
        int32_t danflag
        int32_t absflag


# Graph display callback types; csound_graph_display.h spells them inline.
ctypedef void (*makeGraphFunc_t)(CSOUND *, WINDAT *windat, const char *name) noexcept nogil
ctypedef void (*drawGraphFunc_t)(CSOUND *, WINDAT *windat) noexcept nogil
ctypedef int32_t (*exitGraphFunc_t)(CSOUND *) noexcept nogil


cdef extern from "csound_graph_display.h":
    int32_t csoundSetIsGraphable(CSOUND *, int32_t isGraphable) nogil
    void csoundSetMakeGraphCallback(CSOUND *, makeGraphFunc_t func) nogil
    void csoundSetDrawGraphCallback(CSOUND *, drawGraphFunc_t func) nogil
    void csoundSetKillGraphCallback(CSOUND *, drawGraphFunc_t func) nogil
    void csoundSetExitGraphCallback(CSOUND *, exitGraphFunc_t func) nogil


# File callback types; csound_files.h spells them inline.
ctypedef void *(*openSoundFileFunc_t)(CSOUND *, const char *path, int32_t mode,
                                      void *sfinfo) noexcept nogil
ctypedef stdio.FILE *(*openFileFunc_t)(CSOUND *, const char *path,
                                       const char *mode) noexcept nogil
ctypedef void (*fileOpenFunc_t)(CSOUND *, const char *path, int32_t type,
                                int32_t writing, int32_t temporary) noexcept nogil


cdef extern from "csound_files.h":
    ctypedef struct SNDFILE_CALLBACKS:
        pass
    void csoundSetOpenSoundFileCallback(CSOUND *, openSoundFileFunc_t func) nogil
    void csoundSetOpenFileCallback(CSOUND *, openFileFunc_t func) nogil
    void csoundSetFileOpenCallback(CSOUND *, fileOpenFunc_t func) nogil
    void csoundSetSndfileCallbacks(CSOUND *, SNDFILE_CALLBACKS *p) nogil


# External MIDI callback types; csound_rtmidi.h spells them inline.
ctypedef int32_t (*midiOpenFunc_t)(CSOUND *, void **userData,
                                   const char *devName) noexcept nogil
ctypedef int32_t (*midiReadFunc_t)(CSOUND *, void *userData,
                                   unsigned char *buf, int32_t nBytes) noexcept nogil
ctypedef int32_t (*midiWriteFunc_t)(CSOUND *, void *userData,
                                    const unsigned char *buf,
                                    int32_t nBytes) noexcept nogil
ctypedef int32_t (*midiCloseFunc_t)(CSOUND *, void *userData) noexcept nogil
ctypedef const char *(*midiErrorStringFunc_t)(int32_t) noexcept nogil
ctypedef int32_t (*midiDevListFunc_t)(CSOUND *, CS_MIDIDEVICE *list,
                                      int32_t isOutput) noexcept nogil


cdef extern from "csound_rtmidi.h":
    void csoundSetMIDIModule(CSOUND *, const char *module) nogil
    void csoundSetHostMIDIIO(CSOUND *) nogil
    void csoundSetExternalMidiInOpenCallback(CSOUND *, midiOpenFunc_t func) nogil
    void csoundSetExternalMidiReadCallback(CSOUND *, midiReadFunc_t func) nogil
    void csoundSetExternalMidiInCloseCallback(CSOUND *, midiCloseFunc_t func) nogil
    void csoundSetExternalMidiOutOpenCallback(CSOUND *, midiOpenFunc_t func) nogil
    void csoundSetExternalMidiWriteCallback(CSOUND *, midiWriteFunc_t func) nogil
    void csoundSetExternalMidiOutCloseCallback(CSOUND *, midiCloseFunc_t func) nogil
    void csoundSetExternalMidiErrorStringCallback(CSOUND *,
                                                  midiErrorStringFunc_t func) nogil
    void csoundSetMIDIDeviceListCallback(CSOUND *, midiDevListFunc_t func) nogil


cdef extern from "ugen.h":
    ctypedef struct UGEN:
        pass
    ctypedef struct UGEN_FACTORY:
        pass
    ctypedef struct UGEN_CONTEXT:
        pass
    ctypedef struct UGEN_GRAPH:
        pass
    ctypedef struct UGEN_VAR:
        pass

    ctypedef enum UGEN_ARG_TYPE:
        UGEN_ARG_TYPE_I
        UGEN_ARG_TYPE_K
        UGEN_ARG_TYPE_A
        UGEN_ARG_TYPE_S
        UGEN_ARG_TYPE_F
        UGEN_ARG_TYPE_UNKNOWN

    ctypedef struct UGEN_OPCODE_INFO:
        const char *opname
        const char *outypes
        const char *intypes
        size_t dsblksiz
        int32_t flags

    UGEN_FACTORY *csoundUgenFactoryNew(CSOUND *) nogil
    bint csoundUgenFactoryDelete(UGEN_FACTORY *factory) nogil
    UGEN_CONTEXT *csoundUgenContextNew(UGEN_FACTORY *factory) nogil
    bint csoundUgenContextDelete(UGEN_CONTEXT *context) nogil
    bint csoundUgenSetContext(UGEN *ugen, UGEN_CONTEXT *context) nogil
    UGEN *csoundUgenNew(UGEN_FACTORY *factory, char *opName,
                        char *outargTypes, char *inargTypes) nogil
    bint csoundUgenDelete(UGEN *ugen) nogil
    UGEN_VAR *csoundUgenGetOutVar(UGEN *ugen, int32_t index) nogil
    UGEN_VAR *csoundUgenGetInVar(UGEN *ugen, int32_t index) nogil
    bint csoundUgenSetInputVar(UGEN *ugen, int32_t inIdx, UGEN_VAR *var) nogil
    UGEN_VAR *csoundUgenVarNew(UGEN_FACTORY *factory, UGEN_ARG_TYPE type) nogil
    void csoundUgenVarDelete(UGEN_VAR *var) nogil
    UGEN_ARG_TYPE csoundUgenVarGetType(UGEN_VAR *var) nogil
    size_t csoundUgenVarGetSize(UGEN_VAR *var) nogil
    void csoundUgenVarSetValue(UGEN_VAR *var, cs_float value) nogil
    cs_float csoundUgenVarGetValue(UGEN_VAR *var) nogil
    void *csoundUgenVarGetData(UGEN_VAR *var) nogil
    bint csoundUgenVarSetString(UGEN_VAR *var, const char *str) nogil
    const char *csoundUgenVarGetString(UGEN_VAR *var) nogil
    void csoundUgenSetValue(UGEN *ugen, int32_t index, cs_float value) nogil
    cs_float csoundUgenGetValue(UGEN *ugen, int32_t index) nogil
    bint csoundUgenSetString(UGEN *ugen, int32_t index, const char *str) nogil
    const char *csoundUgenGetString(UGEN *ugen, int32_t index) nogil
    int32_t csoundUgenGetInCount(UGEN *ugen) nogil
    int32_t csoundUgenGetOutCount(UGEN *ugen) nogil
    UGEN_ARG_TYPE csoundUgenGetInType(UGEN *ugen, int32_t index) nogil
    UGEN_ARG_TYPE csoundUgenGetOutType(UGEN *ugen, int32_t index) nogil
    int32_t csoundUgenInit(UGEN *ugen) nogil
    int32_t csoundUgenPerform(UGEN *ugen) nogil
    int32_t csoundUgenListOpcodes(UGEN_FACTORY *factory,
                                  UGEN_OPCODE_INFO **list, int32_t *count) nogil
    void csoundUgenFreeOpcodeList(UGEN_FACTORY *factory, UGEN_OPCODE_INFO *list) nogil
    bint csoundUgenFindOpcode(UGEN_FACTORY *factory, const char *opname,
                              const char *outargTypes, const char *inargTypes) nogil
    UGEN_GRAPH *csoundUgenGraphNew(UGEN_FACTORY *factory) nogil
    int32_t csoundUgenGraphAdd(UGEN_GRAPH *graph, UGEN *ugen) nogil
    int32_t csoundUgenGraphInit(UGEN_GRAPH *graph) nogil
    int32_t csoundUgenGraphPerform(UGEN_GRAPH *graph) nogil
    bint csoundUgenGraphDelete(UGEN_GRAPH *graph) nogil
    bint csoundUgenGraphDeleteAll(UGEN_GRAPH *graph) nogil


cdef extern from "csPerfThread.h":
    ctypedef void CS_PERF_THREAD

    CS_PERF_THREAD *csoundCreatePerformanceThread(CSOUND *) nogil
    void csoundDestroyPerformanceThread(CS_PERF_THREAD *pt) nogil
    int32_t csoundPerformanceThreadIsRunning(CS_PERF_THREAD *pt) nogil
    void csoundPerformanceThreadSetProcessCB(
        CS_PERF_THREAD *pt, void (*callback)(void *) noexcept nogil,
        void *cbData) nogil
    int32_t csoundPerformanceThreadGetStatus(CS_PERF_THREAD *pt) nogil
    void csoundPerformanceThreadPlay(CS_PERF_THREAD *pt) nogil
    void csoundPerformanceThreadPause(CS_PERF_THREAD *pt) nogil
    void csoundPerformanceThreadTogglePause(CS_PERF_THREAD *pt) nogil
    void csoundPerformanceThreadStop(CS_PERF_THREAD *pt) nogil
    void csoundPerformanceThreadRecord(CS_PERF_THREAD *pt, const char *filename,
                                       int32_t samplebits, int32_t numbufs) nogil
    void csoundPerformanceThreadStopRecord(CS_PERF_THREAD *pt) nogil
    void csoundPerformanceThreadScoreEvent(CS_PERF_THREAD *pt, int32_t absp2mode,
                                           char opcod, int32_t pcnt,
                                           cs_float *p) nogil
    void csoundPerformanceThreadInputMessage(CS_PERF_THREAD *pt, const char *s) nogil
    void csoundPerformanceThreadSetScoreOffsetSeconds(CS_PERF_THREAD *pt,
                                                      cs_double timeVal) nogil
    void csoundPerformanceThreadCompileOrc(CS_PERF_THREAD *pt, const char *code) nogil
    void csoundPerformanceThreadEvalCodeWithData(
        CS_PERF_THREAD *pt, const char *code,
        void (*returncb)(cs_float, void *userdata) noexcept nogil,
        void *userdata) nogil
    void csoundPerformanceThreadRequestCallback(
        CS_PERF_THREAD *pt, void (*func)(void *) noexcept nogil) nogil
    int32_t csoundPerformanceThreadJoin(CS_PERF_THREAD *pt) nogil
    void csoundPerformanceThreadFlushMessageQueue(CS_PERF_THREAD *pt) nogil
