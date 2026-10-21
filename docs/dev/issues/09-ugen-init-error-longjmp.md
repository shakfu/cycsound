# An opcode init error in `csoundUgenInit()` crashes the host

**Version:** 7.0.0

## Summary

`csoundUgenInit()` calls the opcode's init function outside an init pass,
where `csound->ids` is NULL. An opcode that reports `csound->InitError()`
then reaches the `ids == NULL` branch of `csoundInitError()`
(`Engine/insert.c:2421`), which calls `csoundLongJmp()`. The jump target
`csound->exitjmp` was set by the first `csoundPerformKsmps()` call
(`Top/csound_perf.c:441`) or not at all. That frame has returned, so the
`longjmp` crashes.

Any init-time error triggers this: a missing function table, or an
argument-count check. `parse_in_types()` (`Engine/ugen.c:162`) always
expands a var-arg parameter to `UGEN_MAX_VAR_ARGS` (8) slots, so var-arg
opcodes that check their count, such as `linsegr`, fail every time.

## Repro

```c
#include <stdio.h>
#include "csound.h"
#include "ugen.h"

int main(void) {
  CSOUND *cs = csoundCreate(NULL, NULL);
  csoundSetOption(cs, "-n");
  csoundSetOption(cs, "-m0");
  csoundCompileOrc(cs, "instr 1\nendin\n", 0);
  csoundStart(cs);
  UGEN_FACTORY *f = csoundUgenFactoryNew(cs);
  /* "m" expands to 8 k-rate slots, so linsegr sees 10 inputs. */
  UGEN *u = csoundUgenNew(f, "linsegr", "k", "iim");
  printf("init...\n");
  fflush(stdout);
  int32_t r = csoundUgenInit(u);  /* csoundInitError -> csoundLongJmp */
  printf("init returned %d\n", r);
  csoundUgenDelete(u);
  csoundUgenFactoryDelete(f);
  csoundDestroy(cs);
  return 0;
}
```

Output:

```
init...

INIT ERROR: incomplete number of input arguments
Segmentation fault (core dumped)
```

## Suggested fix

Have `csoundUgenInit()`/`csoundUgenPerform()` (and the graph variants)
save `exitjmp`, `setjmp` into it, run the opcode, and restore it. Return
`CSOUND_INITIALIZATION`/`CSOUND_PERFORMANCE` when the jump fires. A
host cannot do this itself: `exitjmp` is in the private part of `CSOUND`.

Separately, let the caller choose the number of var-arg slots instead of
always expanding to 8.

## cycsound

No workaround is possible from the host. The `Ugen` docstring documents the
crash.
