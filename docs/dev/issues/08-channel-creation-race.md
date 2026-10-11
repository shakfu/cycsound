# Channel creation is not thread-safe

**Version:** 7.0.0-beta.18

## Summary

`csoundGetChannelPtr()` creates a missing channel without a lock. A host
thread reading a channel the orchestra has not created yet can race the
performing thread's `chnset`. Two entries are then created for one name. The
orchestra writes to one and the host reads the other, so the value never
reaches the host.

The comment at `OOps/bus.c:2841` describes the channel API functions as
thread-safe.

## Repro

```c
#include <pthread.h>
#include <stdio.h>
#include "csound.h"

static void *perform(void *cs) {
  while (csoundPerformKsmps((CSOUND *) cs) == 0) {}
  return NULL;
}

int main(void) {
  int lost = 0, trials = 200;
  for (int i = 0; i < trials; i++) {
    CSOUND *cs = csoundCreate(NULL, NULL);
    csoundSetOption(cs, "-n");
    csoundSetOption(cs, "-m0");
    /* "p4" is created by chnset at i-time, not declared with chn_k */
    csoundCompileOrc(cs, "ksmps = 32\ninstr 1\nchnset p4, \"p4\"\nendin\n", 0);
    csoundEventString(cs, "i 1 0.001 0.01 5", 0);
    csoundStart(cs);
    pthread_t t;
    pthread_create(&t, NULL, perform, cs);
    /* The host reads "p4" while instr 1 may be creating it. */
    for (int k = 0; k < 2000; k++)
      csoundGetControlChannel(cs, "p4", NULL);
    pthread_join(t, NULL);
    if (csoundGetControlChannel(cs, "p4", NULL) != 5) lost++;
    csoundDestroy(cs);
  }
  printf("chnset value lost in %d of %d runs (expected 0)\n", lost, trials);
  return lost != 0;
}
```

Output: `chnset value lost in 130 of 200 runs (expected 0)`.

The same sequence without the thread returns 5: the host creates the channel
first, then the engine performs. The loss therefore needs concurrent creation.

## Cause

`csoundGetChannelPtr()` (`OOps/bus.c:525`) calls `find_channel()`, then
`create_new_channel()` (`OOps/bus.c:482`), then `find_channel()` again.
`create_new_channel()` inserts with `cs_hash_table_put()` (`OOps/bus.c:506`).
No lock covers the find-create-insert sequence, so two threads can both miss
and both insert.

## Suggested fix

Hold a channel-database lock across lookup and creation in
`csoundGetChannelPtr()` and the opcode init paths that create channels.

## Workaround

Declare every channel the host touches in the orchestra header (`chn_k`,
`chn_S`, `chn_a`), so it exists before performance starts.
