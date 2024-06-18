from libc cimport stdio

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

