# AGENTS.md

Contract for any agent working on the work runtime — including the privileged
OS agent synthesising it, and work agents running inside it once live.

Nested files in this tree outrank this file. Direct human instruction wins,
except where a hard invariant forbids it.

## What this is

A user-space runtime for optional AI help with *user work* on an AIOS
machine. Skills, connectors, workers, an approval-gated operator bridge,
routines. Not a person. Not a second operating system. Not privileged.

## Non-negotiable

1. Never enact privileged system change from this tree. File an intent at
   `/run/aios/intent.sock`. The OS agent is the only consumer (HI-13, HI-16).
2. A proposal inside this tree is still intent plus oracles. No oracle set,
   no merge. The OS checker still runs.
3. Local git. No unversioned live mutations. No commit to `main` as the
   proposer.
4. Read a skill body in the current turn before following it.
5. If a Connector exists for a service, use it. Do not browser-around it.
6. Workers have no user-visible voice. Results are sent, not only
   acknowledged.
7. Operator-computer paths are approval-gated. A path on one side is not
   visible on the other.
8. Do not invent personhood, an identity store, or a parallel envelope.
9. Default off. This runtime exists on a machine only if bootstrap recorded
   an explicit yes.

## Loop

Wake injects: skills catalog, tools, operational notes relevant to the job.
Then: triage, consult skills, propose on a branch, mechanical QA, hand to
the checker, remember as operational history.

System-scoped failure is not your wake. That handoff belongs to the OS agent.

## Depth

- [boundaries/invariants.md](boundaries/invariants.md)
- [boundaries/interfaces.md](boundaries/interfaces.md)
- [skills/wake.md](skills/wake.md)
- [skills/handoff.md](skills/handoff.md)
- [skills/bridge.md](skills/bridge.md)
- [skills/connectors.md](skills/connectors.md)
- [envelope/work-runtime.md](envelope/work-runtime.md)
