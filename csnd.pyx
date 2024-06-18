cimport csound as cs

from libc.stdio cimport printf, fprintf, stderr, FILE
from posix.unistd cimport sleep

# from libc.string cimport strcpy, strlen
# from libc.stdlib cimport malloc




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

# def csoundSetOpcodedir(s: str):
#     """Sets an opcodedir override for csoundCreate()"""
#     csound.csoundSetOpcodedir(s.encode())


