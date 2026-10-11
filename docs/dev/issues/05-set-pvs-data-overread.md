# csoundSetPvsData() reads past the caller's frame

**Version:** 7.0.0-beta.18

## Summary

`csoundSetPvsData()` copies `frame.size` bytes from the caller's buffer.
`csoundGetPvsChannel()` can lower a `PVSDAT`'s FFT size `N` without shrinking
`frame.size`. A caller that passes `N + 2` floats, which is the documented
frame length, then causes a heap over-read.

## Repro

Build with `-fsanitize=address`.

```c
#include <stdio.h>
#include <stdlib.h>
#include "csound.h"

int main(void) {
  CSOUND *cs = csoundCreate(NULL, NULL);
  csoundSetOption(cs, "-n");
  csoundSetOption(cs, "-m0");
  csoundCompileOrc(cs, "instr 1\nendin\n", 0);
  csoundStart(cs);
  PVSDAT *small = csoundInitPvsChannel(cs, "small", 512, 128, 512,
                                       PVS_WIN_HANN, PVS_AMP_FREQ);
  PVSDAT *big = csoundInitPvsChannel(cs, "big", 1024, 256, 1024,
                                     PVS_WIN_HANN, PVS_AMP_FREQ);
  (void) small;
  /* Copies N = 512 into big; big's frame stays (1024 + 2) floats. */
  csoundGetPvsChannel(cs, "small", big);
  int n = csoundPvsDataFFTSize(big) + 2;           /* 514 */
  float *frame = calloc((size_t) n, sizeof(float));
  printf("fft size now %d; passing %d floats\n", n - 2, n);
  csoundSetPvsData(big, frame);                    /* reads 1026 floats */
  free(frame);
  csoundDestroy(cs);
  return 0;
}
```

Output: `AddressSanitizer: heap-buffer-overflow ... READ of size 4104`. The
buffer holds 2056 bytes.

## Cause

- `csoundSetPvsData()`: `memcpy(pvsdat->frame.auxp, frame, pvsdat->frame.size)`
  (`OOps/bus.c:312-314`).
- `csoundGetPvsChannel()` copies the header, including `N`, but not the
  `AUXCH` (`OOps/bus.c:3049`). The destination keeps its larger allocation.

The public API cannot read `frame.size`, so a caller cannot size the buffer
correctly.

## Suggested fix

Copy `(N + 2) * sizeof(float)` bytes, the size `pvs_frame_nbytes()`
(`OOps/bus.c:42`) already computes. Alternatively, add a length argument.
