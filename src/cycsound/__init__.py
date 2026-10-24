"""cycsound - Cython bindings for the Csound 7 audio synthesis library."""

import os
import sys

# Point Csound at the plugins installed with the package (a wheel), else the
# vendored directory of a source build, unless the environment already
# selects one. The plugins hold the realtime audio/MIDI drivers. Without this
# the macOS binary looks in /Applications/Csound, a possibly mismatched install.
if "OPCODE7DIR64" not in os.environ:
    _here = os.path.dirname(os.path.abspath(__file__))
    # An editable install keeps the installed plugins apart from this file,
    # so look along the whole package path.
    for _plugins in (
        *(os.path.join(_dir, "plugins") for _dir in __path__),
        os.path.join(os.path.dirname(os.path.dirname(_here)),
                     "vendor", "plugins"),
    ):
        if os.path.isdir(_plugins):
            os.environ["OPCODE7DIR64"] = _plugins
            break
    del _here, _plugins

# A Windows source build links csound7_64.dll from the Csound 7 install that
# CMake recorded in _dlldir.txt; wheels bundle the DLL instead. It sits next to
# _core, which an editable install keeps apart from this file, so search the
# whole package path.
if sys.platform == "win32":
    for _dir in __path__:
        _dlldir = os.path.join(_dir, "_dlldir.txt")
        if os.path.exists(_dlldir):
            with open(_dlldir) as _f:
                _bin = _f.read().strip()
            if os.path.isdir(_bin):
                os.add_dll_directory(_bin)
            del _f, _bin
            break
    del _dir, _dlldir

# On Linux the Csound 7 release ships its opcode library as external plugins
# that are dlopen()ed by libcsound64 at csoundCreate() time. Those plugins
# resolve Csound symbols out of the global symbol namespace, so the extension
# (and with it libcsound64) has to be loaded with RTLD_GLOBAL -- otherwise the
# plugin opcodes silently fail to register and orchestras using them do not
# compile.
if sys.platform.startswith("linux"):
    _dlopenflags = sys.getdlopenflags()
    sys.setdlopenflags(_dlopenflags | os.RTLD_GLOBAL)
    try:
        from cycsound import _core  # noqa: F401
    finally:
        sys.setdlopenflags(_dlopenflags)
    del _dlopenflags

from cycsound._core import (
    # Module-level functions
    initialize,
    get_version,
    get_size_of_cs_float,
    get_size_of_cs_double,
    get_size_of_myflt,
    set_global_env,
    sleep,
    # Enums (Python Enum classes)
    Msg,
    Color,
    Mask,
    # Enums (cpdef enums from the Csound API)
    Status,
    EventType,
    ChannelType,
    ChannelBehavior,
    PvsWindow,
    PvsFormat,
    KeyCallbackType,
    UgenArgType,
    GraphPolarity,
    FileType,
    # Constants
    OPDS_SIZE,
    # Classes
    Csound,
    Params,
    PvsData,
    CsoundPerformanceThread,
    Tree,
    UgenFactory,
    UgenContext,
    Ugen,
    UgenVar,
    UgenGraph,
    ArrayChannel,
    CircularBuffer,
    GraphWindow,
)

__all__ = [
    "initialize",
    "get_version",
    "get_size_of_cs_float",
    "get_size_of_cs_double",
    "get_size_of_myflt",
    "set_global_env",
    "sleep",
    "Msg",
    "Color",
    "Mask",
    "Status",
    "EventType",
    "ChannelType",
    "ChannelBehavior",
    "PvsWindow",
    "PvsFormat",
    "KeyCallbackType",
    "UgenArgType",
    "GraphPolarity",
    "FileType",
    "OPDS_SIZE",
    "Csound",
    "Params",
    "PvsData",
    "CsoundPerformanceThread",
    "Tree",
    "UgenFactory",
    "UgenContext",
    "Ugen",
    "UgenVar",
    "UgenGraph",
    "ArrayChannel",
    "CircularBuffer",
    "GraphWindow",
]
