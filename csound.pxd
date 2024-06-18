from libc cimport stdint



#  include "text.h"
#  include <stdarg.h>
#  include <stdio.h>

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
    ctypedef stdint.int32_t int32
    ctypedef stdint.int_least64_t int_least64_t

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



    int csoundInitialize(int flags)
    CSOUND *csoundCreate(void *hostData)
    void csoundDestroy(CSOUND *)
    int csoundCompileCsd(CSOUND *csound, const char *csd_filename)
    int csoundCompileCsdText(CSOUND *csound, const char *csd_text)




    
