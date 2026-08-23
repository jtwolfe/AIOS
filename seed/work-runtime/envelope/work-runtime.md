# Clause: work runtime

Compiled from bootstrap. Default is off.

## Predicate

`envelope/work-runtime.enabled` is true only if bootstrap recorded an
explicit yes to "Do you want to work with AI agents on this system?"
Skipping the question is not a yes.

When enabled:

- `/srv/aios/src/work-runtime` exists as its own git repository.
- Its `AGENTS.md` forbids privileged system mutation.
- User units for the runtime are declared in `state/` and installed only
  after the checker passes. Unit file:
  `/usr/lib/systemd/user/aios-work-runtime.service` (system-managed;
  not a system unit under `/etc/systemd/system/`; not only in a live
  `~/.config`). Linger `aios-work` so the user instance starts at boot.
- Resource caps match the `aios-work.slice` floor (MemoryMax / CPUQuota)
  on the user unit. Processes run as uid `aios-work`.

When disabled:

- No work-runtime units are started.
- The seed may remain in this GitHub tree. Absence of live units is not a
  defect.

## Oracle examples

- `test ! -f /usr/lib/systemd/user/aios-work-runtime.service` when disabled.
- `systemctl --user -M aios-work@ is-enabled aios-work-runtime.service`
  is enabled only when the clause is true.
- `git -C /srv/aios/src/work-runtime rev-parse --is-inside-work-tree` is
  true when enabled.
