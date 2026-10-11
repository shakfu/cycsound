# csoundKillInstance() unlocks API_lock without holding it

**Version:** 7.0.0-beta.18

## Summary

On an invalid `mode`, `csoundKillInstance()` unlocks `API_lock` without having
locked it, then returns `CSOUND_ERROR`.

## Code

`Top/threadsafe.c:383-386`:

```c
  if (UNLIKELY(mode < 0 || mode > 15 || (mode & 3) == 3)) {
    csoundUnlockMutex(csound->API_lock);
    return CSOUND_ERROR;
  }
```

The function locks `API_lock` only later, in the synchronous branch
(`Top/threadsafe.c:395`).

## Effect

Unlocking a mutex the thread does not own is undefined behaviour in POSIX. For
a recursive pthread mutex, glibc returns `EPERM`, which the call ignores. If
another thread holds the lock, a Windows critical section would be corrupted.
The effect on Windows comes from documentation, not a run.

Found by reading the code; there is no runtime repro.

## Suggested fix

Delete the `csoundUnlockMutex()` call in that branch.
