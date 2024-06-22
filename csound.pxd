from libc cimport stdint
from libc cimport stdio



#  include "text.h"
#  include <stdarg.h>
#  include <stdio.h>

cdef extern from "stdarg.h":
    ctypedef struct va_list:
        pass
    ctypedef struct fake_type:
        pass
    void va_start(va_list, void* arg)
    void* va_arg(va_list, fake_type)
    void va_end(va_list)
    fake_type int_type "int"

cdef extern from "csound.h":
    """
    #ifndef USE_DOUBLE
    #define MYFLT float
    #else
    #define MYFLT double
    #endif
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

    int csoundInitialize(int flags)
    void csoundSetOpcodedir(const char* s)
    CSOUND* csoundCreate(void* hostData)
    int csoundLoadPlugins(CSOUND* csound, const char* dir)
    void csoundDestroy(CSOUND*)
    int csoundGetVersion()
    int csoundGetAPIVersion()

    TREE* csoundParseOrc(CSOUND* csound, const char* str)
    int csoundCompileTree(CSOUND* csound, TREE* root)
    int csoundCompileTreeAsync(CSOUND* csound, TREE* root)
    void csoundDeleteTree(CSOUND* csound, TREE* tree)
    int csoundCompileOrc(CSOUND* csound, const char* str)
    int csoundCompileOrcAsync(CSOUND* csound, const char* str)


    MYFLT csoundEvalCode(CSOUND* csound, const char* str)
    int csoundInitializeCscore(CSOUND*, stdio.FILE* insco, stdio.FILE* outsco)
    int csoundCompileArgs(CSOUND*, int argc, const char** argv)
    int csoundStart(CSOUND* csound)
    int csoundCompile(CSOUND*, int argc, const char** argv)
    int csoundCompileCsd(CSOUND* csound, const char* csd_filename)
    int csoundCompileCsdText(CSOUND* csound, const char* csd_text)
    int csoundPerform(CSOUND*)
    int csoundPerformKsmps(CSOUND*)
    int csoundPerformBuffer(CSOUND*)
    void csoundStop(CSOUND*)
    int csoundCleanup(CSOUND*)
    void csoundReset(CSOUND*)
    int csoundUDPServerStart(CSOUND* csound, unsigned int port)
    int csoundUDPServerStatus(CSOUND* csound)
    int csoundUDPServerClose(CSOUND* csound)
    int csoundUDPConsole(CSOUND* csound, const char* addr, int port, int mirror)
    void csoundStopUDPConsole(CSOUND* csound)
    MYFLT csoundGetSr(CSOUND*)
    MYFLT csoundGetKr(CSOUND*)


    uint32_t csoundGetKsmps(CSOUND*)
    uint32_t csoundGetNchnls(CSOUND*)
    uint32_t csoundGetNchnlsInput(CSOUND* csound)
    MYFLT csoundGet0dBFS(CSOUND*)
    MYFLT csoundGetA4(CSOUND*)
    int64_t csoundGetCurrentTimeSamples(CSOUND* csound)
    int csoundGetSizeOfMYFLT()
    void* csoundGetHostData(CSOUND*)
    void csoundSetHostData(CSOUND*, void* hostData)
    int csoundSetOption(CSOUND* csound, const char* option)
    void csoundSetParams(CSOUND* csound, CSOUND_PARAMS* p)
    void csoundGetParams(CSOUND* csound, CSOUND_PARAMS* p)
    int csoundGetDebug(CSOUND*)
    void csoundSetDebug(CSOUND*, int debug)
    MYFLT csoundSystemSr(CSOUND* csound, MYFLT val)
    const char* csoundGetOutputName(CSOUND*)
    const char* csoundGetInputName(CSOUND*)
    void csoundSetOutput(CSOUND* csound, const char* name, const char* type, const char* format)
    void csoundGetOutputFormat(CSOUND* csound, char* type, char* format)
    void csoundSetInput(CSOUND* csound, const char* name)
    void csoundSetMIDIInput(CSOUND* csound, const char* name)
    void csoundSetMIDIFileInput(CSOUND* csound, const char* name)
    void csoundSetMIDIOutput(CSOUND* csound, const char* name)
    void csoundSetMIDIFileOutput(CSOUND* csound, const char* name)
    void csoundSetFileOpenCallback(CSOUND* p, void (*func)(CSOUND*, const char*, int, int, int))
    void csoundSetRTAudioModule(CSOUND* csound, const char* module)
    int csoundGetModule(CSOUND* csound, int number, char** name, char** type)
    long csoundGetInputBufferSize(CSOUND*)
    long csoundGetOutputBufferSize(CSOUND*)
    MYFLT* csoundGetInputBuffer(CSOUND*)
    MYFLT* csoundGetOutputBuffer(CSOUND*)
    MYFLT* csoundGetSpin(CSOUND*)
    void csoundClearSpin(CSOUND*)
    void csoundAddSpinSample(CSOUND* csound, int frame, int channel, MYFLT sample)
    void csoundSetSpinSample(CSOUND* csound, int frame, int channel, MYFLT sample)
    MYFLT* csoundGetSpout(CSOUND* csound)
    MYFLT csoundGetSpoutSample(CSOUND* csound, int frame, int channel)
    void** csoundGetRtRecordUserData(CSOUND*)
    void** csoundGetRtPlayUserData(CSOUND*)
    void csoundSetHostImplementedAudioIO(CSOUND*, int state, int bufSize)
    int csoundGetAudioDevList(CSOUND* csound, CS_AUDIODEVICE* list, int isOutput)
    void csoundSetPlayopenCallback(CSOUND*, int (*playopen__)(CSOUND*, const csRtAudioParams* parm))
    void csoundSetRtplayCallback(CSOUND*, void (*rtplay__)(CSOUND*, const MYFLT* outBuf, int nbytes))
    void csoundSetRecopenCallback(CSOUND*, int (*recopen_)(CSOUND*, const csRtAudioParams* parm))
    void csoundSetRtrecordCallback(CSOUND*, int (*rtrecord__)(CSOUND*, MYFLT* inBuf, int nbytes))
    void csoundSetRtcloseCallback(CSOUND*, void (*rtclose__)(CSOUND*))
    void csoundSetAudioDeviceListCallback(CSOUND* csound, int (*audiodevlist__)(CSOUND*, CS_AUDIODEVICE* list, int isOutput))
    void csoundSetMIDIModule(CSOUND* csound, const char* module)
    void csoundSetHostImplementedMIDIIO(CSOUND* csound, int state)
    int csoundGetMIDIDevList(CSOUND* csound, CS_MIDIDEVICE* list, int isOutput)
    void csoundSetExternalMidiInOpenCallback(CSOUND*, int (*func)(CSOUND*, void** userData, const char* devName))
    void csoundSetExternalMidiReadCallback(CSOUND*, int (*func)(CSOUND*, void* userData, unsigned char* buf, int nBytes))
    void csoundSetExternalMidiInCloseCallback(CSOUND*, int (*func)(CSOUND*, void* userData))
    void csoundSetExternalMidiOutOpenCallback(CSOUND*, int (*func)(CSOUND*, void** userData, const char* devName))
    void csoundSetExternalMidiWriteCallback(CSOUND*, int (*func)(CSOUND*, void* userData, const unsigned char* buf, int nBytes))
    void csoundSetExternalMidiOutCloseCallback(CSOUND*, int (*func)(CSOUND*, void* userData))
    void csoundSetExternalMidiErrorStringCallback(CSOUND*, const char* (*func)(int))
    void csoundSetMIDIDeviceListCallback(CSOUND* csound, int (*mididevlist__)(CSOUND*, CS_MIDIDEVICE* list, int isOutput))
    int csoundReadScore(CSOUND* csound, const char* str)
    void csoundReadScoreAsync(CSOUND* csound, const char* str)
    double csoundGetScoreTime(CSOUND*)
    int csoundIsScorePending(CSOUND*)
    void csoundSetScorePending(CSOUND*, int pending)
    MYFLT csoundGetScoreOffsetSeconds(CSOUND*)
    void csoundSetScoreOffsetSeconds(CSOUND*, MYFLT time)
    void csoundRewindScore(CSOUND*)
    void csoundSetCscoreCallback(CSOUND*, void (*cscoreCallback_)(CSOUND*))
    int csoundScoreSort(CSOUND*, stdio.FILE* inFile, stdio.FILE* outFile)
    int csoundScoreExtract(CSOUND*, stdio.FILE* inFile, stdio.FILE* outFile, stdio.FILE* extractFile)

    void csoundMessage(CSOUND*, const char* format, ...)
    void csoundMessageS(CSOUND*, int attr, const char* format, ...)

    void csoundMessageV(CSOUND*, int attr, const char* format, va_list args)
    void csoundSetDefaultMessageCallback(void (*csoundMessageCallback_)(CSOUND*, int attr, const char* format, va_list valist))
    void csoundSetMessageCallback(CSOUND*, void (*csoundMessageCallback_)(CSOUND*, int attr, const char* format,va_list valist))

    void csoundSetMessageStringCallback(CSOUND* csound, void (*csoundMessageStrCallback)(CSOUND* csound, int attr, const char* str))
    int csoundGetMessageLevel(CSOUND*)
    void csoundSetMessageLevel(CSOUND*, int messageLevel)
    void csoundCreateMessageBuffer(CSOUND* csound, int toStdOut)
    const char* csoundGetFirstMessage(CSOUND* csound)
    int csoundGetFirstMessageAttr(CSOUND* csound)
    void csoundPopFirstMessage(CSOUND* csound)
    int csoundGetMessageCnt(CSOUND* csound)
    void csoundDestroyMessageBuffer(CSOUND* csound)
    int csoundGetChannelPtr(CSOUND*, MYFLT** p, const char* name, int type)
    int csoundListChannels(CSOUND*, controlChannelInfo_t** lst)
    void csoundDeleteChannelList(CSOUND*, controlChannelInfo_t* lst)
    int csoundSetControlChannelHints(CSOUND*, const char* name, controlChannelHints_t hints)
    int csoundGetControlChannelHints(CSOUND*, const char* name, controlChannelHints_t* hints)
    int* csoundGetChannelLock(CSOUND*, const char* name)
    MYFLT csoundGetControlChannel(CSOUND* csound, const char* name, int* err)
    void csoundSetControlChannel(CSOUND* csound, const char* name, MYFLT val)
    void csoundGetAudioChannel(CSOUND* csound, const char* name, MYFLT* samples)
    void csoundSetAudioChannel(CSOUND* csound, const char* name, MYFLT* samples)
    void csoundGetStringChannel(CSOUND* csound, const char* name, char* string)
    void csoundSetStringChannel(CSOUND* csound, const char* name, char* string)
    int csoundGetChannelDatasize(CSOUND* csound, const char* name)
    void csoundSetInputChannelCallback(CSOUND* csound, channelCallback_t inputChannelCalback)
    void csoundSetOutputChannelCallback(CSOUND* csound, channelCallback_t outputChannelCalback)
    int csoundSetPvsChannel(CSOUND*, const PVSDATEXT* fin, const char* name)
    int csoundGetPvsChannel(CSOUND* csound, PVSDATEXT* fout, const char* name)
    int csoundScoreEvent(CSOUND*, char type, const MYFLT* pFields, long numFields)
    void csoundScoreEventAsync(CSOUND*, char type, const MYFLT* pFields, long numFields)
    int csoundScoreEventAbsolute(CSOUND*, char type, const MYFLT* pfields, long numFields, double time_ofs)
    void csoundScoreEventAbsoluteAsync(CSOUND*, char type, const MYFLT* pfields, long numFields, double time_ofs)
    void csoundInputMessage(CSOUND*, const char* message)
    void csoundInputMessageAsync(CSOUND*, const char* message)
    int csoundKillInstance(CSOUND* csound, MYFLT instr, char* instrName, int mode, int allow_release)
    int csoundRegisterSenseEventCallback(CSOUND*, void (*func)(CSOUND*, void*), void* userData)
    void csoundKeyPress(CSOUND*, char c)
    int csoundRegisterKeyboardCallback(CSOUND*, int (*func)(void* userData, void* p, unsigned int type), void* userData, unsigned int type)
    void csoundRemoveKeyboardCallback(CSOUND* csound, int (*func)(void*, void*, unsigned int))
    int csoundTableLength(CSOUND*, int table)
    MYFLT csoundTableGet(CSOUND*, int table, int index)
    void csoundTableSet(CSOUND*, int table, int index, MYFLT value)
    void csoundTableCopyOut(CSOUND* csound, int table, MYFLT* dest)
    void csoundTableCopyOutAsync(CSOUND* csound, int table, MYFLT* dest)
    void csoundTableCopyIn(CSOUND* csound, int table, MYFLT* src)
    void csoundTableCopyInAsync(CSOUND* csound, int table, MYFLT* src)
    int csoundGetTable(CSOUND*, MYFLT** tablePtr, int tableNum)
    int csoundGetTableArgs(CSOUND* csound, MYFLT** argsPtr, int tableNum)
    int csoundIsNamedGEN(CSOUND* csound, int num)
    void csoundGetNamedGEN(CSOUND* csound, int num, char* name, int len)
    int csoundSetIsGraphable(CSOUND*, int isGraphable)
    void csoundSetMakeGraphCallback(CSOUND*, void (*makeGraphCallback_)(CSOUND*, WINDAT* windat, const char* name))
    void csoundSetDrawGraphCallback(CSOUND*, void (*drawGraphCallback_)(CSOUND*, WINDAT* windat))
    void csoundSetKillGraphCallback(CSOUND*, void (*killGraphCallback_)(CSOUND*, WINDAT* windat))
    void csoundSetExitGraphCallback(CSOUND*, int (*exitGraphCallback_)(CSOUND*))
    void* csoundGetNamedGens(CSOUND*)
    int csoundNewOpcodeList(CSOUND*, opcodeListEntry** opcodelist)
    void csoundDisposeOpcodeList(CSOUND*, opcodeListEntry* opcodelist)
    int csoundAppendOpcode(CSOUND*, const char* opname, int dsblksiz, int flags, int thread, const char* outypes, const char* intypes, int (*iopadr)(CSOUND*, void*), int (*kopadr)(CSOUND*, void*), int (*aopadr)(CSOUND*, void*))
    void csoundSetYieldCallback(CSOUND*, int (*yieldCallback_)(CSOUND*))
    void* csoundCreateThread(uintptr_t (*threadRoutine)(void*), void* userdata)
    void* csoundCreateThread2(uintptr_t (*threadRoutine)(void*), unsigned int stack, void* userdata)
    void* csoundGetCurrentThreadId()
    uintptr_t csoundJoinThread(void* thread)
    void* csoundCreateThreadLock()
    int csoundWaitThreadLock(void* lock, size_t milliseconds)
    void csoundWaitThreadLockNoTimeout(void* lock)
    void csoundNotifyThreadLock(void* lock)
    void csoundDestroyThreadLock(void* lock)
    void* csoundCreateMutex(int isRecursive)
    void csoundLockMutex(void* mutex_)
    int csoundLockMutexNoWait(void* mutex_)
    void csoundUnlockMutex(void* mutex_)
    void csoundDestroyMutex(void* mutex_)
    void* csoundCreateBarrier(unsigned int max)
    int csoundDestroyBarrier(void* barrier)
    int csoundWaitBarrier(void* barrier)
    void* csoundCreateCondVar()
    void csoundCondWait(void* condVar, void* mutex)
    void csoundCondSignal(void* condVar)
    void csoundDestroyCondVar(void* condVar)
    void csoundSleep(size_t milliseconds)
    # int csoundSpinLockInit(spin_lock_t* spinlock)
    # void csoundSpinLock(spin_lock_t* spinlock)
    # int csoundSpinTryLock(spin_lock_t* spinlock)
    # void csoundSpinUnLock(spin_lock_t* spinlock)
    long csoundRunCommand(const char* const* argv, int noWait)
    void csoundInitTimerStruct(RTCLOCK*)
    double csoundGetRealTime(RTCLOCK*)
    double csoundGetCPUTime(RTCLOCK*)
    uint32_t csoundGetRandomSeedFromTime()
    void csoundSetLanguage(cslanguage_t lang_code)
    const char* csoundGetEnv(CSOUND* csound, const char* name)
    int csoundSetGlobalEnv(const char* name, const char* value)
    int csoundCreateGlobalVariable(CSOUND*, const char* name, size_t nbytes)
    void* csoundQueryGlobalVariable(CSOUND*, const char* name)
    void* csoundQueryGlobalVariableNoCheck(CSOUND*, const char* name)
    int csoundDestroyGlobalVariable(CSOUND*, const char* name)
    int csoundRunUtility(CSOUND*, const char* name, int argc, char** argv)
    char** csoundListUtilities(CSOUND*)
    void csoundDeleteUtilityList(CSOUND*, char** lst)
    const char* csoundGetUtilityDescription(CSOUND*, const char* utilName)
    int csoundRand31(int* seedVal)
    void csoundSeedRandMT(CsoundRandMTState* p, const uint32_t* initKey, uint32_t keyLength)
    uint32_t csoundRandMT(CsoundRandMTState* p)
    void* csoundCreateCircularBuffer(CSOUND* csound, int numelem, int elemsize)
    int csoundReadCircularBuffer(CSOUND* csound, void* circular_buffer, void* out, int items)
    int csoundPeekCircularBuffer(CSOUND* csound, void* circular_buffer, void* out, int items)
    int csoundWriteCircularBuffer(CSOUND* csound, void* p, const void* inp, int items)
    void csoundFlushCircularBuffer(CSOUND* csound, void* p)
    void csoundDestroyCircularBuffer(CSOUND* csound, void* circularbuffer)
    int csoundOpenLibrary(void** library, const char* libraryPath)
    int csoundCloseLibrary(void* library)
    void* csoundGetLibrarySymbol(void* library, const char* symbolName)

cdef extern from "text.h":

    cdef enum cslanguage_t:
        CSLANGUAGE_DEFAULT
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

