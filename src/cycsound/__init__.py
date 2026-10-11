"""cycsound - Cython bindings for the Csound 7 audio synthesis library."""

import os
import sys

# On Linux the Csound 7 release ships its opcode library as external plugins
# that are dlopen()ed by libcsound64 at csoundCreate() time. Those plugins
# resolve Csound symbols out of the global symbol namespace, so the extension
# (and with it libcsound64) has to be loaded with RTLD_GLOBAL -- otherwise the
# plugin opcodes silently fail to register and orchestras using them do not
# compile. The macOS framework has its opcodes built in, so this is a no-op
# there.
if sys.platform.startswith("linux"):
    # Point Csound at the vendored plugin directory of a source build unless
    # the environment already selects one.
    if "OPCODE7DIR64" not in os.environ:
        _plugins = os.path.join(
            os.path.dirname(os.path.dirname(os.path.dirname(
                os.path.abspath(__file__)))),
            "vendor", "plugins",
        )
        if os.path.isdir(_plugins):
            os.environ["OPCODE7DIR64"] = _plugins
        del _plugins

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
    # Classes
    Csound,
    Params,
    PvsData,
    CsoundPerformanceThread,
    Tree,
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
    "Csound",
    "Params",
    "PvsData",
    "CsoundPerformanceThread",
    "Tree",
]
