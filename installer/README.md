# installer

TTY TUI in installer mode (P5.1, L-09, L-18). systemd unit
`aios-installer.service` owns `/dev/console` on the installed disk until
envelope accept. It is not enabled on the live ISO.

Views: `chrome`, `conversation`, `questions`, `envelope`, `accept`,
`recovery`. Conversation is one view. Keyboard-complete so a serial
fixture can finish the path. Skip is not a yes (HI-15).

Operator username is **asked** as the questions-view field `operator`.
It is not derived from purpose (fragile, PII-adjacent). Skip/empty is
not a username (same class as skip ≠ yes). Accept is refused until a
valid POSIX portable login (`[a-z_][a-z0-9_-]*`) that is not `root`,
`aios-agent`, `aios-checker`, or `aios-work`. Written to `answers.json`
as `operator`.

On accept of a valid login (L-13): create that one non-root human
login; do not give it enact sudo (`aios-agent` already has the only
enact sudoers). After accept, tty1 and serial-getty@ttyS0 autologin
that operator (same consoles as the installer). Disable/mask
`aios-installer.service` in the **target**, not on the live ISO.
Service uids stay nologin. Root is recovery only. Production uses
`useradd` for the human login (not a fourth sysuser in `aios.conf`).
Host oracles set `AIOS_ROOT` to a destdir and write the same
passwd/shadow/group/home/getty files when `useradd` is missing. Live
Grok login stays after accept (L-17). Work runtime stays default off
(HI-15).

On the machine the wrapper is `/usr/lib/aios/bin/installer` and the
Python tree is `/usr/lib/aios/installer`. Progress is snapshotted under
`/srv/aios/state/bootstrap-in-progress` (or `AIOS_BOOTSTRAP`):
`answers.json`, `envelope.draft.md`, `snapper_pre`, `step`. A restart
re-presents last accepted answers. Skip is not a yes (HI-15). Reject
does not create an operator login, stamp accept, or sysupgrade; L-19
rollback is offered, not enacted here (HI-09).

```
python3 installer/aios_installer/main.py
```

Piped stdin is a fixture. On a TTY, Ctrl+D and Ctrl+C keep the console;
the unit does not exit into getty (L-09). Brake writes
`/srv/aios/state/brake` (or `AIOS_BRAKE`) and keeps this process up
(L-12). The brake flag is on only if that file exists.
