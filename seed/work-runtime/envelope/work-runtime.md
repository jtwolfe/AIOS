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
  after the checker passes.
- A systemd slice caps CPU and memory for work-runtime processes.

When disabled:

- No work-runtime units are started.
- The seed may remain in this GitHub tree. Absence of live units is not a
  defect.

## Oracle examples

- `test ! -f /etc/systemd/system/aios-work-runtime.service` when disabled.
- `systemctl is-enabled aios-work-runtime.service` is enabled only when the
  clause is true.
- `git -C /srv/aios/src/work-runtime rev-parse --is-inside-work-tree` is
  true when enabled.
