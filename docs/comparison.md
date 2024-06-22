# A comparison with ctcsound


```text
enums:
	CSOUND_STATUS
	CSOUND_FILETYPES



structs:
	# opaque
    CSOUND
    WINDAT
    XYINDAT

    # non-opaque
    CSOUND_PARAMS           -> CsoundParams
    CS_AUDIODEVICE          -> CsoundAudioDevice
    CS_MIDIDEVICE           -> CsoundMidiDevice
    csRtAudioParams         -> CsoundRtAudioParams
    RTCLOCK                 -> RtClock
    opcodeListEntry         -> OpcodeListEntry
    CsoundRandMTState       -> CsoundRandMTState
    PVSDATEXT               -> PvsdatExt
    ORCTOKEN
    TREE
    controlChannelType
    controlChannelBehavior
    controlChannelHints_t   -> ControlChannelHints
    controlChannelInfo_t.   -> ControlChannelInfo



class NamedGen(ct.Structure):
    pass

NamedGen._fields_ = [
    ("name", ct.c_char_p),
    ("genum", ct.c_int),
    ("next", ct.POINTER(NamedGen))]


class Windat(ct.Structure):
    _fields_ = [("windid", ct.POINTER(ct.c_uint)),    # set by makeGraph()
                ("fdata", ct.POINTER(MYFLT)),      # data passed to drawGraph()
                ("npts", ct.c_int32),              # size of above array
                ("caption", ct.c_char * CAPSIZE),  # caption string for graph
                ("waitflg", ct.c_int16 ),          # set =1 to wait for ms after Draw
                ("polarity", ct.c_int16),          # controls positioning of X axis
                ("max", MYFLT),                 # workspace .. extrema this frame
                ("min", MYFLT),
                ("absmax", MYFLT),              # workspace .. largest of above
                ("oabsmax", MYFLT),             # Y axis scaling factor
                ("danflag", ct.c_int),             # set to 1 for extra Yaxis mid span
                ("absflag", ct.c_int)]             # set to 1 to skip abs check



globals:
    CAPSIZE  = 60

    # Symbols for Windat.polarity field
    NOPOL = 0
    NEGPOL = 1
    POSPOL = 2
    BIPOL = 3

    # message types (only one can be specified)
    CSOUNDMSG_DEFAULT = 0x0000       # standard message
    CSOUNDMSG_ERROR = 0x1000         # error message (initerror, perferror, etc.)
    CSOUNDMSG_ORCH = 0x2000          # orchestra opcodes (e.g. printks)
    CSOUNDMSG_REALTIME = 0x3000      # for progress display and heartbeat characters
    CSOUNDMSG_WARNING = 0x4000       # warning messages
    CSOUNDMSG_STDOUT = 0x5000

    # format attributes (colors etc.), use the bitwise OR of any of these:
    CSOUNDMSG_FG_BLACK = 0x0100
    CSOUNDMSG_FG_RED = 0x0101
    CSOUNDMSG_FG_GREEN = 0x0102
    CSOUNDMSG_FG_YELLOW = 0x0103
    CSOUNDMSG_FG_BLUE = 0x0104
    CSOUNDMSG_FG_MAGENTA = 0x0105
    CSOUNDMSG_FG_CYAN = 0x0106
    CSOUNDMSG_FG_WHITE = 0x0107

    CSOUNDMSG_FG_BOLD = 0x0008
    CSOUNDMSG_FG_UNDERLINE = 0x0080

    CSOUNDMSG_BG_BLACK = 0x0200
    CSOUNDMSG_BG_RED = 0x0210
    CSOUNDMSG_BG_GREEN = 0x0220
    CSOUNDMSG_BG_ORANGE = 0x0230
    CSOUNDMSG_BG_BLUE = 0x0240
    CSOUNDMSG_BG_MAGENTA = 0x0250
    CSOUNDMSG_BG_CYAN = 0x0260
    CSOUNDMSG_BG_GREY = 0x0270

    CSOUNDMSG_TYPE_MASK = 0x7000
    CSOUNDMSG_FG_COLOR_MASK = 0x0107
    CSOUNDMSG_FG_ATTR_MASK = 0x0088
    CSOUNDMSG_BG_COLOR_MASK = 0x0270


    # ERROR DEFINITIONS
    CSOUND_SUCCESS = 0               # Completed successfully.
    CSOUND_ERROR = -1                # Unspecified failure.
    CSOUND_INITIALIZATION = -2       # Failed during initialization.
    CSOUND_PERFORMANCE = -3          # Failed during performance.
    CSOUND_MEMORY = -4               # Failed to allocate requested memory.
    CSOUND_SIGNAL = -5               # Termination requested by SIGINT or SIGTERM.

    # Flags for csoundInitialize().
    CSOUNDINIT_NO_SIGNAL_HANDLER = 1
    CSOUNDINIT_NO_ATEXIT = 2

    # Types for keyboard callbacks set in registerKeyboardCallback()
    CSOUND_CALLBACK_KBD_EVENT = 1
    CSOUND_CALLBACK_KBD_TEXT = 2

    # Constants used by the bus interface (csoundGetChannelPtr() etc.).
    CSOUND_CONTROL_CHANNEL = 1
    CSOUND_AUDIO_CHANNEL  = 2
    CSOUND_STRING_CHANNEL = 3
    CSOUND_PVS_CHANNEL = 4
    CSOUND_VAR_CHANNEL = 5

    CSOUND_CHANNEL_TYPE_MASK = 15

    CSOUND_INPUT_CHANNEL = 16
    CSOUND_OUTPUT_CHANNEL = 32

    CSOUND_CONTROL_CHANNEL_NO_HINTS  = 0
    CSOUND_CONTROL_CHANNEL_INT  = 1
    CSOUND_CONTROL_CHANNEL_LIN  = 2
    CSOUND_CONTROL_CHANNEL_EXP  = 3

```
