# AGENTS.md

Contract for the TTY operator client. Nested files in this tree outrank
this file. Direct human instruction wins, except where a hard invariant
forbids it; those conflicts are raised, not swallowed.

Canonical hard invariants: [`docs/envelope/hard-invariants.md`](../docs/envelope/hard-invariants.md).
Quote them by id. Do not extend them here.

## What this is

Unprivileged TTY client. One binary `/usr/lib/aios/bin/aios` (P7.1).
`aios` / `aios os` is OS mode. `aios work` is work mode. Not the
installer, not the proposer, not the checker, not a work agent (HI-02,
HI-13). Python 3 stdlib only (L-01). No systemd unit for this TUI.

Work runtime stays default off (HI-15).

## Non-negotiable

1. Named OS views only (L-18). Do not invent extra view ids. `brake` is
   a chrome action (L-12), not a view id.
2. One binary. Do not add a second command. Shortcuts belong to an
   installed graphical client later, not this OS contract.
3. Work summon is refused while HI-15 is default off. Do not open work
   tools. Do not synthesise `/srv/aios/src/work-runtime`.
4. Emergency brake writes `/srv/aios/state/brake.d/stamp` (or
   `AIOS_BRAKE`). Accept grants a 1731 drop dir; do not chmod
   `/srv/aios/state` 0777 (HI-16). Freeze privileged writes. TUI stays.
   Human-only. No enact sudo.
5. `mode installer` is refused. This is not firstboot (L-09).
6. No sysupgrade. No curl. Live login is L-17 after envelope accept.
7. Never commit to `main`. Never force-push (HI-03).
