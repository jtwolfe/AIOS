# Invariants

Testable. Terms match the machine glossary. These restated the privilege
rule for this tree; they do not replace
[docs/envelope/hard-invariants.md](../../../docs/envelope/hard-invariants.md).

1. Given the envelope has no explicit bots-extension yes, when the machine
   reaches a steady envelope, then no work-runtime-bots unit is enabled.
2. Given a fleet member requests a package, unit, VM lifecycle change, or
   envelope patch, when it acts, then the action is an intent filed at
   `/run/aios/intent.sock`, not a live privileged write.
3. Given a roster entry, when it is addressed, then it is a job plus a
   slice plus a skill path — not a self, an avatar, or an identity store.
4. Given inter-agent handoff, when a job moves, then the payload is
   operational (paths, oracles, last evidence), not a psyche.
5. Given a guest VM on the AIOS host, when a fleet member maintains it,
   then host mutation (bridge, disk, libvirt unit) is still an OS-agent
   intent. The guest is not a back door into host privilege.
6. Given experimental enactment, when it is not yet checker-passed, then it
   lives in a worktree or subvolume under `aios-work.slice` — not as a live
   `/usr` mutation, and not as a snapper substitute.
