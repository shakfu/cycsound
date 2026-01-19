from libc cimport stdint
from libc cimport stdio
from libc.stdint cimport int32_t


cdef extern from "stdarg.h":
    ctypedef struct va_list:
        pass
    ctypedef struct fake_type:
        pass
    void va_start(va_list, void* arg)
    void* va_arg(va_list, fake_type)
    void va_end(va_list)
    fake_type int_type "int"


cdef extern from "sysdep.h":
    ctypedef int32_t spin_lock_t

cdef extern from "csound.h":
    """
    #ifndef USE_DOUBLE
    #define MYFLT float
    #else
    #define MYFLT double
    #endif
    #define PUBLIC __attribute__ ( (visibility("default")) )
    """

    # Platform-dependent definitions and declarations.
    
    ctypedef float MYFLT
    
    cdef enum CSOUND_STATUS:
        CSOUND_SUCCESS = 0
        CSOUND_ERROR = -1
        CSOUND_INITIALIZATION = -2
        CSOUND_PERFORMANCE = -3
        CSOUND_MEMORY = -4
        CSOUND_SIGNAL = -5

    cdef enum CSOUND_FILETYPES:
        # This should only be used internally by the original FileOpen()
        # API call or for temp files written with <CsFileB>
        CSFTYPE_UNKNOWN = 0

        CSFTYPE_UNIFIED_CSD = 1   # Unified Csound document
        CSFTYPE_ORCHESTRA         # the primary orc file (may be temporary)
        CSFTYPE_SCORE             # the primary sco file (may be temporary)
                                  # or any additional score opened by Cscore
        CSFTYPE_ORC_INCLUDE       # a file #included by the orchestra
        CSFTYPE_SCO_INCLUDE       # a file #included by the score
        CSFTYPE_SCORE_OUT         # used for score.srt score.xtr cscore.out
        CSFTYPE_SCOT              # Scot score input format
        CSFTYPE_OPTIONS           # for .csoundrc and -@ flag
        CSFTYPE_EXTRACT_PARMS     # extraction file specified by -x

        # audio file types that Csound can write (10-19) or read
        CSFTYPE_RAW_AUDIO
        CSFTYPE_IRCAM
        CSFTYPE_AIFF
        CSFTYPE_AIFC
        CSFTYPE_WAVE
        CSFTYPE_AU
        CSFTYPE_SD2
        CSFTYPE_W64
        CSFTYPE_WAVEX
        CSFTYPE_FLAC
        CSFTYPE_CAF
        CSFTYPE_WVE
        CSFTYPE_OGG
        CSFTYPE_MPC2K
        CSFTYPE_RF64
        CSFTYPE_AVR
        CSFTYPE_HTK
        CSFTYPE_MAT4
        CSFTYPE_MAT5
        CSFTYPE_NIST
        CSFTYPE_PAF
        CSFTYPE_PVF
        CSFTYPE_SDS
        CSFTYPE_SVX
        CSFTYPE_VOC
        CSFTYPE_XI
        CSFTYPE_MPEG
        CSFTYPE_UNKNOWN_AUDIO     # used when opening audio file for reading
                                  # or temp file written with <CsSampleB>

        # miscellaneous music formats
        CSFTYPE_SOUNDFONT
        CSFTYPE_STD_MIDI          # Standard MIDI file
        CSFTYPE_MIDI_SYSEX        # Raw MIDI codes eg. SysEx dump

        # analysis formats
        CSFTYPE_HETRO
        CSFTYPE_HETROT
        CSFTYPE_PVC               # original PVOC format
        CSFTYPE_PVCEX             # PVOC-EX format
        CSFTYPE_CVANAL
        CSFTYPE_LPC
        CSFTYPE_ATS
        CSFTYPE_LORIS
        CSFTYPE_SDIF
        CSFTYPE_HRTF

        # Types for plugins and the files they read/write
        CSFTYPE_UNUSED
        CSFTYPE_LADSPA_PLUGIN
        CSFTYPE_SNAPSHOT

        # Special formats for Csound ftables or scanned synthesis matrices with header info
        CSFTYPE_FTABLES_TEXT        # for ftsave and ftload 
        CSFTYPE_FTABLES_BINARY      # for ftsave and ftload 
        CSFTYPE_XSCANU_MATRIX       # for xscanu opcode 

        # These are for raw lists of numbers without header info
        CSFTYPE_FLOATS_TEXT         # used by GEN23 GEN28 dumpk readk
        CSFTYPE_FLOATS_BINARY       # used by dumpk readk etc.
        CSFTYPE_INTEGER_TEXT        # used by dumpk readk etc.
        CSFTYPE_INTEGER_BINARY      # used by dumpk readk etc.

        # image file formats
        CSFTYPE_IMAGE_PNG

        # For files that don't match any of the above
        CSFTYPE_POSTSCRIPT          # EPS format used by graphs
        CSFTYPE_SCRIPT_TEXT         # executable script files (eg. Python)
        CSFTYPE_OTHER_TEXT
        CSFTYPE_OTHER_BINARY

    ctypedef struct CSOUND
    ctypedef struct WINDAT
    ctypedef struct XYINDAT

    ctypedef struct CSOUND_PARAMS:
        int   debug_mode              # debug mode, 0 or 1
        int   buffer_frames           # number of frames in in/out buffers
        int   hardware_buffer_frames  # ibid. hardware
        int   displays                # graph displays, 0 or 1
        int   ascii_graphs            # use ASCII graphs, 0 or 1
        int   postscript_graphs       # use postscript graphs, 0 or 1
        int   message_level           # message printout control
        int   tempo                   # tempo (sets Beatmode) 
        int   ring_bell               # bell, 0 or 1
        int   use_cscore              # use cscore for processing
        int   terminate_on_midi       # terminate performance at the end of midifile, 0 or 1
        int   heartbeat               # print heart beat, 0 or 1
        int   defer_gen01_load        # defer GEN01 load, 0 or 1
        int   midi_key                # pfield to map midi key no
        int   midi_key_cps            # pfield to map midi key no as cps
        int   midi_key_oct            # pfield to map midi key no as oct
        int   midi_key_pch            # pfield to map midi key no as pch
        int   midi_velocity           # pfield to map midi velocity
        int   midi_velocity_amp       # pfield to map midi velocity as amplitude
        int   no_default_paths        # disable relative paths from files, 0 or 1
        int   number_of_threads       # number of threads for multicore performance
        int   syntax_check_only       # do not compile, only check syntax
        int   csd_line_counts         # csd line error reporting
        int   compute_weights         # deprecated, kept for backwards comp. 
        int   realtime_mode           # use realtime priority mode, 0 or 1
        int   sample_accurate         # use sample-level score event accuracy
        MYFLT sample_rate_override    # overriding sample rate
        MYFLT control_rate_override   # overriding control rate
        int   nchnls_override         # overriding number of out channels
        int   nchnls_i_override       # overriding number of in channels
        MYFLT e0dbfs_override         # overriding 0dbfs
        int   daemon                  # daemon mode
        int   ksmps_override          # ksmps override
        int   FFT_library             # fft_lib


    ctypedef struct CS_AUDIODEVICE:
        char device_name[128]
        char device_id[128]
        char rt_module[128]
        int max_nchnls
        int isOutput

    ctypedef struct CS_MIDIDEVICE:
        char device_name[128]
        char interface_name[128]
        char device_id[128]
        char midi_module[128]
        int isOutput

    ctypedef struct csRtAudioParams:
        char    *devName        # device name (NULL/empty: default)        
        int     devNum          # device number (0-1023), 1024: default
        unsigned int bufSamp_SW # buffer fragment size (-b) in sample frames        
        int     bufSamp_HW      # total buffer size (-B) in sample frames[]
        int     nChannels       # number of channels
        int     sampleFormat    # sample format (AE_SHORT etc.)        
        float   sampleRate      # sample rate in Hz

    ctypedef stdint.uint32_t uint32_t
    ctypedef stdint.uint64_t uint64_t
    ctypedef stdint.uint32_t uint32
    ctypedef stdint.int32_t int32
    ctypedef stdint.int64_t int64_t
    ctypedef stdint.int_least64_t int_least64_t
    ctypedef stdint.uintptr_t uintptr_t

    ctypedef struct RTCLOCK:
        int_least64_t   starttime_real
        int_least64_t   starttime_CPU


    ctypedef struct opcodeListEntry:
        char        *opname
        char        *outypes
        char        *intypes
        int         flags



    ctypedef struct CsoundRandMTState:
        int         mti
        uint32_t    mt[624]


    ctypedef struct PVSDATEXT:
        int32           N
        int             sliding     # Flag to indicate sliding case
        int32           NB
        int32           overlap
        int32           winsize
        int             wintype
        int32           format
        uint32          framecount
        float*          frame

    ctypedef struct ORCTOKEN:
        int              type
        char             *lexeme
        int              value
        double           fvalue
        char             *optype
        ORCTOKEN         *next

    ctypedef struct TREE:
        int           type
        ORCTOKEN      *value
        int           rate
        int           len
        int           line
        uint64_t      locn
        TREE          *left
        TREE          *right
        TREE          *next
        void          *markup  

   # Constants used by the bus interface (csoundGetChannelPtr() etc.).

    cdef enum controlChannelType:
        CSOUND_CONTROL_CHANNEL = 1
        CSOUND_AUDIO_CHANNEL = 2
        CSOUND_STRING_CHANNEL = 3
        CSOUND_PVS_CHANNEL = 4
        CSOUND_VAR_CHANNEL = 5
        CSOUND_CHANNEL_TYPE_MASK = 15
        CSOUND_INPUT_CHANNEL = 16
        CSOUND_OUTPUT_CHANNEL = 32


    cdef enum controlChannelBehavior:
        CSOUND_CONTROL_CHANNEL_NO_HINTS
        CSOUND_CONTROL_CHANNEL_INT
        CSOUND_CONTROL_CHANNEL_LIN
        CSOUND_CONTROL_CHANNEL_EXP


   # This structure holds the parameter hints for control channels

    ctypedef struct controlChannelHints_t:
        controlChannelBehavior    behav
        MYFLT   dflt
        MYFLT   min
        MYFLT   max
        int x
        int y
        int width
        int height
        # This member must be set explicitly to NULL if not used
        char *attributes

    ctypedef struct controlChannelInfo_t:
        char  *name
        int     type
        controlChannelHints_t    hints

    ctypedef void (*channelCallback_t)(CSOUND *csound, const char *channelName, void *channelValuePtr, const void *channelType);

    int csoundInitialize(int flags) nogil
    void csoundSetOpcodedir(const char* s) nogil
    CSOUND* csoundCreate(void* hostData) nogil
    int csoundLoadPlugins(CSOUND* csound, const char* dir) nogil
    void csoundDestroy(CSOUND*) nogil
    int csoundGetVersion() nogil
    int csoundGetAPIVersion() nogil

    TREE* csoundParseOrc(CSOUND* csound, const char* str) nogil
    int csoundCompileTree(CSOUND* csound, TREE* root) nogil
    int csoundCompileTreeAsync(CSOUND* csound, TREE* root) nogil
    void csoundDeleteTree(CSOUND* csound, TREE* tree) nogil
    int csoundCompileOrc(CSOUND* csound, const char* str) nogil
    int csoundCompileOrcAsync(CSOUND* csound, const char* str) nogil


    MYFLT csoundEvalCode(CSOUND* csound, const char* str) nogil
    int csoundInitializeCscore(CSOUND*, stdio.FILE* insco, stdio.FILE* outsco) nogil
    int csoundCompileArgs(CSOUND*, int argc, const char** argv) nogil
    int csoundStart(CSOUND* csound) nogil
    int csoundCompile(CSOUND*, int argc, const char** argv) nogil
    int csoundCompileCsd(CSOUND* csound, const char* csd_filename) nogil
    int csoundCompileCsdText(CSOUND* csound, const char* csd_text) nogil
    int csoundPerform(CSOUND*) nogil
    int csoundPerformKsmps(CSOUND*) nogil
    int csoundPerformBuffer(CSOUND*) nogil
    void csoundStop(CSOUND*) nogil
    int csoundCleanup(CSOUND*) nogil
    void csoundReset(CSOUND*) nogil
    int csoundUDPServerStart(CSOUND* csound, unsigned int port) nogil
    int csoundUDPServerStatus(CSOUND* csound) nogil
    int csoundUDPServerClose(CSOUND* csound) nogil
    int csoundUDPConsole(CSOUND* csound, const char* addr, int port, int mirror) nogil
    void csoundStopUDPConsole(CSOUND* csound) nogil
    MYFLT csoundGetSr(CSOUND*) nogil
    MYFLT csoundGetKr(CSOUND*) nogil


    uint32_t csoundGetKsmps(CSOUND*) nogil
    uint32_t csoundGetNchnls(CSOUND*) nogil
    uint32_t csoundGetNchnlsInput(CSOUND* csound) nogil
    MYFLT csoundGet0dBFS(CSOUND*) nogil
    MYFLT csoundGetA4(CSOUND*) nogil
    int64_t csoundGetCurrentTimeSamples(CSOUND* csound) nogil
    int csoundGetSizeOfMYFLT() nogil
    void* csoundGetHostData(CSOUND*) nogil
    void csoundSetHostData(CSOUND*, void* hostData) nogil
    int csoundSetOption(CSOUND* csound, const char* option) nogil
    void csoundSetParams(CSOUND* csound, CSOUND_PARAMS* p) nogil
    void csoundGetParams(CSOUND* csound, CSOUND_PARAMS* p) nogil
    int csoundGetDebug(CSOUND*) nogil
    void csoundSetDebug(CSOUND*, int debug) nogil
    MYFLT csoundSystemSr(CSOUND* csound, MYFLT val) nogil
    const char* csoundGetOutputName(CSOUND*) nogil
    const char* csoundGetInputName(CSOUND*) nogil
    void csoundSetOutput(CSOUND* csound, const char* name, const char* type, const char* format) nogil
    void csoundGetOutputFormat(CSOUND* csound, char* type, char* format) nogil
    void csoundSetInput(CSOUND* csound, const char* name) nogil
    void csoundSetMIDIInput(CSOUND* csound, const char* name) nogil
    void csoundSetMIDIFileInput(CSOUND* csound, const char* name) nogil
    void csoundSetMIDIOutput(CSOUND* csound, const char* name) nogil
    void csoundSetMIDIFileOutput(CSOUND* csound, const char* name) nogil
    void csoundSetFileOpenCallback(CSOUND* p, void (*func)(CSOUND*, const char*, int, int, int)) nogil
    void csoundSetRTAudioModule(CSOUND* csound, const char* module) nogil
    int csoundGetModule(CSOUND* csound, int number, char** name, char** type) nogil
    long csoundGetInputBufferSize(CSOUND*) nogil
    long csoundGetOutputBufferSize(CSOUND*) nogil
    MYFLT* csoundGetInputBuffer(CSOUND*) nogil
    MYFLT* csoundGetOutputBuffer(CSOUND*) nogil
    MYFLT* csoundGetSpin(CSOUND*) nogil
    void csoundClearSpin(CSOUND*) nogil
    void csoundAddSpinSample(CSOUND* csound, int frame, int channel, MYFLT sample) nogil
    void csoundSetSpinSample(CSOUND* csound, int frame, int channel, MYFLT sample) nogil
    MYFLT* csoundGetSpout(CSOUND* csound) nogil
    MYFLT csoundGetSpoutSample(CSOUND* csound, int frame, int channel) nogil
    void** csoundGetRtRecordUserData(CSOUND*) nogil
    void** csoundGetRtPlayUserData(CSOUND*) nogil
    void csoundSetHostImplementedAudioIO(CSOUND*, int state, int bufSize) nogil
    int csoundGetAudioDevList(CSOUND* csound, CS_AUDIODEVICE* list, int isOutput) nogil
    void csoundSetPlayopenCallback(CSOUND*, int (*playopen__)(CSOUND*, const csRtAudioParams* parm)) nogil
    void csoundSetRtplayCallback(CSOUND*, void (*rtplay__)(CSOUND*, const MYFLT* outBuf, int nbytes)) nogil
    void csoundSetRecopenCallback(CSOUND*, int (*recopen_)(CSOUND*, const csRtAudioParams* parm)) nogil
    void csoundSetRtrecordCallback(CSOUND*, int (*rtrecord__)(CSOUND*, MYFLT* inBuf, int nbytes)) nogil
    void csoundSetRtcloseCallback(CSOUND*, void (*rtclose__)(CSOUND*)) nogil
    void csoundSetAudioDeviceListCallback(CSOUND* csound, int (*audiodevlist__)(CSOUND*, CS_AUDIODEVICE* list, int isOutput)) nogil
    void csoundSetMIDIModule(CSOUND* csound, const char* module) nogil
    void csoundSetHostImplementedMIDIIO(CSOUND* csound, int state) nogil
    int csoundGetMIDIDevList(CSOUND* csound, CS_MIDIDEVICE* list, int isOutput) nogil
    void csoundSetExternalMidiInOpenCallback(CSOUND*, int (*func)(CSOUND*, void** userData, const char* devName)) nogil
    void csoundSetExternalMidiReadCallback(CSOUND*, int (*func)(CSOUND*, void* userData, unsigned char* buf, int nBytes)) nogil
    void csoundSetExternalMidiInCloseCallback(CSOUND*, int (*func)(CSOUND*, void* userData)) nogil
    void csoundSetExternalMidiOutOpenCallback(CSOUND*, int (*func)(CSOUND*, void** userData, const char* devName)) nogil
    void csoundSetExternalMidiWriteCallback(CSOUND*, int (*func)(CSOUND*, void* userData, const unsigned char* buf, int nBytes)) nogil
    void csoundSetExternalMidiOutCloseCallback(CSOUND*, int (*func)(CSOUND*, void* userData)) nogil
    void csoundSetExternalMidiErrorStringCallback(CSOUND*, const char* (*func)(int)) nogil
    void csoundSetMIDIDeviceListCallback(CSOUND* csound, int (*mididevlist__)(CSOUND*, CS_MIDIDEVICE* list, int isOutput)) nogil
    int csoundReadScore(CSOUND* csound, const char* str) nogil
    void csoundReadScoreAsync(CSOUND* csound, const char* str) nogil
    double csoundGetScoreTime(CSOUND*) nogil
    int csoundIsScorePending(CSOUND*) nogil
    void csoundSetScorePending(CSOUND*, int pending) nogil
    MYFLT csoundGetScoreOffsetSeconds(CSOUND*) nogil
    void csoundSetScoreOffsetSeconds(CSOUND*, MYFLT time) nogil
    void csoundRewindScore(CSOUND*) nogil
    void csoundSetCscoreCallback(CSOUND*, void (*cscoreCallback_)(CSOUND*)) nogil
    int csoundScoreSort(CSOUND*, stdio.FILE* inFile, stdio.FILE* outFile) nogil
    int csoundScoreExtract(CSOUND*, stdio.FILE* inFile, stdio.FILE* outFile, stdio.FILE* extractFile) nogil

    void csoundMessage(CSOUND*, const char* format, ...) nogil
    void csoundMessageS(CSOUND*, int attr, const char* format, ...) nogil

    void csoundMessageV(CSOUND*, int attr, const char* format, va_list args) nogil
    void csoundSetDefaultMessageCallback(void (*csoundMessageCallback_)(CSOUND*, int attr, const char* format, va_list valist)) nogil
    void csoundSetMessageCallback(CSOUND*, void (*csoundMessageCallback_)(CSOUND*, int attr, const char* format,va_list valist)) nogil

    void csoundSetMessageStringCallback(CSOUND* csound, void (*csoundMessageStrCallback)(CSOUND* csound, int attr, const char* str)) nogil
    int csoundGetMessageLevel(CSOUND*) nogil
    void csoundSetMessageLevel(CSOUND*, int messageLevel) nogil
    void csoundCreateMessageBuffer(CSOUND* csound, int toStdOut) nogil
    const char* csoundGetFirstMessage(CSOUND* csound) nogil
    int csoundGetFirstMessageAttr(CSOUND* csound) nogil
    void csoundPopFirstMessage(CSOUND* csound) nogil
    int csoundGetMessageCnt(CSOUND* csound) nogil
    void csoundDestroyMessageBuffer(CSOUND* csound) nogil
    int csoundGetChannelPtr(CSOUND*, MYFLT** p, const char* name, int type) nogil
    int csoundListChannels(CSOUND*, controlChannelInfo_t** lst) nogil
    void csoundDeleteChannelList(CSOUND*, controlChannelInfo_t* lst) nogil
    int csoundSetControlChannelHints(CSOUND*, const char* name, controlChannelHints_t hints) nogil
    int csoundGetControlChannelHints(CSOUND*, const char* name, controlChannelHints_t* hints) nogil
    int* csoundGetChannelLock(CSOUND*, const char* name) nogil
    MYFLT csoundGetControlChannel(CSOUND* csound, const char* name, int* err) nogil
    void csoundSetControlChannel(CSOUND* csound, const char* name, MYFLT val) nogil
    void csoundGetAudioChannel(CSOUND* csound, const char* name, MYFLT* samples) nogil
    void csoundSetAudioChannel(CSOUND* csound, const char* name, MYFLT* samples) nogil
    void csoundGetStringChannel(CSOUND* csound, const char* name, char* string) nogil
    void csoundSetStringChannel(CSOUND* csound, const char* name, char* string) nogil
    int csoundGetChannelDatasize(CSOUND* csound, const char* name) nogil
    void csoundSetInputChannelCallback(CSOUND* csound, channelCallback_t inputChannelCalback) nogil
    void csoundSetOutputChannelCallback(CSOUND* csound, channelCallback_t outputChannelCalback) nogil
    int csoundSetPvsChannel(CSOUND*, const PVSDATEXT* fin, const char* name) nogil
    int csoundGetPvsChannel(CSOUND* csound, PVSDATEXT* fout, const char* name) nogil
    int csoundScoreEvent(CSOUND*, char type, const MYFLT* pFields, long numFields) nogil
    void csoundScoreEventAsync(CSOUND*, char type, const MYFLT* pFields, long numFields) nogil
    int csoundScoreEventAbsolute(CSOUND*, char type, const MYFLT* pfields, long numFields, double time_ofs) nogil
    void csoundScoreEventAbsoluteAsync(CSOUND*, char type, const MYFLT* pfields, long numFields, double time_ofs) nogil
    void csoundInputMessage(CSOUND*, const char* message) nogil
    void csoundInputMessageAsync(CSOUND*, const char* message) nogil
    int csoundKillInstance(CSOUND* csound, MYFLT instr, char* instrName, int mode, int allow_release) nogil
    int csoundRegisterSenseEventCallback(CSOUND*, void (*func)(CSOUND*, void*), void* userData) nogil
    void csoundKeyPress(CSOUND*, char c) nogil
    int csoundRegisterKeyboardCallback(CSOUND*, int (*func)(void* userData, void* p, unsigned int type), void* userData, unsigned int type) nogil
    void csoundRemoveKeyboardCallback(CSOUND* csound, int (*func)(void*, void*, unsigned int)) nogil
    int csoundTableLength(CSOUND*, int table) nogil
    MYFLT csoundTableGet(CSOUND*, int table, int index) nogil
    void csoundTableSet(CSOUND*, int table, int index, MYFLT value) nogil
    void csoundTableCopyOut(CSOUND* csound, int table, MYFLT* dest) nogil
    void csoundTableCopyOutAsync(CSOUND* csound, int table, MYFLT* dest) nogil
    void csoundTableCopyIn(CSOUND* csound, int table, MYFLT* src) nogil
    void csoundTableCopyInAsync(CSOUND* csound, int table, MYFLT* src) nogil
    int csoundGetTable(CSOUND*, MYFLT** tablePtr, int tableNum) nogil
    int csoundGetTableArgs(CSOUND* csound, MYFLT** argsPtr, int tableNum) nogil
    int csoundIsNamedGEN(CSOUND* csound, int num) nogil
    void csoundGetNamedGEN(CSOUND* csound, int num, char* name, int len) nogil
    int csoundSetIsGraphable(CSOUND*, int isGraphable) nogil
    void csoundSetMakeGraphCallback(CSOUND*, void (*makeGraphCallback_)(CSOUND*, WINDAT* windat, const char* name)) nogil
    void csoundSetDrawGraphCallback(CSOUND*, void (*drawGraphCallback_)(CSOUND*, WINDAT* windat)) nogil
    void csoundSetKillGraphCallback(CSOUND*, void (*killGraphCallback_)(CSOUND*, WINDAT* windat)) nogil
    void csoundSetExitGraphCallback(CSOUND*, int (*exitGraphCallback_)(CSOUND*)) nogil
    void* csoundGetNamedGens(CSOUND*) nogil
    int csoundNewOpcodeList(CSOUND*, opcodeListEntry** opcodelist) nogil
    void csoundDisposeOpcodeList(CSOUND*, opcodeListEntry* opcodelist) nogil
    int csoundAppendOpcode(CSOUND*, const char* opname, int dsblksiz, int flags, int thread, const char* outypes, const char* intypes, int (*iopadr)(CSOUND*, void*), int (*kopadr)(CSOUND*, void*), int (*aopadr)(CSOUND*, void*)) nogil
    void csoundSetYieldCallback(CSOUND*, int (*yieldCallback_)(CSOUND*)) nogil
    void* csoundCreateThread(uintptr_t (*threadRoutine)(void*), void* userdata) nogil
    void* csoundCreateThread2(uintptr_t (*threadRoutine)(void*), unsigned int stack, void* userdata) nogil
    void* csoundGetCurrentThreadId() nogil
    uintptr_t csoundJoinThread(void* thread) nogil
    void* csoundCreateThreadLock() nogil
    int csoundWaitThreadLock(void* lock, size_t milliseconds) nogil
    void csoundWaitThreadLockNoTimeout(void* lock) nogil
    void csoundNotifyThreadLock(void* lock) nogil
    void csoundDestroyThreadLock(void* lock) nogil
    void* csoundCreateMutex(int isRecursive) nogil
    void csoundLockMutex(void* mutex_) nogil
    int csoundLockMutexNoWait(void* mutex_) nogil
    void csoundUnlockMutex(void* mutex_) nogil
    void csoundDestroyMutex(void* mutex_) nogil
    void* csoundCreateBarrier(unsigned int max) nogil
    int csoundDestroyBarrier(void* barrier) nogil
    int csoundWaitBarrier(void* barrier) nogil
    void* csoundCreateCondVar() nogil
    void csoundCondWait(void* condVar, void* mutex) nogil
    void csoundCondSignal(void* condVar) nogil
    void csoundDestroyCondVar(void* condVar) nogil
    void csoundSleep(size_t milliseconds) nogil
    int csoundSpinLockInit(spin_lock_t* spinlock) nogil
    void csoundSpinLock(spin_lock_t* spinlock) nogil
    int csoundSpinTryLock(spin_lock_t* spinlock) nogil
    void csoundSpinUnLock(spin_lock_t* spinlock) nogil
    long csoundRunCommand(const char* const* argv, int noWait) nogil
    void csoundInitTimerStruct(RTCLOCK*) nogil
    double csoundGetRealTime(RTCLOCK*) nogil
    double csoundGetCPUTime(RTCLOCK*) nogil
    uint32_t csoundGetRandomSeedFromTime() nogil
    void csoundSetLanguage(cslanguage_t lang_code) nogil
    const char* csoundGetEnv(CSOUND* csound, const char* name) nogil
    int csoundSetGlobalEnv(const char* name, const char* value) nogil
    int csoundCreateGlobalVariable(CSOUND*, const char* name, size_t nbytes) nogil
    void* csoundQueryGlobalVariable(CSOUND*, const char* name) nogil
    void* csoundQueryGlobalVariableNoCheck(CSOUND*, const char* name) nogil
    int csoundDestroyGlobalVariable(CSOUND*, const char* name) nogil
    int csoundRunUtility(CSOUND*, const char* name, int argc, char** argv) nogil
    char** csoundListUtilities(CSOUND*) nogil
    void csoundDeleteUtilityList(CSOUND*, char** lst) nogil
    const char* csoundGetUtilityDescription(CSOUND*, const char* utilName) nogil
    int csoundRand31(int* seedVal) nogil
    void csoundSeedRandMT(CsoundRandMTState* p, const uint32_t* initKey, uint32_t keyLength) nogil
    uint32_t csoundRandMT(CsoundRandMTState* p) nogil
    void* csoundCreateCircularBuffer(CSOUND* csound, int numelem, int elemsize) nogil
    int csoundReadCircularBuffer(CSOUND* csound, void* circular_buffer, void* out, int items) nogil
    int csoundPeekCircularBuffer(CSOUND* csound, void* circular_buffer, void* out, int items) nogil
    int csoundWriteCircularBuffer(CSOUND* csound, void* p, const void* inp, int items) nogil
    void csoundFlushCircularBuffer(CSOUND* csound, void* p) nogil
    void csoundDestroyCircularBuffer(CSOUND* csound, void* circularbuffer) nogil
    int csoundOpenLibrary(void** library, const char* libraryPath) nogil
    int csoundCloseLibrary(void* library) nogil
    void* csoundGetLibrarySymbol(void* library, const char* symbolName) nogil

cdef extern from "text.h":

    ctypedef enum cslanguage_t:
        CSLANGUAGE_DEFAULT = 0
        CSLANGUAGE_AFRIKAANS
        CSLANGUAGE_ALBANIAN
        CSLANGUAGE_ARABIC
        CSLANGUAGE_ARMENIAN
        CSLANGUAGE_ASSAMESE
        CSLANGUAGE_AZERI
        CSLANGUAGE_BASQUE
        CSLANGUAGE_BELARUSIAN
        CSLANGUAGE_BENGALI
        CSLANGUAGE_BULGARIAN
        CSLANGUAGE_CATALAN
        CSLANGUAGE_CHINESE
        CSLANGUAGE_CROATIAN
        CSLANGUAGE_CZECH
        CSLANGUAGE_DANISH
        CSLANGUAGE_DUTCH
        CSLANGUAGE_ENGLISH_UK
        CSLANGUAGE_ENGLISH_US
        CSLANGUAGE_ESTONIAN
        CSLANGUAGE_FAEROESE
        CSLANGUAGE_FARSI
        CSLANGUAGE_FINNISH
        CSLANGUAGE_FRENCH
        CSLANGUAGE_GEORGIAN
        CSLANGUAGE_GERMAN
        CSLANGUAGE_GREEK
        CSLANGUAGE_GUJARATI
        CSLANGUAGE_HEBREW
        CSLANGUAGE_HINDI
        CSLANGUAGE_HUNGARIAN
        CSLANGUAGE_ICELANDIC
        CSLANGUAGE_INDONESIAN
        CSLANGUAGE_ITALIAN
        CSLANGUAGE_JAPANESE
        CSLANGUAGE_KANNADA
        CSLANGUAGE_KASHMIRI
        CSLANGUAGE_KAZAK
        CSLANGUAGE_KONKANI
        CSLANGUAGE_KOREAN
        CSLANGUAGE_LATVIAN
        CSLANGUAGE_LITHUANIAN
        CSLANGUAGE_MACEDONIAN
        CSLANGUAGE_MALAY
        CSLANGUAGE_MALAYALAM
        CSLANGUAGE_MANIPURI
        CSLANGUAGE_MARATHI
        CSLANGUAGE_NEPALI
        CSLANGUAGE_NORWEGIAN
        CSLANGUAGE_ORIYA
        CSLANGUAGE_POLISH
        CSLANGUAGE_PORTUGUESE
        CSLANGUAGE_PUNJABI
        CSLANGUAGE_ROMANIAN
        CSLANGUAGE_RUSSIAN
        CSLANGUAGE_SANSKRIT
        CSLANGUAGE_SERBIAN
        CSLANGUAGE_SINDHI
        CSLANGUAGE_SLOVAK
        CSLANGUAGE_SLOVENIAN
        CSLANGUAGE_SPANISH
        CSLANGUAGE_SWAHILI
        CSLANGUAGE_SWEDISH
        CSLANGUAGE_TAMIL
        CSLANGUAGE_TATAR
        CSLANGUAGE_TELUGU
        CSLANGUAGE_THAI
        CSLANGUAGE_TURKISH
        CSLANGUAGE_UKRAINIAN
        CSLANGUAGE_URDU
        CSLANGUAGE_UZBEK
        CSLANGUAGE_VIETNAMESE
        CSLANGUAGE_COLUMBIAN

    # DEPRECATED -------------------------------------------------------------------

    # Callback typedefs for new functions
    # ctypedef void (*CsoundChannelIOCallback_t)(CSOUND *csound, const char *channelName, void *channelValuePtr, const void *channelType)
    # ctypedef void (*inputValueCallback_t)(CSOUND *csound, const char *channelName, MYFLT *value)
    # ctypedef void (*outputValueCallback_t)(CSOUND *csound, const char *channelName, MYFLT value)

    # Channel I/O Callbacks 
    # void csoundSetChannelIOCallback(CSOUND *, CsoundChannelIOCallback_t func)
    # void csoundSetInputValueCallback(CSOUND *, inputValueCallback_t func)
    # void csoundSetOutputValueCallback(CSOUND *, outputValueCallback_t func)
