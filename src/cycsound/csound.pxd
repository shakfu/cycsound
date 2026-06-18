# Cython declarations for the Csound 7 Host API (csound.h and friends).
#
# The Csound 7 API splits the former monolithic csound.h into several
# headers. csound.h is declared first so its #include precedes the modular
# headers (which rely on the CSOUND type and friends being visible).

from libc cimport stdio
from libc.stdint cimport (
    int32_t, int64_t, uint32_t, uint64_t, uintptr_t, int_least64_t,
)


cdef extern from "stdarg.h":
    ctypedef struct va_list:
        pass


cdef extern from "sysdep.h":
    ctypedef int32_t spin_lock_t
    ctypedef int32_t int32


cdef extern from "csound.h":
    """
    #ifndef USE_DOUBLE
    #define MYFLT float
    #else
    #define MYFLT double
    #endif
    """

    ctypedef float MYFLT

    cdef enum CSOUND_STATUS:
        CSOUND_SUCCESS = 0
        CSOUND_ERROR = -1
        CSOUND_INITIALIZATION = -2
        CSOUND_PERFORMANCE = -3
        CSOUND_MEMORY = -4
        CSOUND_SIGNAL = -5

    # csoundEvent() event types
    cdef enum:
        CS_INSTR_EVENT = 0
        CS_TABLE_EVENT
        CS_END_EVENT
        CS_ADV_EVENT

    # Opaque/forward-declared types.
    ctypedef struct CSOUND
    ctypedef struct STRINGDAT
    ctypedef struct ARRAYDAT
    ctypedef struct PVSDAT
    ctypedef struct CS_TYPE
    ctypedef struct OENTRY

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
        double cmdTempo
        MYFLT sr_override
        MYFLT kr_override
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
        MYFLT e0dbfs_override
        int32_t daemon
        int32_t ksmps_override

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
    cdef enum controlChannelType:
        CSOUND_CONTROL_CHANNEL = 1
        CSOUND_AUDIO_CHANNEL = 2
        CSOUND_STRING_CHANNEL = 3
        CSOUND_PVS_CHANNEL = 4
        CSOUND_VAR_CHANNEL = 5
        CSOUND_ARRAY_CHANNEL = 6
        CSOUND_CHANNEL_TYPE_MASK = 15
        CSOUND_INPUT_CHANNEL = 16
        CSOUND_OUTPUT_CHANNEL = 32

    cdef enum controlChannelBehavior:
        CSOUND_CONTROL_CHANNEL_NO_HINTS = 0
        CSOUND_CONTROL_CHANNEL_INT = 1
        CSOUND_CONTROL_CHANNEL_LIN = 2
        CSOUND_CONTROL_CHANNEL_EXP = 3

    ctypedef struct controlChannelHints_t:
        controlChannelBehavior behav
        MYFLT dflt
        MYFLT min
        MYFLT max
        int32_t x
        int32_t y
        int32_t width
        int32_t height
        char *attributes

    ctypedef struct controlChannelInfo_t:
        char *name
        int32_t type
        controlChannelHints_t hints

    # ---- Instantiation ----
    int32_t csoundInitialize(int32_t flags) nogil
    CSOUND *csoundCreate(void *hostData, const char *opcodedir) nogil
    void csoundDestroy(CSOUND *) nogil

    # ---- Attributes ----
    int32_t csoundGetVersion() nogil
    MYFLT csoundGetSr(CSOUND *) nogil
    MYFLT csoundGetKr(CSOUND *) nogil
    uint32_t csoundGetKsmps(CSOUND *) nogil
    uint64_t csoundGetKcounter(CSOUND *) nogil
    uint32_t csoundGetChannels(CSOUND *, int32_t isInput) nogil
    MYFLT csoundGet0dBFS(CSOUND *) nogil
    MYFLT csoundGetA4(CSOUND *) nogil
    int64_t csoundGetCurrentTimeSamples(CSOUND *) nogil
    int32_t csoundGetSizeOfMYFLT() nogil
    void *csoundGetHostData(CSOUND *) nogil
    void csoundSetHostData(CSOUND *, void *hostData) nogil
    int32_t csoundErrCnt(CSOUND *) nogil
    const char *csoundGetEnv(CSOUND *, const char *name) nogil
    int32_t csoundSetGlobalEnv(const char *name, const char *value) nogil
    int32_t csoundSetOption(CSOUND *, const char *option) nogil
    const OPARMS *csoundGetParams(CSOUND *) nogil
    int32_t csoundGetDebug(CSOUND *) nogil
    void csoundSetDebug(CSOUND *, int32_t debug) nogil
    MYFLT csoundSystemSr(CSOUND *, MYFLT val) nogil
    int32_t csoundGetModule(CSOUND *, int32_t number, char **name, char **type) nogil
    int32_t csoundGetAudioDevList(CSOUND *, CS_AUDIODEVICE *lst, int32_t isOutput) nogil
    int32_t csoundGetMIDIDevList(CSOUND *, CS_MIDIDEVICE *lst, int32_t isOutput) nogil
    int32_t csoundGetMessageLevel(CSOUND *) nogil
    void csoundSetMessageLevel(CSOUND *, int32_t messageLevel) nogil

    # ---- Compilation and performance ----
    int32_t csoundCompile(CSOUND *, int32_t argc, const char **argv) nogil
    int32_t csoundCompileOrc(CSOUND *, const char *str, int32_t is_async) nogil
    MYFLT csoundEvalCode(CSOUND *, const char *str) nogil
    int32_t csoundCompileCSD(CSOUND *, const char *csd, int32_t mode, int32_t is_async) nogil
    int32_t csoundStart(CSOUND *) nogil
    int32_t csoundPerformKsmps(CSOUND *) nogil
    int32_t csoundRunUtility(CSOUND *, const char *name, int32_t argc, char **argv) nogil
    void csoundReset(CSOUND *) nogil

    # ---- Audio I/O ----
    MYFLT *csoundGetSpin(CSOUND *) nogil
    const MYFLT *csoundGetSpout(CSOUND *) nogil

    # ---- Messages ----
    void csoundMessage(CSOUND *, const char *format, ...) nogil
    void csoundMessageS(CSOUND *, int32_t attr, const char *format, ...) nogil
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
    void csoundLockChannel(CSOUND *, const char *channel) nogil
    void csoundUnlockChannel(CSOUND *, const char *channel) nogil
    MYFLT csoundGetControlChannel(CSOUND *, const char *name, int32_t *err) nogil
    void csoundSetControlChannel(CSOUND *, const char *name, MYFLT val) nogil
    void csoundGetAudioChannel(CSOUND *, const char *name, MYFLT *samples) nogil
    void csoundSetAudioChannel(CSOUND *, const char *name, const MYFLT *samples) nogil
    void csoundGetStringChannel(CSOUND *, const char *name, char *string) nogil
    void csoundSetStringChannel(CSOUND *, const char *name, const char *string) nogil
    int32_t csoundGetChannelDatasize(CSOUND *, const char *name) nogil

    void csoundEvent(CSOUND *, int32_t type, const MYFLT *params, int32_t nparams, int32_t is_async) nogil
    void csoundEventString(CSOUND *, const char *message, int32_t is_async) nogil
    int32 csoundGetInstrNumber(CSOUND *, const char *name) nogil
    void csoundKeyPress(CSOUND *, char c) nogil

    # ---- Tables ----
    int32_t csoundTableLength(CSOUND *, int32_t table) nogil
    int32_t csoundGetTable(CSOUND *, MYFLT **tablePtr, int32_t tableNum) nogil
    int32_t csoundGetTableArgs(CSOUND *, MYFLT **argsPtr, int32_t tableNum) nogil
    void csoundTableCopyIn(CSOUND *, int32_t table, const MYFLT *ptable, int32_t is_async) nogil
    void csoundTableCopyOut(CSOUND *, int32_t table, MYFLT *ptable, int32_t is_async) nogil

    # ---- Score handling ----
    double csoundGetScoreTime(CSOUND *) nogil
    int32_t csoundIsScorePending(CSOUND *) nogil
    void csoundSetScorePending(CSOUND *, int32_t pending) nogil
    MYFLT csoundGetScoreOffsetSeconds(CSOUND *) nogil
    void csoundSetScoreOffsetSeconds(CSOUND *, MYFLT time) nogil
    void csoundRewindScore(CSOUND *) nogil
    int32_t csoundScoreSort(CSOUND *, stdio.FILE *inFile, stdio.FILE *outFile) nogil
    int32_t csoundScoreExtract(CSOUND *, stdio.FILE *inFile, stdio.FILE *outFile, stdio.FILE *extractFile) nogil
    void csoundSleep(size_t milliseconds) nogil

    # ---- Opcodes ----
    int32_t csoundLoadPlugins(CSOUND *, const char *dir) nogil


cdef extern from "csound_compiler.h":
    ctypedef struct ORCTOKEN:
        int32_t type
        char *lexeme
        int32_t value
        double fvalue
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


cdef extern from "csound_rtmidi.h":
    void csoundSetMIDIModule(CSOUND *, const char *module) nogil
    void csoundSetHostMIDIIO(CSOUND *) nogil
