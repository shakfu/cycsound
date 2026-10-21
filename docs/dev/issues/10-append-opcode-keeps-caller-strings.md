# `csoundAppendOpcode()` keeps the caller's strings instead of copying them

**Version:** 7.0.0

## Summary

`csound.h:1560` says of `csoundAppendOpcode()` that "the parameters are copied
into the new slot". The function stores `opname`, `outypes` and `intypes` in a
stack `OENTRY` (`Top/csound.c:1731`). `opcode_list_new_oentry()` then copies
that struct with `memcpy` (`Top/csound.c:1698`). The copy holds the caller's
string pointers, and Csound reads them on every later opcode lookup.

A host that passes temporary strings leaves dangling pointers in the opcode
table. A freed or reused buffer then changes, or corrupts, the registered
opcode. Language bindings are exposed by default: their encoded strings are
temporaries. Plugins are unaffected, because they pass string literals.

## Repro

```c
#include <stdio.h>
#include <string.h>
#include "csound.h"

/* Registers "hostop" (out "i", no inputs), then optionally rewrites the
   caller's type string, as reuse of a freed temporary would. */
static void run(int clobber) {
  char outypes[] = "i";
  CSOUND *cs = csoundCreate(NULL, NULL);
  csoundSetOption(cs, "-n");
  csoundSetOption(cs, "-m0");
  csoundAppendOpcode(cs, "hostop", 256, 0, outypes, "", NULL, NULL, NULL);
  if (clobber)
    strcpy(outypes, "k");
  int32_t err = csoundCompileOrc(cs, "instr 1\ni1 hostop\nendin\n", 0);
  printf("clobber=%d compile=%d\n", clobber, err);
  csoundDestroy(cs);
}

int main(void) {
  run(0);
  run(1);
  return 0;
}
```

Output (parser messages trimmed):

```
clobber=0 compile=0
Unable to find opcode entry for 'hostop'
Candidates:
  k hostop
clobber=1 compile=-1
```

The registered entry changed from `i hostop` to `k hostop` after
registration.

## Suggested fix

In `csoundAppendOpcode()`, duplicate the three strings with
`csound->Strdup()` before building the entry. Pool memory lives until
`csoundReset()`, which also frees the opcode table. Alternatively, correct
the header to say the strings must outlive the instance. That is already
the natural expectation for `csoundAppendOpcodes()`, whose static `OENTRY`
arrays carry static strings.

## cycsound

`Csound.append_opcode()` keeps the encoded strings until `reset()`.
`append_opcodes()` documents that the strings must outlive the instance.
