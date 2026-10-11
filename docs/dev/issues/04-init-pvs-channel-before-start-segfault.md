# csoundInitPvsChannel() segfaults before csoundStart()

**Version:** 7.0.0-beta.18

## Summary

`csoundInitPvsChannel()` called after compiling an orchestra but before
`csoundStart()` crashes with SIGSEGV. The header documents no such
precondition. Other channel functions, such as `csoundSetControlChannel()`,
work before start.

## Repro

```c
#include <stdio.h>
#include "csound.h"

int main(void) {
  CSOUND *cs = csoundCreate(NULL, NULL);
  csoundSetOption(cs, "-n");
  csoundCompileOrc(cs, "instr 1\nendin\n", 0);
  /* csoundStart() not called yet */
  PVSDAT *p = csoundInitPvsChannel(cs, "host", 1024, 256, 1024,
                                   PVS_WIN_HANN, PVS_AMP_FREQ);
  printf("csoundInitPvsChannel returned %p\n", (void *) p);
  csoundDestroy(cs);
  return 0;
}
```

Output: `Csound tidy up: Segmentation fault`. The `printf` is not reached.
Calling `csoundStart()` first avoids the crash.

## Cause

Not identified. The backtrace ends in two unnamed frames below
`csoundInitPvsChannel+0xb9`. The function calls `csoundGetChannelPtr()` and
then `csound->AuxAlloc()` (`OOps/bus.c:316-335`). One of these likely needs
state that only `csoundStart()` sets up (inference, not verified).

## Suggested fix

Return `NULL` before start, or document the precondition in `csound.h`.
