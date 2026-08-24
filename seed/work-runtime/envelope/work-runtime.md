# Clause: work runtime

Compiled from bootstrap. Default is off.

## Predicate

`envelope/work-runtime.enabled` is true only if bootstrap recorded an
explicit yes to "Do you want to work with AI agents on this system?"
Skipping the question is not a yes.

When enabled:

- `/srv/aios/src/work-runtime` exists as its own git repository.
- Write set is only `/srv/aios/src/work-runtime` plus `/tmp` and
  `/var/tmp`. Operator home including `~/src` is the approval-gated
  bridge. `/home` is not in `ReadWritePaths`.
- Its `AGENTS.md` forbids privileged system mutation.
- User units are declared in `state/` and **enabled** only after the
  checker passes. Vendor unit **file** (P8.2 / L-23):
  `/usr/lib/systemd/user/aios-work-runtime.service` (system-managed;
  not a system unit under `/etc/systemd/system/`; not only in a live
  `~/.config`). That file may already exist before enable. Linger
  `aios-work` so the user instance starts at boot.
- Resource caps match the `aios-work.slice` floor (MemoryMax / CPUQuota)
  on the user unit. Processes run as uid `aios-work`.
- Work store (notes, skills, routines, connectors) is git in
  `/srv/aios/src/work-runtime`, not `/srv/aios/memory`.

When disabled:

- No work-runtime unit is enabled or active (HI-15). No linger-started
  work-runtime service. The work tree is absent or inert.
- Disable is an envelope patch (`enabled: false`): stop the L-23 user
  units, leave git. Do not delete `/srv/aios/src/work-runtime`. Do not
  snapper-rollback the work tree. Work-tree mistakes are ordinary git.
- The vendor user-unit file may still exist after P8.2. That is not a
  defect. A **system** unit at `/etc/systemd/system/` must not exist.
- The seed may remain in this GitHub tree.

## Oracle examples

- `test ! -f /etc/systemd/system/aios-work-runtime.service` (must never
  be a system unit).
- When disabled: `systemctl --user -M aios-work@ is-enabled
  aios-work-runtime.service` and `is-active` are false (user instance
  absent counts as not active); no linger-started service; work tree
  absent or inert. Do not require `test ! -f` on the user-unit path.
- `systemctl --user -M aios-work@ is-enabled aios-work-runtime.service`
  is enabled only when the clause is true.
- User unit `ReadWritePaths=/tmp /var/tmp /srv/aios/src/work-runtime`
  (single line; no `/home`).
- `git -C /srv/aios/src/work-runtime rev-parse --is-inside-work-tree` is
  true when enabled.
- `! git -C /srv/aios/memory ls-files | grep -E 'routines|connectors'`
- After disable: `is-enabled`/`is-active` false; the work git remains.
