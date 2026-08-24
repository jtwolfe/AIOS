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

1. Named L-18 views only. Do not invent extra view ids. `brake` is
   a chrome action (L-12), not a view id. OS and work catalogs must
   not mix (L-14).
2. One binary. Do not add a second command. Shortcuts belong to an
   installed graphical client later, not this OS contract.
3. Work summon is refused unless `answers.json` has `work_runtime` JSON
   true (HI-15). Skip, `1`, and `"true"` are not a yes. When yes,
   `aios work` opens work chrome, not OS tools (L-14). Work catalog
   (L-18): conversation, skills, connectors, bridge, store, login.
   Every action has a keyboard path. `roster`/`job` stay refused
   (HI-15). Do not synthesise `/srv/aios/src/work-runtime`. This client
   must not run inside aios-work.slice. Mixed-privilege chat fails.
4. Emergency brake writes `/srv/aios/state/brake.d/stamp` (or
   `AIOS_BRAKE`). Accept grants a 1731 drop dir; do not chmod
   `/srv/aios/state` 0777 (HI-16). Freeze privileged writes. TUI stays.
   Human-only. No enact sudo.
5. `mode installer` is refused. This is not firstboot (L-09).
6. No sysupgrade. No curl. Live login is L-17 after envelope accept.
   Device-code: one https URL + user_code. Never a pasted API key. `start`
   writes `/run/aios/login-request`; the agent uid writes
   `/srv/aios/state/provider/os.token` mode `0600`. Token not in the
   transcript. Do not sudo live login. Remotes veto refuses login (L-17).
7. Never commit to `main`. Never force-push (HI-03).
8. Snapper rollback is L-19 (HI-06): TUI files `/run/aios/rollback-request`;
   `aios-agent` runs `enact rollback N`. Do not sudo. Do not call
   `snapper rollback` or `undochange`. Do not boot a RO snapper snapshot.
