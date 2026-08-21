# Handoff

---
name: handoff
description: Route failure. System-scoped events go to the OS agent. User-work events stay here.
---

System-scoped (OS agent wake, structured payload):

- systemd unit entered failed
- pacman transaction abort
- checker rejection of a privileged proposal
- disk or memory past envelope thresholds
- snapper / btrfs faults

Payload: unit or executable, journal slice since last healthy, last related
state commit, snapper id, matching envelope clause and skill path if any.
Not a free-form chat seed.

User-scoped (work-runtime wake, only if enabled):

- failed tests in a project under `~/src` or `/srv/aios/src` excluding the
  OS trees
- connector errors for a user job
- a routine the human asked for

If work-runtime is disabled, user-scoped failure is ordinary software.
Do not open the OS definition surface for it.
