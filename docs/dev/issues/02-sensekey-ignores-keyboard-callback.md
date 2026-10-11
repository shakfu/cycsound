# sensekey ignores a successful keyboard callback

**Version:** 7.0.0-beta.18

## Summary

A keyboard callback registered with `csoundRegisterKeyboardCallback()` that
writes a key and returns `CSOUND_SUCCESS` has no effect on `sensekey`.
`sensekey` instead polls stdin and overwrites the key. It also switches the
terminal on fd 0 to non-canonical mode.

## Repro

```c
#include <stdio.h>
#include "csound.h"

static int32_t on_key(void *userData, void *p, uint32_t type) {
  (void) userData; (void) type;
  *(int32_t *) p = 'A';
  return 0;   /* CSOUND_SUCCESS: key supplied */
}

int main(int argc, char **argv) {
  int workaround = argc > 1;
  CSOUND *cs = csoundCreate(NULL, NULL);
  csoundSetOption(cs, "-n");
  csoundSetOption(cs, "-m0");
  csoundCompileOrc(cs, "ksmps = 32\ninstr 1\nkk sensekey\n"
                       "chnset kk, \"key\"\nendin\n", 0);
  csoundRegisterKeyboardCallback(cs, on_key, NULL, CSOUND_CALLBACK_KBD_TEXT);
  if (workaround) csoundKeyPress(cs, 0);   /* sets inChar_ = 0 */
  csoundEventString(cs, "i 1 0 1", 0);
  csoundStart(cs);
  csoundPerformKsmps(cs);
  csoundPerformKsmps(cs);
  double key = csoundGetControlChannel(cs, "key", NULL);
  printf("sensekey%s: %g (expected 65)\n",
         workaround ? " with csoundKeyPress(cs, 0)" : "", key);
  csoundDestroy(cs);
  return key == 65 ? 0 : 1;
}
```

Run with stdin at EOF (`./repro < /dev/null`):

- `sensekey: -1 (expected 65)`
- With any argument: `sensekey with csoundKeyPress(cs, 0): 65 (expected 65)`

## Cause

`csoundDoCallback_()` (`Top/csound.c:2230-2244`) returns a callback's result
only if it is not `CSOUND_SUCCESS`. Once every callback succeeds, it falls
through to `return 1`. The registration comment (`Top/csound.c:2278`) defines
a positive result as "callback ignored".

`sensekey_perf()` (`OOps/bus.c:3134`) treats `retval > 0` as no callback
(`OOps/bus.c:3143`). `inChar_` starts at -1 (`Top/csound.c:952`), so it then
polls stdin and replaces the callback's key.

`readline` is not affected: `poll_terminal()` (`OOps/readline.c:676`) checks the
key value, not the return code.

## Suggested fix

Return `CSOUND_SUCCESS` from `csoundDoCallback_()` when at least one callback
matched the type and succeeded. Return 1 only when no callback matched.
