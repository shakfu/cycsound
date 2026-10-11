# csoundReset() drops the message string callback

**Version:** 7.0.0-beta.18

## Summary

After `csoundReset()`, messages go to the default printer. A callback set with
`csoundSetMessageStringCallback()` is no longer called. A callback set with
`csoundSetMessageCallback()` survives.

## Repro

```c
#include <stdio.h>
#include <string.h>
#include "csound.h"

static int hits = 0;
static void on_message(CSOUND *cs, int32_t attr, const char *s) {
  (void) cs; (void) attr;
  if (strstr(s, "probe")) hits++;
}

int main(void) {
  CSOUND *cs = csoundCreate(NULL, NULL);
  csoundSetMessageStringCallback(cs, on_message);
  csoundSetOption(cs, "-n");
  csoundCompileOrc(cs, "instr 1\nendin\n", 0);
  csoundStart(cs);
  csoundMessage(cs, "probe\n");
  csoundReset(cs);
  csoundMessage(cs, "probe\n");
  printf("callback hits: %d (expected 2)\n", hits);
  csoundDestroy(cs);
  return hits == 2 ? 0 : 1;
}
```

Output: `callback hits: 1 (expected 2)`. The second `probe` prints to stdout.

## Cause

`reset()` (`Top/csound.c:1878`) restores only the fields between
`first_callback_` and `last_callback_` (`include/csoundCore.h:1584-1597`), plus
a list of named fields. `csoundMessageStringCallback`
(`include/csoundCore.h:1609`) lies outside that range and is not in the list,
so it reverts to its `cenviron_` default. `message_string`, the buffer the
string callback formats into, is also reset to `NULL`.

## Suggested fix

Preserve `csoundMessageStringCallback` in `reset()`, as `hostdata` is
(`Top/csound.c:1955`). Re-allocate `message_string` when the callback is set,
or move both fields into the preserved range.
