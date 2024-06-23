
## ----------------------------------------------------------------------------
## Error Handling

cpdef enum CSOUND_STATUS:
    CSOUND_SUCCESS = 0
    CSOUND_ERROR = -1
    CSOUND_INITIALIZATION = -2
    CSOUND_PERFORMANCE = -3
    CSOUND_MEMORY = -4
    CSOUND_SIGNAL = -5

class CsoundError(Exception): pass
class CsoundInitializationError(Exception): pass
class CsoundPerformanceError(Exception): pass
class CsoundMemoryError(Exception): pass
class CsoundSignalError(Exception): pass

def check(result: int):
    if result == CSOUND_SUCCESS:
        return

    elif result == CSOUND_ERROR:
        raise CsoundError

    elif result == CSOUND_INITIALIZATION:
        raise CsoundInitializationError
    
    elif result == CSOUND_PERFORMANCE:
        raise CsoundPerformanceError
    
    elif result == CSOUND_MEMORY:
        raise CsoundMemoryError
    
    elif result == CSOUND_SIGNAL:
        raise CsoundSignalError

    else:
        raise Exception("Unknown Error")
    

