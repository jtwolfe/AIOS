# Clause: work-runtime-bots

Second envelope bit. Default off.

## Predicate

`envelope/work-runtime-bots.enabled` is true only if the operator
recorded an explicit yes on the OS envelope view **after** work-runtime
was already yes. Never a third bootstrap question. `answers.json`
`bots` is never a yes. Skipping is not a yes.

When enabled:

- `/srv/aios/src/work-runtime-bots` exists as its own git repository.
- Write set is only `/srv/aios/src/work-runtime-bots` plus `/tmp` and
  `/var/tmp`. Privileged trees stay `InaccessiblePaths`.
- Jobs are path + slice + skill + state, not selves. No avatars, no
  identity store, no personhood.
- Handoff payload is operational (paths, oracles, last evidence).
- VM define/start/stop/snapshot/destroy is an intent at
  `/run/aios/intent.sock`. `virsh` from the slice fails.
- Vendor user-unit **file** (L-23):
  `/usr/lib/systemd/user/aios-work-runtime-bots.service`. Enable only
  when this clause is true: `systemctl --user -M aios-work@`. That file
  may already exist before enable. Never a system unit.

When disabled:

- No bots unit is enabled or active. No linger-started bots service.
  The bots tree is absent or inert.
- Work-runtime yes does not start bots (HI-15-class).
- The vendor user-unit file may still exist. A **system** unit at
  `/etc/systemd/system/` must not exist.

## Oracle examples

- `test ! -f /etc/systemd/system/aios-work-runtime-bots.service`
- When disabled: `systemctl --user -M aios-work@ is-enabled
  aios-work-runtime-bots.service` and `is-active` are false; no
  linger-started bots service; bots tree absent or inert. Do not
  require `test ! -f` on the user-unit path.
- User unit `ReadWritePaths=/tmp /var/tmp /srv/aios/src/work-runtime-bots`
  (single line; no `/home`).
- `git -C /srv/aios/src/work-runtime-bots rev-parse --is-inside-work-tree`
  is true only when this clause is true.
