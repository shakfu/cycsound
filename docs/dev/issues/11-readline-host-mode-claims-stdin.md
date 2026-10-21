# `readline` claims process stdin even with a host readline callback

**Version:** 7.0.0

## Summary

`readline_init()` claims process-wide stdin ownership for its instance
(`OOps/readline.c:929`). A second instance that runs `readline` while the
first holds the claim gets an init error: "stdin is owned by another Csound
instance". The claim lasts until the first instance's `readline` deinits or
the instance resets (`release_readline()`, `OOps/readline.c:702`).

With `csoundSetReadlineCallback()` the instance never reads stdin:
`configure_terminal()` returns before touching the terminal
(`OOps/readline.c:627`), and polling returns before `read()`
(`OOps/readline.c:789`). Two instances with host callbacks therefore
exclude each other over a resource neither uses. This blocks hosts that run
several instances, and test suites that keep an instance alive between
tests.

## Repro

```c
#include <stdio.h>
#include "csound.h"

static void on_request(CSOUND *cs, void *ud, uint32_t id, const char *prompt) {
  (void)cs;
  if (prompt != NULL) {
    printf("%s: request %u opened\n", (const char *)ud, id);
    fflush(stdout);
  }
}

static CSOUND *start(const char *name) {
  CSOUND *cs = csoundCreate(NULL, NULL);
  csoundSetOption(cs, "-n");
  csoundSetOption(cs, "-m0");
  /* Host input: this instance never reads stdin. */
  csoundSetReadlineCallback(cs, on_request, (void *)name);
  csoundCompileOrc(cs, "instr 1\nS, k readline \"> \"\nendin\n", 0);
  csoundEventString(cs, "i 1 0 1", 0);
  csoundStart(cs);
  csoundPerformKsmps(cs);
  return cs;
}

int main(void) {
  CSOUND *a = start("A");
  CSOUND *b = start("B");  /* readline init error */
  csoundDestroy(b);
  csoundDestroy(a);
  return 0;
}
```

Output:

```
A: request 1 opened
INIT ERROR in instr 1 (opcode readline) line 2: readline: stdin is owned by another Csound instance
S:S,k:k readline "> ":S
INIT ERROR in instr 1: note deleted (1 init errors)
```

B's request never opens.

## Suggested fix

In `readline_init()`, skip `claim_process_input()` when
`csound->readlineCallback != NULL`, and leave `ownsProcessInput` at 0 so
release stays balanced. Keep the claim for terminal input and for
`csoundReadlinePushText()` without a callback: that mode still polls stdin.
The `stdin_assign_flg` check (`OOps/readline.c:926`) has the same scope
question in host mode.

## cycsound

None in the wrapper. `tests/test_cs7_700.py` resets each instance after a
`readline` test, which releases the claim.
