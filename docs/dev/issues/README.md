# Upstream issue drafts (csound/csound)

Found while wrapping Csound 7.0.0-beta.18. Line numbers refer to the
`7.0.0-beta.18` tag. Each C repro was built against the vendored Linux
x86_64 release (`-DUSE_DOUBLE`) and fails as described.

| File | Title | Status | cycsound workaround |
|-|-|-|-|
| [01](01-reset-drops-message-string-callback.md) | `csoundReset()` drops the message string callback | to file | re-install after `reset()` |
| [02](02-sensekey-ignores-keyboard-callback.md) | `sensekey` ignores a successful keyboard callback | to file | `csoundKeyPress(cs, 0)` on registration and after `reset()` |
| [03](03-udp-console-ignores-string-callback.md) | UDP console does not mirror to, and clobbers, the string callback | to file | message callback and UDP console are exclusive |
| [04](04-init-pvs-channel-before-start-segfault.md) | `csoundInitPvsChannel()` segfaults before `csoundStart()` | to file | raise before `start()` |
| [05](05-set-pvs-data-overread.md) | `csoundSetPvsData()` reads past the caller's frame | to file | write `N + 2` floats directly |
| [06](06-kill-instance-unlocks-unowned-mutex.md) | `csoundKillInstance()` unlocks `API_lock` without holding it | to file | none needed (not wrapped) |
| [08](08-channel-creation-race.md) | Channel creation is not thread-safe | to file | none; declare host channels with `chn_*` |
| [09](09-ugen-init-error-longjmp.md) | An opcode init error in `csoundUgenInit()` crashes the host (7.0.0) | to file | none possible; documented |
| [07](07-atexit-destroy-runs-host-callbacks.md) | atexit destroy runs host callbacks after host shutdown | not filed: host-side | detach callbacks in a Python `atexit` handler |

File only after re-checking against the current `develop` branch.
