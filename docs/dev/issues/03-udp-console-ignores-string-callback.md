# UDP console does not mirror to, and clobbers, the string callback

**Version:** 7.0.0-beta.18

## Summary

With a host message callback set via `csoundSetMessageStringCallback()`:

1. `csoundUDPConsole(..., mirror = 1)` does not mirror messages to it.
2. `csoundStopUDPConsole()` installs the default printer, so the host
   callback stays disconnected after the console stops.

## Repro

```c
#include <stdio.h>
#include <string.h>
#include "csound.h"
#include "csound_server.h"

static int hits = 0;
static void on_message(CSOUND *cs, int32_t attr, const char *s) {
  (void) cs; (void) attr;
  if (strstr(s, "probe")) hits++;
}

int main(void) {
  CSOUND *cs = csoundCreate(NULL, NULL);
  csoundSetMessageStringCallback(cs, on_message);
  csoundMessage(cs, "probe\n");                      /* hits = 1 */
  csoundUDPConsole(cs, "127.0.0.1", 9, 1);           /* mirror = 1 */
  csoundMessage(cs, "probe\n");                      /* expected hits = 2 */
  int mirrored = hits;
  csoundStopUDPConsole(cs);
  csoundMessage(cs, "probe\n");                      /* expected hits = 3 */
  printf("while mirroring: %d (expected 2); after stop: %d (expected 3)\n",
         mirrored, hits);
  csoundDestroy(cs);
  return hits == 3 ? 0 : 1;
}
```

Output: `while mirroring: 1 (expected 2); after stop: 1 (expected 3)`.

## Cause

- `csoundUDPConsole()` saves only `csoundMessageCallback_` for mirroring
  (`Top/server.c:590`). `csoundSetMessageStringCallback()` sets that field to
  `NULL` (`Top/csound_messages.c:86`), so `p->cb` is `NULL` and
  `udp_msg_callback()` (`Top/server.c:548`) mirrors nothing.
- `udp_console_stop()` (`Top/server.c:564`) calls
  `csoundSetMessageCallback(csound, p->cb)` with `NULL`. That installs
  `csoundDefaultMessageCallback`, which takes precedence over the string
  callback in `csoundMessage()`.

## Suggested fix

When `csoundMessageCallback_` is `NULL`, mirror by formatting into
`message_string` and calling `csoundMessageStringCallback`. On stop, restore
the saved callback without going through the `NULL`-to-default substitution in
`csoundSetMessageCallback()`.
