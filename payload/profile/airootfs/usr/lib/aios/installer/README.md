# installer

TTY TUI in installer mode (P5.1, L-09, L-18). systemd unit
`aios-installer.service` owns `/dev/console` on the installed disk until
envelope accept. It is not enabled on the live ISO.

Views: `chrome`, `conversation`, `questions`, `envelope`, `accept`,
`recovery`. Conversation is one view. Keyboard-complete so a serial
fixture can finish the path. Skip is not a yes (HI-15).

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
